#!/usr/bin/env bash
# ==============================================================================
# Module: 04_health_check.sh
# Muc dich: Kiem tra thong tuyen mang, tinh san sang cua DNS, ket noi API
#           va kiem tra giay phep (License) tren may chu ESXi Host
# ==============================================================================
set -euo pipefail

health_check() {
    local base_dir="$1"

    print_section "KIỂM TRA SỨC KHỎE VÀ TÍNH SẴN SÀNG CỦA HẠ TẦNG (HEALTH CHECK)"

    if ! load_config "${base_dir}"; then
        return 1
    fi

    echo -e "${C_BOLD}Danh sach thong so kiem tra:${C_RESET}"
    echo -e "  - ESXi Host        : ${ESXI_HOSTNAME:-Chua khai bao}"
    echo -e "  - Gateway          : ${UBUNTU_GATEWAY:-Chua khai bao}"
    echo -e "  - VCSA FQDN / IP   : ${VCSA_FQDN:-Chua khai bao} (${VCSA_STATIC_IP:-Chua khai bao})"
    echo -e "  - VCSA ISO Path    : ${VCSA_ISO_PATH:-Chua khai bao}"
    echo ""

    # 1. Kiem tra Ping ket noi mang
    log_step "1. Kiem tra thong tuyen mang (Ping test)..."
    local -a hosts_to_ping=()
    [[ -n "${ESXI_HOSTNAME:-}" && ! "${ESXI_HOSTNAME}" =~ \<.* ]] && hosts_to_ping+=("${ESXI_HOSTNAME}")
    [[ -n "${UBUNTU_GATEWAY:-}" && ! "${UBUNTU_GATEWAY}" =~ \<.* ]] && hosts_to_ping+=("${UBUNTU_GATEWAY}")

    for target in "${hosts_to_ping[@]}"; do
        if ping -c 2 -W 2 "${target}" &>/dev/null; then
            echo -e "  Ping toi ${C_YELLOW}${target}${C_RESET}: ${C_GREEN}[THONG TUYEN]${C_RESET}"
        else
            echo -e "  Ping toi ${C_YELLOW}${target}${C_RESET}: ${C_RED}[THAT BAI - Khong phan hoi]${C_RESET}"
        fi
    done

    # 2. Kiem tra ket noi HTTPS va dich vu Hostd tren ESXi
    log_step "2. Kiem tra dich vu HTTPS / API tren ESXi Host..."
    if [[ -n "${ESXI_HOSTNAME:-}" && ! "${ESXI_HOSTNAME}" =~ \<.* ]]; then
        local http_code
        http_code="$(curl -k -s -o /dev/null -w "%{http_code}" --connect-timeout 3 "https://${ESXI_HOSTNAME}/" || true)"
        if [[ "${http_code}" =~ ^(200|301|302|400)$ ]]; then
            echo -e "  Ket noi HTTPS toi ${ESXI_HOSTNAME}: ${C_GREEN}[HOAT DONG - HTTP ${http_code}]${C_RESET}"
        else
            echo -e "  Ket noi HTTPS toi ${ESXI_HOSTNAME}: ${C_RED}[THAT BAI - HTTP ${http_code:-000}]${C_RESET}"
        fi
    fi

    # 3. Kiem tra phan giai ten mien DNS cho VCSA
    log_step "3. Kiem tra phan giai ten mien DNS hai chieu cho VCSA..."
    if [[ -n "${VCSA_FQDN:-}" && ! "${VCSA_FQDN}" =~ \<.* && -n "${VCSA_STATIC_IP:-}" && ! "${VCSA_STATIC_IP}" =~ \<.* ]]; then
        if command -v dig &>/dev/null; then
            local fwd_res rev_res
            fwd_res="$(dig @127.0.0.1 "${VCSA_FQDN}" +short 2>/dev/null || true)"
            rev_res="$(dig @127.0.0.1 -x "${VCSA_STATIC_IP}" +short 2>/dev/null || true)"

            if [[ "${fwd_res}" == "${VCSA_STATIC_IP}" ]]; then
                echo -e "  Phan giai thuan (${VCSA_FQDN} -> ${VCSA_STATIC_IP}): ${C_GREEN}[DAT YEU CAU]${C_RESET}"
            else
                echo -e "  Phan giai thuan (${VCSA_FQDN}): ${C_RED}[CHUA HOAT DONG - Tra ve: '${fwd_res:-NXDOMAIN}']${C_RESET}"
                echo -e "  ${C_YELLOW}Goi y: Chay muc [3] trong menu de tu dong cau hinh dnsmasq.${C_RESET}"
            fi

            if [[ -n "${rev_res}" ]]; then
                echo -e "  Phan giai nghich (${VCSA_STATIC_IP} -> ${rev_res}): ${C_GREEN}[DAT YEU CAU]${C_RESET}"
            else
                echo -e "  Phan giai nghich (${VCSA_STATIC_IP}): ${C_RED}[CHUA HOAT DONG - Tra ve: NXDOMAIN]${C_RESET}"
            fi
        else
            log_warn "Chua cai dat cong cu 'dig' (goi dnsutils) de kiem tra DNS."
        fi
    else
        log_warn "VCSA_FQDN hoac VCSA_STATIC_IP chua duoc khai bao day du trong config.env."
    fi

    # 4. Kiem tra tep ISO VCSA
    log_step "4. Kiem tra su ton tai cua tep ISO VCSA..."
    if [[ -n "${VCSA_ISO_PATH:-}" && ! "${VCSA_ISO_PATH}" =~ \<.* ]]; then
        if [[ -f "${VCSA_ISO_PATH}" ]]; then
            local iso_size
            iso_size="$(ls -lh "${VCSA_ISO_PATH}" | awk '{print $5}')"
            echo -e "  Tep ISO VCSA: ${C_GREEN}[TON TAI - Dung luong ${iso_size}]${C_RESET}"
        else
            echo -e "  Tep ISO VCSA: ${C_RED}[KHONG TIM THAY tai '${VCSA_ISO_PATH}']${C_RESET}"
        fi
    fi

    echo ""
    log_info "Hoan tat qua trinh kiem tra tong the."
}
