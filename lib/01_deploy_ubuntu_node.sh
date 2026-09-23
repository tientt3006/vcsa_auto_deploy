#!/usr/bin/env bash
# ==============================================================================
# Module: 01_deploy_ubuntu_node.sh
# Muc dich: Khoi tao nut mam tu dong hoa (Bootstrap / Automation Seed Node)
#           tren may chu Standalone ESXi thong qua cong cu govc va NoCloud seed.iso
# Pham vi thuc thi: May tram khoi tao (Operator / Bootstrap Workstation)
# ==============================================================================
set -euo pipefail

deploy_ubuntu_node() {
    local base_dir="$1"
    
    print_section "GIAI DOAN 1: KHỞI TẠO NÚT MẦM ĐIỀU KHIỂN (BOOTSTRAP SEED NODE)"

    # 1. Kiem tra tinh hop le cua cau hinh
    if ! validate_config "${base_dir}" "seed"; then
        return 1
    fi

    # 2. Kiem tra cong cu phu thuoc tren may tram
    log_step "Kiem tra cac cong cu dong lenh phu thuoc..."
    
    # Kiem tra hoac ho tro tai govc
    if ! command -v govc &>/dev/null; then
        log_warn "Chua tim thay cong cu 'govc' tren he thong."
        read -r -p "Tu dong tai va cai dat govc vao /usr/local/bin? (Y/n): " confirm_govc
        confirm_govc=${confirm_govc:-Y}
        if [[ "${confirm_govc}" =~ ^[yY]([eE][sS])?$ ]]; then
            log_info "Dang tai govc phien ban moi nhat..."
            local os_type arch_type
            os_type="$(uname -s)"
            arch_type="$(uname -m)"
            curl -L -s "https://github.com/vmware/govmomi/releases/latest/download/govc_${os_type}_${arch_type}.tar.gz" | sudo tar -C /usr/local/bin -xvzf - govc
            sudo chmod +x /usr/local/bin/govc
            log_success "Da cai dat govc thanh cong tai /usr/local/bin/govc"
        else
            log_error "Thao tac can cong cu 'govc' de tiep tuc. Vui long cai dat thu cong."
            return 1
        fi
    fi

    # Kiem tra genisoimage hoac mkisofs
    local iso_tool=""
    if command -v genisoimage &>/dev/null; then
        iso_tool="genisoimage"
    elif command -v mkisofs &>/dev/null; then
        iso_tool="mkisofs"
    else
        log_error "Khong tim thay 'genisoimage' hoac 'mkisofs'."
        echo -e "Vui long cai dat: ${C_YELLOW}sudo apt update && sudo apt install -y genisoimage${C_RESET}"
        return 1
    fi

    # 3. Kiem tra su ton tai cua tep Ubuntu Cloud OVA
    if [[ ! -f "${UBUNTU_OVA_PATH}" ]]; then
        log_error "Tep Ubuntu Cloud OVA khong ton tai tai: ${UBUNTU_OVA_PATH}"
        echo -e "Goi y tai tep OVA chinh thuc tu Canonical:"
        echo -e "${C_YELLOW}wget https://cloud-images.ubuntu.com/releases/22.04/release/ubuntu-22.04-server-cloudimg-amd64.ova${C_RESET}"
        return 1
    fi

    # 4. Tiep nhan mat khau an toan
    local esxi_password=""
    local ubuntu_password=""
    
    echo ""
    log_info "Tiep nhan thong tin xac thuc an toan (du lieu chi luu tam thoi trong RAM):"
    prompt_secret "Nhap mat khau root cua ESXi Host (${ESXI_USERNAME}@${ESXI_HOSTNAME})" esxi_password
    prompt_secret "Dat mat khau quan tri cho user '${UBUNTU_VM_USER:-ubuntu}' cua may ao sap tao" ubuntu_password true

    # 5. Thiet lap moi truong ket noi govc toi ESXi
    export GOVC_URL="https://${ESXI_USERNAME}:${esxi_password}@${ESXI_HOSTNAME}"
    export GOVC_INSECURE=true
    export GOVC_DATASTORE="${ESXI_DATASTORE}"
    export GOVC_NETWORK="${ESXI_NETWORK}"

    log_step "Kiem tra ket noi toi may chu ESXi qua API..."
    if ! govc about &>/dev/null; then
        log_error "Khong the ket noi toi ESXi Host tai '${ESXI_HOSTNAME}'. Vui long kiem tra IP va mat khau."
        unset esxi_password ubuntu_password GOVC_URL
        return 1
    fi
    log_success "Ket noi API toi ESXi Host thanh cong."

    # Kiem tra may ao da ton tai hay chua
    if govc vm.info "${UBUNTU_VM_NAME}" &>/dev/null; then
        log_warn "May ao '${UBUNTU_VM_NAME}' da ton tai tren ESXi Host."
        read -r -p "Huy bo va tiep tuc su dung may ao cu? (Y/n): " keep_vm
        keep_vm=${keep_vm:-Y}
        if [[ "${keep_vm}" =~ ^[yY]([eE][sS])?$ ]]; then
            unset esxi_password ubuntu_password GOVC_URL
            return 0
        else
            log_error "Vui long doi ten UBUNTU_VM_NAME trong config.env hoac xoa may ao cu tren ESXi."
            unset esxi_password ubuntu_password GOVC_URL
            return 1
        fi
    fi

    # 6. Tao tep seed.iso (Cloud-Init NoCloud)
    log_step "Dang khoi tao tep seed.iso chua cau hinh mang va mat khau..."
    local temp_dir
    temp_dir="$(mktemp -d /tmp/seed_build_XXXXXX)"
    local seed_iso="${temp_dir}/seed.iso"

    cat <<EOF > "${temp_dir}/user-data"
#cloud-config
hostname: ${UBUNTU_VM_NAME}
manage_etc_hosts: true

users:
  - name: ${UBUNTU_VM_USER:-ubuntu}
    sudo: ALL=(ALL) NOPASSWD:ALL
    lock_passwd: false
    shell: /bin/bash

chpasswd:
  list: |
    ${UBUNTU_VM_USER:-ubuntu}:${ubuntu_password}
  expire: false

ssh_pwauth: true

network:
  version: 2
  ethernets:
    ens192:
      dhcp4: false
      addresses:
        - ${UBUNTU_STATIC_IP}/${UBUNTU_PREFIX:-24}
      routes:
        - to: default
          via: ${UBUNTU_GATEWAY}
      nameservers:
        addresses:
          - ${UBUNTU_DNS_UPSTREAM:-8.8.8.8}
          - 8.8.8.8
EOF

    touch "${temp_dir}/meta-data"

    "${iso_tool}" -output "${seed_iso}" -volid cidata -joliet -rock "${temp_dir}/user-data" "${temp_dir}/meta-data" &>/dev/null
    rm -f "${temp_dir}/user-data" "${temp_dir}/meta-data"
    log_success "Da tao tep seed.iso cuc bo tai: ${seed_iso}"

    # 7. Trien khai OVA len ESXi
    log_step "Dang import Ubuntu Cloud OVA len ESXi Datastore '${ESXI_DATASTORE}'..."
    govc import.ova \
        -name="${UBUNTU_VM_NAME}" \
        -ds="${ESXI_DATASTORE}" \
        -net="${ESXI_NETWORK}"="${ESXI_NETWORK}" \
        "${UBUNTU_OVA_PATH}"
    log_success "Da import OVA thanh cong."

    # 8. Tai seed.iso len Datastore
    log_step "Dang tai seed.iso len Datastore..."
    govc datastore.upload -ds="${ESXI_DATASTORE}" "${seed_iso}" "${UBUNTU_VM_NAME}/seed.iso"
    rm -rf "${temp_dir}"

    # 9. Gan seed.iso vao CD-ROM
    log_step "Dang gan seed.iso vao o dia CD-ROM ao..."
    govc device.cdrom.add -vm="${UBUNTU_VM_NAME}" 2>/dev/null || true
    govc device.cdrom.insert -vm="${UBUNTU_VM_NAME}" -ds="${ESXI_DATASTORE}" "${UBUNTU_VM_NAME}/seed.iso"

    # 10. Bat nguon may ao
    log_step "Dang bat nguon may ao '${UBUNTU_VM_NAME}'..."
    govc vm.power -on "${UBUNTU_VM_NAME}"

    # Don dep thong tin bao mat
    unset esxi_password ubuntu_password GOVC_URL
    
    echo ""
    log_success "=========================================================================="
    log_success "TRIEN KHAI NUT MAM DIEU KHIEN (UBUNTU AUTOMATION) THANH CONG!"
    log_success "=========================================================================="
    echo -e "Thong so ket noi:"
    echo -e "  - Dia chi IP   : ${C_YELLOW}${UBUNTU_STATIC_IP}${C_RESET}"
    echo -e "  - Tai khoan SSH: ${C_YELLOW}${UBUNTU_VM_USER:-ubuntu}${C_RESET}"
    echo -e "  - Cong dich vu : 22"
    echo -e "\n${C_BOLD}HUONG DAN BUOC TIEP THEO:${C_RESET}"
    echo -e "1. Doi khoang 60 giay de Cloud-Init hoan tat khoi tao mang va mat khau."
    echo -e "2. Ket noi SSH vao may ao:"
    echo -e "   ${C_CYAN}ssh ${UBUNTU_VM_USER:-ubuntu}@${UBUNTU_STATIC_IP}${C_RESET}"
    echo -e "3. Sao chep hoac clone thu muc ma nguon nay len may ao Ubuntu:"
    echo -e "   ${C_CYAN}scp -r $(pwd) ${UBUNTU_VM_USER:-ubuntu}@${UBUNTU_STATIC_IP}:~/vcsa_deploy${C_RESET}"
    echo -e "4. Tren may ao Ubuntu, chay '${C_YELLOW}sudo ./run.sh${C_RESET}' va thuc thi cac muc o Giai doan 2."
    echo -e "=========================================================================="
}
