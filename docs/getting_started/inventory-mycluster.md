# Cấu trúc `inventory/mycluster` trong Kubespray

Thư mục `inventory/mycluster` là nơi chứa toàn bộ cấu hình Ansible cho một cluster Kubernetes cụ thể. Đây là nơi người dùng khai báo **máy chủ nào thuộc về cluster** và **cluster đó được cấu hình như thế nào** — từ network plugin, container runtime, etcd, đến các add-on.

---

## Tổng quan cấu trúc thư mục

```
inventory/mycluster/
├── inventory.ini                        # Khai báo nodes và nhóm Ansible
└── group_vars/                          # Biến cấu hình theo nhóm
    ├── all/                             # Áp dụng cho TẤT CẢ nodes
    │   ├── all.yml                      # Cấu hình chung (proxy, NTP, LB, cert...)
    │   ├── etcd.yml                     # Cấu hình etcd
    │   ├── containerd.yml               # Cấu hình container runtime containerd
    │   ├── docker.yml                   # Cấu hình container runtime Docker
    │   ├── cri-o.yml                    # Cấu hình container runtime CRI-O
    │   ├── coreos.yml                   # Cấu hình đặc thù cho CoreOS/Flatcar
    │   ├── offline.yml                  # Cấu hình cài đặt offline (airgap)
    │   ├── aws.yml                      # Cấu hình cloud provider AWS
    │   ├── azure.yml                    # Cấu hình cloud provider Azure
    │   ├── gcp.yml                      # Cấu hình cloud provider GCP
    │   ├── openstack.yml                # Cấu hình cloud provider OpenStack
    │   ├── vsphere.yml                  # Cấu hình cloud provider vSphere
    │   ├── oci.yml                      # Cấu hình cloud provider Oracle Cloud
    │   ├── hcloud.yml                   # Cấu hình cloud provider Hetzner Cloud
    │   ├── huaweicloud.yml              # Cấu hình cloud provider Huawei Cloud
    │   └── upcloud.yml                  # Cấu hình cloud provider UpCloud
    └── k8s_cluster/                     # Áp dụng cho nhóm k8s_cluster
        ├── k8s-cluster.yml              # Cấu hình cốt lõi của Kubernetes cluster
        ├── addons.yml                   # Bật/tắt các add-on (Helm, Ingress, MetalLB...)
        ├── kube_control_plane.yml       # Resource reservation cho control plane
        ├── k8s-net-calico.yml           # Cấu hình CNI Calico
        ├── k8s-net-cilium.yml           # Cấu hình CNI Cilium
        ├── k8s-net-flannel.yml          # Cấu hình CNI Flannel
        ├── k8s-net-kube-ovn.yml         # Cấu hình CNI Kube-OVN
        ├── k8s-net-kube-router.yml      # Cấu hình CNI Kube-Router
        ├── k8s-net-macvlan.yml          # Cấu hình CNI Macvlan
        └── k8s-net-custom-cni.yml       # Cấu hình CNI tùy chỉnh
```

---

## 1. `inventory.ini` — Khai báo Nodes và Nhóm Ansible

Đây là file quan trọng nhất: nó xác định **máy chủ nào** tham gia cluster và **vai trò** của từng máy.

```ini
[kube_control_plane]
# node1 ansible_host=95.54.0.12  # ip=10.3.0.1 etcd_member_name=etcd1
# node2 ansible_host=95.54.0.13  # ip=10.3.0.2 etcd_member_name=etcd2
# node3 ansible_host=95.54.0.14  # ip=10.3.0.3 etcd_member_name=etcd3

[etcd:children]
kube_control_plane

[kube_node]
# node4 ansible_host=95.54.0.15  # ip=10.3.0.4
# node5 ansible_host=95.54.0.16  # ip=10.3.0.5
# node6 ansible_host=95.54.0.17  # ip=10.3.0.6
```

### Các nhóm Ansible

| Nhóm | Vai trò |
|------|---------|
| `kube_control_plane` | Chạy API Server, Controller Manager, Scheduler. Tối thiểu 1 node, khuyến nghị 3 node để HA. |
| `etcd` | Chạy etcd — cơ sở dữ liệu phân tán lưu trạng thái cluster. Ví dụ trên dùng `etcd:children` → etcd chạy cùng node với control plane (Stacked etcd). |
| `kube_node` | Worker nodes — nơi Pod của workload được lập lịch chạy. |

### Các biến quan trọng trong inventory

| Biến | Ý nghĩa |
|------|---------|
| `ansible_host` | Public IP hoặc hostname để Ansible SSH vào |
| `ip` | IP nội bộ để các thành phần Kubernetes liên lạc với nhau |
| `etcd_member_name` | Tên định danh node trong etcd cluster (chỉ cần cho node etcd) |
| `access_ip` | IP mà các node khác dùng để truy cập node này (hữu ích trên AWS/GCP) |

---

## 2. `group_vars/all/` — Biến áp dụng cho tất cả nodes

### `all.yml` — Cấu hình hệ thống chung

File cấu hình quan trọng nhất trong `group_vars/all/`. Các tham số chính:

**Thư mục và Load Balancer:**
```yaml
bin_dir: /usr/local/bin                     # Thư mục cài binary (kubectl, kubeadm...)
loadbalancer_apiserver_port: 6443           # Port của kube-apiserver
loadbalancer_apiserver_healthcheck_port: 8081
```

**Proxy và Certificate:**
```yaml
# http_proxy: ""
# https_proxy: ""
# cert_management: script   # "script" hoặc "none" (nếu dùng cert tự cấp)
```

**NTP:**
```yaml
ntp_enabled: false
ntp_manage_config: false
ntp_servers:
  - "0.pool.ntp.org iburst"
  ...
```

**Webhook Auth:**
```yaml
kube_webhook_token_auth: false
kube_webhook_token_auth_url_skip_tls_verify: false
```

**Các cấu hình đáng chú ý khác:**
- `access_ip`: override IP để các node truy cập nhau (quan trọng trên cloud)
- `loadbalancer_apiserver`: địa chỉ external LB cho HA cluster
- `loadbalancer_apiserver_localhost`: dùng nginx/haproxy local làm LB
- `no_proxy_exclude_workers`: loại worker node ra khỏi no_proxy
- `unsafe_show_logs: false`: ẩn log nhạy cảm khi chạy Ansible
- `allow_unsupported_distribution_setup: false`: chặn cài trên distro không hỗ trợ

---

### `etcd.yml` — Cấu hình etcd

```yaml
etcd_data_dir: /var/lib/etcd    # Thư mục lưu dữ liệu etcd
etcd_deployment_type: host      # "host" = cài trực tiếp, không dùng container
# container_manager: containerd  # Có thể override riêng cho etcd node
```

etcd là **trái tim** của Kubernetes — lưu toàn bộ trạng thái cluster. File này cho phép:
- Chỉ định thư mục data (nên đặt trên ổ SSD)
- Chọn cách triển khai: `host` (binary) hoặc qua container
- Dùng container runtime khác với phần còn lại của cluster

---

### `containerd.yml` — Cấu hình Container Runtime Containerd

Containerd là container runtime mặc định của Kubespray. File này cấu hình:

```yaml
# containerd_storage_dir: "/var/lib/containerd"
# containerd_default_runtime: "runc"
# containerd_snapshotter: "native"
```

Các tính năng chính có thể cấu hình:
- **Registry mirrors**: cấu hình mirror cho docker.io, gcr.io... để tăng tốc pull image
- **Registry auth**: thêm credentials cho private registry
- **Additional runtimes**: thêm Kata Containers hoặc gVisor
- **Debug**: log level, metrics endpoint

---

### `docker.yml` — Cấu hình Docker (runtime thay thế)

Cấu hình khi dùng Docker làm container runtime (thay vì containerd mặc định). Bao gồm storage driver, log driver, daemon options.

---

### `cri-o.yml` — Cấu hình CRI-O (runtime thay thế)

Cấu hình khi dùng CRI-O — container runtime nhẹ, tuân thủ OCI, thường dùng với OpenShift.

---

### `coreos.yml` — Cấu hình cho CoreOS/Flatcar Linux

Các thiết lập đặc thù khi triển khai trên CoreOS Container Linux hoặc Flatcar Linux (immutable OS cho containers).

---

### `offline.yml` — Cài đặt Offline/Airgap

File quan trọng cho môi trường **không có Internet**. Cho phép override URL tải về binary và image:

```yaml
# registry_host: "myprivateregistry.com"    # Private container registry
# files_repo: "http://myprivatehttpd"        # HTTP server chứa binary

# Override image repos:
# kube_image_repo: "{{ registry_host }}"
# gcr_image_repo: "{{ registry_host }}"
# github_image_repo: "{{ registry_host }}"

# Override download URLs cho từng binary:
# kubeadm_download_url: "{{ files_repo }}/dl.k8s.io/..."
# kubectl_download_url: "..."
# etcd_download_url: "..."
# cni_download_url: "..."
# helm_download_url: "..."
```

---

### Cloud Provider Files

Mỗi file cloud provider chứa cấu hình đặc thù để tích hợp Kubernetes với cloud tương ứng:

| File | Cloud Provider | Chức năng chính |
|------|---------------|-----------------|
| `aws.yml` | Amazon Web Services | EBS CSI driver, volume scheduling |
| `azure.yml` | Microsoft Azure | Azure Disk CSI, Azure CNI |
| `gcp.yml` | Google Cloud Platform | GCE persistent disk, GKE-compat |
| `openstack.yml` | OpenStack | Cinder CSI, Neutron networking |
| `vsphere.yml` | VMware vSphere | vSphere CSI, vCenter integration |
| `oci.yml` | Oracle Cloud Infrastructure | OCI block volume, LB |
| `hcloud.yml` | Hetzner Cloud | Hetzner CCM, CSI driver |
| `huaweicloud.yml` | Huawei Cloud | EVS volumes, ELB |
| `upcloud.yml` | UpCloud | UpCloud CSI |

> Tất cả các file này đều commented-out theo mặc định. Chỉ uncomment và điền thông tin khi triển khai trên cloud tương ứng.

---

## 3. `group_vars/k8s_cluster/` — Biến cấu hình Kubernetes Cluster

### `k8s-cluster.yml` — Cấu hình cốt lõi Kubernetes

Đây là file **cấu hình chính** của toàn bộ cluster. Các tham số quan trọng:

**Đường dẫn hệ thống:**
```yaml
kube_config_dir: /etc/kubernetes
kube_cert_dir: "{{ kube_config_dir }}/ssl"
kube_token_dir: "{{ kube_config_dir }}/tokens"
local_release_dir: "/tmp/releases"         # Thư mục tạm tải binary
credentials_dir: "{{ inventory_dir }}/credentials"
```

**Network:**
```yaml
kube_network_plugin: calico               # CNI plugin mặc định
kube_network_plugin_multus: false         # Multus (multi-NIC support)
kube_service_addresses: 10.233.0.0/18     # CIDR cho Kubernetes Services
kube_pods_subnet: 10.233.64.0/18          # CIDR cho Pods
kube_network_node_prefix: 24              # /24 per node = tối đa 254 pods/node
```

**API Server:**
```yaml
kube_apiserver_port: 6443
kube_proxy_mode: ipvs                     # ipvs, iptables hoặc nftables
kube_proxy_strict_arp: false              # Cần true cho MetalLB/kube-vip ARP mode
```

**DNS:**
```yaml
cluster_name: cluster.local               # DNS domain của cluster
dns_mode: coredns                         # coredns, manual, hoặc none
enable_nodelocaldns: true                 # NodeLocal DNSCache (tăng perf DNS)
nodelocaldns_ip: 169.254.25.10
```

**Container Runtime:**
```yaml
container_manager: containerd             # containerd, docker, hoặc crio
kata_containers_enabled: false
```

**Bảo mật:**
```yaml
kube_encrypt_secret_data: false           # Mã hóa Secret ở rest (etcd)
kube_api_anonymous_auth: true
kubernetes_audit: false                   # Audit log
auto_renew_certificates: false            # Tự gia hạn cert ngày đầu tháng
remove_anonymous_access: false            # Xóa anonymous RBAC binding của kubeadm
```

**Resource Management:**
```yaml
# kube_reserved: false                    # Reserve CPU/RAM cho k8s components
# system_reserved: true                   # Reserve CPU/RAM cho OS daemons
# eviction_hard: {}                       # Ngưỡng evict pod tránh OOM
```

---

### `addons.yml` — Add-on Components

Bật/tắt các thành phần mở rộng cài thêm vào cluster. Tất cả đều `false` theo mặc định:

| Add-on | Biến bật | Mô tả |
|--------|---------|-------|
| **Helm** | `helm_enabled: false` | Package manager cho Kubernetes |
| **Metrics Server** | `metrics_server_enabled: false` | Thu thập CPU/RAM metrics cho HPA |
| **Nginx Ingress** | `ingress_nginx_enabled: false` | Ingress controller |
| **Cert Manager** | `cert_manager_enabled: false` | Tự động cấp phát TLS cert |
| **MetalLB** | `metallb_enabled: false` | LoadBalancer cho bare-metal cluster |
| **ArgoCD** | `argocd_enabled: false` | GitOps CD tool |
| **Kube-VIP** | `kube_vip_enabled: false` | Virtual IP cho HA control plane |
| **Registry** | `registry_enabled: false` | Container registry nội bộ |
| **Local Path Provisioner** | `local_path_provisioner_enabled: false` | Dynamic PV provisioner dùng local disk |
| **Local Volume Provisioner** | `local_volume_provisioner_enabled: false` | Static PV provisioner cho local volumes |
| **Gateway API** | `gateway_api_enabled: false` | Kubernetes Gateway API CRDs |
| **Node Feature Discovery** | `node_feature_discovery_enabled: false` | Tự động label node theo hardware |

---

### `kube_control_plane.yml` — Resource Reservation cho Control Plane

Cấu hình dự trữ tài nguyên riêng cho control plane nodes (tách biệt với `all.yml`):

```yaml
# kube_memory_reserved: 512Mi    # RAM dự trữ cho k8s components
# kube_cpu_reserved: 200m        # CPU dự trữ cho k8s components
# system_memory_reserved: 256Mi  # RAM dự trữ cho OS
# system_cpu_reserved: 250m      # CPU dự trữ cho OS
```

---

### Network Plugin Files — Cấu hình CNI

Mỗi file cấu hình một CNI plugin. Chỉ file của plugin được chọn trong `k8s-cluster.yml` (`kube_network_plugin`) mới có hiệu lực.

#### `k8s-net-calico.yml` — Calico (mặc định)

```yaml
calico_pool_blocksize: 26          # Mỗi node được /26 = 64 Pod IPs
# calico_network_backend: vxlan    # "bird" (BGP), "vxlan", hoặc "none"
# calico_ipip_mode: 'Never'        # IP-in-IP encapsulation
# calico_vxlan_mode: 'Always'      # VXLAN encapsulation
# peer_with_router: false          # BGP peering với datacenter router
# calico_wireguard_enabled: false  # Mã hóa traffic giữa nodes
# calico_bpf_enabled: false        # eBPF data plane
# typha_enabled: false             # Typha daemon (cần cho cluster > 50 nodes)
```

Calico là CNI mặc định — hỗ trợ NetworkPolicy, BGP routing, và nhiều chế độ encapsulation.

#### `k8s-net-cilium.yml` — Cilium

```yaml
cilium_l2announcements: false      # L2 announcement (thay thế MetalLB)
# cilium_identity_allocation_mode: kvstore  # "crd" hoặc "kvstore"
# cilium_debug: false
```

Cilium dùng eBPF — hiệu năng cao, hỗ trợ NetworkPolicy nâng cao, observability tích hợp (Hubble).

#### `k8s-net-flannel.yml` — Flannel

```yaml
# flannel_backend_type: "vxlan"    # "vxlan", "host-gw", hoặc "wireguard"
# flannel_interface:               # Interface dùng cho Flannel
```

Flannel là CNI đơn giản nhất — không hỗ trợ NetworkPolicy, phù hợp môi trường dev/test.

#### `k8s-net-kube-ovn.yml` — Kube-OVN

CNI dựa trên Open vSwitch — hỗ trợ VPC, subnet per namespace, QoS, và traffic mirroring.

#### `k8s-net-kube-router.yml` — Kube-Router

CNI tích hợp routing (BGP), firewall (iptables), và load balancing (IPVS) trong một binary.

#### `k8s-net-macvlan.yml` — Macvlan

Cho phép Pod có địa chỉ MAC riêng — cần thiết cho workload cần truy cập trực tiếp vào physical network (không qua NAT).

#### `k8s-net-custom-cni.yml` — Custom CNI

Template để tích hợp CNI bên thứ ba không có trong danh sách hỗ trợ mặc định.

---

## 4. Luồng hoạt động của Ansible với Inventory

```
ansible-playbook -i inventory/mycluster/inventory.ini cluster.yml
                              │
                              ▼
             Ansible đọc inventory.ini
             → Xác định hosts và nhóm
                              │
                              ▼
             Ansible load group_vars/
             → all/*.yml      áp dụng cho tất cả nodes
             → k8s_cluster/*.yml  áp dụng cho kube_control_plane + kube_node
                              │
                              ▼
             Ansible chạy roles theo thứ tự
             → bootstrap-os → preinstall → container-engine
             → etcd → kubernetes/control-plane → network_plugin
             → kubernetes/node → addons
```

---

## 5. Thứ tự ưu tiên biến

Kubespray có nhiều tầng cấu hình. Thứ tự ưu tiên từ thấp đến cao:

```
roles/*/defaults/main.yml          (giá trị mặc định của role)
        ↓
inventory/mycluster/group_vars/    (cấu hình của người dùng — override ở đây)
        ↓
inventory/mycluster/host_vars/     (override cho từng host cụ thể)
        ↓
Extra vars (-e) khi chạy playbook  (ưu tiên cao nhất)
```

> **Nguyên tắc**: Không chỉnh sửa `roles/*/defaults/`. Chỉ override trong `group_vars/` của inventory để dễ upgrade Kubespray sau này.

---

## 6. Hướng dẫn tùy chỉnh nhanh

### Cài cluster cơ bản

1. Sửa `inventory.ini`: điền IP thực của các node
2. Sửa `group_vars/all/all.yml`: cấu hình proxy (nếu có), NTP
3. Sửa `group_vars/k8s_cluster/k8s-cluster.yml`: chọn CNI, CIDR
4. Chạy: `ansible-playbook -i inventory/mycluster/inventory.ini cluster.yml`

### Thêm Load Balancer cho HA

Trong `group_vars/all/all.yml`:
```yaml
loadbalancer_apiserver:
  address: 10.0.0.100   # VIP hoặc external LB IP
  port: 6443
```

### Cài offline (airgap)

1. Sửa `group_vars/all/offline.yml`
2. Điền `registry_host` và `files_repo`
3. Uncomment các `*_download_url` và `*_image_repo` tương ứng

### Bật MetalLB

Trong `group_vars/k8s_cluster/addons.yml`:
```yaml
metallb_enabled: true
metallb_speaker_enabled: true
```
Và trong `k8s-cluster.yml`:
```yaml
kube_proxy_strict_arp: true   # Bắt buộc cho MetalLB ARP mode
```
