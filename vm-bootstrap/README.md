# VM Bootstrap for Kubespray

Tạo các VM Rocky Linux 9 bằng Multipass để chạy cụm Kubernetes (3 control-plane + 2 worker) và 1 node Nexus Repository.

## Yêu cầu

- [Multipass](https://multipass.run/) đã cài đặt trên host
- File cloud image Rocky 9 ở dạng `file:///path/to/Rocky-9-GenericCloud-Base.latest.x86_64.qcow2` (truyền vào lúc chạy script)

## Cấu trúc VM

| Tên VM       | Vai trò            | CPU | RAM | Disk |
|--------------|--------------------|-----|-----|------|
| k8s-cp1      | Control Plane      | 2   | 3G  | 15G  |
| k8s-cp2      | Control Plane      | 2   | 3G  | 15G  |
| k8s-cp3      | Control Plane      | 2   | 3G  | 15G  |
| k8s-worker1  | Worker Node        | 2   | 2G  | 15G  |
| k8s-worker2  | Worker Node        | 2   | 2G  | 15G  |
| nexus        | Nexus Repository   | 4   | 8G  | 20G  |

> Nexus cần tối thiểu 8GB RAM — JVM heap được cấu hình ở `-Xms4g -Xmx4g`. Disk 20GB đủ cho 1 phiên bản Kubernetes (~7GB dữ liệu thực tế).

## Cấu trúc thư mục

```
vm-bootstrap/
├── ansible/
│   ├── inventory-nexus.yml   # Inventory cho nexus node
│   └── setup-nexus.yml       # Playbook cài Docker + Nexus Repository Manager
├── cloud-init.yml            # Bootstrap OS cho tất cả VM
├── launch-vms.sh             # Script tạo VM bằng Multipass
└── README.md
```

## Cloud-init

File [cloud-init.yml](cloud-init.yml) thực hiện các bước bootstrap sau khi VM khởi động:

- Tạo user `rocky` với sudo không cần mật khẩu
- Cài các gói cơ bản: `curl`, `wget`, `git`, `vim`, `python3`, v.v.
- Bật NTP (`chronyd`), set timezone UTC
- Disable root SSH login, chỉ dùng SSH key

SSH public key được nhúng sẵn trong `cloud-init.yml`. Cập nhật trường `ssh_authorized_keys` nếu cần dùng key khác.

## Cách chạy

### 1. Tạo tất cả VM

```bash
# Truyền đường dẫn image qua argument
bash vm-bootstrap/launch-vms.sh "file:///path/to/Rocky-9-GenericCloud-Base.latest.x86_64.qcow2"

# Hoặc truyền qua biến môi trường
CLOUD_IMAGE="file:///path/to/Rocky-9.qcow2" bash vm-bootstrap/launch-vms.sh
```

> `CLOUD_IMAGE` là bắt buộc — script sẽ báo lỗi và thoát nếu không truyền vào.

Script sẽ lần lượt tạo 3 control-plane, 2 worker, và 1 nexus node.

### 2. Cài Docker + Nexus lên nexus node

Sau khi VM nexus đã chạy, cập nhật `ansible_host` trong [ansible/inventory-nexus.yml](ansible/inventory-nexus.yml) với IP thực tế:

```bash
multipass info nexus | grep IPv4
```

Sau đó chạy playbook:

```bash
ansible-playbook -i vm-bootstrap/ansible/inventory-nexus.yml \
  --become \
  vm-bootstrap/ansible/setup-nexus.yml
```

Lấy mật khẩu admin Nexus sau khi khởi động xong (~1–2 phút):

```bash
ssh -i ~/.ssh/id_ed25519 rocky@<NEXUS_IP> "sudo cat /opt/sonatype-work/nexus3/admin.password"
```

Nexus UI: `http://<NEXUS_IP>:8081`

### 3. Chạy từng VM thủ công

Thay `<name>`, `<cpu>`, `<mem>`, `<disk>` theo bảng cấu trúc VM ở trên:

```bash
multipass launch \
  --name <name> \
  --cpus <cpu> \
  --memory <mem> \
  --disk <disk> \
  --cloud-init vm-bootstrap/cloud-init.yml \
  "file:///path/to/Rocky-9-GenericCloud-Base.latest.x86_64.qcow2"
```

## Kiểm tra trạng thái VM

```bash
# Xem danh sách VM và IP
multipass list

# Xem chi tiết một VM
multipass info k8s-cp1

# SSH vào VM
ssh rocky@<IP>
```

## Dọn dẹp

`multipass delete` đánh dấu VM để xóa nhưng chưa giải phóng disk. `multipass purge` mới thực sự thu hồi toàn bộ disk đã cấp phát.

```bash
# Bước 1: Đánh dấu xóa toàn bộ VM
for vm in k8s-cp1 k8s-cp2 k8s-cp3 k8s-worker1 k8s-worker2 nexus; do
  multipass delete "$vm"
done

# Bước 2: Thu hồi disk — không thể hoàn tác sau bước này
multipass purge
```

Nếu chỉ muốn xóa một VM cụ thể:

```bash
multipass delete <tên-vm> && multipass purge
```

## Bước tiếp theo

Sau khi các VM đã chạy, lấy IP của từng node:

```bash
multipass list
```

Cập nhật file `inventory/mycluster/hosts.yml` với IP thực tế, sau đó chạy Kubespray để cài Kubernetes.
