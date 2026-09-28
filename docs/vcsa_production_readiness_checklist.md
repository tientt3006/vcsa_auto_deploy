# Danh mục kiểm tra và cấu hình chuẩn hóa VMware vCenter Server (VCSA Production Readiness Checklist)

Tài liệu này cung cấp danh mục toàn diện các tiêu chuẩn kỹ thuật bắt buộc để đưa hệ thống VMware vCenter Server Appliance (VCSA) và hạ tầng ảo hóa VMware vSphere từ trạng thái mới triển khai lên mức sẵn sàng vận hành chính thức trong môi trường doanh nghiệp (Enterprise Production).

Mỗi hạng mục cấu hình được phân loại chi tiết theo mức độ ưu tiên, cơ chế kỹ thuật và khả năng tự động hóa:
- **Tự động hóa hoàn toàn (Automated):** Có thể thực thi 100% không giám sát thông qua Terraform, Ansible, vCenter REST API hoặc CLI script.
- **Bán tự động (Semi-Automated):** Yêu cầu tương tác trung gian (như ký chứng chỉ CA, phê duyệt tài khoản, hoặc liên kết hệ thống ngoài).
- **Thủ công (Manual):** Phụ thuộc vào đấu nối vật lý, cấu hình thiết bị phần cứng ngoài (Switch, Router, Storage SAN) hoặc thao tác xác nhận an toàn.

---

## 1. Bảng tổng hợp các phân hệ cấu hình Production

| Mã phân hệ | Tên phân hệ cấu hình | Số lượng hạng mục | Mức độ tự động hóa khả thi |
| :---: | :--- | :---: | :--- |
| **SEC** | Định danh, bảo mật và siết chặt an toàn (Identity & Hardening) | 7 | Tự động hóa 70% (Bán tự động phần CA) |
| **NET** | Mạng chuyển mạch ảo và bảo mật cổng (Virtual Networking) | 6 | Tự động hóa 100% qua Terraform |
| **STO** | Hiệu năng lưu trữ, đa đường truyền và SIOC (Storage Optimization) | 6 | Tự động hóa 85% qua Terraform & CLI |
| **HA-DRS** | Điều phối tài nguyên và sẵn sàng cao (Cluster Compute & HA/DRS) | 5 | Tự động hóa 100% qua Terraform |
| **MON** | Giám sát, nhật ký và cảnh báo sự cố (Logging & Monitoring) | 5 | Tự động hóa 80% qua API & PowerCLI |
| **BKP** | Quản trị sao lưu và khôi phục thảm họa (Backup & Disaster Recovery) | 4 | Tự động hóa 75% qua VAMI REST API |
| **LCM** | Vòng đời phần mềm và cập nhật phần cứng (vLCM & Maintenance) | 3 | Tự động hóa 65% qua vLCM Image API |

---

## 2. Chi tiết các hạng mục kiểm tra kỹ thuật (Checklist Specifications)

### Phân hệ 1: Định danh, bảo mật và siết chặt hệ thống (Security & Hardening)

#### SEC-01: Tích hợp nguồn định danh tập trung (Active Directory over LDAPS / OIDC)
- **Mục đích:** Vô hiệu hóa việc sử dụng tài khoản cục bộ dùng chung (`administrator@vsphere.local`). Toàn bộ kỹ sư vận hành phải đăng nhập bằng tài khoản cá nhân định danh qua máy chủ thư mục doanh nghiệp.
- **Thông số kỹ thuật:**
  - Cổng dịch vụ: TCP 636 (LDAPS) kèm chứng chỉ Root CA nội bộ.
  - Phân quyền theo nhóm bảo mật Active Directory (AD Security Groups) gán vào các vai trò RBAC của vSphere.
- **Khả năng tự động hóa:** **Bán tự động (Semi-Automated)**.
  - *Giải thích:* Quá trình nạp chứng chỉ CA và cấu hình Identity Source có thể tự động qua vCenter REST API hoặc PowerCLI (`New-LDAPIdentitySource`), nhưng cần chuẩn bị sẵn tệp chứng chỉ PEM của hệ thống PKI doanh nghiệp.

#### SEC-02: Thay thế chứng chỉ số Machine SSL bằng chứng chỉ CA doanh nghiệp
- **Mục đích:** Loại bỏ chứng chỉ tự ký mặc định của VMware Certificate Authority (VMCA), ngăn chặn tấn công giả mạo (Man-in-the-Middle) và loại bỏ cảnh báo chứng chỉ không tin cậy trên trình duyệt.
- **Thông số kỹ thuật:** Khởi tạo yêu cầu ký chứng chỉ (CSR) với độ dài khóa RSA 2048-bit hoặc 4096-bit, SHA-256, nạp tệp chứng chỉ do Enterprise CA ký vào kho lưu trữ Machine SSL.
- **Khả năng tự động hóa:** **Bán tự động (Semi-Automated)**.
  - *Giải thích:* Có thể tự động tạo CSR và nạp chứng chỉ qua tiện ích dòng lệnh `/usr/lib/vmware-vmca/bin/certificate-manager`, nhưng bước ký chứng chỉ cần cơ quan cấp phát chứng chỉ (CA) phê duyệt.

#### SEC-03: Khóa quyền truy cập dịch vụ SSH trên VCSA và ESXi Host
- **Mục đích:** Triệt tiêu bề mặt tấn công qua giao thức đầu cuối. Mọi thao tác quản trị phải được kiểm soát và ghi vết qua vSphere API / vSphere Client.
- **Thông số kỹ thuật:**
  - VCSA: Thiết lập `Access.SSH = false` trong cấu hình hệ thống VAMI.
  - ESXi Host: Tắt dịch vụ `TSM-SSH` (`vim-cmd hostsvc/enable_ssh false`).
  - Thiết lập thời gian chờ thoát phiên nhàn rỗi (Shell Timeout) = 900 giây (15 phút).
- **Khả năng tự động hóa:** **Tự động hóa hoàn toàn (Automated)**.
  - *Công cụ:* Ansible (`vmware_host_service_manager`), PowerCLI (`Set-VMHostService`), hoặc REST API.

#### SEC-04: Kích hoạt chế độ khóa nghiêm ngặt trên ESXi (Lockdown Mode)
- **Mục đích:** Chặn hoàn toàn việc đăng nhập trực tiếp của quản trị viên vào từng máy chủ ESXi thông qua giao diện DCUI (Direct Console User Interface) hoặc Web Host Client, buộc mọi lệnh quản trị phải thông qua vCenter.
- **Thông số kỹ thuật:** Chuyển trạng thái sang `lockdownMode = "lockdownNormal"` hoặc `"lockdownStrict"`. Khai báo danh sách tài khoản ngoại lệ (Exception Users) nếu có các agent phần cứng đặc thù.
- **Khả năng tự động hóa:** **Tự động hóa hoàn toàn (Automated)**.
  - *Công cụ:* Terraform (`vsphere_host.lockdown`), PowerCLI (`Set-VMHost -LockdownMode Normal`).

#### SEC-05: Khóa các phiên bản giao thức mã hóa yếu (TLS Hardening)
- **Mục đích:** Tuân thủ các tiêu chuẩn an toàn thông tin (PCI-DSS, ISO 27001), ngăn chặn việc khai thác lỗ hổng trong các giao thức mã hóa cũ.
- **Thông số kỹ thuật:** Chạy công cụ `vSphere TLS Configuration Utility` (`tls-configurator.sh`) trên VCSA để khóa toàn bộ TLS 1.0 và TLS 1.1, chỉ cho phép TLS 1.2 và TLS 1.3 trên tất cả các cổng (443, 902, 5480, 8084).
- **Khả năng tự động hóa:** **Tự động hóa hoàn toàn (Automated)**.
  - *Công cụ:* Script CLI thực thi từ xa qua SSH trước khi tắt SSH.

#### SEC-06: Vô hiệu hóa chương trình cải thiện trải nghiệm khách hàng (CEIP)
- **Mục đích:** Ngăn chặn việc máy chủ vCenter định kỳ đóng gói và gửi dữ liệu đo kiểm (telemetry) ra ngoài Internet, đặc biệt quan trọng trong các hạ tầng cô lập (Air-gapped) hoặc dữ liệu nhạy cảm.
- **Thông số kỹ thuật:** Thiết lập cờ `ceip_status = false` qua API `com.vmware.cis.telemetry.c11n`.
- **Khả năng tự động hóa:** **Tự động hóa hoàn toàn (Automated)**.
  - *Công cụ:* vCenter REST API hoặc PowerCLI.

#### SEC-07: Phân định vai trò quản trị tùy biến chi tiết (Custom RBAC Roles)
- **Mục đích:** Áp dụng nguyên tắc đặc quyền tối thiểu (Least Privilege). Không gán vai trò `Administrator` toàn quyền cho các nhóm kỹ sư vận hành hoặc hệ thống tích hợp (CI/CD, Backup).
- **Thông số kỹ thuật:** Tạo các vai trò độc lập: `DevOps-Provisioner`, `Backup-Operator`, `Network-Admin`, `Audit-ReadOnly` với danh mục đặc quyền chính xác.
- **Khả năng tự động hóa:** **Tự động hóa hoàn toàn (Automated)**.
  - *Công cụ:* Đã tích hợp sẵn trong bộ công cụ qua Terraform resource `vsphere_role`.

---

### Phân hệ 2: Mạng chuyển mạch ảo và an toàn cổng mạng (Virtual Networking)

#### NET-01: Phân tách vùng mạng lưu lượng độc lập (Network Segmentation)
- **Mục đích:** Cách ly hoàn toàn các luồng dữ liệu khác nhau để tránh nghẽn băng thông và ngăn chặn tấn công leo thang giữa các vùng mạng.
- **Thông số kỹ thuật:** Tối thiểu 4 VLAN độc lập:
  1. *Management Network (VLAN riêng):* MTU 1500, có Default Gateway.
  2. *vMotion Network (VLAN riêng):* MTU 9000 (Jumbo Frames), không Default Gateway (cùng lớp L2).
  3. *Storage Network (VLAN riêng cho iSCSI/NFS):* MTU 9000, không Default Gateway.
  4. *VM Workload Networks (Nhiều VLAN):* Gán thẻ VLAN Tagging (1 - 4094).
- **Khả năng tự động hóa:** **Tự động hóa hoàn toàn (Automated)**.
  - *Công cụ:* Đã tích hợp sẵn qua Terraform `vsphere_distributed_port_group`.

#### NET-02: Kích hoạt Multi-NIC vMotion
- **Mục đích:** Nhân đôi hoặc nhân bốn băng thông di trú máy ảo bằng cách cho phép tiến trình vMotion sử dụng đồng thời nhiều card mạng vật lý khác nhau.
- **Thông số kỹ thuật:** Tạo 2 cổng VMkernel (`vmk1`, `vmk2`) gán nhãn dịch vụ vMotion, mỗi cổng gán một Uplink hoạt động chính riêng biệt (`vmk1` dùng `vmnic1` Active, `vmk2` dùng `vmnic2` Active).
- **Khả năng tự động hóa:** **Tự động hóa hoàn toàn (Automated)**.
  - *Công cụ:* PowerCLI (`New-VMHostNetworkAdapter`) hoặc Ansible.

#### NET-03: Cấu hình an toàn cổng mạng trên vDS (Port Security Policies)
- **Mục đích:** Ngăn chặn các kỹ thuật tấn công hạ tầng mạng ảo: MAC Spoofing, Forged Transmits và nghe lén lưu lượng giữa các máy ảo.
- **Thông số kỹ thuật:**
  - `allow_promiscuous = false`
  - `allow_mac_changes = false`
  - `allow_forged_transmits = false`
- **Khả năng tự động hóa:** **Tự động hóa hoàn toàn (Automated)**.
  - *Công cụ:* Đã tích hợp sẵn qua Terraform `vsphere_distributed_port_group`.

#### NET-04: Cấu hình kiểm soát chất lượng dịch vụ mạng (Network I/O Control - NetIOC v3)
- **Mục đích:** Đảm bảo khi xảy ra nghẽn băng thông trên card mạng vật lý 10GbE/25GbE chia sẻ, các luồng lưu lượng trọng yếu (Management, Storage, vMotion) không bị chiếm đoạt tài nguyên bởi các máy ảo thông thường.
- **Thông số kỹ thuật:** Kích hoạt NetIOC v3 trên vDS. Thiết lập tỷ lệ dự trữ (Shares/Reservations) chuẩn:
  - Virtual Machine: High (Shares: 100)
  - iSCSI/NFS Storage: High (Shares: 100)
  - vMotion: Low (Shares: 25)
  - Management: Normal (Shares: 50)
- **Khả năng tự động hóa:** **Tự động hóa hoàn toàn (Automated)**.
  - *Công cụ:* Đã tích hợp cờ `enable_netioc = true` trên Terraform `vsphere_distributed_virtual_switch`.

#### NET-05: Kiểm soát lưu lượng băng thông cổng (Traffic Shaping)
- **Mục đích:** Ngăn chặn tình trạng một máy ảo chiếm dụng toàn bộ thông lượng cổng Uplink bằng cách áp đặt trần băng thông trung bình (Average Bandwidth), băng thông đỉnh (Peak Bandwidth) và dung lượng truyền bùng nổ (Burst Size).
- **Thông số kỹ thuật:** Cấu hình Ingress và Egress Shaping trên các Distributed Port Groups phục vụ môi trường Dev/Staging hoặc ứng dụng không ưu tiên.
- **Khả năng tự động hóa:** **Tự động hóa hoàn toàn (Automated)**.
  - *Công cụ:* Đã tích hợp sẵn trong tham số `vds_portgroups` của Terraform.

#### NET-06: Cấu hình tính năng Switch vật lý bảo vệ máy ảo (PortFast & BPDU Guard)
- **Mục đích:** Tránh việc cây cầu Spanning Tree (STP) mất 30-50 giây chuyển trạng thái khi cổng mạng kết nối, làm ngắt liên lạc máy ảo; đồng thời chống loop mạng nếu máy ảo gửi gói tin BPDU.
- **Thông số kỹ thuật:** Kích hoạt `spanning-tree portfast trunk` (Cisco) hoặc `edge port` và `spanning-tree bpduguard enable` trên toàn bộ cổng switch vật lý đấu vào ESXi.
- **Khả năng tự động hóa:** **Thủ công / Bán tự động (Manual / External Ansible)**.
  - *Giải thích:* Thao tác này thuộc hạ tầng thiết bị mạng vật lý ngoài tầm kiểm soát của vSphere API.

---

### Phân hệ 3: Hiệu năng lưu trữ và đa đường truyền (Storage Optimization)

#### STO-01: Chuyển đổi chính sách đa đường truyền SAN sang Round Robin (PSP)
- **Mục đích:** Tối ưu hóa hiệu năng đọc/ghi I/O trên hệ thống lưu trữ SAN (iSCSI, FC, NVMe-oF). Thay thế chính sách mặc định `Fixed` (chỉ dùng 1 đường) bằng `Round Robin` (cân bằng tải đều qua toàn bộ card HBA/NIC).
- **Thông số kỹ thuật:**
  - SATP Rule: Gán `VMW_PSP_RR` cho thiết bị lưu trữ.
  - Chuyển mạch đường truyền theo số lượng I/O: Đặt `iops=1` (thay vì 1000 mặc định).
  ```bash
  esxcli storage nmp satp setbootpath --satp VMW_SATP_ALUA --psp VMW_PSP_RR
  ```
- **Khả năng tự động hóa:** **Tự động hóa hoàn toàn (Automated)**.
  - *Công cụ:* Ansible (`community.vmware.vmware_host_storage`) hoặc lệnh CLI tự động qua SSH/PowerCLI.

#### STO-02: Phân vùng lưu trữ nhật ký hệ thống bền vững (Persistent Scratch Partition)
- **Mục đích:** Khi ESXi cài đặt trên thẻ nhớ SD hoặc USB, thư mục `/scratch` nằm trên bộ nhớ tạm (RAM disk). Nếu máy chủ bị lỗi màn hình tím (PSOD) hoặc khởi động lại, toàn bộ log chẩn đoán sự cố sẽ bị mất sạch.
- **Thông số kỹ thuật:** Trỏ tham số nâng cao `Syslog.global.logDir` về một thư mục chỉ định trên phân vùng VMFS Datastore dùng chung: `[Datastore_Name]/scratch/log/<hostname>`.
- **Khả năng tự động hóa:** **Tự động hóa hoàn toàn (Automated)**.
  - *Công cụ:* PowerCLI (`Set-VMHostAdvancedConfiguration`) hoặc Ansible.

#### STO-03: Kích hoạt Storage I/O Control (SIOC) và Storage DRS (SDRS)
- **Mục đích:** Ngăn ngừa hiện tượng máy ảo gây nghẽn hàng đợi (Noisy Neighbor). Khi độ trễ trung bình của Datastore vượt ngưỡng (15ms - 30ms), SIOC sẽ tự động điều tiết hàng đợi theo tỷ lệ Shares của từng máy ảo.
- **Thông số kỹ thuật:** Gom các Datastore vào Datastore Cluster, bật SDRS fullyAutomated và thiết lập ngưỡng độ trễ trần `sdrs_io_latency_threshold = 15`.
- **Khả năng tự động hóa:** **Tự động hóa hoàn toàn (Automated)**.
  - *Công cụ:* Đã tích hợp sẵn trong cấu hình Terraform `vsphere_datastore_cluster`.

#### STO-04: Cấu hình thu hồi dung lượng đĩa tự động (Automatic UNMAP)
- **Mục đích:** Khi người dùng xóa dữ liệu hoặc xóa máy ảo trên VMFS Datastore cấp phát mỏng (Thin Provisioning), các khối dữ liệu rác không tự giải phóng về cho SAN Storage nếu không có lệnh UNMAP.
- **Thông số kỹ thuật:** Bật tính năng SCSI UNMAP với mức ưu tiên `Priority: Low` (tốc độ xử lý từ 25MB/s đến 100MB/s) trên toàn bộ VMFS-6 Datastores.
- **Khả năng tự động hóa:** **Tự động hóa hoàn toàn (Automated)**.
  - *Công cụ:* Mặc định được kích hoạt tự động trên các Datastore định dạng VMFS-6.

#### STO-05: Cấu hình trích xuất lỗi hạt nhân qua mạng (Network Core Dump / Netdump)
- **Mục đích:** Đảm bảo khi ESXi gặp lỗi sập hệ điều hành nghiêm trọng (Purple Screen of Death - PSOD), tệp crash dump được gửi trực tiếp qua mạng về dịch vụ VMware Core Dump Collector trên vCenter để kỹ sư phân tích nguyên nhân gốc rễ (RCA).
- **Thông số kỹ thuật:**
  ```bash
  esxcli system coredump network set --interface-name vmk0 --server-ipv4 <VCSA_IP> --server-port 6500
  esxcli system coredump network set --enable true
  ```
- **Khả năng tự động hóa:** **Tự động hóa hoàn toàn (Automated)**.
  - *Công cụ:* PowerCLI, Ansible hoặc Host Profile.

#### STO-06: Khởi tạo thư viện nội dung tập trung (Content Library)
- **Mục đích:** Chuẩn hóa việc phân phối tệp mẫu máy ảo (VM Templates, OVF/OVA) và tệp ảnh đĩa cài đặt (ISO Images) đồng bộ tới toàn bộ các cụm máy chủ trong hệ thống.
- **Thông số kỹ thuật:** Khởi tạo Content Library cục bộ được lưu trữ trên Datastore dùng chung có dung lượng lớn.
- **Khả năng tự động hóa:** **Tự động hóa hoàn toàn (Automated)**.
  - *Công cụ:* Đã tích hợp sẵn trong cấu hình Terraform `vsphere_content_library`.

---

### Phân hệ 4: Điều phối tài nguyên và sẵn sàng cao (Compute, HA & DRS)

#### HA-01: Cấu hình kiểm soát tài nguyên dự phòng HA (Admission Control Policy)
- **Mục đích:** Ngăn chặn việc máy ảo bị quá tải hoặc không thể khởi động lại khi một máy chủ vật lý trong cụm gặp sự cố phần cứng.
- **Thông số kỹ thuật:**
  - Lựa chọn chính sách: `Resource Percentage`.
  - Thiết lập tỷ lệ dự trữ: Nếu cụm có 4 Hosts, đặt dự phòng 25% CPU và 25% RAM (tương đương dung lượng của đúng 1 Host chịu lỗi `Host Failure Tolerance = 1`).
- **Khả năng tự động hóa:** **Tự động hóa hoàn toàn (Automated)**.
  - *Công cụ:* Đã tích hợp sẵn trong cấu hình Terraform `vsphere_compute_cluster`.

#### HA-02: Cấu hình kênh giám sát nhịp tim phụ (Datastore Heartbeating)
- **Mục đích:** Giúp cơ chế vSphere HA phân biệt chính xác giữa việc máy chủ ESXi bị mất nguồn hoàn toàn (cần khởi động lại VM trên host khác) với việc chỉ bị đứt kết nối mạng quản trị (Host Isolation), tránh nguy cơ xung đột truy cập đĩa (Split-Brain).
- **Thông số kỹ thuật:** Chỉ định tối thiểu **2 Datastore dùng chung** độc lập nằm trên các Storage Controller khác nhau làm kênh Heartbeat.
- **Khả năng tự động hóa:** **Tự động hóa hoàn toàn (Automated)**.
  - *Công cụ:* Terraform `vsphere_compute_cluster` (`ha_heartbeat_datastore_policy`).

#### HA-03: Thiết lập hành vi khi máy chủ bị cô lập mạng (Host Isolation Response)
- **Mục đích:** Khi ESXi không thể liên lạc với Gateway quản trị và các node khác trong cụm HA, máy ảo phải được giải phóng khóa đĩa (`.vmdk`) để cụm khởi động lại máy ảo trên node an toàn.
- **Thông số kỹ thuật:** Đặt tham số `ha_host_isolation_response = "shutdown"` (Tắt máy ảo nhẹ nhàng qua VMware Tools, sau đó HA sẽ khởi động lại VM trên host khác).
- **Khả năng tự động hóa:** **Tự động hóa hoàn toàn (Automated)**.
  - *Công cụ:* Terraform `vsphere_compute_cluster`.

#### HA-04: Thiết lập quy tắc phân tách máy ảo dự phòng (DRS Anti-Affinity Rules)
- **Mục đích:** Đảm bảo các cặp máy ảo chạy dự phòng lẫn nhau không bao giờ bị dồn về chạy chung trên cùng một máy chủ ESXi vật lý:
  - 2 máy chủ Active Directory Domain Controllers (`DC01`, `DC02`).
  - Cụm cân bằng tải mạng (HAProxy / NGINX / F5).
  - Cụm cơ sở dữ liệu (PostgreSQL Primary/Standby, Oracle RAC, MS SQL Always On).
- **Thông số kỹ thuật:** Tạo quy tắc `vsphere_compute_cluster_vm_anti_affinity_rule` với cơ chế bắt buộc (Mandatory / Strict).
- **Khả năng tự động hóa:** **Tự động hóa hoàn toàn (Automated)**.
  - *Công cụ:* Terraform resource `vsphere_compute_cluster_vm_anti_affinity_rule`.

#### HA-05: Cấu hình tính năng giám sát máy ảo nội tại (VM Monitoring)
- **Mục đích:** Tự động khởi động lại máy ảo nếu hệ điều hành khách bị treo hoàn toàn (Kernel Panic / Blue Screen of Death) và không còn phản hồi tín hiệu nhịp tim từ VMware Tools.
- **Thông số kỹ thuật:** Kích hoạt `ha_vm_monitoring = "vmMonitoringOnly"`, thời gian chờ không nhận nhịp tim là 30 giây, số lần reset tối đa 3 lần trong vòng 1 giờ.
- **Khả năng tự động hóa:** **Tự động hóa hoàn toàn (Automated)**.
  - *Công cụ:* Đã tích hợp sẵn trong cấu hình Terraform `vsphere_compute_cluster`.

---

### Phân hệ 5: Giám sát, quản lý nhật ký và cảnh báo sự cố (Logging & Monitoring)

#### MON-01: Chuyển tiếp nhật ký sự kiện về máy chủ Syslog/SIEM tập trung
- **Mục đích:** Lưu trữ nhật ký dài hạn phục vụ việc đối soát bảo mật và phân tích sự cố theo tiêu chuẩn ISO 27001.
- **Thông số kỹ thuật:** Chuyển tiếp toàn bộ log của VCSA và các node ESXi về cụm Syslog Server (Splunk, Graylog, ELK, VMware Aria Operations for Logs) qua TCP cổng 514/1514.
- **Khả năng tự động hóa:** **Tự động hóa hoàn toàn (Automated)**.
  - *Công cụ:* VAMI REST API (đối với VCSA) và PowerCLI / Host Profile (đối với ESXi).

#### MON-02: Cấu hình cổng chuyển tiếp thư điện tử cảnh báo (SMTP Server)
- **Mục đích:** vCenter gửi cảnh báo khẩn cấp ngay lập tức tới đội ngũ trực vận hành khi xuất hiện lỗi hạ tầng.
- **Thông số kỹ thuật:** Khai báo thông tin máy chủ chuyển phát thư: SMTP IP/FQDN, cổng kết nối (25 hoặc 587), địa chỉ email người gửi (`vcsa-alerts@domain.com`).
- **Khả năng tự động hóa:** **Tự động hóa hoàn toàn (Automated)**.
  - *Công cụ:* PowerCLI (`Get-AdvancedSetting -Entity $vcenter -Name mail.smtp.server | Set-AdvancedSetting -Value <IP>`).

#### MON-03: Kích hoạt hành vi gửi email cho các cảnh báo sự cố nghiêm trọng
- **Mục đích:** Không để sót các sự cố phần cứng hoặc mạng âm thầm diễn ra.
- **Thông số kỹ thuật:** Gán hành vi `Send a notification email` đối với các định nghĩa cảnh báo (Alarms):
  - *Datastore usage on disk:* Cảnh báo vàng tại 80%, Đỏ tại 90%.
  - *Host connection and state:* Đứt kết nối ESXi Host.
  - *Network uplink redundancy degraded:* Mất 1 trong 2 card Uplink mạng.
  - *Storage connectivity degraded (APD/PDL):* Mất đường truyền kho đĩa.
- **Khả năng tự động hóa:** **Tự động hóa hoàn toàn (Automated)**.
  - *Công cụ:* PowerCLI script (`New-AlarmAction`).

#### MON-04: Đồng bộ thời gian chuẩn xác cao (NTP Synchronization)
- **Mục đích:** Đảm bảo sai lệch thời gian (Clock Drift) giữa toàn bộ các nút máy chủ và vCenter luôn nhỏ hơn 1 giây, ngăn chặn việc hỏng thẻ xác thực SSO Kerberos.
- **Thông số kỹ thuật:** Khai báo danh sách tối thiểu 2 đến 4 máy chủ NTP độc lập (Stratum 1/2) trên cả ESXi Host và VCSA.
- **Khả năng tự động hóa:** **Tự động hóa hoàn toàn (Automated)**.
  - *Công cụ:* Ansible (`vmware_host_ntp`), PowerCLI hoặc tệp cấu hình `config.env`.

#### MON-05: Tích hợp giám sát hiệu năng qua SNMP / vSphere API (Zabbix/Prometheus)
- **Mục đích:** Thu thập dữ liệu hiệu năng (CPU, Memory, IOPS, Network Throughput) của hạ tầng theo thời gian thực.
- **Thông số kỹ thuật:** Khởi tạo tài khoản giám sát Read-Only trên vCenter hoặc cấu hình SNMP v3 Agent (Community string, Authentication Engine ID).
- **Khả năng tự động hóa:** **Tự động hóa hoàn toàn (Automated)**.
  - *Công cụ:* Đã tích hợp vai trò `Security-Auditor-ReadOnly` qua Terraform `vsphere_role`.

---

### Phân hệ 6: Quản trị sao lưu và khôi phục thảm họa (Backup & Disaster Recovery)

#### BKP-01: Lên lịch tự động sao lưu cấu hình vCenter (VAMI File-Based Backup)
- **Mục đích:** Bảo vệ toàn bộ dữ liệu cấu hình logic của vCenter (Inventory, vDS, Permissions, Clusters, vPostgres DB).
- **Thông số kỹ thuật:**
  - Tần suất: Chạy tự động hàng ngày vào khung giờ thấp điểm (01:00 AM).
  - Vị trí lưu trữ: Đẩy qua SFTP / SMB / NFS tới máy chủ Backup biệt lập.
  - Mã hóa: Bật mã hóa mật khẩu AES-256.
  - Lưu giữ: Duy trì tối thiểu 30 bản sao lưu gần nhất.
- **Khả năng tự động hóa:** **Tự động hóa hoàn toàn (Automated)**.
  - *Công cụ:* vCenter REST API (`POST https://<VCSA_IP>:5480/api/appliance/recovery/backup/schedules`).

#### BKP-02: Thiết lập cụm vCenter Server High Availability (VCHA)
- **Mục đích:** Loại trừ điểm nghẽn chịu lỗi đơn nhất (Single Point of Failure) cho tầng quản trị trung tâm trong các môi trường Tier-1 Enterprise.
- **Thông số kỹ thuật:** Cụm 3 node (Active, Passive, Witness). Mạng VCHA Heartbeat riêng biệt qua dải IP cô lập (không trùng với Management IP).
- **Khả năng tự động hóa:** **Bán tự động (Semi-Automated)**.
  - *Giải thích:* Có thể gọi qua PowerCLI / REST API, nhưng cần cấu hình trước dải mạng VCHA và cần xác nhận giao diện để tránh rủi ro phân mảnh cụm khi triển khai.

#### BKP-03: Tích hợp phần mềm sao lưu chuyên dụng (Veeam / Commvault qua VADP)
- **Mục đích:** Tự động hóa sao lưu toàn diện hệ điều hành và dữ liệu của tất cả các máy ảo nghiệp vụ chạy trên cụm vCenter.
- **Thông số kỹ thuật:** Cấu hình tài khoản dịch vụ (Service Account) trên vCenter với quyền hạn chuyên biệt: `Datastore.AllocateSpace`, `VirtualMachine.Provisioning.DiskRandomAccess`, `Cryptographer.Access`.
- **Khả năng tự động hóa:** **Tự động hóa hoàn toàn (Automated)**.
  - *Công cụ:* Đã sẵn sàng qua Terraform `vsphere_role` gán quyền sao lưu.

#### BKP-04: Kiểm thử quy trình phục hồi dữ liệu từ bản sao lưu (Restore Drill)
- **Mục đích:** Đảm bảo bản sao lưu không bị lỗi logic và thời gian phục hồi đáp ứng mục tiêu thời gian khôi phục (RTO / RPO).
- **Thông số kỹ thuật:** Định kỳ hàng quý thực hiện dựng thử nghiệm một phiên bản VCSA mới từ bản sao lưu File-Based trên môi trường Lab biệt lập mạng.
- **Khả năng tự động hóa:** **Thủ công (Manual)**.
  - *Giải thích:* Đây là quy trình nghiệp vụ kiểm toán và diễn tập an toàn thông tin bắt buộc phải có sự chứng kiến và phê duyệt của con người.

---

### Phân hệ 7: Quản lý vòng đời phần mềm và firmware (vLCM & Maintenance)

#### LCM-01: Quản lý cụm bằng mô hình khai báo ảnh (vLCM Single Cluster Image)
- **Mục đích:** Đảm bảo toàn bộ máy chủ ESXi trong cùng một cụm tính toán có tính đồng nhất tuyệt đối về phiên bản OS, bản vá bảo mật và driver phần cứng.
- **Thông số kỹ thuật:** Chuyển đổi quản lý cụm từ Baseline cũ sang **Cluster Image**:
  - *ESXi Base Image:* Phiên bản ESXi chuẩn của VMware.
  - *Vendor Add-on:* Gói driver phần cứng được hãng chứng thực (Dell, HPE, Cisco).
- **Khả năng tự động hóa:** **Tự động hóa hoàn toàn (Automated)**.
  - *Công cụ:* vCenter REST API hoặc PowerCLI.

#### LCM-02: Tích hợp trình quản lý phần cứng (Hardware Support Manager - HSM)
- **Mục đích:** Cho phép vCenter kiểm soát và tự động nâng cấp đồng bộ cả Firmware (BIOS, Network Card, RAID Controller) cùng thời điểm với quá trình nâng cấp hệ điều hành ESXi.
- **Thông số kỹ thuật:** Cài đặt các gói tích hợp phần cứng chính hãng: OpenManage Integration for VMware vCenter (OMIVV / OMEVV cho máy chủ Dell) hoặc HPE OneView for VMware vCenter.
- **Khả năng tự động hóa:** **Bán tự động (Semi-Automated)**.
  - *Giải thích:* Cần triển khai máy ảo thiết bị (Virtual Appliance) của nhà sản xuất phần cứng trước khi đăng ký tích hợp vào vCenter.

#### LCM-03: Cấu hình kho bản vá ngoại tuyến (vSphere Update Manager Download Service)
- **Mục đích:** Cho phép cụm vCenter nằm trong mạng cô lập (không có Internet) vẫn nhận được đầy đủ các bản cập nhật bảo mật định kỳ.
- **Thông số kỹ thuật:** Thiết lập máy chủ trung gian UMDS đặt tại vùng mạng DMZ để tải bản vá từ VMware Repositories, sau đó đồng bộ dữ liệu vào kho lưu trữ nội bộ của vCenter qua giao thức Web nội bộ hoặc đĩa cứng di động.
- **Khả năng tự động hóa:** **Tự động hóa hoàn toàn (Automated)**.
  - *Công cụ:* Script cronjob tự động chạy lệnh `vmware-umds` trên máy chủ DMZ.

---

## 3. Lộ trình triển khai và mức độ hoàn thiện hiện tại của bộ công cụ

```text
+----------------------------------------------------------------------------------------------------+
| TRẠNG THÁI HIỆN TẠI (ĐÃ HOÀN TẤT TRONG BỘ CÔNG CỤ TỰ ĐỘNG HÓA VCSA_DEPLOY)                          |
+----------------------------------------------------------------------------------------------------+
| [X] NET-01: Phân tách vùng mạng độc lập qua Distributed Port Groups (Management, vMotion, Storage)  |
| [X] NET-03: Chính sách bảo mật cổng mạng (Khóa Promiscuous, MAC Changes, Forged Transmits)        |
| [X] NET-04: Kích hoạt NetIOC phiên bản 3 quản trị QoS băng thông                                   |
| [X] NET-05: Kiểm soát trần băng thông mạng Traffic Shaping (Ingress/Egress)                        |
| [X] STO-03: Cụm kho lưu trữ Datastore Cluster tích hợp Storage DRS và Storage I/O Control (SIOC)   |
| [X] STO-06: Khởi tạo vSphere Content Library cục bộ lưu trữ Templates/ISO                          |
| [X] HA-01:  Chính sách HA Admission Control dự trữ tài nguyên CPU/RAM theo tỷ lệ phần trăm         |
| [X] HA-05:  Giám sát trạng thái máy ảo nội tại (VM Monitoring)                                     |
| [X] SEC-07: Phân định hệ thống vai trò quản trị tùy biến RBAC động qua Terraform                   |
| [X] MON-04: Đồng bộ thời gian qua máy chủ NTP tập trung                                            |
+----------------------------------------------------------------------------------------------------+
                                                |
                                                | Các bước bổ sung cần hoàn tất trước khi Go-Live
                                                v
+----------------------------------------------------------------------------------------------------+
| HẠNG MỤC CẦN TRIỂN KHAI TIẾP THEO (GIAI ĐOẠN HOÀN THIỆN SẢN XUẤT - PRODUCTION GO-LIVE)            |
+----------------------------------------------------------------------------------------------------+
| [ ] BKP-01: Bật lịch sao lưu tự động VAMI File-Based Backup hàng ngày qua SFTP (Gọi qua VAMI API)  |
| [ ] SEC-01: Nạp chứng chỉ CA và cấu hình Identity Source liên kết Active Directory qua LDAPS       |
| [ ] SEC-03: Tắt dịch vụ SSH trên VCSA và các node ESXi Host; đặt Timeout 900 giây                 |
| [ ] SEC-04: Kích hoạt ESXi Normal Lockdown Mode                                                    |
| [ ] STO-01: Đổi chính sách lưu trữ SAN sang Multipathing Round Robin (iops=1) trên các ESXi Hosts   |
| [ ] STO-02: Trỏ phân vùng Persistent Scratch Log của ESXi về VMFS Datastore dùng chung             |
| [ ] MON-01: Cấu hình chuyển tiếp Syslog tập trung về hệ thống máy chủ SIEM nội bộ                  |
| [ ] MON-02: Khai báo SMTP Mail Server và kích hoạt gửi Email cảnh báo sự cố Datastore/Uplink       |
| [ ] HA-04:  Thiết lập DRS Anti-Affinity Rules tách rời các máy ảo Domain Controller và Database   |
+----------------------------------------------------------------------------------------------------+
```
