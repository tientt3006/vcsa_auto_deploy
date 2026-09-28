#!/usr/bin/env bash
# ==============================================================================
# Module: 06_terraform_vcsa_config.sh
# Mục đích: Điều phối tự động hóa cấu hình vCenter Day-2 bằng Terraform
# Tác vụ:
#   - Tự động kiểm tra và cài đặt công cụ Terraform nếu chưa có
#   - Quản lý tệp tham số terraform.tfvars độc lập (không gộp vào config.env)
#   - Kiểm tra lặp (validation loop) yêu cầu người dùng hoàn tất điền placeholder <...>
#   - Hỗ trợ mô hình hạ tầng tổng quát: vDS / VSS, VLAN, Teaming, NetIOC, SIOC, RBAC
#   - Thực thi Terraform Init, Plan, Apply và Destroy an toàn, bảo mật mật khẩu
# ==============================================================================
set -euo pipefail

# Kiểm tra hoặc tự động cài đặt công cụ Terraform trên Linux Ubuntu/Debian
check_or_install_terraform() {
    if command -v terraform &>/dev/null; then
        local tf_version
        tf_version="$(terraform version | head -n 1)"
        log_info "Phát hiện công cụ Terraform đã sẵn sàng: ${tf_version}"
        return 0
    fi

    log_warn "Chưa tìm thấy công cụ Terraform trên hệ thống."
    if ! command -v apt-get &>/dev/null; then
        log_error "Môi trường hiện tại không hỗ trợ apt-get. Vui lòng cài đặt Terraform thủ công."
        return 1
    fi

    log_step "Tiến hành cài đặt Terraform phiên bản 1.8.5..."
    local tf_ver="1.8.5"
    local tf_zip="/tmp/terraform_${tf_ver}_linux_amd64.zip"

    if command -v curl &>/dev/null; then
        curl -fsSL "https://releases.hashicorp.com/terraform/${tf_ver}/terraform_${tf_ver}_linux_amd64.zip" -o "${tf_zip}"
    elif command -v wget &>/dev/null; then
        wget -q "https://releases.hashicorp.com/terraform/${tf_ver}/terraform_${tf_ver}_linux_amd64.zip" -O "${tf_zip}"
    else
        log_error "Không tìm thấy curl hoặc wget để tải gói cài đặt Terraform."
        return 1
    fi

    # Cài đặt unzip nếu chưa có
    if ! command -v unzip &>/dev/null; then
        if [[ $EUID -eq 0 ]]; then
            DEBIAN_FRONTEND=noninteractive apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq unzip
        elif sudo -n true 2>/dev/null; then
            sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq && sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq unzip
        fi
    fi

    if [[ $EUID -eq 0 ]]; then
        unzip -q -o "${tf_zip}" -d /usr/local/bin/
        chmod +x /usr/local/bin/terraform
    elif sudo -n true 2>/dev/null; then
        sudo unzip -q -o "${tf_zip}" -d /usr/local/bin/
        sudo chmod +x /usr/local/bin/terraform
    else
        mkdir -p "${HOME}/.local/bin"
        unzip -q -o "${tf_zip}" -d "${HOME}/.local/bin/"
        chmod +x "${HOME}/.local/bin/terraform"
        export PATH="${HOME}/.local/bin:${PATH}"
    fi

    rm -f "${tf_zip}"
    log_success "Đã cài đặt Terraform thành công: $(terraform version | head -n 1)"
    return 0
}

# Khởi tạo tệp terraform.tfvars nếu chưa tồn tại
ensure_terraform_tfvars() {
    local base_dir="$1"
    local tf_dir="${base_dir}/terraform"
    local tfvars_file="${tf_dir}/terraform.tfvars"
    local example_file="${tf_dir}/terraform.tfvars.example"

    if [[ ! -f "${tfvars_file}" ]]; then
        if [[ -f "${example_file}" ]]; then
            log_info "Chưa tìm thấy 'terraform.tfvars'. Khởi tạo từ tệp mẫu '${example_file}'..."
            cp "${example_file}" "${tfvars_file}"
            log_success "Đã tạo '${tfvars_file}'. Tệp này nằm trong .gitignore và không bị commit lên Git."
        else
            log_error "Không tìm thấy tệp mẫu: ${example_file}"
            return 1
        fi
    fi
    return 0
}

# Đảm bảo môi trường Terraform Provider đã được khởi tạo (terraform init)
ensure_terraform_initialized() {
    local base_dir="$1"
    local tf_dir="${base_dir}/terraform"

    if [[ ! -d "${tf_dir}/.terraform" || ! -f "${tf_dir}/.terraform.lock.hcl" ]]; then
        log_step "Khởi tạo môi trường nhà cung cấp Terraform (Tự động chạy 'terraform init')..."
        if ! (cd "${tf_dir}" && terraform init -input=false); then
            log_error "Lỗi khởi tạo Terraform Provider qua 'terraform init'. Vui lòng kiểm tra kết nối mạng Internet."
            return 1
        fi
        log_success "Đã khởi tạo thành công môi trường Terraform Provider."
    fi
    return 0
}

# Kiểm tra lặp (validation loop) đến khi người dùng điền hết toàn bộ placeholder <...>
validate_and_prompt_tfvars() {
    local base_dir="$1"
    local tf_dir="${base_dir}/terraform"
    local tfvars_file="${tf_dir}/terraform.tfvars"

    ensure_terraform_tfvars "${base_dir}" || return 1
    ensure_terraform_initialized "${base_dir}" || return 1

    local editor_cmd="${EDITOR:-nano}"
    if ! command -v "${editor_cmd}" &>/dev/null; then
        editor_cmd="vi"
    fi

    while true; do
        local -a placeholders=()
        while IFS= read -r line; do
            local content="${line#*:}"
            # Bỏ qua các dòng chỉ chứa ghi chú (#)
            if [[ -n "${content}" && ! "${content}" =~ ^[[:space:]]*# ]]; then
                placeholders+=("${line}")
            fi
        done < <(grep -n '<[^>]*>' "${tfvars_file}" 2>/dev/null || true)

        if [[ ${#placeholders[@]} -gt 0 ]]; then
            echo ""
            log_warn "Phát hiện ${#placeholders[@]} thông số trong 'terraform.tfvars' chưa được điền (còn ký hiệu <...>):"
            echo -e "${C_RED}------------------------------------------------------------------------------${C_RESET}"
            for item in "${placeholders[@]}"; do
                echo -e "  Dòng ${item}"
            done
            echo -e "${C_RED}------------------------------------------------------------------------------${C_RESET}"
            echo -e "Đường dẫn tệp cấu hình: ${C_YELLOW}${tfvars_file}${C_RESET}"
            echo ""
            echo -e "  ${C_BOLD}[1]${C_RESET} Mở trình soạn thảo (${editor_cmd}) để điền thông số ngay bây giờ"
            echo -e "  ${C_BOLD}[2]${C_RESET} Tôi đã hoàn thành điền bằng tệp/IDE khác, tiến hành kiểm tra lại"
            echo -e "  ${C_BOLD}[0]${C_RESET} Hủy bỏ và quay lại menu trước"
            echo -e "${C_BLUE}------------------------------------------------------------------------------${C_RESET}"
            local action_choice=""
            read -r -p "Vui lòng chọn thao tác [1/2/0]: " action_choice

            case "${action_choice}" in
                1)
                    "${editor_cmd}" "${tfvars_file}"
                    continue
                    ;;
                2)
                    continue
                    ;;
                0)
                    log_info "Người dùng hủy bỏ quá trình cấu hình Terraform."
                    return 1
                    ;;
                *)
                    log_warn "Lựa chọn không hợp lệ."
                    continue
                    ;;
            esac
        fi

        # Kiểm tra tính hợp lệ cú pháp HCL với terraform validate
        log_step "Kiểm tra cú pháp cấu hình Terraform (terraform validate)..."
        local validate_output=""
        if ! validate_output="$(cd "${tf_dir}" && terraform validate 2>&1)"; then
            # Tự động khắc phục nếu phát hiện thiếu provider plugin
            if echo "${validate_output}" | grep -qi "Missing required provider"; then
                log_warn "Phát hiện thiếu plugin provider. Tiến hành 'terraform init' tự động..."
                if (cd "${tf_dir}" && terraform init -input=false); then
                    validate_output="$(cd "${tf_dir}" && terraform validate 2>&1)" || true
                fi
            fi
        fi

        if ! (cd "${tf_dir}" && terraform validate &>/dev/null); then
            echo ""
            log_error "Phát hiện lỗi cú pháp trong cấu hình Terraform:"
            echo -e "${C_RED}${validate_output}${C_RESET}"
            echo ""
            echo -e "  ${C_BOLD}[1]${C_RESET} Mở trình soạn thảo (${editor_cmd}) để sửa lỗi"
            echo -e "  ${C_BOLD}[2]${C_RESET} Đã sửa xong, kiểm tra lại"
            echo -e "  ${C_BOLD}[0]${C_RESET} Hủy bỏ"
            local err_choice=""
            read -r -p "Vui lòng chọn [1/2/0]: " err_choice
            case "${err_choice}" in
                1)
                    "${editor_cmd}" "${tfvars_file}"
                    continue
                    ;;
                2)
                    continue
                    ;;
                *)
                    return 1
                    ;;
            esac
        fi

        log_success "Tệp cấu hình 'terraform.tfvars' hợp lệ và không còn placeholder nào."
        break
    done

    return 0
}

# Tiếp nhận mật khẩu quản trị SSO vCenter an toàn (nếu để trống trong tfvars)
prompt_terraform_credentials() {
    local base_dir="$1"
    local tf_dir="${base_dir}/terraform"
    local tfvars_file="${tf_dir}/terraform.tfvars"

    # Nếu biến môi trường TF_VAR_vsphere_password đã được thiết lập thì tái sử dụng
    if [[ -n "${TF_VAR_vsphere_password:-}" ]]; then
        return 0
    fi

    # Kiểm tra xem vsphere_password trong terraform.tfvars có được khai báo hay để trống ""
    local tfvars_pass=""
    if [[ -f "${tfvars_file}" ]]; then
        tfvars_pass="$(grep -E '^\s*vsphere_password\s*=' "${tfvars_file}" 2>/dev/null | cut -d'=' -f2- | tr -d ' "' || true)"
    fi

    # Nếu người dùng để trống hoặc không khai báo trong file để tăng tính bảo mật, nhận qua terminal ẩn
    if [[ -z "${tfvars_pass}" ]]; then
        local vcenter_target="vCenter"
        if [[ -f "${tfvars_file}" ]]; then
            local parsed_server
            parsed_server="$(grep -E '^\s*vsphere_server\s*=' "${tfvars_file}" 2>/dev/null | cut -d'=' -f2- | tr -d ' "' || true)"
            if [[ -n "${parsed_server}" ]]; then
                vcenter_target="${parsed_server}"
            fi
        fi

        local vcenter_pass=""
        prompt_secret "Nhập mật khẩu quản trị vCenter SSO (${vcenter_target})" vcenter_pass
        export TF_VAR_vsphere_password="${vcenter_pass}"
        log_info "Đã nạp mật khẩu SSO vCenter vào phiên làm việc qua biến môi trường RAM."
    fi
}

# Khởi tạo môi trường nhà cung cấp Terraform (Terraform Init)
terraform_init_action() {
    local base_dir="$1"
    print_section "KHỞI TẠO MÔI TRƯỜNG TERRAFORM VSPHERE PROVIDER"

    check_or_install_terraform || return 1
    ensure_terraform_tfvars "${base_dir}" || return 1

    local tf_dir="${base_dir}/terraform"
    log_step "Thực thi 'terraform init' tại ${tf_dir}..."
    (
        cd "${tf_dir}"
        terraform init
    )
    log_success "Khởi tạo môi trường Terraform thành công."
}

# Lập kế hoạch và kiểm tra mô phỏng cấu hình (Terraform Plan)
terraform_plan_action() {
    local base_dir="$1"
    print_section "LẬP KẾ HOẠCH CẤU HÌNH VCENTER DAY-2 (TERRAFORM PLAN)"

    check_or_install_terraform || return 1
    validate_and_prompt_tfvars "${base_dir}" || return 0
    prompt_terraform_credentials "${base_dir}"

    local tf_dir="${base_dir}/terraform"
    log_step "Thực thi 'terraform plan' để mô phỏng toàn bộ tài nguyên sẽ tạo..."
    (
        cd "${tf_dir}"
        terraform plan -out=tfplan.binary
    )
    echo ""
    log_info "Kế hoạch cấu hình đã được tạo và lưu tại: ${tf_dir}/tfplan.binary"
    log_success "Mô phỏng hoàn tất. Người dùng có thể chọn chức năng Apply để áp dụng thực tế."
}

# Thực thi áp dụng cấu hình tự động lên vCenter (Terraform Apply)
terraform_apply_action() {
    local base_dir="$1"
    print_section "THỰC THI CẤU HÌNH TOÀN DIỆN VCENTER DAY-2 (TERRAFORM APPLY)"

    check_or_install_terraform || return 1
    validate_and_prompt_tfvars "${base_dir}" || return 0
    prompt_terraform_credentials "${base_dir}"

    local tf_dir="${base_dir}/terraform"
    local tfvars_file="${tf_dir}/terraform.tfvars"

    # Trích xuất thông tin tóm tắt để hiển thị người dùng kiểm tra trước khi xác nhận
    local vcenter_target="Chưa xác định"
    if [[ -f "${tfvars_file}" ]]; then
        vcenter_target="$(grep -E '^\s*vsphere_server\s*=' "${tfvars_file}" 2>/dev/null | cut -d'=' -f2- | tr -d ' "' || echo "Chưa xác định")"
    fi

    log_step "Chuẩn bị áp dụng cấu hình lên mục tiêu vCenter: ${vcenter_target}..."
    echo -e "${C_YELLOW}Các hạng mục được thiết lập tự động (theo khai báo tại terraform.tfvars):${C_RESET}"
    echo "  1. Datacenter & cấu trúc thư mục VM Folders"
    echo "  2. Compute Cluster, DRS tự động hóa & vSphere HA Admission Control"
    echo "  3. Tự động truy vấn SSL Thumbprint và nạp các máy chủ ESXi Hosts"
    echo "  4. Mạng chuyển mạch phân tán (vDS với NetIOC v3) hoặc Standard vSwitch (VSS)"
    echo "  5. Danh mục Port Groups (VLAN, Teaming & Failover, Traffic Shaping, Security)"
    echo "  6. Datastore Cluster (Storage DRS & SIOC) & Thư viện nội dung Content Library"
    echo "  7. Phân quyền và các vai trò quản trị tùy biến động (RBAC Custom Roles)"
    echo ""

    local confirm=""
    read -r -p "Xác nhận thực thi áp dụng cấu hình ngay bây giờ? (y/N): " confirm
    if [[ ! "${confirm}" =~ ^[Yy]$ ]]; then
        log_info "Đã hủy bỏ thao tác thực thi theo yêu cầu người dùng."
        return 0
    fi

    local apply_status=0
    (
        cd "${tf_dir}"
        if [[ -f "tfplan.binary" ]]; then
            terraform apply "tfplan.binary"
            rm -f "tfplan.binary"
        else
            terraform apply -auto-approve
        fi
    ) || apply_status=$?

    if [[ ${apply_status} -ne 0 ]]; then
        echo ""
        log_error "Quá trình thực thi 'terraform apply' không thành công (Mã lỗi: ${apply_status})."
        log_warn "Vui lòng kiểm tra lại log chi tiết lỗi ở trên để xử lý."
        return ${apply_status}
    fi

    echo ""
    log_success "=========================================================================="
    log_success "CẤU HÌNH TỰ ĐỘNG HẠ TẦNG VCENTER (DAY-2 PROVISIONING) HOÀN TẤT!"
    log_success "=========================================================================="
    echo "Kiểm tra trực tiếp trên giao diện vSphere Client tại: https://${vcenter_target}/ui"
    echo "=========================================================================="
}

# Hủy bỏ tài nguyên đã cấu hình (Terraform Destroy)
terraform_destroy_action() {
    local base_dir="$1"
    print_section "HỦY BỎ TÀI NGUYÊN CẤU HÌNH VCENTER (TERRAFORM DESTROY)"

    check_or_install_terraform || return 1
    validate_and_prompt_tfvars "${base_dir}" || return 0
    prompt_terraform_credentials "${base_dir}"

    local tf_dir="${base_dir}/terraform"
    log_warn "CẢNH BÁO NGUY HIỂM: Thao tác này sẽ xóa Datacenter, Cluster, vDS, Port Groups và gỡ ESXi khỏi vCenter!"
    echo -n "Vui lòng nhập chính xác chữ 'DESTROY' để xác nhận hủy bỏ tài nguyên: "
    local confirm_text=""
    read -r confirm_text

    if [[ "${confirm_text}" != "DESTROY" ]]; then
        log_info "Chuỗi xác nhận không trùng khớp. Đã hủy bỏ thao tác."
        return 0
    fi

    local destroy_status=0
    (
        cd "${tf_dir}"
        terraform destroy -auto-approve
    ) || destroy_status=$?

    if [[ ${destroy_status} -ne 0 ]]; then
        echo ""
        log_error "Quá trình thực thi 'terraform destroy' không thành công (Mã lỗi: ${destroy_status})."
        return ${destroy_status}
    fi

    log_success "Đã gỡ bỏ toàn bộ tài nguyên cấu hình Terraform."
}

# Menu con điều khiển chuyên sâu cấu hình Terraform Day-2
manage_terraform_menu() {
    local base_dir="$1"
    local tf_dir="${base_dir}/terraform"
    local tfvars_file="${tf_dir}/terraform.tfvars"
    local sub_choice=""

    while true; do
        clear || true
        local current_server="Chưa cấu hình"
        if [[ -f "${tfvars_file}" ]]; then
            local parsed
            parsed="$(grep -E '^\s*vsphere_server\s*=' "${tfvars_file}" 2>/dev/null | cut -d'=' -f2- | tr -d ' "' || true)"
            if [[ -n "${parsed}" && "${parsed}" != *"<"*">"* ]]; then
                current_server="${parsed}"
            elif [[ "${parsed}" == *"<"*">"* ]]; then
                current_server="Chưa điền (${parsed})"
            fi
        fi

        echo -e "${C_BLUE}==============================================================================${C_RESET}"
        echo -e "${C_WHITE}${C_BOLD}   CẤU HÌNH TỰ ĐỘNG HẠ TẦNG VCENTER (TERRAFORM DAY-2 PROVISIONING)${C_RESET}"
        echo -e "${C_BLUE}==============================================================================${C_RESET}"
        echo -e " Mục tiêu vCenter : ${C_CYAN}${current_server}${C_RESET}"
        echo -e " Tệp tham số      : ${C_CYAN}terraform/terraform.tfvars${C_RESET}"
        echo -e "${C_BLUE}==============================================================================${C_RESET}"
        echo -e "  ${C_BOLD}[1]${C_RESET} Khởi tạo môi trường nhà cung cấp (Terraform Init)"
        echo -e "  ${C_BOLD}[2]${C_RESET} Kiểm tra và chỉnh sửa tệp tham số cấu hình (Validate & Edit terraform.tfvars)"
        echo -e "  ${C_BOLD}[3]${C_RESET} Lập kế hoạch và kiểm tra mô phỏng cấu hình (Terraform Plan)"
        echo -e "  ${C_BOLD}[4]${C_RESET} Thực thi áp dụng cấu hình tự động toàn diện (Terraform Apply)"
        echo -e "  ${C_BOLD}[5]${C_RESET} Hủy bỏ tài nguyên cấu hình vCenter (Terraform Destroy - Thận trọng)"
        echo -e "${C_BLUE}------------------------------------------------------------------------------${C_RESET}"
        echo -e "  ${C_BOLD}[0]${C_RESET} Quay lại menu chính"
        echo -e "${C_BLUE}==============================================================================${C_RESET}"
        echo -n "Vui lòng nhập lựa chọn [0-5]: "
        read -r sub_choice

        case "${sub_choice}" in
            1)
                clear || true
                terraform_init_action "${base_dir}" || true
                pause_menu
                ;;
            2)
                clear || true
                validate_and_prompt_tfvars "${base_dir}" || true
                pause_menu
                ;;
            3)
                clear || true
                terraform_plan_action "${base_dir}" || true
                pause_menu
                ;;
            4)
                clear || true
                terraform_apply_action "${base_dir}" || true
                pause_menu
                ;;
            5)
                clear || true
                terraform_destroy_action "${base_dir}" || true
                pause_menu
                ;;
            0)
                break
                ;;
            *)
                log_warn "Lựa chọn không hợp lệ."
                sleep 1
                ;;
        esac
    done
}
