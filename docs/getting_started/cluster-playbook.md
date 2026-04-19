# cluster.yml Playbook Explained

`playbooks/cluster.yml` is the main entry point for deploying a full Kubernetes cluster with Kubespray. It orchestrates a series of plays executed in a fixed order, each responsible for a distinct phase of the installation.

## Overview

```
playbooks/cluster.yml
├── playbooks/boilerplate.yml          — Common pre-flight tasks
├── playbooks/internal_facts.yml       — Gather host facts
├── Prepare for etcd install           — Preinstall + container engine + downloads
├── playbooks/install_etcd.yml         — Deploy etcd cluster
├── Install Kubernetes nodes           — Deploy kubelet and node components
├── Install the control plane          — Deploy API server, scheduler, controller-manager
├── Invoke kubeadm / CNI               — Bootstrap cluster, label/taint nodes, install CNI
├── Calico Route Reflector             — (Optional) configure Calico RR nodes
├── Patch for Windows                  — (Optional) Windows node patches
├── Install Kubernetes apps            — Deploy cloud controllers, ingress, storage, etc.
└── Apply resolv.conf                  — Final DNS configuration on all nodes
```

---

## Play-by-Play Breakdown

### 1. Common tasks for every playbooks
**Imported from:** [`playbooks/boilerplate.yml`](../../playbooks/boilerplate.yml)

Runs shared pre-flight tasks that every Kubespray playbook requires — validating the Ansible version, checking Python dependencies, and setting common variables. This play has no host scope of its own; it delegates scope to whatever `boilerplate.yml` defines.

---

### 2. Gather facts
**Imported from:** [`playbooks/internal_facts.yml`](../../playbooks/internal_facts.yml)

Collects host facts (OS, CPU architecture, IP addresses, etc.) and populates internal Kubespray variables derived from those facts. Later plays rely on this data, so it runs early before any installation begins.

---

### 3. Prepare for etcd install
**Hosts:** `k8s_cluster`, `etcd`

Prepares all cluster nodes (both Kubernetes nodes and dedicated etcd nodes) for the installation. Runs four roles in sequence:

| Role | Path | Tag | Purpose |
|---|---|---|---|
| `kubespray_defaults` | [`roles/kubespray_defaults`](../../roles/kubespray_defaults) | — | Load default variables and merge with user overrides |
| `kubernetes/preinstall` | [`roles/kubernetes/preinstall`](../../roles/kubernetes/preinstall) | `preinstall` | OS-level prerequisites: kernel modules, sysctl settings, package dependencies, firewall rules |
| `container-engine` | [`roles/container-engine`](../../roles/container-engine) | `container-engine` | Install the configured container runtime (containerd, Docker, etc.). Skipped when `deploy_container_engine` is false |
| `download` | [`roles/download`](../../roles/download) | `download` | Pre-fetch all required binaries and container images. Skipped when `skip_downloads` is true |

---

### 4. Install etcd
**Imported from:** [`playbooks/install_etcd.yml`](../../playbooks/install_etcd.yml)
**Variables set:** `etcd_cluster_setup: true`, `etcd_events_cluster_setup` (driven by `etcd_events_cluster_enabled`)

Deploys and configures the etcd cluster. When `etcd_events_cluster_enabled` is true, a separate etcd ring dedicated to Kubernetes Event objects is also created, reducing load on the main etcd cluster.

---

### 5. Install Kubernetes nodes
**Hosts:** `k8s_cluster`

Installs low-level Kubernetes node components on every node in the cluster (both control-plane nodes and workers). Runs two roles:

| Role | Path | Tag | Purpose |
|---|---|---|---|
| `kubespray_defaults` | [`roles/kubespray_defaults`](../../roles/kubespray_defaults) | — | Load default variables |
| `kubernetes/node` | [`roles/kubernetes/node`](../../roles/kubernetes/node) | `node` | Install kubelet, configure systemd unit, set up node PKI certificates, configure `/etc/kubernetes` |

---

### 6. Install the control plane
**Hosts:** `kube_control_plane`

Sets up the Kubernetes control plane components on designated control-plane nodes. Runs four roles:

| Role | Path | Tag | Purpose |
|---|---|---|---|
| `kubespray_defaults` | [`roles/kubespray_defaults`](../../roles/kubespray_defaults) | — | Load default variables |
| `kubernetes/control-plane` | [`roles/kubernetes/control-plane`](../../roles/kubernetes/control-plane) | `control-plane` | Deploy kube-apiserver, kube-scheduler, kube-controller-manager (as static pods or systemd services) |
| `kubernetes/client` | [`roles/kubernetes/client`](../../roles/kubernetes/client) | `client` | Install and configure `kubectl`, generate `kubeconfig` for admin access |
| `kubernetes-apps/cluster_roles` | [`roles/kubernetes-apps/cluster_roles`](../../roles/kubernetes-apps/cluster_roles) | `cluster-roles` | Create built-in ClusterRoles and ClusterRoleBindings required by Kubespray |

---

### 7. Invoke kubeadm and install a CNI
**Hosts:** `k8s_cluster`

Bootstraps the cluster with kubeadm, applies node metadata, and installs the Container Network Interface plugin. Runs six roles:

| Role | Path | Tag | Purpose |
|---|---|---|---|
| `kubespray_defaults` | [`roles/kubespray_defaults`](../../roles/kubespray_defaults) | — | Load default variables |
| `kubernetes/kubeadm` | [`roles/kubernetes/kubeadm`](../../roles/kubernetes/kubeadm) | `kubeadm` | Run `kubeadm init` / `kubeadm join` to form the cluster; generate and distribute join tokens |
| `kubernetes/node-label` | [`roles/kubernetes/node-label`](../../roles/kubernetes/node-label) | `node-label` | Apply user-defined labels to nodes via `kubectl label` |
| `kubernetes/node-taint` | [`roles/kubernetes/node-taint`](../../roles/kubernetes/node-taint) | `node-taint` | Apply user-defined taints to nodes via `kubectl taint` |
| `kubernetes-apps/common_crds` | [`roles/kubernetes-apps/common_crds`](../../roles/kubernetes-apps/common_crds) | — | Install shared CustomResourceDefinitions (CRDs) needed by multiple components |
| `network_plugin` | [`roles/network_plugin`](../../roles/network_plugin) | `network` | Install the configured CNI plugin (Calico, Flannel, Cilium, etc.) |

---

### 8. Install Calico Route Reflector *(optional)*
**Hosts:** `calico_rr`

Only runs if there are hosts in the `calico_rr` inventory group. Configures designated nodes as [Calico Route Reflectors](https://docs.tigera.io/calico/latest/networking/configuring/bgp), which distribute BGP routes in large clusters to avoid a full mesh of peer connections.

| Role | Path | Tags | Purpose |
|---|---|---|---|
| `kubespray_defaults` | [`roles/kubespray_defaults`](../../roles/kubespray_defaults) | — | Load default variables |
| `network_plugin/calico/rr` | [`roles/network_plugin/calico/rr`](../../roles/network_plugin/calico/rr) | `network`, `calico_rr` | Configure the BGP route reflector role on selected nodes |

---

### 9. Patch Kubernetes for Windows *(optional)*
**Hosts:** `kube_control_plane[0]` (first control-plane node only)

Applies Kubernetes patches required to support Windows worker nodes. This play targets only the first control-plane node because the patches are cluster-wide API operations that only need to be applied once.

| Role | Path | Tags | Purpose |
|---|---|---|---|
| `kubespray_defaults` | [`roles/kubespray_defaults`](../../roles/kubespray_defaults) | — | Load default variables |
| `win_nodes/kubernetes_patch` | [`roles/win_nodes/kubernetes_patch`](../../roles/win_nodes/kubernetes_patch) | `control-plane`, `win_nodes` | Create Windows-specific RuntimeClasses, node labels, and RBAC rules |

---

### 10. Install Kubernetes apps
**Hosts:** `kube_control_plane`

Deploys optional cluster-level applications and integrations. Runs six roles:

| Role | Path | Tag | Purpose |
|---|---|---|---|
| `kubespray_defaults` | [`roles/kubespray_defaults`](../../roles/kubespray_defaults) | — | Load default variables |
| `kubernetes-apps/external_cloud_controller` | [`roles/kubernetes-apps/external_cloud_controller`](../../roles/kubernetes-apps/external_cloud_controller) | `external-cloud-controller` | Deploy the out-of-tree cloud controller manager (AWS, Azure, GCP, OpenStack, etc.) |
| `kubernetes-apps/policy_controller` | [`roles/kubernetes-apps/policy_controller`](../../roles/kubernetes-apps/policy_controller) | `policy-controller` | Deploy a network policy controller if required by the chosen CNI |
| `kubernetes-apps/ingress_controller` | [`roles/kubernetes-apps/ingress_controller`](../../roles/kubernetes-apps/ingress_controller) | `ingress-controller` | Deploy an Ingress controller (e.g. Nginx, MetalLB) if configured |
| `kubernetes-apps/external_provisioner` | [`roles/kubernetes-apps/external_provisioner`](../../roles/kubernetes-apps/external_provisioner) | `external-provisioner` | Deploy an external storage provisioner (e.g. local-path, NFS) if configured |
| `kubernetes-apps` | [`roles/kubernetes-apps`](../../roles/kubernetes-apps) | `apps` | Deploy remaining enabled applications: Dashboard, Metrics Server, Cert-Manager, Helm, etc. |

---

### 11. Apply resolv.conf changes
**Hosts:** `k8s_cluster`

Re-runs the `kubernetes/preinstall` role with `dns_late: true` to update `/etc/resolv.conf` on every node so that the cluster DNS (CoreDNS) is used for name resolution. This play only executes when `dns_mode != 'none'` and `resolvconf_mode == 'host_resolvconf'` — i.e., when Kubespray is managing the host resolver and a DNS mode is active.

| Role | Path | Tag | Purpose |
|---|---|---|---|
| `kubespray_defaults` | [`roles/kubespray_defaults`](../../roles/kubespray_defaults) | — | Load default variables |
| `kubernetes/preinstall` | [`roles/kubernetes/preinstall`](../../roles/kubernetes/preinstall) | `resolvconf` | Re-apply DNS resolver config after CoreDNS is running (`dns_late: true`) |

---

## Execution Flow Diagram

```
All nodes (k8s_cluster + etcd)
  └─ boilerplate / facts / preinstall / container-engine / downloads
        │
        ▼
etcd nodes
  └─ etcd cluster install
        │
        ▼
All k8s_cluster nodes
  └─ kubelet + node components
        │
        ▼
kube_control_plane nodes
  └─ apiserver / scheduler / controller-manager / kubectl / cluster roles
        │
        ▼
All k8s_cluster nodes
  └─ kubeadm init/join + node labels/taints + CRDs + CNI plugin
        │
        ├─▶ calico_rr nodes (if present) — BGP route reflectors
        │
        ├─▶ kube_control_plane[0] (if Windows nodes) — Windows patches
        │
        ▼
kube_control_plane nodes
  └─ cloud controller / policy / ingress / storage / apps
        │
        ▼
All k8s_cluster nodes
  └─ resolv.conf update (if host_resolvconf mode)
```

## Common Tags

You can limit execution to specific phases using Ansible tags:

| Tag | Phase |
|---|---|
| `preinstall` | OS prerequisites |
| `container-engine` | Container runtime install |
| `download` | Binary/image pre-fetch |
| `node` | Kubelet setup |
| `control-plane` | Control plane components |
| `client` | kubectl setup |
| `kubeadm` | Cluster bootstrap |
| `network` | CNI plugin install |
| `apps` | Kubernetes applications |
| `resolvconf` | DNS resolver config |

Example — run only the network plugin installation:

```bash
ansible-playbook -i inventory/mycluster/hosts.yaml playbooks/cluster.yml --tags network
```
