#!/usr/bin/env bash
# ==============================================================================
# Module: 05_iso_manager.sh
# Muc dich: Quan ly, tai nhanh va duyet tep ISO cai dat VMware VCSA
# Tac vu:
#   - Tai nhanh tep ISO tu URL su dung da luong (aria2c / curl) co kha nang resume
#   - Quet va duyet tep ISO tu thu muc chi dinh de cap nhat VCSA_ISO_PATH
#   - Kiem tra mount thu nghiem de xac thuc bo cai VCSA CLI Installer
# ==============================================================================
set -euo pipefail

# Tai nhanh tep ISO tu URL
download_iso_from_url() {
    local base_dir="$1"
    print_section "TẢI NHANH TỆP ISO VCSA TỪ ĐƯỜNG DẪN URL"

    # 1. Tiep nhan URL
    local iso_url=""
    while [[ -z "${iso_url}" ]]; do
        read -r -p "Nhap duong dan URL tai tep ISO (HTTP/HTTPS/FTP, hoac 'q' de huy): " iso_url
        iso_url="$(echo "${iso_url}" | xargs)"
        if [[ "${iso_url}" == "q" || "${iso_url}" == "Q" ]]; then
            log_info "Da huy thao tac tai tep ISO."
            return 0
        fi
        if [[ ! "${iso_url}" =~ ^(https?|ftp):// ]]; then
            log_warn "URL khong hop le. Vui long bat dau bang http://, https:// hoac ftp://"
            iso_url=""
        fi
    done

    # 2. Trich xuat ten tep tu URL
    local detected_name=""
    detected_name="$(basename "${iso_url%%\?*}")"
    if [[ -z "${detected_name}" || ! "${detected_name}" =~ \.iso$ ]]; then
        detected_name="VMware-VCSA-all.iso"
    fi

    local filename=""
    read -r -p "Xac nhan ten tep luu tru [Mac dinh: ${detected_name}]: " filename
    filename="${filename:-${detected_name}}"

    # 3. Thu muc luu tru
    local default_dest="/var/tmp"
    if [[ ! -w "${default_dest}" && -w "/tmp" ]]; then
        default_dest="/tmp"
    fi
    local dest_dir=""
    read -r -p "Nhap thu muc luu tep ISO [Mac dinh: ${default_dest}]: " dest_dir
    dest_dir="${dest_dir:-${default_dest}}"
    dest_dir="${dest_dir/#\~/$HOME}"

    mkdir -p "${dest_dir}" 2>/dev/null || sudo mkdir -p "${dest_dir}"

    # 4. Kiem tra dung luong o dia con trong
    local avail_gb=""
    avail_gb="$(df -BG "${dest_dir}" 2>/dev/null | awk 'NR==2 {gsub(/G/,""); print $4}')"
    if [[ -n "${avail_gb}" && "${avail_gb}" =~ ^[0-9]+$ ]]; then
        if [[ ${avail_gb} -lt 12 ]]; then
            log_warn "Dung luong trong tai '${dest_dir}' chi con ${avail_gb}GB (Tep ISO VCSA yeu cau ~10-12GB)."
            local proceed=""
            read -r -p "Tiep tuc tien trinh tai xuong? (y/N): " proceed
            if [[ ! "${proceed}" =~ ^[Yy]$ ]]; then
                log_info "Da huy thao tac tai tep."
                return 0
            fi
        else
            log_info "Dung luong trong tren o dia: ${avail_gb}GB (Dat yeu cau cho bo cai VCSA)."
        fi
    fi

    local target_file="${dest_dir}/${filename}"

    # 5. Kiem tra tep da ton tai hay chua
    if [[ -f "${target_file}" ]]; then
        local existing_size
        existing_size="$(du -h "${target_file}" | cut -f1)"
        log_warn "Tep '${target_file}' da ton tai tren he thong (Dung luong hien tai: ${existing_size})."
        echo "Lựa chọn xử lý:"
        echo "  [1] Tiếp tục tải nối tiếp (Resume download)"
        echo "  [2] Ghi đè và tải lại từ đầu (Overwrite)"
        echo "  [0] Hủy bỏ thao tác"
        local conflict_choice=""
        read -r -p "Vui long chon [1/2/0]: " conflict_choice
        case "${conflict_choice}" in
            1)
                log_info "Che do tai noi tiep (Resume) duoc kich hoat."
                ;;
            2)
                rm -f "${target_file}"
                log_info "Da xoa tep cu. Bat dau tai moi hoan toan."
                ;;
            *)
                log_info "Da huy thao tac."
                return 0
                ;;
        esac
    fi

    # 6. Cai dat hoac chon cong cu tai toc do cao (aria2c hoac curl/wget)
    local downloader="curl"
    if command -v aria2c &>/dev/null; then
        downloader="aria2c"
    else
        # Kiem tra quyen cai dat aria2c de tang toc
        if command -v apt-get &>/dev/null; then
            log_info "Dang cai dat cong cu tang toc tai da luong 'aria2'..."
            if [[ $EUID -eq 0 ]]; then
                apt-get update -qq && apt-get install -y -qq aria2 &>/dev/null || true
            elif sudo -n true 2>/dev/null; then
                sudo apt-get update -qq && sudo apt-get install -y -qq aria2 &>/dev/null || true
            fi
            if command -v aria2c &>/dev/null; then
                downloader="aria2c"
            fi
        fi
    fi

    # 7. Thuc thi tai tep
    log_step "Tien hanh tai tep ISO ve: ${target_file}"
    local download_status=0
    if [[ "${downloader}" == "aria2c" ]]; then
        log_info "Su dung cong cu 'aria2c' da luong (16 connections, ho tro resume)..."
        aria2c \
            --max-connection-per-server=16 \
            --split=16 \
            --min-split-size=1M \
            --continue=true \
            --file-allocation=none \
            --summary-interval=5 \
            --dir="${dest_dir}" \
            --out="${filename}" \
            "${iso_url}" || download_status=$?
    elif command -v curl &>/dev/null; then
        log_info "Su dung cong cu 'curl' co che do tiep noi (-C -)..."
        curl -L -C - -o "${target_file}" --progress-bar "${iso_url}" || download_status=$?
    elif command -v wget &>/dev/null; then
        log_info "Su dung cong cu 'wget' co che do tiep noi (-c)..."
        wget -c --progress=bar:force -O "${target_file}" "${iso_url}" || download_status=$?
    else
        log_error "Khong tim thay aria2c, curl hoac wget tren he thong."
        return 1
    fi

    if [[ ${download_status} -ne 0 ]]; then
        log_error "Tien trinh tai tep that bai voi ma loi: ${download_status}"
        return 1
    fi

    # 8. Kiem tra ket qua sau khi tai
    if [[ ! -f "${target_file}" ]]; then
        log_error "Khong tim thay tep sau khi tai xong tai: ${target_file}"
        return 1
    fi

    local final_size
    final_size="$(du -h "${target_file}" | cut -f1)"
    log_success "Tai tep ISO thanh cong!"
    echo "  - Duong dan tep : ${target_file}"
    echo "  - Dung luong     : ${final_size}"

    # 9. Cap nhat VCSA_ISO_PATH trong config.env
    log_step "Cap nhat duong dan tệp vao config.env..."
    update_config_var "${base_dir}" "VCSA_ISO_PATH" "${target_file}"
    VCSA_ISO_PATH="${target_file}"
    export VCSA_ISO_PATH
    log_success "Da cap nhat bien VCSA_ISO_PATH='${target_file}' trong config.env."
    return 0
}

# Quet va duyet tep ISO tu mot thu muc chi dinh
browse_and_select_iso() {
    local base_dir="$1"
    print_section "QUÉT VÀ DUYỆT TỆP ISO TỪ THƯ MỤC CHỈ ĐỊNH"

    # 1. Tiep nhan thu muc quet
    local default_scan_dir="/var/tmp"
    if [[ -n "${VCSA_ISO_PATH:-}" && -d "$(dirname "${VCSA_ISO_PATH}")" ]]; then
        default_scan_dir="$(dirname "${VCSA_ISO_PATH}")"
    fi

    local scan_dir=""
    echo "Thu muc mac dinh de quet: ${default_scan_dir}"
    read -r -p "Nhap duong dan thu muc can quet tim tep ISO [Mac dinh: ${default_scan_dir}]: " scan_dir
    scan_dir="${scan_dir:-${default_scan_dir}}"
    scan_dir="${scan_dir/#\~/$HOME}"

    if [[ ! -d "${scan_dir}" ]]; then
        log_error "Thu muc khong ton tai: ${scan_dir}"
        return 1
    fi

    # 2. Tim kiem tep ISO (do sau toi da 3 cap thu muc)
    log_step "Dang quet tep *.iso trong thu muc '${scan_dir}'..."
    local -a iso_list=()
    while IFS= read -r file_found; do
        if [[ -n "${file_found}" ]]; then
            iso_list+=("${file_found}")
        fi
    done < <(find "${scan_dir}" -maxdepth 3 -type f \( -name "*.iso" -o -name "*.ISO" \) 2>/dev/null | sort)

    # 3. Xu ly ket qua tim kiem
    if [[ ${#iso_list[@]} -eq 0 ]]; then
        log_warn "Khong tim thay tep co duoi *.iso nao trong thu muc '${scan_dir}'."
        
        # Ho tro quet them cac tep lon hon 1GB de phong tep bi doi ten
        local -a large_files=()
        while IFS= read -r large_file; do
            if [[ -n "${large_file}" ]]; then
                large_files+=("${large_file}")
            fi
        done < <(find "${scan_dir}" -maxdepth 2 -type f -size +1G 2>/dev/null | sort)

        if [[ ${#large_files[@]} -gt 0 ]]; then
            echo ""
            log_info "Phat hien cac tep co dung luong > 1GB trong thu muc:"
            local idx=1
            for f in "${large_files[@]}"; do
                local sz
                sz="$(du -h "${f}" | cut -f1)"
                echo "  [${idx}] ${sz} - ${f}"
                ((idx++)) || true
            done
            local pick_large=""
            read -r -p "Chon so thu tu tep can su dung [1-${#large_files[@]}] (hoac '0' de huy): " pick_large
            if [[ "${pick_large}" =~ ^[0-9]+$ && "${pick_large}" -ge 1 && "${pick_large}" -le ${#large_files[@]} ]]; then
                local selected_file="${large_files[$((pick_large-1))]}"
                update_config_var "${base_dir}" "VCSA_ISO_PATH" "${selected_file}"
                VCSA_ISO_PATH="${selected_file}"
                export VCSA_ISO_PATH
                log_success "Da cap nhat VCSA_ISO_PATH='${selected_file}' trong config.env."
                return 0
            fi
        fi
        return 0
    fi

    # 4. Hien thi danh sach tep ISO tim thay
    echo ""
    echo -e "${C_BOLD}Danh sach tep ISO tim thay tai '${scan_dir}':${C_RESET}"
    echo -e "${C_BLUE}--------------------------------------------------------------------------------${C_RESET}"
    printf "%-5s %-10s %-18s %s\n" "STT" "DUNG LƯỢNG" "NGÀY SỬA ĐỔI" "ĐƯỜNG DẪN TỆP"
    echo -e "${C_BLUE}--------------------------------------------------------------------------------${C_RESET}"

    local i=1
    for iso_item in "${iso_list[@]}"; do
        local f_size f_date
        f_size="$(du -h "${iso_item}" 2>/dev/null | cut -f1 || echo "N/A")"
        f_date="$(date -r "${iso_item}" "+%Y-%m-%d %H:%M" 2>/dev/null || echo "N/A")"
        printf "[%d]   %-10s %-18s %s\n" "${i}" "${f_size}" "${f_date}" "${iso_item}"
        ((i++)) || true
    done
    echo -e "${C_BLUE}--------------------------------------------------------------------------------${C_RESET}"

    # 5. Nguoi dung chon tep
    local choice=""
    read -r -p "Chon so thu tu tep ISO de gan lam bo cai VCSA [1-${#iso_list[@]}] (hoac '0' de huy): " choice

    if [[ -z "${choice}" || "${choice}" == "0" ]]; then
        log_info "Da huy thao tac chon tep."
        return 0
    fi

    if [[ ! "${choice}" =~ ^[0-9]+$ || "${choice}" -lt 1 || "${choice}" -gt ${#iso_list[@]} ]]; then
        log_warn "Lua chon khong hop le."
        return 1
    fi

    local selected_iso="${iso_list[$((choice-1))]}"
    log_info "Ban da chon: ${selected_iso}"

    # 6. Kiem tra quyen doc tep
    if [[ ! -r "${selected_iso}" ]]; then
        log_warn "Tep hien khong co quyen doc. Dang thu cap quyen..."
        chmod 644 "${selected_iso}" 2>/dev/null || sudo chmod 644 "${selected_iso}" 2>/dev/null || true
    fi

    # 7. Cap nhat vao config.env
    update_config_var "${base_dir}" "VCSA_ISO_PATH" "${selected_iso}"
    VCSA_ISO_PATH="${selected_iso}"
    export VCSA_ISO_PATH
    log_success "Da cap nhat VCSA_ISO_PATH='${selected_iso}' vao tep config.env thanh cong."
    return 0
}

# Kiem tra mount thu nghiem de xac thuc bo cai VCSA
test_mount_vcsa_iso() {
    local base_dir="$1"
    print_section "XÁC THỰC BỘ CÀI VCSA BẰNG MOUNT THỬ NGHIỆM"

    local iso_file="${VCSA_ISO_PATH:-}"
    if [[ -z "${iso_file}" || ! -f "${iso_file}" ]]; then
        log_error "Tep ISO hien tai khong ton tai hoac chua duoc khai bao: '${iso_file:-<Trong>}'"
        echo -e "Vui long su dung chuc nang tai tu URL hoac duyet thu muc truoc."
        return 1
    fi

    local mount_test_dir="/mnt/vcsa_iso_test_$(date +%s)"
    mkdir -p "${mount_test_dir}" 2>/dev/null || sudo mkdir -p "${mount_test_dir}"

    log_step "Tien hanh mount thu nghiem tep ISO vao: ${mount_test_dir}..."
    local mount_cmd="mount -o loop,ro \"${iso_file}\" \"${mount_test_dir}\""
    if [[ $EUID -eq 0 ]]; then
        eval "${mount_cmd}"
    else
        sudo mount -o loop,ro "${iso_file}" "${mount_test_dir}"
    fi

    local installer_bin="${mount_test_dir}/vcsa-cli-installer/lin64/vcsa-deploy"
    if [[ -f "${installer_bin}" ]]; then
        log_success "Xac thuc bo cai thanh cong! Phat hien tep thuc thi VCSA CLI Installer:"
        echo "  - File thuc thi: vcsa-cli-installer/lin64/vcsa-deploy"
        if "${installer_bin}" --version &>/dev/null; then
            local ver_info
            ver_info="$("${installer_bin}" --version 2>&1 | head -n 1 || true)"
            echo "  - Phien ban installer: ${ver_info}"
        fi
    else
        log_warn "Tep ISO da mount thanh cong nhung khong tim thay 'vcsa-cli-installer/lin64/vcsa-deploy'."
        log_warn "Vui long kiem tra lai day co phai la tep ISO cai dat VCSA chuan hay khong."
    fi

    log_step "Don dep diem mount thu nghiem..."
    if [[ $EUID -eq 0 ]]; then
        umount "${mount_test_dir}" 2>/dev/null || umount -l "${mount_test_dir}" 2>/dev/null || true
        rmdir "${mount_test_dir}" 2>/dev/null || true
    else
        sudo umount "${mount_test_dir}" 2>/dev/null || sudo umount -l "${mount_test_dir}" 2>/dev/null || true
        sudo rmdir "${mount_test_dir}" 2>/dev/null || true
    fi
    log_success "Hoan tat kiem tra."
    return 0
}

# Menu quan ly tep ISO
manage_vcsa_iso_menu() {
    local base_dir="$1"
    local sub_choice=""

    while true; do
        clear || true
        local current_iso="${VCSA_ISO_PATH:-<Chưa khai báo>}"
        local iso_status="${C_RED}[Không tồn tại]${C_RESET}"
        if [[ -n "${VCSA_ISO_PATH:-}" && -f "${VCSA_ISO_PATH}" ]]; then
            local sz
            sz="$(du -h "${VCSA_ISO_PATH}" 2>/dev/null | cut -f1 || echo "")"
            iso_status="${C_GREEN}[Hợp lệ - ${sz}]${C_RESET}"
        fi

        echo -e "${C_BLUE}==============================================================================${C_RESET}"
        echo -e "${C_WHITE}${C_BOLD}   QUẢN LÝ VÀ CHUẨN BỊ TỆP ISO VCENTER (VCSA ISO MANAGER)${C_RESET}"
        echo -e "${C_BLUE}==============================================================================${C_RESET}"
        echo -e " Đường dẫn ISO hiện tại : ${C_YELLOW}${current_iso}${C_RESET}"
        echo -e " Trạng thái tệp         : ${iso_status}"
        echo -e "${C_BLUE}==============================================================================${C_RESET}"
        echo -e "  ${C_BOLD}[1]${C_RESET} Tải nhanh tệp ISO từ đường dẫn URL (Hỗ trợ đa luồng aria2c)"
        echo -e "  ${C_BOLD}[2]${C_RESET} Duyệt và chọn tệp ISO từ thư mục chỉ định (Cập nhật config.env)"
        echo -e "  ${C_BOLD}[3]${C_RESET} Kiểm tra mount thử nghiệm tệp ISO hiện tại (Xác thực bộ cài)"
        echo -e "${C_BLUE}------------------------------------------------------------------------------${C_RESET}"
        echo -e "  ${C_BOLD}[0]${C_RESET} Quay lại menu chính"
        echo -e "${C_BLUE}==============================================================================${C_RESET}"
        echo -n "Vui lòng nhập lựa chọn [0-3]: "
        read -r sub_choice

        case "${sub_choice}" in
            1)
                clear || true
                download_iso_from_url "${base_dir}" || true
                pause_menu
                ;;
            2)
                clear || true
                browse_and_select_iso "${base_dir}" || true
                pause_menu
                ;;
            3)
                clear || true
                test_mount_vcsa_iso "${base_dir}" || true
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
