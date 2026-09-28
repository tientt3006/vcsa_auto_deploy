# Bộ công cụ tự động hóa triển khai và cấu hình VMware vCenter Server (VCSA Automation Toolkit)

Bộ công cụ mã nguồn mở, chuẩn hóa theo thiết kế dùng chung (generic) và tiêu chuẩn công nghiệp nhằm tự động hóa toàn diện vòng đời hạ tầng vSphere từ máy chủ VMware ESXi độc lập:
1. **Giai đoạn 1**: Khởi tạo nút mầm điều khiển (Ubuntu Automation Seed VM) bằng `govc` và đĩa cấu hình NoCloud `seed.iso`.
2. **Giai đoạn 2**: Thiết lập môi trường dịch vụ phân giải tên miền hai chiều (`dnsmasq`), quản lý tải ISO đa luồng (`aria2c`) và triển khai máy chủ quản trị trung tâm vCenter Server Appliance (VCSA) bằng công cụ dòng lệnh không giám sát (`vcsa-deploy CLI`).
3. **Giai đoạn 3**: Tự động hóa cấu hình ngày thứ hai (Day-2 Provisioning) bằng Terraform: Datacenter, VM Folders, Compute Cluster (DRS & HA), nạp ESXi Hosts, Distributed Switch (vDS) / Standard Switch (VSS), Port Groups (VLAN, Teaming, Shaping), Storage I/O Control (SIOC / SDRS), Content Library, và hệ thống phân quyền tùy biến (RBAC Custom Roles).

Toàn bộ công cụ được điều phối qua một tệp duy nhất (`run.sh`) tích hợp giao diện tương tác dòng lệnh (TUI Menu), bảo mật tuyệt đối các thông tin xác thực nhạy cảm trong bộ nhớ RAM, tách biệt hoàn toàn cấu hình biến giữa các giai đoạn và không hardcode bất kỳ tham số nào.

---

## 1. Cấu trúc thư mục kho mã nguồn

```text
vcsa_deploy/
|-- run.sh                             # Tệp khởi chạy duy nhất tích hợp giao diện TUI Menu điều phối 3 giai đoạn
|-- config.env.example                 # Tệp mẫu khai báo biến hạ tầng Giai đoạn 1 & 2 (Seed Node + VCSA Deploy)
|-- config.env                         # Tệp cấu hình thực tế Giai đoạn 1 & 2 (tự sinh, nằm trong .gitignore)
|-- .gitignore                         # Loại trừ cấu hình cục bộ, tệp nhạy cảm và trạng thái Terraform
|-- README.md                          # Tài liệu hướng dẫn vận hành kỹ thuật
|-- templates/
|   `-- embedded_vcs_on_esxi.json.tpl  # Tệp mẫu đặc tả cấu hình VCSA JSON cho vcsa-deploy
|-- terraform/                         # Bộ mã nguồn Terraform tự động hóa vCenter Day-2 (Độc lập 100%)
|   |-- versions.tf                    # Yêu cầu phiên bản Terraform >= 1.5 và vSphere Provider
|   |-- provider.tf                    # Khởi tạo vSphere Provider với SSL Insecure
|   |-- variables.tf                   # Khai báo toàn bộ biến đầu vào hạ tầng dạng Generic
|   |-- terraform.tfvars.example       # Tệp tham số mẫu chi tiết cho Giai đoạn 3 (chứa placeholder <...>)
|   |-- terraform.tfvars               # Tệp tham số thực tế (nằm trong .gitignore, người dùng tự điền)
|   |-- 01_datacenter_folders.tf       # Khởi tạo Datacenter & VM Folders phân cấp linh hoạt
|   |-- 02_cluster_ha_drs.tf           # Khởi tạo Compute Cluster (tùy chọn), DRS & HA Admission Control
|   |-- 03_esxi_hosts.tf               # Tự động quét SSL Thumbprint và nạp ESXi Host vào Cluster hoặc Datacenter
|   |-- 04_networking.tf               # Khởi tạo vDS hoặc Standard vSwitch, NetIOC v3, Port Groups (VLAN, Teaming, Shaping)
|   |-- 05_storage_content_library.tf  # Khởi tạo Datastore Cluster (SDRS/SIOC) & Content Library cục bộ
|   |-- 06_roles_permissions.tf        # Khởi tạo vai trò phân quyền tùy biến động (RBAC Custom Roles)
|   `-- outputs.tf                     # Đầu ra xuất Managed Object ID các tài nguyên
`-- lib/
    |-- common.sh                      # Thư viện dùng chung: logging, validate, bảo mật mật khẩu
    |-- 01_deploy_ubuntu_node.sh       # Module Giai đoạn 1: Tạo Ubuntu Seed VM qua govc + seed.iso
    |-- 02_setup_environment.sh        # Module Giai đoạn 2: Cài gói phụ trợ, thiết lập DNS dnsmasq
    |-- 03_deploy_vcsa.sh              # Module Giai đoạn 2: Tiền kiểm tra và cài đặt VCSA qua CLI
    |-- 04_health_check.sh             # Tiện ích: Kiểm tra mạng, cổng dịch vụ và phân giải DNS
    |-- 05_iso_manager.sh              # Tiện ích: Tải nhanh ISO đa luồng aria2c & duyệt thư mục
    `-- 06_terraform_vcsa_config.sh    # Module Giai đoạn 3: Điều phối thực thi Terraform Day-2 độc lập
```

---

## 2. Mô hình luồng vận hành ba giai đoạn

```text
+-----------------------------------------------------------------------------------------------+
| GIAI ĐOẠN 1: KHỞI TẠO NÚT MẦM ĐIỀU KHIỂN (BOOTSTRAP SEED NODE)                                |
| Cấu hình quản trị: 'config.env'                                                              |
| Thực thi tại: Máy trạm khởi tạo (Operator / Engineer Workstation)                              |
|                                                                                               |
| 1. Kỹ sư sao chép config.env.example thành config.env và điền thông số mạng ESXi/Ubuntu.      |
| 2. Thực thi './run.sh' -> Chọn mục [2]:                                                       |
|    - Tạo đĩa cấu hình NoCloud 'seed.iso' chứa IP tĩnh và mật khẩu máy ảo Ubuntu.              |
|    - Công cụ 'govc' import tệp OVA lên ESXi Datastore, gắn 'seed.iso' vào ổ CD-ROM ảo.        |
|    - Bật nguồn máy ảo Ubuntu Automation (Seed VM).                                            |
+-----------------------------------------------------------------------------------------------+
                                                |
                                                | Kỹ sư kết nối SSH và chuyển mã nguồn lên VM
                                                v
+-----------------------------------------------------------------------------------------------+
| GIAI ĐOẠN 2: TRIỂN KHAI VCENTER VÀ HẠ TẦNG (CORE APPLIANCE DEPLOYMENT)                         |
| Cấu hình quản trị: 'config.env'                                                              |
| Thực thi tại: Nút điều khiển (Automation Node / Ubuntu VM vừa tạo)                            |
|                                                                                               |
| 1. Kỹ sư kết nối SSH vào máy ảo Ubuntu mới tạo: 'ssh ubuntu@<UBUNTU_IP>'                      |
| 2. Thực thi './run.sh':                                                                       |
|    - Mục [3]: Cài đặt gói phụ trợ, giải phóng xung đột cổng 53 và chạy 'dnsmasq' nội bộ.      |
|    - Mục [4]/[5]: Chuẩn bị tệp ISO cài đặt VCSA (tải nhanh qua aria2c hoặc duyệt thư mục).   |
|    - Mục [6]: Tự động mount ISO, chạy precheck an toàn và cài đặt VCSA hoàn chỉnh qua CLI.    |
+-----------------------------------------------------------------------------------------------+
                                                |
                                                | vCenter Server Appliance hoạt động sẵn sàng
                                                v
+-----------------------------------------------------------------------------------------------+
| GIAI ĐOẠN 3: CẤU HÌNH TỰ ĐỘNG HẠ TẦNG VCENTER (TERRAFORM DAY-2 PROVISIONING)                  |
| Cấu hình quản trị: 'terraform/terraform.tfvars' (Độc lập hoàn toàn với config.env)            |
| Thực thi tại: Nút điều khiển (Automation Node) hoặc Máy trạm khởi tạo                          |
|                                                                                               |
| 1. Kỹ sư sao chép 'terraform/terraform.tfvars.example' -> 'terraform/terraform.tfvars'.      |
| 2. Khai báo các tham số hạ tầng linh hoạt (vDS hoặc Standard Switch, Port Groups, Roles...).  |
| 3. Thực thi './run.sh' -> Chọn mục [7] (Plan) hoặc [8] (Apply) hoặc [9] (Quản lý Terraform):   |
|    - Tự động kiểm tra công cụ Terraform (cài đặt nếu thiếu).                                  |
|    - Cơ chế kiểm tra lặp (Validation Loop): Quét placeholder <...>; yêu cầu điền hoàn tất.    |
|    - Thực thi 'terraform plan' / 'terraform apply':                                           |
|      * Tạo Datacenter & VM Folders phân cấp.                                                  |
|      * Tạo Compute Cluster, kích hoạt DRS và HA Admission Control (hoặc thêm Host trực tiếp). |
|      * Quét SSL Thumbprint và nạp các máy chủ ESXi Hosts vào quản lý.                         |
|      * Tạo vSphere Distributed Switch (vDS) kèm NetIOC v3 HOẶC Standard vSwitch trên Host.    |
|      * Cấu hình Port Groups (VLAN, Teaming & Failover, Traffic Shaping Ingress/Egress).       |
|      * Khởi tạo Datastore Cluster (Storage DRS & SIOC) và vSphere Content Library cục bộ.     |
|      * Thiết lập các vai trò quản trị phân quyền tùy biến động (RBAC Custom Roles).           |
+-----------------------------------------------------------------------------------------------+
```

---

## 3. Giao diện bảng điều khiển trung tâm (TUI Menu)

Khi khởi chạy `./run.sh`, giao diện menu phân cấp xuất hiện đầy đủ 3 giai đoạn:

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
  [4] Tải nhanh tệp ISO VCSA từ liên kết URL (Hỗ trợ đa luồng aria2c)
  [5] Quét và chọn tệp ISO từ thư mục chỉ định (Cập nhật config.env)
  [6] Tự động triển khai vCenter Server Appliance (VCSA) qua CLI
------------------------------------------------------------------------------
  GIAI ĐOẠN 3: CẤU HÌNH TỰ ĐỘNG HẠ TẦNG VCENTER (TERRAFORM DAY-2 PROVISIONING)
  [7] Lập kế hoạch cấu hình vCenter: Host, Cluster, vDS, RBAC (Terraform Plan)
  [8] Thực thi áp dụng cấu hình tự động toàn diện vCenter (Terraform Apply)
  [9] Quản lý chi tiết Terraform (Submenu cấu hình & Destroy tài nguyên)
------------------------------------------------------------------------------
  TIỆN ÍCH VÀ CHẨN ĐOÁN (UTILITIES & DIAGNOSTICS)
  [10] Kiểm tra sức khỏe, thông tuyến mạng và DNS (Health Check)
  [11] Quản lý và kiểm tra tệp ISO VCSA (Submenu chi tiết & Mount test)
  [12] Mở tệp cấu hình biến hạ tầng (Chỉnh sửa config.env)
------------------------------------------------------------------------------
  [0] Thoát chương trình (Exit)
==============================================================================
```

---

## 4. Phân định tệp cấu hình và tính linh hoạt (Generic)

### 4.1. Tệp `config.env` (Giai đoạn 1 & 2)
Chỉ chịu trách nhiệm phục vụ việc khởi tạo máy ảo Ubuntu điều khiển và cài đặt gói VCSA cơ sở:
- `ESXI_HOSTNAME`, `ESXI_USERNAME`, `ESXI_DATASTORE`: Thông tin máy chủ ESXi triển khai.
- `UBUNTU_VM_NAME`, `UBUNTU_OVA_PATH`, `UBUNTU_STATIC_IP`, `UBUNTU_GATEWAY`: Thông số máy ảo điều khiển.
- `VCSA_VM_NAME`, `VCSA_STATIC_IP`, `VCSA_GATEWAY`, `VCSA_FQDN`, `VCSA_ISO_PATH`: Thông số vCenter.
- `NTP_SERVERS`, `SSO_DOMAIN_NAME`: Thông số dịch vụ thời gian và danh tính.

### 4.2. Tệp `terraform/terraform.tfvars` (Giai đoạn 3 - Day-2 Provisioning)
Chịu trách nhiệm toàn bộ các cấu hình kiến trúc logic trên vCenter sau khi cài đặt thành công:
- **Tùy biến bộ chuyển mạch**: Cho phép lựa chọn tạo Distributed Switch (`create_vds = true/false`) hoặc chỉ tạo Standard vSwitch (`create_standard_vswitches = true/false`), hoặc cả hai.
- **Port Groups đa dạng**: Khai báo danh mục Port Groups với VLAN ID, chính sách Teaming & Failover, giới hạn băng thông Ingress/Egress Shaping và chính sách bảo mật cổng.
- **Cấu hình nâng cao**: NetIOC phiên bản 3, Storage I/O Control (ngưỡng trễ milli-giây SIOC), vSphere DRS (mức tự động hóa và ngưỡng di trú), vSphere HA (chính sách Admission Control, tỷ lệ phần trăm dự trữ CPU/RAM).
- **Thư mục máy ảo**: Khai báo danh sách tên thư mục tùy ý theo nhu cầu quản trị (`vm_folders`).
- **Phân quyền vai trò RBAC**: Tùy biến định nghĩa danh mục vai trò (`custom_roles`) với danh sách đặc quyền (privileges) chi tiết.
- **Máy chủ ESXi**: Khai báo danh sách các host (`esxi_hosts`) kèm cơ chế tự động quét SSL Thumbprint.
- **Cơ chế xác thực lặp (Validation Loop)**: Kịch bản quét định dạng giữ chỗ `<...>`. Nếu người dùng chưa điền xong, kịch bản sẽ liệt kê chính xác số dòng còn thiếu và hỗ trợ mở trình soạn thảo chỉnh sửa trực tiếp cho đến khi hoàn tất.

---

## 5. Tích hợp với kho mã nguồn tổng thể (auto_provision_configuration)

Kho mã nguồn `vcsa_deploy` này được chuẩn hóa kiến trúc mô-đun độc lập cao:
- Toàn bộ thư viện nằm gọn trong `lib/` với quy ước đặt tên và gọi hàm thống nhất.
- Không phụ thuộc vào đường dẫn tuyệt đối; tự động nhận diện thư mục gốc qua `$(dirname "${BASH_SOURCE[0]}")`.
- Có thể được tích hợp trực tiếp làm thư mục con `vcsa_deploy/` bên trong kho `auto_provision_configuration` và gọi qua kịch bản master `run.sh` của nền tảng mà không gây xung đột biến môi trường.
