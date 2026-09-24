#!/usr/bin/env bash
# ==============================================================================
# Script: run.sh
# Muc dich: Diem khoi chay duy nhat (Single Entrypoint) tich hop giao dien TUI
#           dieu phoi toan bo quy trinh tu dong hoa VMware ESXi & VCSA
# Tac vu:
#   - Giai doan 1: Khoi tao nut mam dieu khien (Seed VM) tu may tram khoi tao
#   - Giai doan 2: Thiet lap moi truong DNS va trien khai VCSA tu nut dieu khien
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/lib"

# Nap thu vien tien ich dung chung
if [[ ! -f "${LIB_DIR}/common.sh" ]]; then
    echo "Loi: Khong tim thay thu vien ${LIB_DIR}/common.sh" >&2
    exit 1
fi
# shellcheck source=/dev/null
source "${LIB_DIR}/common.sh"

# Nap cac module chuc nang
# shellcheck source=/dev/null
source "${LIB_DIR}/01_deploy_ubuntu_node.sh"
# shellcheck source=/dev/null
source "${LIB_DIR}/02_setup_environment.sh"
# shellcheck source=/dev/null
source "${LIB_DIR}/03_deploy_vcsa.sh"
# shellcheck source=/dev/null
source "${LIB_DIR}/04_health_check.sh"
# shellcheck source=/dev/null
source "${LIB_DIR}/05_iso_manager.sh"

# Nhan dien moi truong dang thuc thi
detect_environment() {
    local env_name="May tram khoi tao (Operator Workstation)"
    if [[ -f "/etc/os-release" ]]; then
        if grep -q "Ubuntu" "/etc/os-release" && [[ "$(hostname)" =~ (ubuntu|automation|UBUNTU) ]]; then
            env_name="Nut dieu khien tu dong (Automation Seed Node)"
        fi
    fi
    echo "${env_name}"
}

# Hien thi trang thai cau hinh
get_config_status() {
    if [[ ! -f "${SCRIPT_DIR}/config.env" ]]; then
        echo -e "${C_RED}Chua khoi tao (Chua co config.env)${C_RESET}"
        return
    fi

    if grep -q '<.*>' "${SCRIPT_DIR}/config.env" 2>/dev/null; then
        echo -e "${C_YELLOW}Chua hoan thien (Con placeholder <...>)${C_RESET}"
        return
    fi

    echo -e "${C_GREEN}Hop le (San sang)${C_RESET}"
}

# Ham tam dung de nguoi dung doc ket qua truoc khi quay lai menu
pause_menu() {
    echo ""
    read -r -p "Nhan [Enter] de quay lai menu chinh..." _
}

# Vong lap hien thi giao dien TUI Menu
show_menu() {
    local choice=""

    while true; do
        clear || true
        local current_env
        current_env="$(detect_environment)"
        local config_status
        config_status="$(get_config_status)"

        echo -e "${C_BLUE}==============================================================================${C_RESET}"
        echo -e "${C_WHITE}${C_BOLD}   BỘ CÔNG CỤ TỰ ĐỘNG HÓA HẠ TẦNG VMWARE (VCSA AUTOMATION TOOLKIT)${C_RESET}"
        echo -e "${C_BLUE}==============================================================================${C_RESET}"
        echo -e " Môi trường : ${C_CYAN}${current_env}${C_RESET}"
        echo -e " Cấu hình   : ${config_status}"
        echo -e "${C_BLUE}==============================================================================${C_RESET}"
        echo -e "  ${C_BOLD}[1]${C_RESET} Kiểm tra tính hợp lệ của cấu hình (Config Validation)"
        echo -e "${C_BLUE}------------------------------------------------------------------------------${C_RESET}"
        echo -e "  ${C_MAGENTA}${C_BOLD}GIAI ĐOẠN 1: KHỞI TẠO NÚT MẦM ĐIỀU KHIỂN (BOOTSTRAP SEED NODE)${C_RESET}"
        echo -e "  ${C_BOLD}[2]${C_RESET} Tự động tạo máy ảo Ubuntu Automation trên Standalone ESXi (Seed VM)"
        echo -e "${C_BLUE}------------------------------------------------------------------------------${C_RESET}"
        echo -e "  ${C_MAGENTA}${C_BOLD}GIAI ĐOẠN 2: TRIỂN KHAI VCENTER VÀ HẠ TẦNG (CORE APPLIANCE DEPLOYMENT)${C_RESET}"
        echo -e "  ${C_BOLD}[3]${C_RESET} Thiết lập môi trường và cấu hình dịch vụ DNS nội bộ (dnsmasq)"
        echo -e "  ${C_BOLD}[4]${C_RESET} Tải nhanh tệp ISO VCSA từ liên kết URL (Hỗ trợ đa luồng aria2c)"
        echo -e "  ${C_BOLD}[5]${C_RESET} Quét và chọn tệp ISO từ thư mục chỉ định (Cập nhật config.env)"
        echo -e "  ${C_BOLD}[6]${C_RESET} Tự động triển khai vCenter Server Appliance (VCSA) qua CLI"
        echo -e "${C_BLUE}------------------------------------------------------------------------------${C_RESET}"
        echo -e "  ${C_MAGENTA}${C_BOLD}TIỆN ÍCH VÀ CHẨN ĐOÁN (UTILITIES & DIAGNOSTICS)${C_RESET}"
        echo -e "  ${C_BOLD}[7]${C_RESET} Kiểm tra sức khỏe, thông tuyến mạng và DNS (Health Check)"
        echo -e "  ${C_BOLD}[8]${C_RESET} Quản lý và kiểm tra tệp ISO VCSA (Submenu chi tiết & Mount test)"
        echo -e "  ${C_BOLD}[9]${C_RESET} Mở tệp cấu hình biến hạ tầng (Chỉnh sửa config.env)"
        echo -e "${C_BLUE}------------------------------------------------------------------------------${C_RESET}"
        echo -e "  ${C_BOLD}[0]${C_RESET} Thoát chương trình (Exit)"
        echo -e "${C_BLUE}==============================================================================${C_RESET}"
        echo -n "Vui lòng nhập lựa chọn [0-9]: "
        read -r choice

        case "${choice}" in
            1)
                clear || true
                load_config "${SCRIPT_DIR}" || true
                validate_config "${SCRIPT_DIR}" "all" || true
                pause_menu
                ;;
            2)
                clear || true
                load_config "${SCRIPT_DIR}" || true
                deploy_ubuntu_node "${SCRIPT_DIR}" || true
                pause_menu
                ;;
            3)
                clear || true
                load_config "${SCRIPT_DIR}" || true
                setup_environment "${SCRIPT_DIR}" || true
                pause_menu
                ;;
            4)
                clear || true
                load_config "${SCRIPT_DIR}" || true
                download_iso_from_url "${SCRIPT_DIR}" || true
                pause_menu
                ;;
            5)
                clear || true
                load_config "${SCRIPT_DIR}" || true
                browse_and_select_iso "${SCRIPT_DIR}" || true
                pause_menu
                ;;
            6)
                clear || true
                load_config "${SCRIPT_DIR}" || true
                deploy_vcsa "${SCRIPT_DIR}" || true
                pause_menu
                ;;
            7)
                clear || true
                health_check "${SCRIPT_DIR}" || true
                pause_menu
                ;;
            8)
                clear || true
                load_config "${SCRIPT_DIR}" || true
                manage_vcsa_iso_menu "${SCRIPT_DIR}" || true
                ;;
            9)
                clear || true
                local editor_cmd="${EDITOR:-nano}"
                if ! command -v "${editor_cmd}" &>/dev/null; then
                    editor_cmd="vi"
                fi
                if [[ ! -f "${SCRIPT_DIR}/config.env" ]]; then
                    cp "${SCRIPT_DIR}/config.env.example" "${SCRIPT_DIR}/config.env"
                fi
                "${editor_cmd}" "${SCRIPT_DIR}/config.env"
                ;;
            0)
                echo -e "\n${C_GREEN}Đã thoát chương trình. Tạm biệt!${C_RESET}\n"
                exit 0
                ;;
            *)
                log_warn "Lựa chọn không hợp lệ. Vui lòng nhập từ 0 đến 9."
                sleep 1
                ;;
        esac
    done
}

# Khoi dong chuong trinh
show_menu
