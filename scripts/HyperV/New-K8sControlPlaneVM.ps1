#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Creates the Hyper-V control-plane VM for the kubeadm lab, bridged onto the LAN.

.DESCRIPTION
    Idempotent: safe to re-run. Each step checks current state and changes only
    what differs. Settings Hyper-V accepts only on a stopped VM are skipped, with
    a warning, while the VM is running.

      1. Verify the Windows edition and enable Hyper-V (one reboot required).
      2. Create or reuse an External switch so the VM gets its own LAN address.
      3. Create the Generation 2 VM and its VHDX (an existing VHDX is reattached).
      4. Enforce lab settings: static memory, no automatic checkpoints, UEFI CA
         Secure Boot template, pinned MAC, automatic start and shutdown.
      5. Attach the Rocky Linux installer ISO, or eject it with -EjectIso.
      6. Stop the host sleeping on AC power, since it now runs the control plane.
      7. Start the VM and print the MAC for the router's DHCP reservation.

    Run from an elevated PowerShell on Windows, not from WSL.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\New-K8sControlPlaneVM.ps1

.EXAMPLE
    # After Rocky is installed, detach the ISO and boot from disk:
    powershell -ExecutionPolicy Bypass -File .\New-K8sControlPlaneVM.ps1 -EjectIso
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
    Justification = 'Interactive admin script: colored progress is meant for the operator console, not the pipeline.')]
[CmdletBinding()]
param(
    [string]$VMName = 'k8s-cp-1',
    [string]$SwitchName = 'LAN',
    # Physical adapter to bridge. Defaults to the one holding the default route.
    [string]$NetAdapterName,
    [string]$IsoPath = "$env:USERPROFILE\Downloads\Rocky-10.2-x86_64-minimal.iso",
    [string]$VMRoot = 'C:\Hyper-V',
    [ValidateRange(2, 16)][int]$CpuCount = 2,
    [long]$MemoryBytes = 8GB,
    [long]$DiskBytes = 40GB,
    [switch]$EjectIso,
    [switch]$SkipHostPowerSettings
)

$ErrorActionPreference = 'Stop'

function Write-Step([string]$Message) { Write-Host "==> $Message" -ForegroundColor Cyan }

# 1. Hyper-V
Write-Step 'Checking Windows edition and Hyper-V'
$os = Get-CimInstance Win32_OperatingSystem
if ($os.Caption -match 'Home') {
    throw "Hyper-V is not available on $($os.Caption). Windows Pro, Enterprise, or Education is required."
}
$feature = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All
if ($feature.State -eq 'EnablePending') {
    Write-Warning 'Hyper-V is enabled but waiting for a reboot. Reboot Windows, then run this script again.'
    return
}
if ($feature.State -ne 'Enabled') {
    Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All -All -NoRestart | Out-Null
    Write-Warning 'Hyper-V was enabled. Reboot Windows, then run this script again.'
    return
}

# 2. External switch. Wi-Fi adapters work too: Hyper-V rewrites the VM's MAC on
# the air, so if ARP misbehaves later, suspect the wireless bridge first.
Write-Step "Ensuring External switch '$SwitchName'"
$switch = Get-VMSwitch -Name $SwitchName -ErrorAction SilentlyContinue
if ($switch -and $switch.SwitchType -ne 'External') {
    throw "Switch '$SwitchName' is $($switch.SwitchType); the VM needs an External switch to get a LAN address."
}
if (-not $switch -and -not $NetAdapterName -and -not $PSBoundParameters.ContainsKey('SwitchName')) {
    # An adapter can back only one External switch, so reuse one that exists.
    $existing = @(Get-VMSwitch -SwitchType External)
    if ($existing.Count -eq 1) {
        $switch = $existing[0]
        $SwitchName = $switch.Name
        Write-Host "    Reusing existing External switch '$SwitchName'"
    } elseif ($existing.Count -gt 1) {
        throw "Several External switches exist ($($existing.Name -join ', ')). Pass -SwitchName to pick one."
    }
}
if (-not $switch) {
    if (-not $NetAdapterName) {
        $route = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
            Sort-Object RouteMetric, InterfaceMetric | Select-Object -First 1
        if (-not $route) { throw 'No default route found. Pass -NetAdapterName (see Get-NetAdapter).' }
        $NetAdapterName = (Get-NetAdapter -InterfaceIndex $route.ifIndex).Name
    }
    $adapter = Get-NetAdapter -Name $NetAdapterName -Physical -ErrorAction SilentlyContinue
    if (-not $adapter) { throw "'$NetAdapterName' is not a physical adapter. Pass -NetAdapterName (see Get-NetAdapter -Physical)." }
    $bound = Get-VMSwitch -SwitchType External | Where-Object NetAdapterInterfaceDescription -eq $adapter.InterfaceDescription
    if ($bound) { throw "Adapter '$NetAdapterName' already backs External switch '$($bound.Name)'. Re-run with -SwitchName '$($bound.Name)'." }
    Write-Warning "Creating the switch on '$NetAdapterName'. Host networking drops for a few seconds."
    $switch = New-VMSwitch -Name $SwitchName -NetAdapterName $NetAdapterName -AllowManagementOS $true
}

# 3. VM and disk
$vmDir = Join-Path $VMRoot $VMName
$vhdPath = Join-Path $vmDir "$VMName.vhdx"
$newVM = $false
$vm = Get-VM -Name $VMName -ErrorAction SilentlyContinue
if (-not $vm) {
    Write-Step "Creating VM '$VMName'"
    New-Item -ItemType Directory -Path $vmDir -Force | Out-Null
    $vmArgs = @{
        Name               = $VMName
        Generation         = 2
        MemoryStartupBytes = $MemoryBytes
        SwitchName         = $SwitchName
        Path               = $VMRoot
    }
    if (Test-Path $vhdPath) {
        $vm = New-VM @vmArgs -VHDPath $vhdPath
    } else {
        $vm = New-VM @vmArgs -NewVHDPath $vhdPath -NewVHDSizeBytes $DiskBytes
    }
    $newVM = $true
}

# 4. VM settings
Write-Step 'Enforcing VM settings'
# Restoring a checkpoint rolls etcd back while the workers keep newer state.
# Back up the control plane with etcdctl snapshot save instead.
Set-VM -VM $vm -AutomaticCheckpointsEnabled $false
$vm = Get-VM -Name $VMName
if ($vm.State -eq 'Off') {
    Set-VM -VM $vm -AutomaticStartAction Start -AutomaticStopAction ShutDown
    Set-VMProcessor -VM $vm -Count $CpuCount
    # The kubelet's eviction thresholds assume memory does not balloon under it.
    Set-VMMemory -VM $vm -DynamicMemoryEnabled $false -StartupBytes $MemoryBytes
    # The default template trusts only Windows; Rocky's shim is signed by the UEFI CA.
    Set-VMFirmware -VM $vm -EnableSecureBoot On -SecureBootTemplate MicrosoftUEFICertificateAuthority

    $nic = Get-VMNetworkAdapter -VM $vm | Select-Object -First 1
    if ($nic.SwitchName -ne $SwitchName) {
        Connect-VMNetworkAdapter -VMNetworkAdapter $nic -SwitchName $SwitchName
    }
    if ($nic.DynamicMacAddressEnabled) {
        # Keep a MAC the VM already used, so an existing DHCP reservation still
        # matches; otherwise pick one in Hyper-V's 00-15-5D range.
        if ($nic.MacAddress -and $nic.MacAddress -ne '000000000000') {
            $mac = $nic.MacAddress
        } else {
            $mac = '00155D' + (-join (1..3 | ForEach-Object { '{0:X2}' -f (Get-Random -Maximum 256) }))
        }
        Set-VMNetworkAdapter -VMNetworkAdapter $nic -StaticMacAddress $mac
    }
} else {
    Write-Warning "VM '$VMName' is $($vm.State); stop it to enforce CPU, memory, Secure Boot, MAC, and start/stop settings."
}

# 5. Installer ISO
$dvd = Get-VMDvdDrive -VM $vm | Select-Object -First 1
if ($EjectIso) {
    Write-Step 'Ejecting the installer ISO and booting from disk'
    if ($dvd -and $dvd.Path) { Set-VMDvdDrive -VMDvdDrive $dvd -Path $null }
    if ($vm.State -eq 'Off') {
        Set-VMFirmware -VM $vm -FirstBootDevice (Get-VMHardDiskDrive -VM $vm | Select-Object -First 1)
    } else {
        Write-Warning 'Stop the VM and re-run with -EjectIso to make the disk the first boot device.'
    }
} else {
    if (-not (Test-Path $IsoPath)) { throw "Installer ISO not found: $IsoPath" }
    if (-not $dvd) {
        if ($vm.State -ne 'Off') { throw "Stop VM '$VMName' before adding a DVD drive." }
        Write-Step "Attaching $IsoPath"
        $dvd = Add-VMDvdDrive -VM $vm -Path $IsoPath -Passthru
    } elseif ($dvd.Path -ne $IsoPath) {
        Write-Step "Attaching $IsoPath"
        Set-VMDvdDrive -VMDvdDrive $dvd -Path $IsoPath
    }
    # Only a new VM boots the installer first; re-runs leave the boot order alone.
    if ($newVM) { Set-VMFirmware -VM $vm -FirstBootDevice $dvd }
}

# 6. Host power. If Windows sleeps, every node loses its API server.
if (-not $SkipHostPowerSettings) {
    Write-Step 'Disabling sleep and hibernate on AC power'
    powercfg /change standby-timeout-ac 0
    powercfg /change hibernate-timeout-ac 0
}

# 7. Start and report
$vm = Get-VM -Name $VMName
if ($vm.State -eq 'Off') {
    Write-Step "Starting '$VMName'"
    Start-VM -VM $vm
}
$nic = Get-VMNetworkAdapter -VM $vm | Select-Object -First 1
$macDisplay = $nic.MacAddress -replace '(..)(?!$)', '$1-'

Write-Host ''
Write-Host "VM:      $VMName ($((Get-VM -Name $VMName).State))"
Write-Host "Switch:  $SwitchName"
Write-Host "MAC:     $macDisplay  <- create a DHCP reservation for this on the router"
Write-Host ''
Write-Host 'Next steps:'
Write-Host "  1. vmconnect localhost $VMName   (install Rocky: no swap, enable SSH, add your user)"
Write-Host '  2. In the VM: sudo dnf install hyperv-daemons'
Write-Host "  3. Re-run this script with -EjectIso after shutting the VM down"
Write-Host '  4. From WSL and from each laptop: ping and ssh the VM'

if ($newVM) { vmconnect.exe localhost $VMName }
