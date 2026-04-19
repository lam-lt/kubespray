# Nexus Repository Setup

Tạo các Nexus repositories cần thiết để proxy/cache toàn bộ dependencies trong quá trình cài đặt Kubernetes, phục vụ cho deployment air-gapped sau này.

Nexus UI: `http://<NEXUS_IP>:8081`

---

## Bước 1 — Bật Docker Bearer Token Realm

**Security → Realms** → kéo `Docker Bearer Token Realm` sang cột Active → **Save**

---

## Bước 2 — Docker repos

### 2.1 Docker proxy repos

**Repository → Repositories → Create repository → `docker (proxy)`**

Tạo lần lượt 3 repos sau:

| Field | `docker-proxy-k8s` | `docker-proxy-quay` | `docker-proxy-hub` |
|-------|--------------------|---------------------|--------------------|
| Name | `docker-proxy-k8s` | `docker-proxy-quay` | `docker-proxy-hub` |
| HTTP port | — | — | — |
| Allow anonymous pull | ✓ | ✓ | ✓ |
| Remote storage | `https://registry.k8s.io` | `https://quay.io` | `https://registry-1.docker.io` |
| Docker Index | `Use proxy registry URL` | `Use proxy registry URL` | `Use Docker Hub` |

### 2.2 Docker hosted repo

**Create repository → `docker (hosted)`**

| Field | Value |
|-------|-------|
| Name | `docker-hosted` |
| HTTP port | `5000` |
| Allow anonymous pull | ✓ |

Dùng để push image thủ công nếu cần.

### 2.3 Docker group repo

**Create repository → `docker (group)`**

| Field | Value |
|-------|-------|
| Name | `docker-group` |
| HTTP port | `8082` |
| Allow anonymous pull | ✓ |
| Member repositories (theo thứ tự) | `docker-hosted` → `docker-proxy-k8s` → `docker-proxy-quay` → `docker-proxy-hub` |

> Port 8082 là endpoint duy nhất các nodes dùng để pull image.

---

## Bước 3 — Raw proxy repos

**Create repository → `raw (proxy)`**

| Field | `raw-proxy-k8s` | `raw-proxy-github` |
|-------|-----------------|--------------------|
| Name | `raw-proxy-k8s` | `raw-proxy-github` |
| Remote storage | `https://dl.k8s.io` | `https://github.com` |

- `raw-proxy-k8s`: dùng cho kubelet, kubectl, kubeadm
- `raw-proxy-github`: dùng cho etcd, containerd, runc, cni-plugins, crictl, nerdctl, cilium-cli

---

## Bước 4 — Yum proxy repos

**Create repository → `yum (proxy)`**

| Field | `yum-proxy-rocky-baseos` | `yum-proxy-rocky-appstream` |
|-------|--------------------------|------------------------------|
| Name | `yum-proxy-rocky-baseos` | `yum-proxy-rocky-appstream` |
| Remote storage | `https://dl.rockylinux.org/pub/rocky/9/BaseOS/x86_64/os/` | `https://dl.rockylinux.org/pub/rocky/9/AppStream/x86_64/os/` |
| Repodata Depth | `1` | `1` |

> `yum-proxy-rocky-appstream` bắt buộc vì `container-selinux` chỉ có trong AppStream repo.

---

## Tổng hợp

| Repo | Format | Type | Port |
|------|--------|------|------|
| `docker-proxy-k8s` | Docker | proxy | — |
| `docker-proxy-quay` | Docker | proxy | — |
| `docker-proxy-hub` | Docker | proxy | — |
| `docker-hosted` | Docker | hosted | 5000 |
| `docker-group` | Docker | group | **8082** |
| `raw-proxy-k8s` | Raw | proxy | 8081 |
| `raw-proxy-github` | Raw | proxy | 8081 |
| `yum-proxy-rocky-baseos` | Yum | proxy | 8081 |
| `yum-proxy-rocky-appstream` | Yum | proxy | 8081 |

---

## Bước tiếp theo

Sau khi tạo xong repos, cấu hình Kubespray để route traffic qua Nexus:

- **Container images** → xem `nexus-kubespray-config.md` (containerd registry mirrors)
- **Binaries** → override download URLs trong `group_vars`
- **OS packages** → cấu hình dnf repo trên các nodes trỏ vào Nexus Yum proxy
