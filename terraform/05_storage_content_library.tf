# ==============================================================================
# 05. KHO LƯU TRỮ, STORAGE I/O CONTROL & CONTENT LIBRARY
# ==============================================================================

# ------------------------------------------------------------------------------
# A. CỤM KHO LƯU TRỮ (DATASTORE CLUSTER VỚI STORAGE DRS & STORAGE I/O CONTROL)
# ------------------------------------------------------------------------------
resource "vsphere_datastore_cluster" "datastore_cluster" {
  count         = var.create_datastore_cluster ? 1 : 0
  name          = var.datastore_cluster_name
  datacenter_id = vsphere_datacenter.dc.moid

  # Cấu hình Storage DRS (SDRS)
  sdrs_enabled          = var.sdrs_enabled
  sdrs_automation_level = var.sdrs_automation_level

  # Cấu hình Storage I/O Control (SIOC - Ngưỡng độ trễ IO mili-giây)
  sdrs_io_latency_threshold = var.sdrs_io_latency_threshold
}

# ------------------------------------------------------------------------------
# B. THƯ VIỆN NỘI DUNG (VSPHERE CONTENT LIBRARY)
# ------------------------------------------------------------------------------
# Truy vấn thông tin Datastore chính trên ESXi sau khi Host đã được nạp
data "vsphere_datastore" "primary_ds" {
  count         = (var.create_content_library && var.primary_datastore_name != "") ? 1 : 0
  name          = var.primary_datastore_name
  datacenter_id = vsphere_datacenter.dc.moid

  depends_on = [vsphere_host.hosts]
}

# Khởi tạo thư viện nội dung vSphere Content Library cục bộ
resource "vsphere_content_library" "library" {
  count           = (var.create_content_library && var.primary_datastore_name != "") ? 1 : 0
  name            = var.content_library_name
  description     = "Thư viện nội dung tự động hóa quản lý ISO, OVF/OVA và VM Templates"
  storage_backing = [data.vsphere_datastore.primary_ds[0].id]

  depends_on = [data.vsphere_datastore.primary_ds]
}
