# ==============================================================================
# KHAI BÁO BIẾN ĐẦU VÀO TERRAFORM VSPHERE DAY-2 PROVISIONING
# Thiết kế tổng quát (Generic) - Linh hoạt 100% cho mọi mô hình hạ tầng
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. KẾT NỐI VCENTER SERVER
# ------------------------------------------------------------------------------
variable "vsphere_server" {
  description = "Địa chỉ FQDN hoặc IP của vCenter Server (Ví dụ: vcsa.int hoặc 10.255.245.107)"
  type        = string
}

variable "vsphere_user" {
  description = "Tài khoản quản trị Single Sign-On (Mặc định: administrator@vsphere.local)"
  type        = string
  default     = "administrator@vsphere.local"
}

variable "vsphere_password" {
  description = "Mật khẩu quản trị Single Sign-On của vCenter Server"
  type        = string
  sensitive   = true
}

variable "vsphere_allow_unverified_ssl" {
  description = "Cho phép kết nối chứng chỉ SSL tự ký của vCenter"
  type        = bool
  default     = true
}

# ------------------------------------------------------------------------------
# 2. CẤU HÌNH DATACENTER VÀ HỆ THỐNG THƯ MỤC (FOLDERS)
# ------------------------------------------------------------------------------
variable "datacenter_name" {
  description = "Tên Datacenter quản trị trung tâm"
  type        = string
  default     = "Datacenter-01"
}

variable "vm_folders" {
  description = "Danh sách tên các thư mục máy ảo cần tạo phân cấp"
  type        = list(string)
  default     = ["Management", "Core-Infra", "Workloads-Production", "Workloads-Staging", "Templates"]
}

# ------------------------------------------------------------------------------
# 3. CỤM TÍNH TOÁN (COMPUTE CLUSTER), DRS, HA VÀ ADMISSION CONTROL
# ------------------------------------------------------------------------------
variable "create_cluster" {
  description = "Tùy chọn tạo Compute Cluster (true: tạo cụm cluster; false: gán trực tiếp Host vào Datacenter độc lập)"
  type        = bool
  default     = true
}

variable "cluster_name" {
  description = "Tên cụm tính toán Cluster"
  type        = string
  default     = "Cluster-01"
}

variable "drs_enabled" {
  description = "Kích hoạt tính năng cân bằng tải tài nguyên DRS"
  type        = bool
  default     = true
}

variable "drs_automation_level" {
  description = "Mức độ tự động hóa DRS: fullyAutomated, partiallyAutomated, manual"
  type        = string
  default     = "fullyAutomated"
}

variable "drs_migration_threshold" {
  description = "Ngưỡng khuyến nghị di trú DRS (từ 1 đến 5, mặc định: 3)"
  type        = number
  default     = 3
}

variable "ha_enabled" {
  description = "Kích hoạt tính năng sẵn sàng cao vSphere HA (Nên để false nếu cụm lab chỉ có 1 Host)"
  type        = bool
  default     = false
}

variable "ha_host_monitoring" {
  description = "Giám sát nhịp tim (heartbeat) khả dụng của máy chủ ESXi trong cụm HA"
  type        = string
  default     = "enabled"
}

variable "ha_vm_monitoring" {
  description = "Giám sát máy ảo trong HA: vmMonitoringDisabled, vmMonitoringOnly, vmAndAppMonitoring"
  type        = string
  default     = "vmMonitoringDisabled"
}

variable "ha_admission_control_policy" {
  description = "Chính sách kiểm soát tài nguyên dự phòng HA: resourcePercentage, slotPolicy, failoverHosts, disabled"
  type        = string
  default     = "resourcePercentage"
}

variable "ha_admission_control_host_failure_tolerance" {
  description = "Số lượng máy chủ ESXi cho phép gặp sự cố đồng thời"
  type        = number
  default     = 1
}

variable "ha_admission_control_cpu_percentage" {
  description = "Tỷ lệ dung lượng CPU dành riêng dự phòng sự cố (%)"
  type        = number
  default     = 25
}

variable "ha_admission_control_ram_percentage" {
  description = "Tỷ lệ dung lượng RAM dành riêng dự phòng sự cố (%)"
  type        = number
  default     = 25
}

variable "ha_heartbeat_datastore_policy" {
  description = "Chính sách lựa chọn Datastore Heartbeating cho HA: allFeasibleBackup, userSelectedDs, allFeasibleBackupWithUserPreference"
  type        = string
  default     = "allFeasibleBackup"
}

variable "ha_heartbeat_datastore_ids" {
  description = "Danh sách ID các Datastore chỉ định làm heartbeat nếu chính sách là userSelectedDs hoặc allFeasibleBackupWithUserPreference"
  type        = list(string)
  default     = null
}

variable "vm_anti_affinity_rules" {
  description = "Bản đồ các quy tắc DRS VM Anti-Affinity tách rời máy ảo dự phòng trên cụm (Mặc định: rỗng {})"
  type = map(object({
    virtual_machine_ids = list(string)
    enabled             = optional(bool, true)
    mandatory           = optional(bool, false)
  }))
  default = {}
}

variable "ha_advanced_options" {
  description = "Bản đồ các tham số nâng cao vSphere HA (Ví dụ: {\"das.ignoreInsufficientHbDatastore\" = \"true\"})"
  type        = map(string)
  default     = {}
}

# ------------------------------------------------------------------------------
# 4. DANH SÁCH MÁY CHỦ ESXI NẠP VÀO QUẢN LÝ (HOST ONBOARDING)
# ------------------------------------------------------------------------------
variable "esxi_hosts" {
  description = "Danh sách các máy chủ ESXi cần kết nạp vào quản lý"
  type = list(object({
    hostname = string
    username = string
    password = string
  }))
  default = []
}

# ------------------------------------------------------------------------------
# 5. CẤU HÌNH MẠNG DISTRIBUTED SWITCH (VDS), TEAMING, NETIOC & PORT GROUPS
# ------------------------------------------------------------------------------
variable "create_vds" {
  description = "Tùy chọn tạo bộ chuyển mạch mạng phân tán (vSphere Distributed Switch)"
  type        = bool
  default     = true
}

variable "vds_name" {
  description = "Tên bộ chuyển mạch phân tán vDS"
  type        = string
  default     = "VDS-Core-01"
}

variable "vds_uplinks" {
  description = "Danh sách cổng Uplink trên vDS"
  type        = list(string)
  default     = ["uplink1", "uplink2"]
}

variable "vds_active_uplinks" {
  description = "Danh sách cổng Uplink hoạt động chính (Active Uplinks)"
  type        = list(string)
  default     = ["uplink1"]
}

variable "vds_standby_uplinks" {
  description = "Danh sách cổng Uplink dự phòng (Standby Uplinks)"
  type        = list(string)
  default     = ["uplink2"]
}

variable "vds_physical_nics" {
  description = "Danh sách card mạng vật lý của Host để gắn vào Uplink vDS (Ví dụ: [\"vmnic1\"]). Để trống [] nếu chưa gắn card"
  type        = list(string)
  default     = []
}

variable "enable_netioc" {
  description = "Kích hoạt Network I/O Control (NetIOC v3) trên vDS"
  type        = bool
  default     = true
}

variable "vds_portgroups" {
  description = "Bản đồ danh mục Distributed Port Groups (VLAN, Teaming override, Traffic Shaping, Security)"
  type = map(object({
    vlan_id                           = number
    teaming_policy                    = optional(string, "loadbalance_loadbased")
    active_uplinks                    = optional(list(string), null)
    standby_uplinks                   = optional(list(string), null)
    shaping_enabled                   = optional(bool, false)
    ingress_shaping_average_bandwidth = optional(number, 100000000)
    ingress_shaping_peak_bandwidth    = optional(number, 200000000)
    ingress_shaping_burst_size        = optional(number, 10485760)
    egress_shaping_average_bandwidth  = optional(number, 100000000)
    egress_shaping_peak_bandwidth     = optional(number, 200000000)
    egress_shaping_burst_size         = optional(number, 10485760)
    allow_promiscuous                 = optional(bool, false)
    allow_forged_transmits            = optional(bool, false)
    allow_mac_changes                 = optional(bool, false)
  }))
  default = {}
}

# ------------------------------------------------------------------------------
# 5.1. CỔNG MẠNG VMKERNEL (VMKERNEL ADAPTERS - MULTI-NIC VMOTION & STORAGE)
# ------------------------------------------------------------------------------
variable "host_vnics" {
  description = "Bản đồ danh mục cổng VMkernel NICs khởi tạo trên từng ESXi Host (Multi-NIC vMotion, vSAN, Management)"
  type = map(object({
    host_hostname  = string                              # Hostname trùng khớp với var.esxi_hosts
    portgroup_type = optional(string, "distributed")     # "distributed" hoặc "standard"
    portgroup_name = string                              # Tên Port Group gắn vNIC vào
    services       = optional(list(string), ["vmotion"]) # Danh mục dịch vụ hỗ trợ trong Terraform: "vmotion", "management", "vsan"
    netstack       = optional(string, null)              # TCP/IP Stack: null (defaultTcpipStack), "vmotion", "provisioning", "ops", "mirror"
    mtu            = optional(number, null)              # Kích thước MTU (ví dụ: 1500 hoặc 9000 cho Jumbo Frame)
    dhcp           = optional(bool, false)               # Tự động nhận IP qua DHCP
    ipv4_ip        = optional(string, null)              # Địa chỉ IP tĩnh IPv4
    ipv4_netmask   = optional(string, null)              # Mặt nạ mạng IPv4 Subnet Mask (ví dụ: 255.255.255.0)
    ipv4_gw        = optional(string, null)              # Cổng mặc định IPv4 Gateway
  }))
  default = {}
}

# ------------------------------------------------------------------------------
# 6. CẤU HÌNH MẠNG TIÊU CHUẨN (STANDARD VSWITCH & STANDARD PORT GROUPS)
# ------------------------------------------------------------------------------
variable "create_standard_vswitches" {
  description = "Tùy chọn tạo thêm bộ chuyển mạch tiêu chuẩn Standard vSwitch trên từng Host"
  type        = bool
  default     = false
}

variable "standard_vswitches" {
  description = "Bản đồ cấu hình Standard vSwitch tạo trên các ESXi Host"
  type = map(object({
    network_adapters = list(string)
    active_nics      = list(string)
    standby_nics     = list(string)
    mtu              = optional(number, 1500)
  }))
  default = {}
}

variable "standard_portgroups" {
  description = "Bản đồ cấu hình Standard Port Groups gắn vào Standard vSwitch"
  type = map(object({
    vswitch_name = string
    vlan_id      = number
  }))
  default = {}
}

# ------------------------------------------------------------------------------
# 7. KHO LƯU TRỮ VÀ THƯ VIỆN NỘI DUNG (STORAGE, SIOC & CONTENT LIBRARY)
# ------------------------------------------------------------------------------
variable "create_content_library" {
  description = "Khởi tạo thư viện nội dung vSphere Content Library cục bộ lưu ISO và Templates"
  type        = bool
  default     = true
}

variable "content_library_name" {
  description = "Tên thư viện nội dung vSphere Content Library"
  type        = string
  default     = "VCSA-Core-Content-Library"
}

variable "primary_datastore_name" {
  description = "Tên Datastore chính dùng để lưu trữ Content Library (Ví dụ: SRV03_Z620_DS)"
  type        = string
  default     = ""
}

variable "create_datastore_cluster" {
  description = "Tùy chọn tạo cụm kho lưu trữ Datastore Cluster tích hợp Storage DRS & Storage I/O Control (SIOC)"
  type        = bool
  default     = false
}

variable "datastore_cluster_name" {
  description = "Tên Datastore Cluster"
  type        = string
  default     = "Datastore-Cluster-01"
}

variable "sdrs_enabled" {
  description = "Bật tính năng Storage DRS cân bằng dung lượng và hiệu năng IO lưu trữ"
  type        = bool
  default     = true
}

variable "sdrs_automation_level" {
  description = "Mức tự động hóa Storage DRS (fullyAutomated, manual)"
  type        = string
  default     = "fullyAutomated"
}

variable "sdrs_io_latency_threshold" {
  description = "Ngưỡng độ trễ IO Control (Storage I/O Control latency threshold) tính bằng mili-giây (ms)"
  type        = number
  default     = 15
}

# ------------------------------------------------------------------------------
# 8. PHÂN QUYỀN VAI TRÒ TÙY BIẾN (CUSTOM ROLES & PERMISSIONS RBAC)
# ------------------------------------------------------------------------------
variable "custom_roles" {
  description = "Bản đồ các vai trò quản trị tùy biến kèm danh mục đặc quyền quyền hạn (Privileges)"
  type = map(object({
    role_privileges = list(string)
  }))
  default = {}
}
