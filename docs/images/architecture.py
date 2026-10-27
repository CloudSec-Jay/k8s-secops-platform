"""Generate docs/site/architecture.svg, the architecture diagram shown by both
the project site (GitHub Pages publishes docs/site/) and the README.

Edit the layout or labels here, then regenerate and check it in a browser:
    python3 docs/images/architecture.py docs/site/architecture.svg

Icons are the official Kubernetes icon set and CNCF project logos, read from
docs/images/icons/ (sources, pinned commits, and terms in its README.md). Each
is embedded as a self-contained data URI so their internal styles and IDs
cannot collide.
"""
import base64
import os
import sys

ICONS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "icons")

BLUE = "#326CE5"
DARK = "#1F2D3D"
MUTED = "#5B6B7F"
CARD = "#EEF3FD"
LINE = "#9FB3D9"
ORANGE = "#E8710A"

out = []


def add(s):
    out.append(s)


def esc(t):
    return t.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def text(x, y, t, size=12, weight=400, fill=DARK, anchor="start", italic=False):
    st = ' font-style="italic"' if italic else ""
    add(f'<text x="{x}" y="{y}" font-size="{size}" font-weight="{weight}" fill="{fill}" text-anchor="{anchor}"{st}>{esc(t)}</text>')


def rect(x, y, w, h, fill="#FFFFFF", stroke=DARK, sw=1.2, rx=10, dash=None):
    d = f' stroke-dasharray="{dash}"' if dash else ""
    add(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{rx}" fill="{fill}" stroke="{stroke}" stroke-width="{sw}"{d}/>')


def person(cx, cy, fill=BLUE):
    add(f'<circle cx="{cx}" cy="{cy - 16}" r="11" fill="{fill}"/>')
    add(f'<path d="M{cx - 20},{cy + 18} a20,20 0 0 1 40,0 z" fill="{fill}"/>')


def cloud(cx, cy):
    add(f'<path d="M{cx-34},{cy+14} a14,14 0 0 1 4,-27 a19,19 0 0 1 35,-6 a15,15 0 0 1 27,12 a12,12 0 0 1 2,21 z" fill="{BLUE}"/>')


def arrow(d, both=False, dash=False, color=DARK):
    da = ' stroke-dasharray="6 4"' if dash else ""
    ms = ' marker-start="url(#a)"' if both else ""
    add(f'<path d="{d}" fill="none" stroke="{color}" stroke-width="1.6"{da}{ms} marker-end="url(#a)"/>')


def badge(x, y, n):
    add(f'<circle cx="{x}" cy="{y}" r="10" fill="{ORANGE}"/>')
    text(x, y + 4, str(n), 11, 700, "#FFFFFF", "middle")


_icon_cache = {}


def img(name, x, y, w, h=None, opacity=1):
    """Place docs/images/icons/<name>.svg, scaled to fit the box. Each icon is
    embedded once as a <symbol> and reused, so repeats cost a few bytes."""
    h = h or w
    if name not in _icon_cache:
        with open(os.path.join(ICONS, name + ".svg"), "rb") as f:
            _icon_cache[name] = base64.b64encode(f.read()).decode()
    op = f' opacity="{opacity}"' if opacity != 1 else ""
    add(f'<use href="#icon-{name}" x="{x}" y="{y}" width="{w}" height="{h}"{op}/>')


def icon_defs():
    """Symbols for every icon placed with img(); emitted once, at the end."""
    add("<defs>")
    for name, data in _icon_cache.items():
        add(f'<symbol id="icon-{name}" viewBox="0 0 100 100"><image width="100" height="100" preserveAspectRatio="xMidYMid meet" href="data:image/svg+xml;base64,{data}"/></symbol>')
    add("</defs>")


def card(x, y, w, h, icon, title, sub, dash=None):
    rect(x, y, w, h, CARD, LINE, 1, 8, dash)
    img(icon, x + 8, y + (h - 38) / 2, 38, opacity=0.55 if dash else 1)
    text(x + 54, y + h / 2 - 3, title, 12, 700)
    text(x + 54, y + h / 2 + 13, sub, 10, 400, MUTED)


W, H = 1400, 960
add(f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" width="{W}" height="{H}" font-family="Helvetica, Arial, sans-serif" role="img" aria-labelledby="t d">')
add('<title id="t">k8s-secops-platform hybrid Kubernetes architecture</title>')
add('<desc id="d">A kubeadm cluster on one home Wi-Fi LAN. The control plane is a Hyper-V VM on the Windows desktop, running etcd, the API server, the scheduler, and the controller manager. The data plane is two bare-metal laptops, each running the kubelet, containerd, the Cilium agent, and a Longhorn replica; the replicas sync over Wi-Fi. The admin manages the cluster from the desktop. A Cilium Gateway at 10.0.0.56 serves HTTPS to the admin desktop only. Cilium provides the eBPF dataplane and a cluster-wide default deny. Nodes reach the internet through the home router. Wazuh, its agents, and Argo CD are planned.</desc>')
add(f'<defs><marker id="a" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M0,0 L10,5 L0,10 z" fill="{DARK}"/></marker></defs>')
add(f'<rect width="{W}" height="{H}" fill="#FFFFFF"/>')

# Title
img("kubernetes", 446, 20, 48)
text(505, 42, "Kubernetes cluster · k8s-secops-platform", 22, 700)
text(505, 64, "Hybrid kubeadm lab · v1.37.1 · Cilium 1.20.2 · Rocky Linux 10.2, CIS-hardened, SELinux enforcing · observed 2026-10-27", 12, 400, MUTED)

# Internet and router (top right)
cloud(1310, 38)
text(1310, 78, "Internet", 12, 700, anchor="middle")
text(1310, 92, "registries · repos · GitHub", 10, 400, MUTED, "middle")

# Home LAN boundary
rect(20, 104, 1360, 780, "#FFFFFF", "#8C4FFF", 1.6, 18, "8 5")
text(40, 128, "Home LAN · 10.0.0.0/24 · Wi-Fi · one flat subnet, no NAT between nodes", 13, 700, "#6B36D9")

rect(1258, 146, 110, 64, "#F6F7F9", "#9AA5B1", 1.2, 8)
text(1313, 170, "Home router", 12, 700, anchor="middle")
text(1313, 186, "10.0.0.1", 10, 400, MUTED, "middle")
text(1313, 200, "DNS · gateway", 10, 400, MUTED, "middle")

# Cluster boundary
rect(200, 146, 1040, 724, "#FFFFFF", BLUE, 2, 16)
text(220, 170, "Kubernetes cluster · kubeadm · containerd 2.4.2", 13, 700, BLUE)

# Control plane
rect(222, 186, 332, 560, "#FFFFFF", DARK, 1.5, 12)
img("k8s-control-plane", 240, 194, 30)
text(276, 214, "Control Plane", 16, 700)
text(242, 233, "control-plane-1 · Hyper-V VM on the Windows desktop", 10, 400, MUTED)
text(242, 247, "2 vCPU · 8 GiB · static pods run as spc_t", 10, 400, MUTED)

for (x, lbl, title, sub) in [(242, "k8s-etcd", "etcd", "key-value store"), (402, "k8s-kubelet", "kubelet", "+ containerd")]:
    rect(x, 266, 132, 112, CARD, LINE, 1, 8)
    img(lbl, x + 40, 274, 52)
    text(x + 66, 352, title, 12, 700, anchor="middle")
    text(x + 66, 367, sub, 10, 400, MUTED, "middle")

rect(242, 418, 292, 70, CARD, LINE, 1, 8)
img("k8s-api", 258, 431, 46)
text(318, 448, "API Server", 14, 700)
text(318, 466, ":6443 · mTLS · RBAC", 10, 400, MUTED)

for (x, lbl, title, sub) in [(242, "k8s-sched", "Scheduler", "kube-scheduler"), (402, "k8s-c-m", "Controller", "Manager")]:
    rect(x, 528, 132, 112, CARD, LINE, 1, 8)
    img(lbl, x + 40, 536, 52)
    text(x + 66, 614, title, 12, 700, anchor="middle")
    text(x + 66, 629, sub, 10, 400, MUTED, "middle")

for x in (308, 468):
    arrow(f"M{x},378 V418", both=True)
    arrow(f"M{x},488 V528", both=True)
text(242, 656, "control-plane taint keeps app workloads off;", 10, 400, MUTED)
text(242, 672, "also runs a CoreDNS replica and the Cilium agent", 10, 400, MUTED)
text(242, 688, "Hyper-V checkpoints off · back up etcd", 10, 400, MUTED)
text(242, 704, "with etcdctl snapshot instead", 10, 400, MUTED)

# Data plane
rect(588, 186, 494, 600, "#FFFFFF", DARK, 1.5, 12, "8 5")
text(608, 214, "Data Plane (Worker Nodes)", 16, 700)
text(608, 233, "bare-metal laptops · LUKS disks · lid ignored · sleep masked", 10, 400, MUTED)


def pods_card(x, y, w, h, pods):
    """One official pod icon per app, labelled; planned pods are dashed and faded."""
    rect(x, y, w, h, CARD, LINE, 1, 8)
    slot = w / len(pods)
    for i, (label, is_planned) in enumerate(pods):
        cx = x + slot * i + slot / 2
        if is_planned:
            rect(cx - slot / 2 + 3, y + 4, slot - 6, h - 8, "none", "#9AA5B1", 1, 6, "4 3")
        img("k8s-pod", cx - 15, y + 7, 30, opacity=0.45 if is_planned else 1)
        text(cx, y + 50, label, 9, 700 if not is_planned else 400, DARK if not is_planned else MUTED, "middle")
    text(x + 6, y + h - 5, "pods observed 2026-10-27", 7, 400, MUTED)


def worker(y0, name, hw, row_runtime_first, cilium_sub, pods):
    rect(606, y0, 458, 224, "#FFFFFF", DARK, 1.2, 10)
    img("k8s-node", 622, y0 + 8, 30)
    text(835, y0 + 24, name, 14, 700, anchor="middle")
    text(835, y0 + 41, hw, 10, 400, MUTED, "middle")
    r1, r2 = y0 + 56, y0 + 140
    rt, st = (r1, r2) if row_runtime_first else (r2, r1)
    card(620, rt, 136, 70, "k8s-kubelet", "kubelet", ":10250")
    card(762, rt, 136, 70, "containerd", "containerd", "runtime · SELinux")
    card(904, rt, 146, 70, "cilium", "Cilium agent", cilium_sub)
    pods_card(620, st, 278, 70, pods)
    card(904, st, 146, 70, "longhorn", "Longhorn", "replica")
    return rt, st


# Pod placement observed with `kubectl get pods -A -o wide` on 2026-10-27,
# grouped by app; the scheduler may move them after a node restart.
w1_rt, w1_st = worker(250, "Worker Node 1 · worker-1", "Dell XPS 13 9360 · 8 threads · 8 GiB", True, "+ Envoy · eBPF",
                      [("Hubble relay", False), ("Hubble UI", False), ("Cilium op.", False), ("Longhorn", False)])
w2_rt, w2_st = worker(510, "Worker Node 2 · worker-2", "Dell XPS 15 9510 · 16 threads · 32 GiB", False, "holds VIP lease",
                      [("CoreDNS", False), ("metrics", False), ("cert-mgr", False), ("Longhorn", False), ("Wazuh", True)])

# Platform services strip
chips = [("cert-manager · Lab CA", 136, None, "cert-manager"), ("metrics-server", 88, None, None),
         ("Argo CD (planned)", 116, "6 4", "argo"), ("Wazuh (planned)", 92, "6 4", None)]
x = 606
for (lbl, w, dash, icon) in chips:
    rect(x, 746, w, 26, "#F6F7F9", "#9AA5B1", 1, 6, dash)
    if icon:
        img(icon, x + 5, 750, 18, opacity=0.55 if dash else 1)
        text(x + 26, 763, lbl, 10, 400, DARK)
    else:
        text(x + w / 2, 763, lbl, 10, 400, DARK, "middle")
    x += w + 6

# Cilium dataplane band
rect(222, 800, 1000, 52, "#F4EFFF", "#8C4FFF", 1.2, 10)
img("cilium", 236, 806, 40)
text(722, 822, "Cilium 1.20.2 · eBPF dataplane · kube-proxy replacement · Hubble flow visibility", 13, 700, "#3B1F80", "middle")
text(722, 840, "cluster-wide default deny · per-namespace allow policies · L2 announcements for LAN addresses", 11, 400, "#3B1F80", "middle")

# Gateway (inside cluster, right column)
rect(1096, 560, 132, 196, CARD, BLUE, 1.4, 10)
img("k8s-ing", 1137, 572, 50)
text(1162, 640, "Gateway", 13, 700, anchor="middle")
text(1162, 657, "lab-gateway", 10, 400, MUTED, "middle")
text(1162, 673, "VIP 10.0.0.56", 10, 700, DARK, "middle")
text(1162, 689, "TLS *.lab.internal", 10, 400, MUTED, "middle")
text(1162, 705, "admin desktop only", 10, 400, MUTED, "middle")
text(1162, 721, "→ Longhorn UI", 10, 400, MUTED, "middle")

# People
person(110, 452)
text(110, 492, "Admin", 13, 700, anchor="middle")
text(110, 508, "Windows desktop · WSL", 10, 400, MUTED, "middle")
text(110, 522, "kubectl · Ansible · SSH", 10, 400, MUTED, "middle")

person(1313, 612)
text(1313, 652, "Admin browser", 12, 700, anchor="middle")
text(1313, 666, "trusts the Lab CA", 10, 400, MUTED, "middle")

person(1313, 742, "#8FA8D8")
text(1313, 782, "Endpoints", 12, 700, anchor="middle")
text(1313, 796, "Wazuh agents", 10, 400, MUTED, "middle")
text(1313, 810, "(planned)", 10, 400, MUTED, "middle")

# Flows
arrow("M140,453 H242")                                   # 1 admin -> API
badge(190, 453, 1)
arrow("M1286,622 H1228")                                 # 2 browser -> gateway
badge(1258, 622, 2)
arrow(f"M1096,712 H1074 V{w2_rt + 35} H1050")            # gateway -> Envoy on worker-2
arrow(f"M977,{w1_st + 70} V{w2_st}", both=True)          # 3 Longhorn sync
badge(990, 492, 3)
arrow("M1240,178 H1258")                                 # 4 nodes -> router
badge(1249, 198, 4)
arrow("M1313,146 V102")                                  # 5 router -> internet
badge(1330, 124, 5)
arrow("M1286,752 H1228", dash=True)                      # 6 agents -> VIP (planned)
badge(1258, 752, 6)
# API -> kubelets
arrow(f"M534,453 H571 V{250 + 56 + 35} H620")
arrow(f"M534,453 H571 V{w2_rt + 35} H620")

# Legend
lx, ly = 40, 912
items = ["Admin kubectl · Ansible · SSH", "HTTPS to the Gateway, desktop only", "Longhorn replica sync over Wi-Fi",
         "Node DNS and egress", "Image and package downloads", "Wazuh agent events (planned)"]
bx = lx
for i, t in enumerate(items):
    badge(bx + 10, ly, i + 1)
    text(bx + 26, ly + 4, t, 11)
    bx += 26 + int(len(t) * 6.1) + 22
add(f'<line x1="40" y1="940" x2="72" y2="940" stroke="{DARK}" stroke-width="1.6"/>')
text(80, 944, "live, verified on the cluster", 11)
add(f'<line x1="260" y1="940" x2="292" y2="940" stroke="{DARK}" stroke-width="1.6" stroke-dasharray="6 4"/>')
text(300, 944, "planned", 11)
text(1380, 944, "Kubernetes icons © The Kubernetes Authors, CC-BY-4.0 · project logos © The Linux Foundation, used to identify software", 10, 400, MUTED, "end", True)

icon_defs()
add("</svg>")
open(sys.argv[1], "w").write("\n".join(out) + "\n")
