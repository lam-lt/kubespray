# Kubespray Kubernetes Cluster Installation Flow

**Entry point:** `cluster.yml` → `playbooks/cluster.yml`

---

## Phase 0 — Pre-flight & Validation

**Playbook:** `playbooks/boilerplate.yml`

| Step | Role / File | What it does |
|------|-------------|-------------|
| 0a | `playbooks/ansible_version.yml` | Asserts Ansible is in the required version range (2.17.3–2.18.0), checks Python `netaddr` |
| 0b | `roles/dynamic_groups/tasks/main.yml` | Normalizes legacy group names (`kube-master` → `kube_control_plane`, etc.) and builds the `k8s_cluster` parent group |
| 0c | `roles/validate_inventory/tasks/main.yml` | Validates inventory: control plane non-empty, etcd exists, k8s version supported, CIDRs don't collide, boolean vars typed correctly, CNI/runtime combinations supported |
| 0d | `roles/bastion-ssh-config/tasks/main.yml` | Configures SSH proxy-jump for bastion host access |

---

## Phase 1 — OS Bootstrap & Fact Gathering

**Playbook:** `playbooks/internal_facts.yml`

| Step | Role / File | What it does |
|------|-------------|-------------|
| 1a | `roles/bootstrap_os/tasks/main.yml` | Detects OS from `/etc/os-release`, loads distro vars (Ubuntu/RHEL/Flatcar/etc.), installs base system packages, optionally sets hostnames |
| 1b | `roles/network_facts/tasks/main.yml` + Ansible `setup` module | Resolves IPs (primary IP, access IP), gathers minimal Ansible facts (memory, interfaces) |

---

## Phase 2 — OS-Level Node Preparation

**Hosts:** `k8s_cluster:etcd` · **Role:** `roles/kubernetes/preinstall/`

| Step | Task file | What it does |
|------|-----------|-------------|
| 2a | `roles/kubernetes/preinstall/tasks/0010-swapoff.yml` | Disables swap (required by kubelet) |
| 2b | `roles/kubernetes/preinstall/tasks/0040-verify-settings.yml` | Node-level assertions: systemd present, OS supported, enough RAM (CP: 1500 MB, node: 1024 MB), cgroups enabled |
| 2c | `roles/kubernetes/preinstall/tasks/0050-create_directories.yml` | Creates `/etc/kubernetes`, cert dirs, etc. |
| 2d | `roles/kubernetes/preinstall/tasks/0060-resolvconf.yml`<br>`roles/kubernetes/preinstall/tasks/0061-systemd-resolved.yml`<br>`roles/kubernetes/preinstall/tasks/0062-networkmanager-unmanaged-devices.yml`<br>`roles/kubernetes/preinstall/tasks/0063-networkmanager-dns.yml` | Early DNS/resolv.conf config (does NOT point at cluster DNS yet) |
| 2e | `roles/kubernetes/preinstall/tasks/0080-system-configurations.yml` | Kernel: SELinux, ip_forward, `fs.may_detach_mounts`, keyring limits; loads dummy module for NodeLocal DNS, disables fapolicyd |
| 2f | `roles/kubernetes/preinstall/tasks/0081-ntp-configurations.yml` | Configures NTP (when `ntp_enabled`) |

---

## Phase 3 — Container Runtime

**Role:** `roles/container-engine/`

Installs exactly one runtime based on `container_manager`:

| Runtime | Task file | What it does |
|---------|-----------|-------------|
| containerd | `roles/container-engine/containerd/tasks/main.yml` | Downloads tarball, writes `config.toml` (v1/v2), configures registry mirrors, starts service |
| CRI-O | `roles/container-engine/cri-o/tasks/main.yml` | Installs and configures CRI-O |
| Docker | `roles/container-engine/cri-dockerd/tasks/main.yml` | Installs Docker + cri-dockerd shim |

Optional sandbox runtimes (parallel):

| Runtime | Task file |
|---------|-----------|
| kata-containers | `roles/container-engine/kata-containers/tasks/main.yml` |
| gvisor | `roles/container-engine/gvisor/tasks/main.yml` |
| crun | `roles/container-engine/crun/tasks/main.yml` |
| youki | `roles/container-engine/youki/tasks/main.yml` |

---

## Phase 4 — Binary & Image Downloads

**Role:** `roles/download/`

| Task file | What it does |
|-----------|-------------|
| `roles/download/tasks/main.yml` | Orchestrates all downloads |
| `roles/download/tasks/prep_download.yml` | Prepares download directories and variables |
| `roles/download/tasks/prep_kubeadm_images.yml` | Runs `kubeadm config images list` on the first control plane to enumerate required images |
| `roles/download/tasks/download_file.yml` | Downloads each binary (kubelet, kubeadm, kubectl, etcd, CNI) |
| `roles/download/tasks/download_container.yml` | Pulls each container image |

In `download_run_once` mode: one node fetches everything and distributes; otherwise each node fetches its own copy.

---

## Phase 5 — etcd Installation

**Playbook:** `playbooks/install_etcd.yml` · **Role:** `roles/etcd/`

Only when `etcd_deployment_type != 'kubeadm'` (otherwise kubeadm manages etcd as static pods in Phase 7):

| Step | Task file | What it does |
|------|-----------|-------------|
| 5a | `roles/etcd/tasks/check_certs.yml` | Checks if existing certs are still valid |
| 5b | `roles/etcd/tasks/gen_certs_script.yml` | Generates etcd TLS certs (CA, server, peer, client) |
| 5c | `roles/etcd/tasks/upd_ca_trust.yml` | Installs etcd CA into system trust store on etcd + control plane nodes |
| 5d | `roles/etcd/tasks/install_host.yml` | Installs etcd binary + writes systemd unit, starts etcd |
| 5e | `roles/etcd/tasks/configure.yml` | Writes etcd environment config and systemd unit |
| 5f | `roles/etcd/tasks/refresh_config.yml` | Switches `initial-cluster-state` from `new` → `existing` for idempotent re-runs |
| 5g | `roles/etcdctl_etcdutl/tasks/main.yml` | Installs `etcdctl` and `etcdutl` binaries |

---

## Phase 6 — kubelet Installation

**Role:** `roles/kubernetes/node/` · **Hosts:** `k8s_cluster`

| Step | Task file | What it does |
|------|-----------|-------------|
| 6a | `roles/kubernetes/node/tasks/facts.yml` | Resolves node-level facts (kubelet version, etc.) |
| 6b | `roles/kubernetes/node/tasks/install.yml` | Copies kubelet binary to bin dir |
| 6c | `roles/kubernetes/node/tasks/loadbalancer/kube-vip.yml` | (control plane, if `kube_vip_enabled`) Installs kube-vip as a static pod manifest |
| 6d | `roles/kubernetes/node/tasks/loadbalancer/nginx-proxy.yml` | (workers, if `loadbalancer_apiserver_type == 'nginx'`) Local nginx proxy to the API server |
| 6e | `roles/kubernetes/node/tasks/loadbalancer/haproxy.yml` | (workers, if `loadbalancer_apiserver_type == 'haproxy'`) Local HAProxy to the API server |
| 6f | `roles/kubernetes/node/tasks/main.yml` | Loads kernel modules: `br_netfilter`, IPVS (`ip_vs*`), `nf_conntrack`, `nf_tables` |
| 6g | `roles/kubernetes/node/tasks/kubelet.yml` | Writes `kubelet.env`, `kubelet-config.yaml`, kubelet systemd unit; starts & enables kubelet |

---

## Phase 7 — Control Plane Bootstrap

**Role:** `roles/kubernetes/control-plane/` · **Hosts:** `kube_control_plane`

| Step | Task file | What it does |
|------|-----------|-------------|
| 7a | `roles/kubernetes/control-plane/tasks/define-first-kube-control.yml` | Determines which control plane node is "first" and which already have kubeadm state |
| 7b | `roles/kubernetes/control-plane/tasks/kubeadm-setup.yml` | Aggregates API server SANs, renders kubeadm init config, checks/regenerates apiserver certs, runs **`kubeadm init`** on the first control plane node |
| 7c | `roles/kubernetes/control-plane/tasks/kubeadm-secondary.yml` | For HA: runs **`kubeadm join --control-plane`** on secondary CPs (serialized, 3 retries each) |
| 7d | `roles/kubernetes/control-plane/tasks/kubeadm-etcd.yml` | When `etcd_deployment_type == 'kubeadm'`: configures etcd as static pods |
| 7e | `roles/kubernetes/control-plane/tasks/kubeadm-fix-apiserver.yml` | Fixes secondary apiserver endpoints post-join |
| 7f | `roles/kubernetes/control-plane/tasks/kubelet-fix-client-cert-rotation.yml` | Applies cert rotation fix if enabled |
| 7g | `roles/kubernetes/client/tasks/main.yml` | Copies admin kubeconfig to `~/.kube/config`; optionally fetches kubeconfig + kubectl to the Ansible controller host |
| 7h | `roles/kubernetes-apps/cluster_roles/tasks/main.yml` | Waits for `/healthz`, creates `kubespray:system:node` ClusterRoleBinding, creates `k8s-cluster-critical` PriorityClass |

---

## Phase 8 — Worker Nodes Join

**Role:** `roles/kubernetes/kubeadm/` · **Hosts:** `k8s_cluster`

| Step | Task file | What it does |
|------|-----------|-------------|
| 8a | `roles/kubernetes/kubeadm/tasks/main.yml` | Creates short-lived bootstrap token |
| 8b | `roles/kubernetes/kubeadm_common/tasks/main.yml` | Renders `kubeadm-client.conf` join config |
| 8c | `roles/kubernetes/kubeadm/tasks/main.yml` | Runs **`kubeadm join`** — workers join the cluster |
| 8d | `roles/kubernetes/kubeadm/tasks/main.yml` | Updates `kubelet.conf` and kube-proxy ConfigMap to point to correct LB endpoint |
| 8e | `roles/kubernetes/kubeadm/tasks/kubeadm_etcd_node.yml` | Extracts etcd certs onto worker nodes if needed by the CNI |

---

## Phase 9 — Node Labels, Taints & CNI

**Hosts:** `k8s_cluster`

| Step | Role / File | What it does |
|------|-------------|-------------|
| 9a | `roles/kubernetes/node-label/tasks/main.yml` | Applies GPU labels (`nvidia.com/gpu=true`) and per-node labels from inventory `node_labels` |
| 9b | `roles/kubernetes/node-taint/tasks/main.yml` | Applies custom taints from inventory |
| 9c | `roles/kubernetes-apps/common_crds/gateway_api/tasks/main.yml`<br>`roles/kubernetes-apps/common_crds/prometheus_operator_crds/tasks/main.yml` | Installs Gateway API CRDs and/or Prometheus Operator CRDs if enabled |
| 9d | `roles/network_plugin/cni/tasks/main.yml` | Copies base CNI binary bundle to `/opt/cni/bin` |
| 9e | CNI plugin (one of): | Installs the selected CNI plugin |
| | `roles/network_plugin/calico/tasks/main.yml` | Calico (via operator or raw manifests) |
| | `roles/network_plugin/cilium/tasks/main.yml` | Cilium (via Helm) |
| | `roles/network_plugin/flannel/tasks/main.yml` | Flannel DaemonSet |
| | `roles/network_plugin/kube-ovn/tasks/main.yml` | OVN/OVS |
| | `roles/network_plugin/kube-router/tasks/main.yml` | kube-router |
| | `roles/network_plugin/macvlan/tasks/main.yml` | macvlan |
| | `roles/network_plugin/custom_cni/tasks/main.yml` | User-supplied CNI manifests |
| 9f | `roles/network_plugin/multus/tasks/main.yml` | (optional) Installs Multus meta-CNI on top |

---

## Phase 10 — Optional: Calico Route Reflector

**Hosts:** `calico_rr`

| Role / File | What it does |
|-------------|-------------|
| `roles/network_plugin/calico/rr/tasks/main.yml` | Configures Calico BGP Route Reflector nodes — only when the `calico_rr` inventory group is populated |

---

## Phase 11 — Kubernetes Add-ons

**Hosts:** `kube_control_plane`

| Category | Role / File | Apps |
|----------|-------------|------|
| Cloud CCM | `roles/kubernetes-apps/external_cloud_controller/openstack/tasks/main.yml`<br>`roles/kubernetes-apps/external_cloud_controller/vsphere/tasks/main.yml`<br>`roles/kubernetes-apps/external_cloud_controller/hcloud/tasks/main.yml`<br>`roles/kubernetes-apps/external_cloud_controller/oci/tasks/main.yml`<br>`roles/kubernetes-apps/external_cloud_controller/huaweicloud/tasks/main.yml` | External Cloud Controller Managers |
| Network policy | `roles/kubernetes-apps/policy_controller/calico/tasks/main.yml` | Calico NetworkPolicy controller |
| Ingress | `roles/kubernetes-apps/ingress_controller/ingress_nginx/tasks/main.yml`<br>`roles/kubernetes-apps/ingress_controller/cert_manager/tasks/main.yml`<br>`roles/kubernetes-apps/ingress_controller/alb_ingress_controller/tasks/main.yml` | ingress-nginx, cert-manager, AWS ALB |
| Storage | `roles/kubernetes-apps/external_provisioner/local_volume_provisioner/tasks/main.yml`<br>`roles/kubernetes-apps/external_provisioner/local_path_provisioner/tasks/main.yml` | Local Volume & Local Path Provisioners |
| CSI Drivers | `roles/kubernetes-apps/csi_driver/cinder/tasks/main.yml`<br>`roles/kubernetes-apps/csi_driver/aws_ebs/tasks/main.yml`<br>`roles/kubernetes-apps/csi_driver/azuredisk/tasks/main.yml`<br>`roles/kubernetes-apps/csi_driver/gcp_pd/tasks/main.yml`<br>`roles/kubernetes-apps/csi_driver/vsphere/tasks/main.yml`<br>`roles/kubernetes-apps/csi_driver/upcloud/tasks/main.yml` | Cinder, EBS, Azure Disk, GCP PD, vSphere, UpCloud |
| DNS | `roles/kubernetes-apps/ansible/tasks/main.yml` | **CoreDNS** (primary + optional dual), **NodeLocal DNSCache** |
| Monitoring | `roles/kubernetes-apps/metrics_server/tasks/main.yml` | Metrics Server |
| UI | `roles/kubernetes-apps/ansible/tasks/main.yml` | Kubernetes Dashboard |
| LB | `roles/kubernetes-apps/metallb/tasks/main.yml` | MetalLB |
| GitOps | `roles/kubernetes-apps/argocd/tasks/main.yml` | ArgoCD |
| GPU | `roles/kubernetes-apps/container_engine_accelerator/nvidia_gpu/tasks/main.yml` | NVIDIA device plugin |
| Scheduling | `roles/kubernetes-apps/scheduler_plugins/tasks/main.yml`<br>`roles/kubernetes-apps/node_feature_discovery/tasks/main.yml` | Scheduler plugins, Node Feature Discovery |
| Package mgr | `roles/kubernetes-apps/helm/tasks/main.yml` | Helm binary |
| Registry | `roles/kubernetes-apps/registry/tasks/main.yml` | In-cluster Docker registry |
| CSR | `roles/kubernetes-apps/kubelet-csr-approver/` | Kubelet CSR auto-approver |

---

## Phase 12 — Final DNS Cutover

**Hosts:** `k8s_cluster`

| Role / File | What it does |
|-------------|-------------|
| `roles/kubernetes/preinstall/tasks/0060-resolvconf.yml`<br>`roles/kubernetes/preinstall/tasks/0061-systemd-resolved.yml`<br>`roles/kubernetes/preinstall/tasks/0062-networkmanager-unmanaged-devices.yml`<br>`roles/kubernetes/preinstall/tasks/0063-networkmanager-dns.yml` | Re-runs with `dns_late: true` — updates `/etc/resolv.conf` to point at the now-running **CoreDNS / NodeLocal DNS** endpoint. Deliberately deferred until DNS pods are running. |

---

## Complete Ordered Summary

```
0.  Preflight:     playbooks/boilerplate.yml
                   → playbooks/ansible_version.yml
                   → roles/dynamic_groups/
                   → roles/validate_inventory/
                   → roles/bastion-ssh-config/

1.  Bootstrap:     playbooks/internal_facts.yml
                   → roles/bootstrap_os/
                   → roles/network_facts/

2.  OS prep:       roles/kubernetes/preinstall/tasks/0010-swapoff.yml
                   → 0040-verify-settings.yml
                   → 0050-create_directories.yml
                   → 0060-006x-*.yml (early DNS)
                   → 0080-system-configurations.yml
                   → 0081-ntp-configurations.yml

3.  Runtime:       roles/container-engine/containerd/ (or cri-o/, cri-dockerd/)
                   + kata-containers/, gvisor/, crun/, youki/

4.  Downloads:     roles/download/tasks/main.yml
                   → prep_download.yml → prep_kubeadm_images.yml
                   → download_file.yml / download_container.yml

5.  etcd:          playbooks/install_etcd.yml
                   → roles/etcd/tasks/check_certs.yml
                   → gen_certs_script.yml → upd_ca_trust.yml
                   → install_host.yml → configure.yml → refresh_config.yml
                   → roles/etcdctl_etcdutl/

6.  kubelet:       roles/kubernetes/node/tasks/install.yml
                   → loadbalancer/kube-vip.yml / nginx-proxy.yml / haproxy.yml
                   → main.yml (kernel modules)
                   → kubelet.yml

7.  Control plane: roles/kubernetes/control-plane/tasks/define-first-kube-control.yml
                   → kubeadm-setup.yml (kubeadm init)
                   → kubeadm-secondary.yml (kubeadm join --control-plane)
                   → kubeadm-fix-apiserver.yml
                   → roles/kubernetes/client/
                   → roles/kubernetes-apps/cluster_roles/

8.  Workers:       roles/kubernetes/kubeadm/tasks/main.yml (kubeadm join)

9.  Post-join:     roles/kubernetes/node-label/
                   → roles/kubernetes/node-taint/
                   → roles/kubernetes-apps/common_crds/
                   → roles/network_plugin/cni/
                   → roles/network_plugin/<chosen-cni>/
                   → roles/network_plugin/multus/ (optional)

10. Calico RR:     roles/network_plugin/calico/rr/ (optional)

11. Add-ons:       roles/kubernetes-apps/external_cloud_controller/
                   → roles/kubernetes-apps/policy_controller/
                   → roles/kubernetes-apps/ingress_controller/
                   → roles/kubernetes-apps/external_provisioner/
                   → roles/kubernetes-apps/csi_driver/
                   → roles/kubernetes-apps/ansible/ (CoreDNS, Dashboard)
                   → roles/kubernetes-apps/metallb/
                   → roles/kubernetes-apps/argocd/
                   → roles/kubernetes-apps/metrics_server/
                   → roles/kubernetes-apps/helm/
                   → ... (other addons)

12. DNS cutover:   roles/kubernetes/preinstall/tasks/0060-006x-*.yml (dns_late=true)
```
