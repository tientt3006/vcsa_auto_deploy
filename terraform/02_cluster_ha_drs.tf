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
  ha_enabled           = var.ha_enabled
  ha_host_monitoring   = var.ha_host_monitoring
  ha_vm_monitoring     = var.ha_vm_monitoring

  # ----------------------------------------------------------------------------
  # Cấu hình chính sách kiểm soát dung lượng (HA Admission Control)
  # ----------------------------------------------------------------------------
  ha_admission_control_policy                     = var.ha_admission_control_policy
  ha_admission_control_host_failure_tolerance     = var.ha_admission_control_host_failure_tolerance
  ha_admission_control_resource_percentage_cpu    = var.ha_admission_control_cpu_percentage
  ha_admission_control_resource_percentage_memory = var.ha_admission_control_ram_percentage
}
