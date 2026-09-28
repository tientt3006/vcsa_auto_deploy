# ==============================================================================
# 06. PHÂN QUYỀN VÀ VAI TRÒ TÙY BIẾN (CUSTOM ROLES & PERMISSIONS RBAC)
# ==============================================================================

# Khởi tạo danh mục các vai trò quản trị tùy biến động theo khai báo trong custom_roles
resource "vsphere_role" "custom" {
  for_each        = var.custom_roles
  name            = each.key
  role_privileges = each.value.role_privileges
}
