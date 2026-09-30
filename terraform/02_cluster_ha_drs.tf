# ==============================================================================
# 02. KHỞI TẠO CỤM TÍNH TOÁN (COMPUTE CLUSTER), CẤU HÌNH DRS, HA & ADMISSION CONTROL
# ==============================================================================

resource "vsphere_compute_cluster" "cluster" {
  count         = var.create_cluster ? 1 : 0
  name          = var.cluster_name
  datacenter_id = vsphere_datacenter.dc.moid

  # ----------------------------------------------------------------------------
  # Cấu hình vSphere DRS (Distributed Resource Scheduler)
  # ----------------------------------------------------------------------------
  drs_enabled             = var.drs_enabled
  drs_automation_level    = var.drs_automation_level
  drs_migration_threshold = var.drs_migration_threshold

  # ----------------------------------------------------------------------------
  # Cấu hình vSphere HA (High Availability)
  # ----------------------------------------------------------------------------
  ha_enabled         = var.ha_enabled
  ha_host_monitoring = var.ha_host_monitoring
  ha_vm_monitoring   = var.ha_vm_monitoring

  # ----------------------------------------------------------------------------
  # Cấu hình chính sách kiểm soát dung lượng (HA Admission Control)
  # ----------------------------------------------------------------------------
  ha_admission_control_policy                     = var.ha_admission_control_policy
  ha_admission_control_host_failure_tolerance     = var.ha_admission_control_host_failure_tolerance
  ha_admission_control_resource_percentage_cpu    = var.ha_admission_control_cpu_percentage
  ha_admission_control_resource_percentage_memory = var.ha_admission_control_ram_percentage

  # ----------------------------------------------------------------------------
  # Cấu hình kênh giám sát nhịp tim Datastore Heartbeating (HA-04)
  # ----------------------------------------------------------------------------
  ha_heartbeat_datastore_policy = var.ha_heartbeat_datastore_policy
  ha_heartbeat_datastore_ids    = var.ha_heartbeat_datastore_ids

  # ----------------------------------------------------------------------------
  # Cấu hình tham số nâng cao vSphere HA (HA Advanced Options)
  # ----------------------------------------------------------------------------
  ha_advanced_options = length(var.ha_advanced_options) > 0 ? var.ha_advanced_options : null
}

# ------------------------------------------------------------------------------
# Quy tắc phân tách máy ảo dự phòng (DRS VM Anti-Affinity Rules - HA-05)
# ------------------------------------------------------------------------------
resource "vsphere_compute_cluster_vm_anti_affinity_rule" "vm_anti_affinity" {
  for_each            = var.create_cluster ? var.vm_anti_affinity_rules : {}
  name                = each.key
  compute_cluster_id  = vsphere_compute_cluster.cluster[0].id
  virtual_machine_ids = each.value.virtual_machine_ids
  enabled             = each.value.enabled
  mandatory           = each.value.mandatory
}
