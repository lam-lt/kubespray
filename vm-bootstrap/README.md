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
| nexus        | Nexus Repository   | 2   | 2G  | 20G  |

## Cloud-init

File [cloud-init.yml](cloud-init.yml) thực hiện các bước bootstrap sau khi VM khởi động:

- Tạo user `rocky` với sudo không cần mật khẩu
- Cài các gói cơ bản: `curl`, `wget`, `git`, `vim`, `python3`, v.v.
- Bật NTP (`chronyd`), set timezone UTC
- Disable root SSH login, chỉ dùng SSH key

SSH public key được nhúng sẵn trong `cloud-init.yml`. Cập nhật trường `ssh_authorized_keys` nếu cần dùng key khác.

## Cách chạy

### 1. Chạy tất cả VM cùng lúc

```bash
cd vm-boostrap/

# Truyền đường dẫn image qua argument
bash launch-vms.sh "file:///path/to/Rocky-9-GenericCloud-Base.latest.x86_64.qcow2"

# Hoặc truyền qua biến môi trường
CLOUD_IMAGE="file:///path/to/Rocky-9.qcow2" bash launch-vms.sh
```

> `CLOUD_IMAGE` là bắt buộc — script sẽ báo lỗi và thoát nếu không truyền vào.

Script sẽ lần lượt tạo 3 control-plane, 2 worker, và 1 nexus node.

### 2. Chạy từng VM thủ công

Thay `<name>`, `<cpu>`, `<mem>`, `<disk>` theo bảng cấu trúc VM ở trên:

```bash
multipass launch \
  --name <name> \
  --cpus <cpu> \
  --memory <mem> \
  --disk <disk> \
  --cloud-init cloud-init.yml \
  "file:///path/to/Rocky-9-GenericCloud-Base.latest.x86_64.qcow2"
```

Ví dụ tạo `k8s-cp1`:

```bash
multipass launch \
  --name k8s-cp1 \
  --cpus 2 \
  --memory 3G \
  --disk 15G \
  --cloud-init cloud-init.yml \
  "file:///path/to/Rocky-9-GenericCloud-Base.latest.x86_64.qcow2"
```

## Kiểm tra trạng thái VM

```bash
# Xem danh sách VM
multipass list

# Xem IP của từng VM
multipass info k8s-cp1

# SSH vào VM
multipass shell k8s-cp1
# hoặc
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

Kiểm tra sau khi purge:

```bash
multipass list
# Không còn VM nào trong danh sách
```

Nếu chỉ muốn xóa một VM cụ thể:

```bash
multipass delete <tên-vm>
multipass purge
```

## Bước tiếp theo

Sau khi các VM đã chạy, lấy IP của từng node:

```bash
multipass list
```

Cập nhật file inventory Kubespray (`inventory/mycluster/hosts.yaml`) với IP thực tế, sau đó chạy Kubespray để cài Kubernetes.
