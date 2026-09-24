#!/usr/bin/env bash
# ==============================================================================
# Module: 03_deploy_vcsa.sh
# Muc dich: Tu dong hoa 100% qua trinh cai dat VMware vCenter Server Appliance (VCSA)
#           thong qua cong cu vcsa-deploy (VMware CLI Installer) khong can giam sat
# Pham vi thuc thi: Nut dieu khien (Automation Node / Ubuntu VM)
# ==============================================================================
set -euo pipefail

deploy_vcsa() {
    local base_dir="$1"
    local mount_point="/mnt/vcsa_iso"
    local ram_spec="/dev/shm/vcsa_deployment_spec_$$.json"

    print_section "GIAI DOAN 2: TRIỂN KHAI VCENTER SERVER APPLIANCE (VCSA) TỰ ĐỘNG"

    # 1. Kiem tra quyen root
    if ! require_root; then
        return 1
    fi

    # 2. Kiem tra cau hinh
    if ! validate_config "${base_dir}" "vcsa"; then
        return 1
    fi

    # 3. Kiem tra cong cu envsubst
    if ! command -v envsubst &>/dev/null; then
        log_error "Khong tim thay lenh 'envsubst'."
        echo -e "Vui long cai dat: ${C_YELLOW}sudo apt install -y gettext-base${C_RESET}"
        return 1
    fi

    # Ham don dep tai nguyen an toan
    cleanup_vcsa() {
        echo ""
        log_info "Tien hanh don dep tai nguyen va huy thong tin bi mat..."
        if [[ -f "${ram_spec}" ]]; then
            shred -u -z -n 3 "${ram_spec}" 2>/dev/null || rm -f "${ram_spec}"
            log_info "Da tieu huy tep dac ta cau hinh trong RAM disk."
        fi
        if mountpoint -q "${mount_point}"; then
            umount "${mount_point}" || true
            log_info "Da go mount (umount) diem mount: ${mount_point}"
        fi
        unset ESXI_PASSWORD VCSA_ROOT_PASSWORD SSO_ADMIN_PASSWORD || true
        log_info "Da giai phong toan bo bien mat khau khoi RAM."
    }
    trap cleanup_vcsa EXIT INT TERM

    # 4. Kiem tra tep ISO ton tai
    log_step "Kiem tra tep ISO cai dat VCSA..."
    if [[ -z "${VCSA_ISO_PATH:-}" || ! -f "${VCSA_ISO_PATH}" ]]; then
        log_warn "Tep ISO VCSA chua ton tai hoac duong dan khong hop le: '${VCSA_ISO_PATH:-<Chua khai bao>}'"
        echo "Lựa chọn xử lý:"
        echo "  [1] Tải nhanh tệp ISO từ đường dẫn URL (aria2c / curl)"
        echo "  [2] Quét và duyệt tệp ISO từ thư mục trên máy"
        echo "  [0] Hủy bỏ tiến trình triển khai"
        local iso_opt=""
        read -r -p "Vui lòng chọn [1/2/0]: " iso_opt
        case "${iso_opt}" in
            1)
                download_iso_from_url "${base_dir}" || return 1
                ;;
            2)
                browse_and_select_iso "${base_dir}" || return 1
                ;;
            *)
                log_info "Đã hủy tiến trình triển khai VCSA."
                return 1
                ;;
        esac
        if [[ -z "${VCSA_ISO_PATH:-}" || ! -f "${VCSA_ISO_PATH}" ]]; then
            log_error "Vẫn chưa xác định được tệp ISO VCSA hợp lệ để tiếp tục."
            return 1
        fi
    fi
    log_success "Phat hien tep ISO hop le tai: ${VCSA_ISO_PATH}"

    # 5. Mount tep ISO VCSA
    log_step "Dang mount tep ISO vao ${mount_point}..."
    mkdir -p "${mount_point}"
    if ! mountpoint -q "${mount_point}"; then
        mount -o loop,ro "${VCSA_ISO_PATH}" "${mount_point}"
    fi

    local vcsa_deploy_bin="${mount_point}/vcsa-cli-installer/lin64/vcsa-deploy"
    if [[ ! -f "${vcsa_deploy_bin}" ]]; then
        log_error "Khong tim thay cong cu vcsa-deploy tai: ${vcsa_deploy_bin}"
        return 1
    fi
    log_success "Cong cu vcsa-deploy san sang."

    # 6. Tiep nhan mat khau quan tri an
    local esxi_password=""
    local vcsa_root_password=""
    local sso_admin_password=""

    echo ""
    log_info "Tiep nhan thong tin xac thuc quan tri (Chi luu tam thoi trong RAM disk /dev/shm):"
    echo -e "${C_YELLOW}Luu y tieu chuan mat khau VMware: Toi thieu 8 ky tu, gom chu hoa, chu thuong, so va ky tu dac biet.${C_RESET}"
    prompt_secret "Nhap mat khau root cua ESXi Host (${ESXI_USERNAME}@${ESXI_HOSTNAME})" esxi_password
    prompt_secret "Dat mat khau root cho he dieu hanh VCSA sap tao" vcsa_root_password true
    prompt_secret "Dat mat khau quan tri Single Sign-On (administrator@${SSO_DOMAIN_NAME:-vsphere.local})" sso_admin_password true

    # 7. Sinh tep dac ta cau hinh JSON trong RAM disk (/dev/shm)
    log_step "Dang sinh tep dac ta cau hinh VCSA trong bo nho RAM (/dev/shm)..."
    local template_file="${base_dir}/templates/embedded_vcs_on_esxi.json.tpl"
    if [[ ! -f "${template_file}" ]]; then
        log_error "Khong tim thay tep mau template tai: ${template_file}"
        return 1
    fi

    # Xu ly bien DNS (Mac dinh tro ve DNS cua Ubuntu Node neu khong khai bao rieng)
    local primary_dns="${VCSA_DNS_PRIMARY:-${UBUNTU_STATIC_IP:-${VCSA_GATEWAY}}}"
    local secondary_dns="${VCSA_DNS_SECONDARY:-${UBUNTU_DNS_UPSTREAM:-8.8.8.8}}"

    export ESXI_HOSTNAME ESXI_USERNAME
    export ESXI_PASSWORD="${esxi_password}"
    export DEPLOYMENT_NETWORK="${ESXI_NETWORK}"
    export DATASTORE_NAME="${ESXI_DATASTORE}"
    export VCSA_SIZE="${VCSA_SIZE:-tiny}"
    export VCSA_VM_NAME="${VCSA_VM_NAME:-VCSA-01}"
    export VCSA_ROOT_PASSWORD="${vcsa_root_password}"
    export NTP_SERVERS="${NTP_SERVERS:-pool.ntp.org}"
    export SSO_ADMIN_PASSWORD="${sso_admin_password}"
    export SSO_DOMAIN_NAME="${SSO_DOMAIN_NAME:-vsphere.local}"
    export VCSA_STATIC_IP
    export DNS_SERVER_PRIMARY="${primary_dns}"
    export DNS_SERVER_SECONDARY="${secondary_dns}"
    export VCSA_PREFIX="${VCSA_PREFIX:-24}"
    export VCSA_GATEWAY
    export VCSA_FQDN

    envsubst < "${template_file}" > "${ram_spec}"
    chmod 0600 "${ram_spec}"
    log_success "Da tao tep dac ta an toan tai: ${ram_spec}"

    # 8. Kiem tra tien trien khai (Pre-check)
    print_section "GIAI DOAN 2.1: KIEM TRA DIEU KIEN TIEN QUYET (PRECHECK-ONLY)"
    "${vcsa_deploy_bin}" install \
        --precheck-only \
        --accept-eula \
        --acknowledge-ceip \
        --no-ssl-certificate-verification \
        "${ram_spec}"

    echo ""
    log_success "Kiem tra dieu kien tien quyet (Pre-check) THANH CONG."
    echo -e "${C_CYAN}Thong so trien khai da duoc xac thuc:${C_RESET}"
    echo -e "  - ESXi Host Dich     : ${C_YELLOW}${ESXI_HOSTNAME}${C_RESET}"
    echo -e "  - Ten May Ao VCSA    : ${C_YELLOW}${VCSA_VM_NAME} (Size: ${VCSA_SIZE})${C_RESET}"
    echo -e "  - Datastore          : ${C_YELLOW}${ESXI_DATASTORE}${C_RESET}"
    echo -e "  - Dia Chi IP Tinh    : ${C_YELLOW}${VCSA_STATIC_IP}/${VCSA_PREFIX} (Gateway: ${VCSA_GATEWAY})${C_RESET}"
    echo -e "  - DNS Primary        : ${C_YELLOW}${primary_dns}${C_RESET}"
    echo -e "  - FQDN He Thong      : ${C_YELLOW}${VCSA_FQDN}${C_RESET}"
    echo -e "  - SSO Domain         : ${C_YELLOW}${SSO_DOMAIN_NAME}${C_RESET}"

    echo ""
    read -r -p "Xac nhan bat dau trien khai VCSA ngay bay gio? (Y/n): " confirm_install
    confirm_install=${confirm_install:-Y}
    if [[ ! "${confirm_install}" =~ ^[yY]([eE][sS])?$ ]]; then
        log_warn "Huy tien trinh cai dat theo yeu cau cua nguoi dung."
        return 0
    fi

    # 9. Thuc thi cai dat chinh thuc
    print_section "GIAI DOAN 2.2: TIEN HANH CAI DAT VCSA (UOC TINH 20 - 35 PHUT)"
    "${vcsa_deploy_bin}" install \
        --accept-eula \
        --acknowledge-ceip \
        --no-ssl-certificate-verification \
        "${ram_spec}"

    echo ""
    log_success "=========================================================================="
    log_success "TRIEN KHAI VCENTER SERVER APPLIANCE (VCSA) THANH CONG!"
    log_success "=========================================================================="
    echo -e "Truy cap giao dien quan tri vSphere Client tai:"
    echo -e "  URL          : ${C_CYAN}https://${VCSA_FQDN}/ui${C_RESET} hoac ${C_CYAN}https://${VCSA_STATIC_IP}/ui${C_RESET}"
    echo -e "  Tai khoan SSO: ${C_YELLOW}administrator@${SSO_DOMAIN_NAME}${C_RESET}"
    echo -e "=========================================================================="
}
