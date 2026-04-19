# Air-Gapped Requirements

Kubespray inventory: `mycluster`
Kubernetes version: `1.33.7`
CNI: Cilium `1.18.4`
CRI: containerd `2.1.5`
etcd: host binary (NOT container) — `etcd_deployment_type: host`
OS: Rocky Linux (RHEL family)
Architecture: `amd64`

---

## 1. Binaries & Archives

Tải về và host trên **Nexus Raw repository**.

| File | Source URL | Version |
|------|-----------|---------|
| `kubelet` | `https://dl.k8s.io/release/v1.33.7/bin/linux/amd64/kubelet` | 1.33.7 |
| `kubectl` | `https://dl.k8s.io/release/v1.33.7/bin/linux/amd64/kubectl` | 1.33.7 |
| `kubeadm` | `https://dl.k8s.io/release/v1.33.7/bin/linux/amd64/kubeadm` | 1.33.7 |
| `etcd-v3.5.25-linux-amd64.tar.gz` | `https://github.com/etcd-io/etcd/releases/download/v3.5.25/etcd-v3.5.25-linux-amd64.tar.gz` | 3.5.25 |
| `containerd-2.1.5-linux-amd64.tar.gz` | `https://github.com/containerd/containerd/releases/download/v2.1.5/containerd-2.1.5-linux-amd64.tar.gz` | 2.1.5 |
| `runc.amd64` | `https://github.com/opencontainers/runc/releases/download/v1.3.4/runc.amd64` | 1.3.4 |
| `cni-plugins-linux-amd64-v1.8.0.tgz` | `https://github.com/containernetworking/plugins/releases/download/v1.8.0/cni-plugins-linux-amd64-v1.8.0.tgz` | 1.8.0 |
| `crictl-v1.33.0-linux-amd64.tar.gz` | `https://github.com/kubernetes-sigs/cri-tools/releases/download/v1.33.0/crictl-v1.33.0-linux-amd64.tar.gz` | 1.33.0 |
| `nerdctl-2.1.6-linux-amd64.tar.gz` | `https://github.com/containerd/nerdctl/releases/download/v2.1.6/nerdctl-2.1.6-linux-amd64.tar.gz` | 2.1.6 |
| `cilium-linux-amd64.tar.gz` (CLI) | `https://github.com/cilium/cilium-cli/releases/download/v0.18.9/cilium-linux-amd64.tar.gz` | 0.18.9 |

> **Lưu ý etcd:** Do `etcd_deployment_type: host`, etcd chạy dưới dạng systemd service — cần binary archive, KHÔNG cần container image.

---

## 2. Container Images

Host trên **Nexus Docker hosted repository**.

### Core Kubernetes — `registry.k8s.io`

| Image | Tag |
|-------|-----|
| `registry.k8s.io/kube-apiserver` | `v1.33.7` |
| `registry.k8s.io/kube-controller-manager` | `v1.33.7` |
| `registry.k8s.io/kube-scheduler` | `v1.33.7` |
| `registry.k8s.io/kube-proxy` | `v1.33.7` |
| `registry.k8s.io/pause` | `3.10` |

### DNS — `registry.k8s.io`

| Image | Tag |
|-------|-----|
| `registry.k8s.io/coredns/coredns` | `v1.12.0` |
| `registry.k8s.io/dns/k8s-dns-node-cache` | `1.25.0` |
| `registry.k8s.io/cpa/cluster-proportional-autoscaler` | `v1.8.8` |

### Metrics Server — `registry.k8s.io`

| Image | Tag |
|-------|-----|
| `registry.k8s.io/metrics-server/metrics-server` | `v0.8.0` |

> **Lưu ý:** `metrics_server_enabled: true` được set trong `k8s-cluster.yml`, override giá trị `false` trong `addons.yml` (file k8s-cluster.yml được load sau theo thứ tự alphabet).

### Cilium CNI — `quay.io`

| Image | Tag |
|-------|-----|
| `quay.io/cilium/cilium` | `v1.18.4` |
| `quay.io/cilium/operator` | `v1.18.4` |

> **Lưu ý:** `cilium_enable_hubble: false` (mặc định) → KHÔNG cần các image hubble-relay, hubble-ui, certgen, cilium-envoy.

---

## 3. OS Packages (Rocky Linux / RHEL)

Cần có sẵn trong **local yum/dnf repository** (Nexus Yum proxy hoặc repo offline).

| Package | Lý do cần |
|---------|-----------|
| `conntrack` | Required by kube-proxy (RedHat family) |
| `container-selinux` | SELinux policy cho container runtime (từ appstream repo) |
| `ipvsadm` | Required vì `kube_proxy_mode: ipvs` |
| `socat` | Required trên tất cả node |
| `ebtables` | Required trên tất cả node |
| `libseccomp` | Required trên RedHat family |

> **Lưu ý:** `container-selinux` nằm trong RHEL/Rocky **appstream** repository — cần đảm bảo repo này có trong môi trường air-gapped.

---

## 4. Scripts

### Download tất cả binaries

```bash
#!/bin/bash
set -e
mkdir -p ./binaries

BASE_K8S="https://dl.k8s.io/release/v1.33.7/bin/linux/amd64"
BASE_GH="https://github.com"

curl -L -o binaries/kubelet       "$BASE_K8S/kubelet"
curl -L -o binaries/kubectl       "$BASE_K8S/kubectl"
curl -L -o binaries/kubeadm       "$BASE_K8S/kubeadm"

curl -L -o binaries/etcd-v3.5.25-linux-amd64.tar.gz \
  "$BASE_GH/etcd-io/etcd/releases/download/v3.5.25/etcd-v3.5.25-linux-amd64.tar.gz"
curl -L -o binaries/containerd-2.1.5-linux-amd64.tar.gz \
  "$BASE_GH/containerd/containerd/releases/download/v2.1.5/containerd-2.1.5-linux-amd64.tar.gz"
curl -L -o binaries/runc.amd64 \
  "$BASE_GH/opencontainers/runc/releases/download/v1.3.4/runc.amd64"
curl -L -o binaries/cni-plugins-linux-amd64-v1.8.0.tgz \
  "$BASE_GH/containernetworking/plugins/releases/download/v1.8.0/cni-plugins-linux-amd64-v1.8.0.tgz"
curl -L -o binaries/crictl-v1.33.0-linux-amd64.tar.gz \
  "$BASE_GH/kubernetes-sigs/cri-tools/releases/download/v1.33.0/crictl-v1.33.0-linux-amd64.tar.gz"
curl -L -o binaries/nerdctl-2.1.6-linux-amd64.tar.gz \
  "$BASE_GH/containerd/nerdctl/releases/download/v2.1.6/nerdctl-2.1.6-linux-amd64.tar.gz"
curl -L -o binaries/cilium-linux-amd64.tar.gz \
  "$BASE_GH/cilium/cilium-cli/releases/download/v0.18.9/cilium-linux-amd64.tar.gz"

echo "Done. Files saved to ./binaries/"
```

### Pull & push container images lên Nexus

```bash
#!/bin/bash
set -e
NEXUS_REGISTRY="nexus.example.com:5000"  # <-- thay bằng địa chỉ Nexus thực tế

IMAGES=(
  "registry.k8s.io/kube-apiserver:v1.33.7"
  "registry.k8s.io/kube-controller-manager:v1.33.7"
  "registry.k8s.io/kube-scheduler:v1.33.7"
  "registry.k8s.io/kube-proxy:v1.33.7"
  "registry.k8s.io/pause:3.10"
  "registry.k8s.io/coredns/coredns:v1.12.0"
  "registry.k8s.io/dns/k8s-dns-node-cache:1.25.0"
  "registry.k8s.io/cpa/cluster-proportional-autoscaler:v1.8.8"
  "registry.k8s.io/metrics-server/metrics-server:v0.8.0"
  "quay.io/cilium/cilium:v1.18.4"
  "quay.io/cilium/operator:v1.18.4"
)

for IMAGE in "${IMAGES[@]}"; do
  echo "Pulling $IMAGE..."
  docker pull "$IMAGE"
  TARGET="$NEXUS_REGISTRY/${IMAGE#*/}"
  docker tag "$IMAGE" "$TARGET"
  docker push "$TARGET"
  echo "Pushed: $TARGET"
done

echo "Done."
```
