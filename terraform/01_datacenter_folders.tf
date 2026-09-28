# ==============================================================================
# 01. KHỞI TẠO DATACENTER VÀ CẤU TRÚC THƯ MỤC PHÂN CẤP (FOLDERS)
# ==============================================================================

# Khởi tạo Datacenter gốc
resource "vsphere_datacenter" "dc" {
  name = var.datacenter_name
}

# Khởi tạo cấu trúc các thư mục quản lý máy ảo (VM Folders)
resource "vsphere_folder" "vm_folders" {
  for_each      = toset(var.vm_folders)
  path          = each.value
  type          = "vm"
  datacenter_id = vsphere_datacenter.dc.id
}
