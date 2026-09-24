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

    # Ham don dep thong tin xac thuc trong bo nho
    cleanup_env() {
        unset esxi_password ubuntu_password GOVC_PASSWORD GOVC_USERNAME GOVC_URL
    }

    # 5. Thiet lap moi truong ket noi govc toi ESXi (Tach rieng de ho tro mat khau co ky tu dac biet nhu @)
    export GOVC_URL="https://${ESXI_HOSTNAME}"
    export GOVC_USERNAME="${ESXI_USERNAME}"
    export GOVC_PASSWORD="${esxi_password}"
    export GOVC_INSECURE=true
    export GOVC_DATASTORE="${ESXI_DATASTORE}"
    export GOVC_NETWORK="${ESXI_NETWORK}"

    log_step "Kiem tra ket noi toi may chu ESXi qua API..."
    if ! govc about &>/dev/null; then
        log_error "Khong the ket noi toi ESXi Host tai '${ESXI_HOSTNAME}'. Vui long kiem tra IP va mat khau."
        cleanup_env
        return 1
    fi
    log_success "Ket noi API toi ESXi Host thanh cong."

    # Kiem tra may ao da ton tai hay chua tren ESXi
    local existing_vm=""
    existing_vm="$(govc find / -type m -name "${UBUNTU_VM_NAME}" 2>/dev/null || true)"
    if [[ -z "${existing_vm}" ]]; then
        local vm_info_output=""
        vm_info_output="$(govc vm.info "${UBUNTU_VM_NAME}" 2>/dev/null || true)"
        if [[ -n "${vm_info_output}" ]] && echo "${vm_info_output}" | grep -qE "Name:[[:space:]]*${UBUNTU_VM_NAME}"; then
            existing_vm="${UBUNTU_VM_NAME}"
        fi
    fi

    if [[ -n "${existing_vm}" ]]; then
        log_warn "May ao '${UBUNTU_VM_NAME}' da ton tai tren ESXi Host (vi tri: ${existing_vm})."
        echo -e "Cac phuong an xu ly:"
        echo -e "  ${C_BOLD}[1]${C_RESET} Giu nguyen va tiep tuc su dung may ao hien tai (bo qua buoc tao moi)"
        echo -e "  ${C_BOLD}[2]${C_RESET} Xoa bo may ao cu (Tat nguon & Destroy) va khoi tao lai tu dau"
        echo -e "  ${C_BOLD}[3]${C_RESET} Huy bo tien trinh de kiem tra hoac doi ten trong config.env"
        read -r -p "Vui long chon [1-3] (mac dinh: 1): " vm_action
        vm_action="${vm_action:-1}"
        case "${vm_action}" in
            1)
                log_info "Giu nguyen may ao '${UBUNTU_VM_NAME}'. Ket thuc tien trinh tao nut mam."
                cleanup_env
                return 0
                ;;
            2)
                log_step "Tien hanh tat nguon va xoa may ao cu '${UBUNTU_VM_NAME}' tren ESXi..."
                govc vm.power -off -force "${UBUNTU_VM_NAME}" 2>/dev/null || true
                govc vm.destroy "${UBUNTU_VM_NAME}"
                govc datastore.rm -ds="${ESXI_DATASTORE}" "${UBUNTU_VM_NAME}" 2>/dev/null || true
                log_success "Da xoa may ao cu thanh cong. Tiep tuc khoi tao may ao moi."
                ;;
            *)
                log_error "Tien trinh bi huy bo boi nguoi dung."
                cleanup_env
                return 1
                ;;
        esac
    fi

    # 6. Tao tep seed.iso (Cloud-Init NoCloud) truc tiep trong thu muc build/ cua repo
    local build_dir="${base_dir}/build"
    mkdir -p "${build_dir}"
    local seed_iso="${build_dir}/seed.iso"
    local user_data_file="${build_dir}/user-data"
    local meta_data_file="${build_dir}/meta-data"
    local network_config_file="${build_dir}/network-config"
    local options_spec_file="${build_dir}/ubuntu_ova_spec.json"

    log_step "Dang khoi tao tep cau hinh Cloud-Init NoCloud tai '${build_dir}'..."

    # 6.1. user-data: Nguoi dung, mat khau, SSH va ghi de Netplan fail-safe
    cat <<EOF > "${user_data_file}"
#cloud-config
hostname: ${UBUNTU_VM_NAME}
manage_etc_hosts: true

growpart:
  mode: auto
  devices: ['/']
  ignore_growroot_disabled: false

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

write_files:
  - path: /etc/netplan/99-static-ip.yaml
    permissions: '0600'
    content: |
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

runcmd:
  - netplan apply
EOF

    # 6.2. network-config: Dinh dang Chuan Networking Config Version 2 cho NoCloud
    cat <<EOF > "${network_config_file}"
version: 2
ethernets:
  ens192:
    match:
      name: "e*"
    set-name: "ens192"
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

    # 6.3. meta-data: instance-id, hostname va network block cho VMware DataSource
    cat <<EOF > "${meta_data_file}"
instance-id: ${UBUNTU_VM_NAME}
local-hostname: ${UBUNTU_VM_NAME}
network:
  version: 2
  ethernets:
    ens192:
      match:
        name: "e*"
      set-name: "ens192"
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

    if ! "${iso_tool}" -output "${seed_iso}" -volid cidata -joliet -rock "${user_data_file}" "${meta_data_file}" "${network_config_file}" &>/dev/null; then
        log_error "Khong the tao tep seed.iso bang cong cu '${iso_tool}'."
        cleanup_env
        return 1
    fi
    log_success "Da tao tep seed.iso (user-data, meta-data, network-config) tai: ${seed_iso}"

    # 7. Khoi tao dac ta import OVA (Thin Provisioning & Network Mapping)
    log_step "Khoi tao dac ta cau hinh import OVA (Thin Provisioning & Network)..."
    local use_spec=false
    if command -v jq &>/dev/null; then
        if govc import.spec "${UBUNTU_OVA_PATH}" 2>/dev/null | jq \
            --arg name "${UBUNTU_VM_NAME}" \
            --arg net "${ESXI_NETWORK}" \
            '.DiskProvisioning = "thin" | .Name = $name | .NetworkMapping[0].Network = $net' > "${options_spec_file}" 2>/dev/null; then
            use_spec=true
            log_info "Da tao dac ta import JSON: ${options_spec_file}"
        fi
    elif command -v python3 &>/dev/null; then
        if govc import.spec "${UBUNTU_OVA_PATH}" 2>/dev/null | python3 -c '
import sys, json
try:
    d = json.load(sys.stdin)
    d["DiskProvisioning"] = "thin"
    d["Name"] = sys.argv[1]
    if "NetworkMapping" in d and len(d["NetworkMapping"]) > 0:
        d["NetworkMapping"][0]["Network"] = sys.argv[2]
    with open(sys.argv[3], "w") as f:
        json.dump(d, f, indent=2)
    sys.exit(0)
except Exception:
    sys.exit(1)
' "${UBUNTU_VM_NAME}" "${ESXI_NETWORK}" "${options_spec_file}" 2>/dev/null; then
            use_spec=true
            log_info "Da tao dac ta import JSON (qua Python): ${options_spec_file}"
        fi
    fi

    # 8. Trien khai OVA len ESXi
    log_step "Dang import Ubuntu Cloud OVA len ESXi Datastore '${ESXI_DATASTORE}'..."
    log_info "Tien trinh upload du lieu dang duoc thuc thi..."

    local import_status=0
    if [[ "${use_spec}" == "true" && -f "${options_spec_file}" ]]; then
        govc import.ova \
            -options="${options_spec_file}" \
            -ds="${ESXI_DATASTORE}" \
            "${UBUNTU_OVA_PATH}" || import_status=$?
    else
        govc import.ova \
            -name="${UBUNTU_VM_NAME}" \
            -ds="${ESXI_DATASTORE}" \
            -net="${ESXI_NETWORK}" \
            "${UBUNTU_OVA_PATH}" || import_status=$?
    fi

    if [[ ${import_status} -ne 0 ]]; then
        log_error "Import Ubuntu Cloud OVA len ESXi that bai (ma loi: ${import_status})."
        cleanup_env
        return 1
    fi
    log_success "Da import OVA len ESXi thanh cong."

    # 9. Dieu chinh cau hinh phan cung (vCPU, RAM, Disk 40GB) va nap VMware guestinfo du phong
    local vm_cpu="${UBUNTU_CPU:-4}"
    local vm_ram="${UBUNTU_RAM_MB:-6144}"
    local vm_disk="${UBUNTU_DISK_GB:-40}"

    log_step "Dang dieu chinh phan cung may ao (${vm_cpu} vCPU, ${vm_ram} MB RAM, ${vm_disk} GB Disk)..."

    local userdata_b64 metadata_b64 netcfg_b64
    userdata_b64="$(base64 < "${user_data_file}" | tr -d '\r\n')"
    metadata_b64="$(base64 < "${meta_data_file}" | tr -d '\r\n')"
    netcfg_b64="$(base64 < "${network_config_file}" | tr -d '\r\n')"

    if ! govc vm.change -vm="${UBUNTU_VM_NAME}" \
        -c="${vm_cpu}" \
        -m="${vm_ram}" \
        -e "guestinfo.userdata=${userdata_b64}" \
        -e "guestinfo.userdata.encoding=base64" \
        -e "guestinfo.metadata=${metadata_b64}" \
        -e "guestinfo.metadata.encoding=base64" \
        -e "guestinfo.network=${netcfg_b64}" \
        -e "guestinfo.network.encoding=base64"; then
        log_warn "Khong the thay doi vCPU/RAM hoac guestinfo qua API. Tiep tuc cac buoc tiep theo."
    fi

    local disk_name
    disk_name="$(govc device.ls -vm="${UBUNTU_VM_NAME}" 2>/dev/null | grep -E '^disk-' | head -n 1 | awk '{print $1}' || true)"
    if [[ -n "${disk_name}" ]]; then
        if ! govc vm.disk.change -vm="${UBUNTU_VM_NAME}" -disk.name="${disk_name}" -size="${vm_disk}G"; then
            log_warn "Khong the mo rong o dia ${disk_name} len ${vm_disk}GB. Giu nguyen dung luong goc."
        else
            log_success "Da mo rong o dia ${disk_name} len ${vm_disk} GB."
        fi
    fi
    log_success "Da thiet lap cau hinh phan cung va co che du phong guestinfo thanh cong."

    # 10. Tai seed.iso len Datastore vao thu muc cua may ao
    log_step "Dang tai seed.iso len Datastore..."
    local upload_status=0
    govc datastore.upload -ds="${ESXI_DATASTORE}" "${seed_iso}" "${UBUNTU_VM_NAME}/seed.iso" || upload_status=$?
    if [[ ${upload_status} -ne 0 ]]; then
        log_error "Tai seed.iso len Datastore that bai."
        cleanup_env
        return 1
    fi
    log_success "Da tai seed.iso len Datastore thanh cong."

    # 11. Gan seed.iso vao CD-ROM ao va bao dam ket noi khi khoi dong
    log_step "Dang gan seed.iso vao o dia CD-ROM ao va thiet lap ket noi..."
    local cdrom_dev
    cdrom_dev="$(govc device.ls -vm="${UBUNTU_VM_NAME}" 2>/dev/null | grep -E '^cdrom-' | head -n 1 | awk '{print $1}' || true)"
    if [[ -z "${cdrom_dev}" ]]; then
        cdrom_dev="$(govc device.cdrom.add -vm="${UBUNTU_VM_NAME}")"
    fi

    local insert_status=0
    govc device.cdrom.insert -vm="${UBUNTU_VM_NAME}" -device="${cdrom_dev}" -ds="${ESXI_DATASTORE}" "${UBUNTU_VM_NAME}/seed.iso" || insert_status=$?
    if [[ ${insert_status} -ne 0 ]]; then
        log_error "Gan seed.iso vao thiet bi ${cdrom_dev} that bai."
        cleanup_env
        return 1
    fi
    govc device.connect -vm="${UBUNTU_VM_NAME}" "${cdrom_dev}" 2>/dev/null || true
    log_success "Da gan seed.iso vao ${cdrom_dev} va thiet lap ket noi khi khoi dong thanh cong."

    # 12. Bat nguon may ao
    log_step "Dang bat nguon may ao '${UBUNTU_VM_NAME}'..."
    local power_status=0
    govc vm.power -on "${UBUNTU_VM_NAME}" || power_status=$?
    if [[ ${power_status} -ne 0 ]]; then
        log_error "Bat nguon may ao '${UBUNTU_VM_NAME}' that bai."
        cleanup_env
        return 1
    fi
    log_success "May ao '${UBUNTU_VM_NAME}' da duoc bat nguon thanh cong."

    # 13. Kiem tra thong mang chu dong (Active Health Probing)
    log_step "Dang cho may ao hoan tat khoi tao Cloud-Init va nhan mang (${UBUNTU_STATIC_IP})..."
    local wait_count=0
    local max_wait=30
    local ip_ready=false

    while [[ ${wait_count} -lt ${max_wait} ]]; do
        if ping -c 1 -W 1 "${UBUNTU_STATIC_IP}" &>/dev/null; then
            ip_ready=true
            break
        fi
        sleep 3
        ((wait_count++)) || true
        echo -n "."
    done
    echo ""

    if [[ "${ip_ready}" == "true" ]]; then
        log_success "May ao da thong mang thanh cong (Ping toi ${UBUNTU_STATIC_IP} OK)."
    else
        log_warn "Chua nhan duoc phan hoi Ping tu ${UBUNTU_STATIC_IP}. Vui long doi them 30-60 giay de he dieu hanh hoan tat cai dat."
    fi

    # Don dep thong tin bao mat khoi RAM
    cleanup_env

    echo ""
    log_success "=========================================================================="
    log_success "TRIEN KHAI NUT MAM DIEU KHIEN (UBUNTU AUTOMATION) THANH CONG!"
    log_success "=========================================================================="
    echo -e "Thong so may ao:"
    echo -e "  - CPU / RAM / Disk : ${C_GREEN}${vm_cpu} vCPU / $((vm_ram / 1024)) GB RAM / ${vm_disk} GB Disk${C_RESET}"
    echo -e "  - Dia chi IP       : ${C_YELLOW}${UBUNTU_STATIC_IP}${C_RESET}"
    echo -e "  - Tai khoan SSH    : ${C_YELLOW}${UBUNTU_VM_USER:-ubuntu}${C_RESET}"
    echo -e "  - Cong dich vu     : 22"
    echo -e "\n${C_BOLD}HUONG DAN BUOC TIEP THEO:${C_RESET}"
    echo -e "1. Ket noi SSH vao may ao:"
    echo -e "   ${C_CYAN}ssh ${UBUNTU_VM_USER:-ubuntu}@${UBUNTU_STATIC_IP}${C_RESET}"
    echo -e "2. Sao chep thu muc ma nguon nay len may ao Ubuntu:"
    echo -e "   ${C_CYAN}scp -r $(pwd) ${UBUNTU_VM_USER:-ubuntu}@${UBUNTU_STATIC_IP}:~/vcsa_deploy${C_RESET}"
    echo -e "3. Tren may ao Ubuntu, chay '${C_YELLOW}sudo ./run.sh${C_RESET}' va thuc thi cac muc o Giai doan 2."
    echo -e "=========================================================================="
}
