# Danh mục kiểm tra cấu hình VMware vCenter sẵn sàng vận hành (VCSA Production Checklist)

Tài liệu này chuẩn hóa toàn bộ các hạng mục cấu hình từ cơ sở đến nâng cao để đưa hệ thống VMware vCenter Server Appliance (VCSA) và các máy chủ ESXi vào môi trường vận hành chính thức (Production). 

Các hạng mục được phân tầng ưu tiên theo mức độ độc lập và khả năng tự động hóa:
- **Tầng 1 (Ưu tiên cao nhất):** Triển khai ngay lập tức qua Terraform, tự động hóa 100%, độc lập hoàn toàn, không phụ thuộc dịch vụ ngoài.
- **Tầng 2:** Triển khai tự động nội bộ qua CLI/API/Script, không phụ thuộc dịch vụ ngoài.
- **Tầng 3:** Triển khai tự động hoặc bán tự động nhưng phụ thuộc dịch vụ hạ tầng bên ngoài (NTP, Syslog, SMTP, AD, CA, Backup Server, Switch vật lý).
- **Tầng 4:** Quy trình kiểm thử, diễn tập và kiểm toán định kỳ.

---

## Tầng 1: Triển khai ngay lập tức qua Terraform (Tự động hóa 100% - Độc lập hoàn toàn)

Toàn bộ các mục trong tầng này được định nghĩa bằng mã nguồn khai báo và có thể chạy ngay sau khi VCSA hoàn tất cài đặt cơ sở mà không cần bất kỳ dịch vụ ngoài nào khác.

### 1.1. Kiến trúc cụm và tính toán (Compute Cluster & HA/DRS)
- [ ] **HA-01 - Kích hoạt vSphere DRS tự động hóa:** Thiết lập `drs_enabled = true`, `drs_automation_level = "fullyAutomated"`, ngưỡng di trú `drs_migration_threshold = 3`. Tự động cân bằng tải CPU và RAM giữa các máy chủ.  
  *Công cụ:* Terraform resource `vsphere_compute_cluster`. | *Phụ thuộc:* Không.
- [ ] **HA-02 - Kích hoạt vSphere HA và Admission Control:** Bật `ha_enabled = true`, chính sách `ha_admission_control_policy = "resourcePercentage"`. Đặt tỷ lệ dự trữ CPU và RAM tương ứng số host chịu lỗi (ví dụ: cụm 4 hosts đặt dự phòng 25% CPU / 25% RAM cho 1 host failure).  
  *Công cụ:* Terraform resource `vsphere_compute_cluster`. | *Phụ thuộc:* Không.
- [ ] **HA-03 - Giám sát máy ảo nội tại (VM Monitoring):** Bật `ha_vm_monitoring = "vmMonitoringOnly"` để tự động khởi động lại máy ảo nếu hệ điều hành khách bị treo và mất nhịp tim VMware Tools.  
  *Công cụ:* Terraform resource `vsphere_compute_cluster`. | *Phụ thuộc:* Không.
- [ ] **HA-04 - Kênh giám sát nhịp tim Datastore Heartbeating:** Cấu hình `ha_heartbeat_datastore_policy` chỉ định tối thiểu 2 Datastore dùng chung độc lập để chống lỗi phân mảnh cụm (Split-Brain) khi mất mạng quản trị.  
  *Công cụ:* Terraform resource `vsphere_compute_cluster`. | *Phụ thuộc:* Không.
- [ ] **HA-05 - Quy tắc phân tách máy ảo dự phòng (DRS Anti-Affinity):** Tạo các quy tắc bắt buộc tách rời các cặp máy ảo chạy dự phòng lẫn nhau (Domain Controllers, Database Cluster, Load Balancers) không chạy chung trên một máy chủ vật lý.  
  *Công cụ:* Terraform resource `vsphere_compute_cluster_vm_anti_affinity_rule`. | *Phụ thuộc:* Không.
- [ ] **HST-01 - Nạp máy chủ ESXi tự động (Host Onboarding):** Tự động truy vấn SSL Thumbprint qua `data "vsphere_host_thumbprint"` và nạp danh sách ESXi Hosts vào quản trị của Cluster.  
  *Công cụ:* Terraform resource `vsphere_host`. | *Phụ thuộc:* Không.
- [ ] **DIR-01 - Khởi tạo Datacenter và cây thư mục máy ảo:** Tạo Datacenter trung tâm và cấu trúc phân cấp VM Folders (`Management`, `Core-Infra`, `Workloads-Production`, `Workloads-Staging`, `Templates`).  
  *Công cụ:* Terraform resources `vsphere_datacenter`, `vsphere_folder`. | *Phụ thuộc:* Không.

### 1.2. Mạng chuyển mạch phân tán và bảo mật cổng (vDS Networking & Security)
- [ ] **NET-01 - Khởi tạo bộ chuyển mạch phân tán (vDS):** Tạo vSphere Distributed Switch gán cổng Uplinks vật lý, thiết lập MTU phù hợp cho toàn cụm.  
  *Công cụ:* Terraform resource `vsphere_distributed_virtual_switch`. | *Phụ thuộc:* Không.
- [ ] **NET-02 - Kích hoạt Network I/O Control (NetIOC v3):** Bật `network_resource_control_enabled = true` trên vDS để quản trị QoS băng thông, chống nghẽn đường truyền khi card mạng vật lý bị quá tải.  
  *Công cụ:* Terraform resource `vsphere_distributed_virtual_switch`. | *Phụ thuộc:* Không.
- [ ] **NET-03 - Phân tách các vùng mạng logic (Distributed Port Groups):** Khởi tạo danh mục Port Groups với VLAN Tagging riêng biệt cho từng luồng: Management (VLAN untagged hoặc riêng), vMotion (VLAN riêng), Storage (VLAN riêng), Workloads (VLAN riêng theo môi trường).  
  *Công cụ:* Terraform resource `vsphere_distributed_port_group`. | *Phụ thuộc:* Không.
- [ ] **NET-04 - Khóa chính sách bảo mật cổng mạng:** Khóa toàn bộ các nguy cơ giả mạo trên Port Groups: `allow_promiscuous = false`, `allow_mac_changes = false`, `allow_forged_transmits = false`.  
  *Công cụ:* Terraform resource `vsphere_distributed_port_group`. | *Phụ thuộc:* Không.
- [ ] **NET-05 - Kiểm soát trần băng thông mạng (Traffic Shaping):** Cấu hình giới hạn băng thông trung bình (Average), băng thông đỉnh (Peak) và Burst Size cho các nhóm tải phụ để chống chiếm dụng đường truyền.  
  *Công cụ:* Terraform resource `vsphere_distributed_port_group`. | *Phụ thuộc:* Không.

### 1.3. Kho lưu trữ và phân quyền (Storage SDRS/SIOC & RBAC)
- [ ] **STO-01 - Cụm kho lưu trữ Datastore Cluster và Storage DRS:** Gom các VMFS Datastore vào cụm, kích hoạt Storage DRS chế độ `fullyAutomated` để tự động di trú cân bằng dung lượng đĩa.  
  *Công cụ:* Terraform resource `vsphere_datastore_cluster`. | *Phụ thuộc:* Không.
- [ ] **STO-02 - Kiểm soát tài nguyên lưu trữ (Storage I/O Control):** Kích hoạt SIOC với ngưỡng trễ trần `sdrs_io_latency_threshold = 15` mili-giây để tự động điều tiết hàng đợi I/O khi đĩa bị nghẽn.  
  *Công cụ:* Terraform resource `vsphere_datastore_cluster`. | *Phụ thuộc:* Không.
- [ ] **STO-03 - Khởi tạo thư viện nội dung cục bộ (Content Library):** Tạo Content Library trên Datastore chính để lưu trữ đồng bộ VM Templates, tệp OVF/OVA và ISO cài đặt.  
  *Công cụ:* Terraform resource `vsphere_content_library`. | *Phụ thuộc:* Không.
- [ ] **SEC-01 - Thiết lập vai trò phân quyền tùy biến (Custom RBAC Roles):** Khởi tạo danh mục vai trò động với quyền hạn tối thiểu: `DevOps-Automation-Engineer`, `Security-Auditor-ReadOnly`, `Backup-Operator`.  
  *Công cụ:* Terraform resource `vsphere_role`. | *Phụ thuộc:* Không.

---

## Tầng 2: Triển khai tự động nội bộ qua CLI / Script (Tự động hóa 100% - Không phụ thuộc dịch vụ ngoài)

Các cấu hình nội bộ máy chủ VCSA và ESXi Host, không cần dịch vụ bên ngoài, thực thi tự động qua tiện ích dòng lệnh, Host Profile, REST API hoặc Ansible.

- [ ] **STO-04 - Chuyển chính sách đa đường truyền SAN sang Round Robin:** Đổi cơ chế chọn đường truyền Native Multipathing Plugin (NMP) sang `VMW_PSP_RR` với tham số chuyển mạch `iops=1` để tối ưu hóa hiệu năng LUN lưu trữ iSCSI / FC.  
  *Lệnh CLI:* `esxcli storage nmp satp setbootpath --satp VMW_SATP_ALUA --psp VMW_PSP_RR`. | *Phụ thuộc:* Không.
- [ ] **STO-05 - Cấu hình phân vùng lưu trữ nhật ký bền vững (Persistent Scratch):** Chuyển hướng thư mục nhật ký và crash dump của ESXi từ RAM disk sang Datastore dùng chung: `[Datastore_Name]/scratch/log/<hostname>`.  
  *Lệnh CLI:* `esxcli system syslog config set --logdir=/vmfs/volumes/<Datastore>/scratch/log`. | *Phụ thuộc:* Không.
- [ ] **STO-06 - Kích hoạt thu hồi dung lượng đĩa tự động (Automatic UNMAP):** Đảm bảo cơ chế gửi lệnh SCSI UNMAP mức ưu tiên thấp (Priority: Low) hoạt động trên toàn bộ các VMFS-6 Datastores để giải phóng khối dữ liệu rác về SAN Storage.  
  *Trạng thái:* Tự động kích hoạt mặc định trên VMFS-6. | *Phụ thuộc:* Không.
- [ ] **NET-06 - Kích hoạt Multi-NIC vMotion:** Khởi tạo 2 cổng VMkernel dành cho vMotion trên 2 card Uplink vật lý độc lập để tăng gấp đôi băng thông và tốc độ di trú máy ảo.  
  *Lệnh CLI:* PowerCLI `New-VMHostNetworkAdapter -VMotionEnabled $true`. | *Phụ thuộc:* Không.
- [ ] **SEC-02 - Vô hiệu hóa dịch vụ SSH và đặt Shell Timeout:** Tắt dịch vụ SSH trên VCSA (`Access.SSH = false`) và trên các máy chủ ESXi Host (`vim-cmd hostsvc/enable_ssh false`). Đặt thời gian tự động thoát phiên nhàn rỗi là 900 giây (15 phút).  
  *Công cụ:* Script CLI / PowerCLI `Set-VMHostService`. | *Phụ thuộc:* Không.
- [ ] **SEC-03 - Kích hoạt chế độ khóa máy chủ ESXi (Lockdown Mode):** Bật `Normal Lockdown Mode` trên toàn bộ các ESXi Hosts để ngăn chặn việc đăng nhập trực tiếp ngoài tầm kiểm soát của vCenter.  
  *Công cụ:* PowerCLI `Set-VMHost -LockdownMode Normal`. | *Phụ thuộc:* Không.
- [ ] **SEC-04 - Khóa các giao thức mã hóa yếu (TLS Hardening):** Chạy công cụ `tls-configurator.sh` trên VCSA để vô hiệu hóa toàn bộ TLS 1.0 và TLS 1.1, chỉ cho phép TLS 1.2 và TLS 1.3.  
  *Lệnh CLI:* `/usr/lib/vmware-tether/bin/tls-configurator.sh vpxd set-ciphers ...` | *Phụ thuộc:* Không.
- [ ] **SEC-05 - Vô hiệu hóa tính năng gửi telemetry (CEIP):** Tắt chương trình Customer Experience Improvement Program để ngăn chặn việc gửi dữ liệu ra ngoài Internet.  
  *Công cụ:* vCenter REST API `com.vmware.cis.telemetry.c11n`. | *Phụ thuộc:* Không.
- [ ] **MON-01 - Cấu hình dịch vụ ghi nhận lỗi nhân mạng (Network Core Dump):** Cấu hình dịch vụ `netdump` trên từng ESXi Host để khi gặp lỗi màn hình tím (PSOD), tệp crash dump được truyền tự động về dịch vụ Dump Collector trên vCenter.  
  *Lệnh CLI:* `esxcli system coredump network set --interface-name vmk0 --server-ipv4 <VCSA_IP> --server-port 6500 --enable true`. | *Phụ thuộc:* Không.

---

## Tầng 3: Cấu hình phụ thuộc vào dịch vụ / hạ tầng bên ngoài (Tự động hóa hoặc bán tự động)

Các cấu hình yêu cầu hệ thống hạ tầng phụ trợ (NTP, Syslog, Mail, AD, CA, Storage Controller, Switch vật lý) phải sẵn sàng trước khi kết nối.

- [ ] **MON-02 - Đồng bộ thời gian chuẩn xác cao (NTP):** Khai báo tối thiểu 2 đến 4 máy chủ NTP độc lập (Stratum 1/2) trên cả ESXi Host và VCSA. Giữ sai lệch thời gian dưới 1 giây.  
  *Công cụ:* Tự động qua `config.env` hoặc PowerCLI. | *Phụ thuộc:* Cụm máy chủ NTP nội bộ hoặc Internet.
- [ ] **MON-03 - Chuyển tiếp nhật ký tập trung (Remote Syslog Collector):** Chuyển tiếp toàn bộ log hệ thống của VCSA và ESXi Hosts về hệ thống SIEM/Syslog tập trung (Splunk, Graylog, ELK, Aria Operations for Logs) qua TCP cổng 514/1514.  
  *Công cụ:* Tự động qua VAMI API và PowerCLI `Set-VMHostSyslogServer`. | *Phụ thuộc:* Máy chủ Syslog trung tâm.
- [ ] **MON-04 - Khai báo máy chủ gửi thư cảnh báo (SMTP Mail Server) và Alarms:** Khai báo thông số SMTP Gateway và gán hành vi gửi email tự động khi xảy ra lỗi nghiêm trọng (mất Uplink, đứt kết nối Datastore, máy chủ mất liên lạc, dung lượng đĩa > 85%).  
  *Công cụ:* Tự động qua PowerCLI `Get-AdvancedSetting mail.smtp.server`. | *Phụ thuộc:* Hệ thống SMTP Relay / Mail Server.
- [ ] **BKP-01 - Lên lịch sao lưu cấu hình vCenter tự động (VAMI File-Based Backup):** Thiết lập lịch sao lưu tự động hàng ngày qua SFTP/SMB/NFS tại VAMI port 5480, bật mã hóa AES-256, lưu giữ tối thiểu 30 bản gần nhất.  
  *Công cụ:* Tự động qua VAMI REST API `POST /api/appliance/recovery/backup/schedules`. | *Phụ thuộc:* Máy chủ lưu trữ file backup (SFTP/NFS).
- [ ] **SEC-06 - Tích hợp nguồn định danh tập trung (Active Directory over LDAPS):** Liên kết vCenter với Active Directory qua cổng TCP 636, gán các nhóm quản trị AD Security Groups vào các vai trò RBAC của vSphere.  
  *Công cụ:* Bán tự động qua PowerCLI / REST API. | *Phụ thuộc:* Máy chủ AD Domain Controller và chứng chỉ Root CA.
- [ ] **SEC-07 - Thay thế chứng chỉ Machine SSL bằng chứng chỉ Enterprise CA:** Thay thế chứng chỉ tự ký VMCA bằng chứng chỉ do CA nội bộ doanh nghiệp ký để đảm bảo tính hợp lệ trên toàn hệ thống.  
  *Công cụ:* Bán tự động qua `certificate-manager` CLI. | *Phụ thuộc:* Hệ thống cấp phát chứng chỉ số (Enterprise PKI).
- [ ] **BKP-02 - Tích hợp phần mềm sao lưu chuyên dụng (Veeam / Commvault qua VADP):** Khởi tạo tài khoản dịch vụ chuyên dụng với quyền hạn `Datastore.AllocateSpace`, `VirtualMachine.Provisioning.DiskRandomAccess` để phần mềm sao lưu tích hợp qua VADP.  
  *Công cụ:* Tự động qua Terraform `vsphere_role`. | *Phụ thuộc:* Hệ thống máy chủ sao lưu chuyên dụng.
- [ ] **BKP-03 - Thiết lập cụm vCenter Server High Availability (VCHA):** Triển khai cụm 3 node (Active, Passive, Witness) cho môi trường Mission-Critical đòi hỏi tính liên tục cấp độ cao nhất.  
  *Công cụ:* Bán tự động qua REST API / PowerCLI. | *Phụ thuộc:* Dải mạng riêng cho VCHA heartbeat và tài nguyên cụm.
- [ ] **NET-07 - Cấu hình an toàn cổng mạng trên Switch vật lý (PortFast & BPDU Guard):** Bật `portfast trunk` và `bpduguard enable` trên các cổng switch mạng vật lý ToR đấu nối với máy chủ ESXi để tránh nghẽn STP và chống loop mạng.  
  *Công cụ:* Bán tự động / Script cấu hình thiết bị mạng ngoài. | *Phụ thuộc:* Hệ thống thiết bị chuyển mạch vật lý (ToR Switches).
- [ ] **LCM-01 - Quản trị cụm theo mô hình khai báo ảnh (vLCM Single Cluster Image):** Khai báo ESXi Base Image, Vendor Add-on (Dell/HPE) và tích hợp Hardware Support Manager (HSM) để nâng cấp đồng bộ cả hệ điều hành lẫn firmware phần cứng.  
  *Công cụ:* Tự động hoặc bán tự động qua vLCM API. | *Phụ thuộc:* Kho bản vá VMware và appliance quản lý phần cứng của hãng.

---

## Tầng 4: Quy trình kiểm thử, diễn tập và kiểm toán định kỳ (Thủ công / Đánh giá định kỳ)

Các quy trình vận hành bắt buộc thực hiện thủ công hoặc có sự tham gia của con người để nghiệm thu an toàn trước khi bàn giao đưa vào khai thác chính thức.

- [ ] **TST-01 - Diễn tập khôi phục vCenter từ bản sao lưu (Restore Drill):** Định kỳ kiểm thử việc dựng lại một máy chủ VCSA từ tệp sao lưu VAMI trên môi trường mạng cô lập để xác nhận tính toàn vẹn của dữ liệu và thời gian phục hồi (RTO/RPO).
- [ ] **TST-02 - Kiểm thử cơ chế chịu lỗi phần cứng (Failover Test):** Thực hiện ngắt kết nối vật lý một card mạng Uplink hoặc tắt nguồn đột ngột một máy chủ ESXi để kiểm chứng tính năng chuyển mạch dự phòng và khả năng vSphere HA tự động bật lại máy ảo.
- [ ] **AUD-01 - Rà soát kiểm toán đặc quyền tài khoản định kỳ:** Rà soát danh sách tài khoản quản trị cá nhân, vô hiệu hóa các tài khoản đã nghỉ việc hoặc không còn nhiệm vụ, xác minh tuân thủ nguyên tắc đặc quyền tối thiểu (Least Privilege).
