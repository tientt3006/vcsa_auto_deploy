# Bộ công cụ tự động hóa triển khai VMware vCenter Server Appliance (VCSA Toolkit)

Bộ công cụ mã nguồn mở, đóng gói dùng chung (generic) được thiết kế theo tiêu chuẩn công nghiệp nhằm tự động hóa toàn diện quy trình khởi tạo trạm điều phối và triển khai máy ảo quản trị trung tâm vCenter Server Appliance (VCSA) trên máy chủ VMware ESXi độc lập (Standalone Host).

Công cụ hoạt động qua một tệp điều phối duy nhất (`run.sh`) tích hợp giao diện menu tương tác dòng lệnh (TUI), bảo mật tuyệt đối các thông tin xác thực nhạy cảm và không chứa bất kỳ dữ liệu định danh tĩnh nào trong mã nguồn.

---

## 1. Cấu trúc thư mục kho mã nguồn

```text
vcsa_deploy/
|-- run.sh                             # Tệp khởi chạy duy nhất tích hợp giao diện TUI Menu
|-- config.env.example                 # Tệp mẫu khai báo tham số hạ tầng (dùng chung)
|-- config.env                         # Tệp cấu hình thực tế (tự sinh, nằm trong .gitignore)
|-- .gitignore                         # Loại trừ cấu hình cục bộ và tệp nhạy cảm
|-- README.md                          # Tài liệu hướng dẫn vận hành kỹ thuật
|-- templates/
|   `-- embedded_vcs_on_esxi.json.tpl  # Tệp mẫu đặc tả cấu hình VCSA JSON cho vcsa-deploy
`-- lib/
    |-- common.sh                      # Thư viện dùng chung: logging, validate, bảo mật mật khẩu
    |-- 01_deploy_ubuntu_node.sh       # Module Giai đoạn 1: Tạo Ubuntu Seed VM qua govc + seed.iso
    |-- 02_setup_environment.sh        # Module Giai đoạn 2: Cài gói phụ trợ, thiết lập DNS dnsmasq
    |-- 03_deploy_vcsa.sh              # Module Giai đoạn 2: Tiền kiểm tra và cài đặt VCSA qua CLI
    `-- 04_health_check.sh             # Tiện ích: Kiểm tra mạng, cổng dịch vụ và phân giải DNS
```

---

## 2. Mô hình luồng vận hành hai giai đoạn

```text
+-----------------------------------------------------------------------------------------------+
| GIAI ĐOẠN 1: KHỞI TẠO NÚT MẦM ĐIỀU KHIỂN (BOOTSTRAP SEED NODE)                                |
| Thực thi tại: Máy trạm khởi tạo (Operator / Engineer Workstation)                              |
|                                                                                               |
| 1. Kỹ sư cài đặt hệ điều hành ESXi thủ công lên máy chủ vật lý, thiết lập IP quản trị.        |
| 2. Kỹ sư sao chép config.env.example thành config.env và khai báo thông số mạng.              |
| 3. Thực thi './run.sh' -> Chọn mục [2]:                                                       |
|    - Tạo đĩa cấu hình NoCloud 'seed.iso' chứa IP tĩnh và mật khẩu máy ảo Ubuntu.              |
|    - Công cụ 'govc' import tệp OVA lên ESXi Datastore, gắn 'seed.iso' vào ổ CD-ROM ảo.        |
|    - Bật nguồn máy ảo Ubuntu Automation (Seed VM).                                            |
+-----------------------------------------------------------------------------------------------+
                                                |
                                                | Kỹ sư kết nối SSH và chuyển mã nguồn lên VM
                                                v
+-----------------------------------------------------------------------------------------------+
| GIAI ĐOẠN 2: TRIỂN KHAI VCENTER VÀ HẠ TẦNG (CORE APPLIANCE DEPLOYMENT)                         |
| Thực thi tại: Nút điều khiển (Automation Node / Ubuntu VM vừa tạo)                            |
|                                                                                               |
| 1. Kỹ sư kết nối SSH vào máy ảo Ubuntu mới tạo: 'ssh ubuntu@<UBUNTU_IP>'                      |
| 2. Chuyển thư mục công cụ này lên máy ảo Ubuntu và chạy 'sudo ./run.sh'.                      |
| 3. Chọn mục [3]: Cài đặt các gói phụ thuộc, giải phóng cổng 53 và cấu hình 'dnsmasq'         |
|    đáp ứng yêu cầu phân giải DNS thuận/nghịch cho tên miền FQDN của VCSA (ví dụ: vcsa.int).  |
| 4. Chọn mục [4]: Tự động mount ISO VCSA, sinh tệp đặc tả JSON vào RAM disk (/dev/shm),        |
|    thực hiện tiền kiểm tra (precheck) và tiến hành cài đặt VCSA không giám sát.               |
+-----------------------------------------------------------------------------------------------+
```

---

## 3. Hướng dẫn sử dụng nhanh (Quick Start)

### Bước 1: Chuẩn bị tệp cấu hình biến
Trên máy trạm của kỹ sư, truy cập thư mục công cụ:
```bash
cd vcsa_deploy
cp config.env.example config.env
```
Mở tệp `config.env` bằng trình soạn thảo bất kỳ và điền đầy đủ các thông số hạ tầng thực tế (thay thế toàn bộ các mục `<...>`).

### Bước 2: Khởi động giao diện điều khiển TUI
Thực thi lệnh:
```bash
chmod +x run.sh
./run.sh
```

Menu chính sẽ xuất hiện:
```text
==============================================================================
   BỘ CÔNG CỤ TỰ ĐỘNG HÓA HẠ TẦNG VMWARE (VCSA AUTOMATION TOOLKIT)
==============================================================================
 Môi trường : Máy trạm khởi tạo (Operator Workstation)
 Cấu hình   : Hợp lệ (Sẵn sàng)
==============================================================================
  [1] Kiểm tra tính hợp lệ của cấu hình (Config Validation)
------------------------------------------------------------------------------
  GIAI ĐOẠN 1: KHỞI TẠO NÚT MẦM ĐIỀU KHIỂN (BOOTSTRAP SEED NODE)
  [2] Tự động tạo máy ảo Ubuntu Automation trên Standalone ESXi (Seed VM)
------------------------------------------------------------------------------
  GIAI ĐOẠN 2: TRIỂN KHAI VCENTER VÀ HẠ TẦNG (CORE APPLIANCE DEPLOYMENT)
  [3] Thiết lập môi trường và cấu hình dịch vụ DNS nội bộ (dnsmasq)
  [4] Tự động triển khai vCenter Server Appliance (VCSA) qua CLI
------------------------------------------------------------------------------
  TIỆN ÍCH VÀ CHẨN ĐOÁN (UTILITIES & DIAGNOSTICS)
  [5] Kiểm tra sức khỏe, thông tuyến mạng và DNS (Health Check)
  [6] Mở tệp cấu hình biến hạ tầng (Chỉnh sửa config.env)
------------------------------------------------------------------------------
  [0] Thoát chương trình (Exit)
==============================================================================
```

### Bước 3: Thực thi Giai đoạn 1 (Tạo máy ảo Ubuntu Seed VM)
- Nhập lựa chọn `2`.
- Nhập mật khẩu root của ESXi Host đích khi được hỏi.
- Đặt mật khẩu cho người dùng quản trị máy ảo Ubuntu.
- Hệ thống tự động đẩy tệp OVA, cấu hình IP tĩnh và bật nguồn máy ảo.

### Bước 4: Chuyển tiếp sang Giai đoạn 2 (Cài đặt VCSA)
1. Đăng nhập SSH vào máy ảo Ubuntu mới tạo:
   ```bash
   ssh ubuntu@<UBUNTU_STATIC_IP>
   ```
2. Chuyển thư mục mã nguồn và gắn tệp ISO VCSA (nếu để trên USB hoặc ổ đĩa mạng).
3. Chạy lệnh:
   ```bash
   sudo ./run.sh
   ```
4. Chọn mục `3` để cấu hình DNS nội bộ tự động.
5. Chọn mục `4` để tiến hành cài đặt tự động máy ảo VCSA lên ESXi.

---

## 4. Cơ chế bảo mật và an toàn dữ liệu

1. **Quản lý mật khẩu qua RAM disk (`/dev/shm`)**:
   - Toàn bộ mật khẩu chỉ tồn tại trong bộ nhớ RAM của phiên thực thi và được nhập qua giao diện ẩn (`read -s -p`).
   - Tệp cấu hình chứa thông tin đăng nhập phục vụ `vcsa-deploy` được tạo tại `/dev/shm/vcsa_deployment_spec_$$.json` với quyền hạn nghiêm ngặt `0600`.
   - Cơ chế bẫy tín hiệu ngắt (`trap EXIT INT TERM`) tự động thực thi lệnh `shred -u -z` xóa sạch tệp tạm và giải phóng các biến mật khẩu ngay khi script kết thúc hoặc bị hủy.

2. **Cơ chế rà quét Placeholder tự động**:
   - Script tự động quét tệp `config.env`. Nếu còn bất kỳ trường nào chứa định dạng `<...>` hoặc để trống các biến cốt lõi, tiến trình sẽ báo lỗi cụ thể số dòng và dừng lại để ngăn chặn việc thực thi sai thông số.

3. **Cơ chế tiền kiểm tra an toàn (Two-Step Precheck)**:
   - Quá trình cài đặt VCSA luôn chạy cờ `--precheck-only` trước để xác thực toàn bộ tài nguyên (RAM, Datastore, Network, DNS). Chỉ khi kiểm tra thành công và người dùng nhập xác nhận `Y`, lệnh cài đặt chính thức mới được kích hoạt.

---

## 5. Danh mục sự cố thường gặp (Troubleshooting)

| Hiện tượng | Nguyên nhân gốc rễ | Cách xử lý |
| :--- | :--- | :--- |
| `vim.fault.RestrictedVersion` | Máy chủ ESXi đang dùng bản quyền Free hoặc Evaluation hết hạn | Chạy `vim-cmd vimsvc/license --set <KEY>` gán key Enterprise Plus hợp lệ |
| `Failed to resolve hostname` | Thiếu bản ghi DNS hai chiều cho FQDN của VCSA | Chạy mục `[3]` trong menu để tự động kích hoạt `dnsmasq` trên máy ảo Ubuntu |
| `Insufficient datastore capacity` | Cấu hình máy ảo dùng Thick Provisioning | Đảm bảo mẫu cấu hình JSON sử dụng `"thin_disk_mode": true` |
| `govc: command not found` | Chưa cài đặt tiện ích govc trên máy trạm | Chọn `Y` khi script hỏi để tự động tải gói govc chính thức về `/usr/local/bin` |
