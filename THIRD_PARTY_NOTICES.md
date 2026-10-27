# Third-Party Notices

This repository configures and documents third-party projects including Kubernetes, Cilium, Wazuh, Helm, and containerd. Their names and trademarks remain the property of their respective owners.

## Wazuh security configuration assessment policy

The file [`wazuh/content/sca/fedora/cis_fedora_custom.yaml`](wazuh/content/sca/fedora/cis_fedora_custom.yaml) was migrated from the Cloud Operations portfolio and is derived from the [Wazuh project](https://github.com/wazuh/wazuh).

Copyright: Wazuh, Inc. and contributors  
License: GNU General Public License version 2

The file identifies itself as based on a Center for Internet Security benchmark. CIS names and benchmark content remain subject to their applicable terms and trademarks.

## Architecture diagram icons

The icons in [`docs/images/icons/`](docs/images/icons/), embedded in [`docs/site/architecture.svg`](docs/site/architecture.svg), are copied unmodified from pinned upstream commits listed in [`docs/images/icons/README.md`](docs/images/icons/README.md).

- **Kubernetes Icons Set** from [kubernetes/community](https://github.com/kubernetes/community/tree/main/icons). Copyright: The Kubernetes Authors. License: [CC-BY-4.0](https://creativecommons.org/licenses/by/4.0/) (offered as Apache-2.0 or CC-BY-4.0).
- **Project logos** for Kubernetes, Longhorn, Cilium, containerd, cert-manager, and Argo from [cncf/artwork](https://github.com/cncf/artwork). These are trademarks of The Linux Foundation, used only to identify the software running in the lab under the [Linux Foundation trademark usage guidelines](https://www.linuxfoundation.org/trademark-usage). No endorsement is implied.

## Referenced upstream deployment

The Wazuh runbook clones a pinned release of [wazuh/wazuh-kubernetes](https://github.com/wazuh/wazuh-kubernetes) into an ignored local directory. Those retrieved files are not committed here and remain governed by the upstream repository's license and notices.
