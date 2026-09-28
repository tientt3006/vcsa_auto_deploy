# ==============================================================================
# 04. CẤU HÌNH HẠ TẦNG MẠNG (DISTRIBUTED SWITCH HOẶC STANDARD VSWITCH, VLAN & NETIOC)
# ==============================================================================

# ------------------------------------------------------------------------------
# A. BỘ CHUYỂN MẠCH PHÂN TÁN (VSPHERE DISTRIBUTED SWITCH - VDS)
# ------------------------------------------------------------------------------
resource "vsphere_distributed_virtual_switch" "vds" {
  count         = var.create_vds ? 1 : 0
  name          = var.vds_name
  datacenter_id = vsphere_datacenter.dc.id

  # Cấu hình Uplinks và Teaming mặc định
  uplinks         = var.vds_uplinks
  active_uplinks  = var.vds_active_uplinks
  standby_uplinks = var.vds_standby_uplinks

  # Kích hoạt Network I/O Control (NetIOC v3)
  network_resource_control_enabled = var.enable_netioc
  network_resource_control_version = "version3"

  # Tự động gán card mạng vật lý của Host vào vDS nếu có khai báo vds_physical_nics
  dynamic "host" {
    for_each = length(var.vds_physical_nics) > 0 ? vsphere_host.hosts : {}
    content {
      host_system_id = host.value.id
      devices        = var.vds_physical_nics
    }
  }

  depends_on = [vsphere_host.hosts]
}

# Khởi tạo danh mục Distributed Port Groups trên vDS
resource "vsphere_distributed_port_group" "pg" {
  for_each                        = var.create_vds ? var.vds_portgroups : {}
  name                            = each.key
  distributed_virtual_switch_uuid = vsphere_distributed_virtual_switch.vds[0].id

  # Cấu hình VLAN ID (0: Untagged/Standard, 1-4094: VLAN Tagging)
  vlan_id = each.value.vlan_id

  # Cấu hình Teaming và Failover
  teaming_policy  = each.value.teaming_policy
  notify_switches = true
  failback        = true

  # Cấu hình Traffic Shaping (Kiểm soát băng thông Ingress và Egress)
  ingress_shaping_enabled           = each.value.shaping_enabled
  ingress_shaping_average_bandwidth = each.value.ingress_shaping_average_bandwidth
  ingress_shaping_peak_bandwidth    = each.value.ingress_shaping_peak_bandwidth
  ingress_shaping_burst_size        = each.value.ingress_shaping_burst_size

  egress_shaping_enabled           = each.value.shaping_enabled
  egress_shaping_average_bandwidth = each.value.egress_shaping_average_bandwidth
  egress_shaping_peak_bandwidth    = each.value.egress_shaping_peak_bandwidth
  egress_shaping_burst_size        = each.value.egress_shaping_burst_size

  # Cấu hình bảo mật cổng mạng (Security Policies)
  allow_promiscuous      = each.value.allow_promiscuous
  allow_forged_transmits = false
  allow_mac_changes      = false
}

# ------------------------------------------------------------------------------
# B. BỘ CHUYỂN MẠCH TIÊU CHUẨN (STANDARD VSWITCH - VSS)
# ------------------------------------------------------------------------------
locals {
  # Cặp ánh xạ Host x Standard Switch
  host_vswitches = var.create_standard_vswitches ? flatten([
    for host_key, host_res in vsphere_host.hosts : [
      for sw_name, sw_cfg in var.standard_vswitches : {
        key              = "${host_key}_${sw_name}"
        host_system_id   = host_res.id
        name             = sw_name
        network_adapters = sw_cfg.network_adapters
        active_nics      = sw_cfg.active_nics
        standby_nics     = sw_cfg.standby_nics
        mtu              = sw_cfg.mtu
      }
    ]
  ]) : []

  # Cặp ánh xạ Host x Standard Port Group
  host_portgroups = var.create_standard_vswitches ? flatten([
    for host_key, host_res in vsphere_host.hosts : [
      for pg_name, pg_cfg in var.standard_portgroups : {
        key                 = "${host_key}_${pg_name}"
        host_system_id      = host_res.id
        name                = pg_name
        virtual_switch_name = pg_cfg.vswitch_name
        vlan_id             = pg_cfg.vlan_id
      }
    ]
  ]) : []
}

resource "vsphere_host_virtual_switch" "standard_vswitch" {
  for_each         = { for item in local.host_vswitches : item.key => item }
  host_system_id   = each.value.host_system_id
  name             = each.value.name
  network_adapters = each.value.network_adapters
  active_nics      = each.value.active_nics
  standby_nics     = each.value.standby_nics
  mtu              = each.value.mtu

  depends_on = [vsphere_host.hosts]
}

resource "vsphere_host_port_group" "standard_pg" {
  for_each            = { for item in local.host_portgroups : item.key => item }
  host_system_id      = each.value.host_system_id
  name                = each.value.name
  virtual_switch_name = each.value.virtual_switch_name
  vlan_id             = each.value.vlan_id

  depends_on = [vsphere_host_virtual_switch.standard_vswitch]
}
