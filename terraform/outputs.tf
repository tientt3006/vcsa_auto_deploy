# ==============================================================================
# ĐẦU RA TỔNG KẾT TÀI NGUYÊN (TERRAFORM OUTPUTS)
# ==============================================================================

output "datacenter_id" {
  description = "Managed Object ID của Datacenter"
  value       = vsphere_datacenter.dc.moid
}

output "cluster_id" {
  description = "Managed Object ID của Compute Cluster (null nếu không tạo cụm)"
  value       = var.create_cluster ? vsphere_compute_cluster.cluster[0].id : null
}

output "onboarded_hosts" {
  description = "Danh sách các máy chủ ESXi đã nạp thành công vào vCenter"
  value       = { for k, v in vsphere_host.hosts : k => v.id }
}

output "vm_folders" {
  description = "Bản đồ các thư mục máy ảo đã khởi tạo"
  value       = { for k, v in vsphere_folder.vm_folders : k => v.id }
}

output "vds_id" {
  description = "ID của vSphere Distributed Switch (null nếu không tạo vDS)"
  value       = var.create_vds ? vsphere_distributed_virtual_switch.vds[0].id : null
}

output "distributed_port_groups" {
  description = "Bản đồ danh mục Distributed Port Groups đã khởi tạo"
  value       = { for k, v in vsphere_distributed_port_group.pg : k => v.id }
}

output "standard_vswitches" {
  description = "Bản đồ danh mục Standard vSwitch đã khởi tạo trên các Host"
  value       = { for k, v in vsphere_host_virtual_switch.standard_vswitch : k => v.id }
}

output "standard_portgroups" {
  description = "Bản đồ danh mục Standard Port Groups đã khởi tạo"
  value       = { for k, v in vsphere_host_port_group.standard_pg : k => v.id }
}

output "datastore_cluster_id" {
  description = "ID của Datastore Cluster (null nếu không tạo cụm kho lưu trữ)"
  value       = var.create_datastore_cluster ? vsphere_datastore_cluster.datastore_cluster[0].id : null
}

output "content_library_id" {
  description = "ID của vSphere Content Library (null nếu không tạo thư viện)"
  value       = (var.create_content_library && var.primary_datastore_name != "") ? vsphere_content_library.library[0].id : null
}

output "custom_roles" {
  description = "Bản đồ ID các vai trò phân quyền tùy biến đã khởi tạo"
  value       = { for k, v in vsphere_role.custom : k => v.id }
}

output "host_vnics" {
  description = "Bản đồ ID các cổng VMkernel NICs đã khởi tạo trên các Host"
  value       = { for k, v in vsphere_vnic.vnic : k => v.id }
}

output "vm_anti_affinity_rules" {
  description = "Bản đồ ID các quy tắc DRS Anti-Affinity đã khởi tạo"
  value       = { for k, v in vsphere_compute_cluster_vm_anti_affinity_rule.vm_anti_affinity : k => v.id }
}
