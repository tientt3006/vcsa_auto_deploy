# ==============================================================================
# 03. TỰ ĐỘNG THÊM MÁY CHỦ ESXI VÀO CLUSTER HOẶC DATACENTER ĐỘC LẬP
# ==============================================================================

# Tự động truy vấn và lấy chứng chỉ SSL Thumbprint của từng máy chủ ESXi
data "vsphere_host_thumbprint" "thumbprint" {
  for_each = { for h in var.esxi_hosts : h.hostname => h }
  address  = each.value.hostname
  insecure = true
}

# Tiến hành thêm ESXi Host vào Compute Cluster hoặc Datacenter
resource "vsphere_host" "hosts" {
  for_each   = { for h in var.esxi_hosts : h.hostname => h }
  hostname   = each.value.hostname
  username   = each.value.username
  password   = each.value.password
  thumbprint = data.vsphere_host_thumbprint.thumbprint[each.key].id

  cluster    = var.create_cluster ? vsphere_compute_cluster.cluster[0].id : null
  datacenter = var.create_cluster ? null : vsphere_datacenter.dc.moid

  # Bỏ qua thay đổi mật khẩu sau khi nạp để tránh kích hoạt lại quy trình reconnect
  lifecycle {
    ignore_changes = [password]
  }

  depends_on = [vsphere_compute_cluster.cluster]
}
