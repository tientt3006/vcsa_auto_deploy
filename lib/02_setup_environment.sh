#!/usr/bin/env bash
# ==============================================================================
# Module: 02_setup_environment.sh
# Muc dich: Cai dat cac goi phan mem phu thuoc, giai phong xung dot cong 53
#           va cau hinh dich vu DNS noi bo (dnsmasq) phan giai hai chieu cho VCSA
# Pham vi thuc thi: Nut dieu khien (Automation Node / Ubuntu VM)
# ==============================================================================
set -euo pipefail

setup_environment() {
    local base_dir="$1"

    print_section "GIAI DOAN 2: THIẾT LẬP MÔI TRƯỜNG VÀ DỊCH VỤ DNS TRÊN NÚT ĐIỀU KHIỂN"

    # 1. Kiem tra quyen root
    if ! require_root; then
        return 1
    fi

    # 2. Kiem tra cau hinh hop le
    if ! validate_config "${base_dir}" "vcsa"; then
        return 1
    fi

    # 3. Cai dat cac goi phan mem phu thuoc tren Ubuntu
    log_step "Cap nhat kho luu tru va cai dat cac goi tien ich bat buoc..."
    apt-get update -y
    apt-get install -y dnsmasq dnsutils jq gettext-base curl wget psmisc aria2

    # 4. Xu ly xung dot cong 53 voi systemd-resolved
    log_step "Kiem tra va giai phong xung dot cong 53 (systemd-resolved)..."
    if ss -tulpn | grep -q ":53 "; then
        log_info "Phat hien tien trinh dang lang nghe tren cong 53. Tien hanh cau hinh DNSStubListener=no..."
        if [[ -f "/etc/systemd/resolved.conf" ]]; then
            sed -i 's/#DNSStubListener=yes/DNSStubListener=no/' /etc/systemd/resolved.conf || true
            sed -i 's/DNSStubListener=yes/DNSStubListener=no/' /etc/systemd/resolved.conf || true
            systemctl restart systemd-resolved || true
            log_success "Da tat DNSStubListener cua systemd-resolved."
        fi
    fi

    # 5. Tinh toan ban ghi phan giai thuan va nghich (PTR)
    local o1 o2 o3 o4
    IFS='.' read -r o1 o2 o3 o4 <<< "${VCSA_STATIC_IP}"
    local reverse_ptr="${o4}.${o3}.${o2}.${o1}.in-addr.arpa"

    log_step "Dang cau hinh dich vu dnsmasq tai /etc/dnsmasq.d/vcsa.conf..."
    cat <<EOF > /etc/dnsmasq.d/vcsa.conf
# ==============================================================================
# Cau hinh ban ghi DNS phuc vu trien khai VMware VCSA
# ==============================================================================

# 1. Ban ghi phan giai thuan (A Record) va nghich (PTR Record)
address=/${VCSA_FQDN}/${VCSA_STATIC_IP}
ptr-record=${reverse_ptr},${VCSA_FQDN}

# 2. Chuyen tiep cac truy van internet ve DNS ha tang
server=${UBUNTU_DNS_UPSTREAM:-10.255.242.1}
server=8.8.8.8

# 3. Giao dien va dia chi lang nghe
listen-address=127.0.0.1,${UBUNTU_STATIC_IP:-127.0.0.1}
bind-interfaces
EOF

    # 6. Kiem tra cu phap va khoi dong lai dnsmasq
    log_step "Kiem tra cu phap va khoi dong lai dnsmasq..."
    dnsmasq --test
    systemctl restart dnsmasq
    systemctl enable dnsmasq &>/dev/null || true
    log_success "Dich vu dnsmasq da khoi dong thanh cong."

    # 7. Mo tuong lua neu co UFW
    if command -v ufw &>/dev/null && ufw status | grep -q "Status: active"; then
        log_step "Cau hinh mo cong 53/tcp va 53/udp tren UFW firewall..."
        ufw allow 53/tcp &>/dev/null || true
        ufw allow 53/udp &>/dev/null || true
        log_success "Da mo cong tuong lua 53."
    fi

    # 8. Kiem tra phan giai DNS
    log_step "Tien hanh kiem tra phan giai ten mien thuc te..."
    local forward_result reverse_result internet_result

    forward_result="$(dig @127.0.0.1 "${VCSA_FQDN}" +short || true)"
    reverse_result="$(dig @127.0.0.1 -x "${VCSA_STATIC_IP}" +short || true)"
    internet_result="$(dig @127.0.0.1 "${NTP_SERVERS:-pool.ntp.org}" +short || true)"

    echo ""
    echo -e "  - Phan giai thuan (${VCSA_FQDN}): ${C_GREEN}${forward_result:-THAT BAI}${C_RESET}"
    echo -e "  - Phan giai nghich (${VCSA_STATIC_IP}): ${C_GREEN}${reverse_result:-THAT BAI}${C_RESET}"
    echo -e "  - Chuyen tiep ngoai (${NTP_SERVERS:-pool.ntp.org}): ${C_GREEN}${internet_result:-THAT BAI}${C_RESET}"

    if [[ "${forward_result}" != "${VCSA_STATIC_IP}" ]]; then
        log_warn "Phan giai thuan chua tra ve dung IP '${VCSA_STATIC_IP}'. Vui long kiem tra lai /etc/dnsmasq.d/vcsa.conf."
        return 1
    fi

    echo ""
    log_success "=========================================================================="
    log_success "THIẾT LẬP MÔI TRƯỜNG VÀ DỊCH VỤ DNS TRÊN NÚT ĐIỀU KHIỂN HOÀN TẤT!"
    log_success "=========================================================================="
    echo -e "Trang thai dich vu: DNS san sang dap ung dieu kien tien quyet cua VCSA."
    echo -e "Buoc tiep theo: Chon muc '[4] Trien khai VCSA' tu menu chinh de tien hanh cai dat."
    echo -e "=========================================================================="
}
