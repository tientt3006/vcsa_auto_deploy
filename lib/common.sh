#!/usr/bin/env bash
# ==============================================================================
# Thu vien tien ich dung chung (Common Library)
# Bo cong cu tu dong hoa trien khai VMware ESXi & VCSA
# ==============================================================================

# Dinh nghia ma mau ANSI
C_RESET="\033[0m"
C_RED="\033[1;31m"
C_GREEN="\033[1;32m"
C_YELLOW="\033[1;33m"
C_BLUE="\033[1;34m"
C_MAGENTA="\033[1;35m"
C_CYAN="\033[1;36m"
C_WHITE="\033[1;37m"
C_BOLD="\033[1m"

# Dinh nghia cac ham ghi log
log_info() {
    echo -e "${C_BLUE}[THONG TIN]${C_RESET} $*"
}

log_step() {
    echo -e "\n${C_CYAN}${C_BOLD}==> $*${C_RESET}"
}

log_success() {
    echo -e "${C_GREEN}[THANH CONG]${C_RESET} $*"
}

log_warn() {
    echo -e "${C_YELLOW}[CANH BAO]${C_RESET} $*" >&2
}

log_error() {
    echo -e "${C_RED}[LOI]${C_RESET} $*" >&2
}

# In tieu de phan doan
print_section() {
    local title="$1"
    echo -e "\n${C_BLUE}==============================================================================${C_RESET}"
    echo -e "${C_WHITE}${C_BOLD}   ${title}${C_RESET}"
    echo -e "${C_BLUE}==============================================================================${C_RESET}"
}

# Kiem tra quyen root (sudo)
require_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "Thao tac nay yeu cau thuc thi voi quyen root (sudo)."
        echo -e "Vui long khoi chay lai: ${C_YELLOW}sudo ./run.sh${C_RESET}"
        return 1
    fi
    return 0
}

# Kiem tra cong cu dong lenh da cai dat chua
check_command() {
    local cmd="$1"
    local install_pkg="${2:-}"
    if ! command -v "${cmd}" &>/dev/null; then
        log_warn "Khong tim thay cong cu bat buoc: '${cmd}'"
        if [[ -n "${install_pkg}" ]]; then
            echo -e "Huong dan cai dat: ${C_YELLOW}sudo apt update && sudo apt install -y ${install_pkg}${C_RESET}"
        fi
        return 1
    fi
    return 0
}

# Khoi tao va nap tep cau hinh config.env
load_config() {
    local base_dir="$1"
    local config_file="${base_dir}/config.env"
    local example_file="${base_dir}/config.env.example"

    if [[ ! -f "${config_file}" ]]; then
        if [[ -f "${example_file}" ]]; then
            log_warn "Chua tim thay tep cau hinh 'config.env'. Tien hanh khoi tao tu 'config.env.example'..."
            cp "${example_file}" "${config_file}"
            log_info "Da tao tep '${config_file}'."
            echo -e "${C_YELLOW}Vui long mo tep '${config_file}' de khai bao cac thong so thuc te truoc khi tiep tuc.${C_RESET}"
            return 2
        else
            log_error "Khong tim thay tep cau hinh 'config.env' hoac tep mau 'config.env.example'."
            return 1
        fi
    fi

    # shellcheck source=/dev/null
    source "${config_file}"
    return 0
}

# Kiem tra placeholder (<...>) va cac truong thieu trong config.env
validate_config() {
    local base_dir="$1"
    local mode="${2:-all}" # all | seed | vcsa
    local config_file="${base_dir}/config.env"

    if [[ ! -f "${config_file}" ]]; then
        log_error "Tep cau hinh '${config_file}' khong ton tai."
        return 1
    fi

    log_step "Kiem tra tinh hop le cua tep cau hinh (config.env)..."

    local missing_count=0
    local -a placeholders=()

    # Tim toan bo cac dong chua ky tu giu cho <...> (bo qua dong chu thich)
    while IFS= read -r line; do
        local content="${line#*:}"
        if [[ -n "${content}" && ! "${content}" =~ ^[[:space:]]*# ]]; then
            placeholders+=("${line}")
            ((missing_count++)) || true
        fi
    done < <(grep -n '<.*>' "${config_file}" 2>/dev/null || true)

    if [[ ${missing_count} -gt 0 ]]; then
        log_error "Phat hien ${missing_count} thong so chua duoc thiet lap (con chua ky tu giu cho <...>):"
        echo -e "${C_RED}------------------------------------------------------------------------------${C_RESET}"
        for item in "${placeholders[@]}"; do
            echo -e "  Dong ${item}"
        done
        echo -e "${C_RED}------------------------------------------------------------------------------${C_RESET}"
        echo -e "Vui long chinh sua tep '${C_YELLOW}${config_file}${C_RESET}' va thay the toan bo cac muc <...> tren."
        return 1
    fi

    # Kiem tra cac bien bat buoc theo che do
    local -a required_vars=("ESXI_HOSTNAME" "ESXI_USERNAME" "ESXI_DATASTORE")
    if [[ "${mode}" == "all" || "${mode}" == "seed" ]]; then
        required_vars+=("UBUNTU_VM_NAME" "UBUNTU_OVA_PATH" "UBUNTU_STATIC_IP" "UBUNTU_GATEWAY")
    fi
    if [[ "${mode}" == "all" || "${mode}" == "vcsa" ]]; then
        required_vars+=("VCSA_VM_NAME" "VCSA_STATIC_IP" "VCSA_GATEWAY" "VCSA_FQDN" "VCSA_ISO_PATH")
    fi

    local empty_count=0
    for var_name in "${required_vars[@]}"; do
        if [[ -z "${!var_name:-}" ]]; then
            log_error "Bien bat buoc chua duoc khai bao hoac de trong: ${C_YELLOW}${var_name}${C_RESET}"
            ((empty_count++)) || true
        fi
    done

    if [[ ${empty_count} -gt 0 ]]; then
        echo -e "Vui long bo sung cac bien tren vao tep: ${C_YELLOW}${config_file}${C_RESET}"
        return 1
    fi

    log_success "Tep cau hinh 'config.env' hop le, khong con placeholder nao."
    return 0
}

# Nhan mat khau an qua ban phim
prompt_secret() {
    local prompt_text="$1"
    local var_ref="$2"
    local confirm="${3:-false}"
    local pass1=""
    local pass2=""

    while true; do
        read -r -s -p "${prompt_text}: " pass1
        echo "" >&2
        if [[ -z "${pass1}" ]]; then
            log_warn "Mat khau khong duoc de trong. Vui long nhap lai." >&2
            continue
        fi

        if [[ "${confirm}" == "true" ]]; then
            read -r -s -p "Xac nhan lai mat khau: " pass2
            echo "" >&2
            if [[ "${pass1}" != "${pass2}" ]]; then
                log_error "Hai lan nhap mat khau khong trung khop. Vui long nhap lai." >&2
                continue
            fi
        fi

        printf -v "${var_ref}" '%s' "${pass1}"
        break
    done
}

# Cap nhat hoac bo sung gia tri bien trong tep config.env
update_config_var() {
    local base_dir="$1"
    local var_name="$2"
    local var_value="$3"
    local config_file="${base_dir}/config.env"

    if [[ ! -f "${config_file}" ]]; then
        log_error "Tep cau hinh khong ton tai: ${config_file}"
        return 1
    fi

    local temp_file
    temp_file="$(mktemp "${base_dir}/config.env.tmp.XXXXXX")"

    local found=false
    while IFS= read -r line || [[ -n "${line}" ]]; do
        if [[ "${line}" =~ ^[[:space:]]*${var_name}= ]]; then
            local comment=""
            if [[ "${line}" =~ (#.*)$ ]]; then
                comment=" ${BASH_REMATCH[1]}"
            fi
            echo "${var_name}=\"${var_value}\"${comment}" >> "${temp_file}"
            found=true
        else
            echo "${line}" >> "${temp_file}"
        fi
    done < "${config_file}"

    if [[ "${found}" == "false" ]]; then
        echo "${var_name}=\"${var_value}\"" >> "${temp_file}"
    fi

    mv "${temp_file}" "${config_file}"
    return 0
}
