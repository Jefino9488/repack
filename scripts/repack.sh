#!/bin/bash -l

set -e

URL="$1"
GITHUB_WORKSPACE="$2"
DEVICE="$3"
# KEY="$4" # Removed since not used in AOSP flow directly or handled by env
FIRMWARE_URL="$5"

UPLOAD="${GITHUB_WORKSPACE}/tools/upload.sh"
RED='\033[1;31m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
GREEN='\033[1;32m'

download_and_extract_firmware() {
    if [ -n "${FIRMWARE_URL}" ]; then
        cd "${GITHUB_WORKSPACE}"
        echo -e "${YELLOW}- Downloading firmware..."
        aria2c -x16 -j"$(nproc)" -U "Mozilla/5.0" -o "firmware.zip" "${FIRMWARE_URL}"
        if [ $? -ne 0 ]; then
            exit 1
        fi

        IMAGES=("apusys.img" "audio_dsp.img" "ccu.img" "dpm.img" "gpueb.img" "gz.img" "lk.img" "mcf_ota.img" "mcupm.img" "md1img.img" "mvpu_algo.img" "pi_img.img" "scp.img" "spmfw.img")
        mkdir -p firmware_images

        # Extract all files to a temporary directory
        unzip -q firmware.zip -d firmware_temp
        if [ $? -ne 0 ]; then
            exit 1
        fi

        # Find and move the specified image files
        for img in "${IMAGES[@]}"; do
            find firmware_temp -type f -name "${img}" -exec mv {} firmware_images/ \;
            if [ $? -ne 0 ]; then
                echo -e "${RED}- Failed to find ${img}"
                exit 1
            fi
        done

        mkdir -p "${GITHUB_WORKSPACE}/new_firmware"
        mv firmware_images/* "${GITHUB_WORKSPACE}/new_firmware/"
        if [ $? -ne 0 ]; then
            exit 1
        fi

        # Clean up
        rm -rf firmware.zip firmware_images firmware_temp
    fi
}

download_recovery_rom() {
    echo -e "${BLUE}- Starting downloading recovery rom"
    aria2c -x16 -j"$(nproc)" -U "Mozilla/5.0" -d "${GITHUB_WORKSPACE}" -o "recovery_rom.zip" "${URL}"
    echo -e "${GREEN}- Downloaded recovery rom"
}

set_permissions_and_create_dirs() {
    sudo chmod -R +rwx "${GITHUB_WORKSPACE}/tools"
    mkdir -p "${GITHUB_WORKSPACE}/${DEVICE}"
    mkdir -p "${GITHUB_WORKSPACE}/super_maker/config"
    mkdir -p "${GITHUB_WORKSPACE}/zip"
}

extract_payload_bin() {
    echo -e "${YELLOW}- Extracting payload.bin"
    RECOVERY_ZIP="recovery_rom.zip"
    7z x "${GITHUB_WORKSPACE}/${RECOVERY_ZIP}" -o"${GITHUB_WORKSPACE}/${DEVICE}" payload.bin || true
    rm -rf "${GITHUB_WORKSPACE:?}/${RECOVERY_ZIP:?}"
    echo -e "${BLUE}- Extracted payload.bin"
}

extract_images() {
    echo -e "${YELLOW}- Extracting images"
    mkdir -p "${GITHUB_WORKSPACE}/${DEVICE}/images"
    "${GITHUB_WORKSPACE}/tools/payload-dumper-go" -o "${GITHUB_WORKSPACE}/${DEVICE}/images" "${GITHUB_WORKSPACE}/${DEVICE}/payload.bin" >/dev/null
    sudo rm -rf "${GITHUB_WORKSPACE:?}/${DEVICE:?}/payload.bin"
    echo -e "${BLUE}- Extracted images"
}

move_images_and_calculate_sizes() {
    echo -e "${YELLOW}- Moving images to super_maker and calculating sizes"
    local IMAGE
    for IMAGE in vendor product system system_ext odm_dlkm odm vendor_dlkm; do
        if [ -f "${GITHUB_WORKSPACE}/${DEVICE}/images/$IMAGE.img" ]; then
             mv -t "${GITHUB_WORKSPACE}/super_maker" "${GITHUB_WORKSPACE}/${DEVICE}/images/$IMAGE.img" || exit
             eval "${IMAGE}_size=\$(du -b \"${GITHUB_WORKSPACE}/super_maker/$IMAGE.img\" | awk '{print \$1}')"
             echo -e "${BLUE}- Moved $IMAGE"
        else
            echo -e "${RED}- Image $IMAGE.img not found, skipping..."
            eval "${IMAGE}_size=0"
        fi
    done

    # Calculate total size of all images
    echo -e "${YELLOW}- Calculating total size of all images"
    super_size=9126805504
    total_size=$((system_size + system_ext_size + product_size + vendor_size + odm_size + odm_dlkm_size + vendor_dlkm_size))
    echo -e "${BLUE}- Size of all images"
    echo -e "system: $system_size"
    echo -e "system_ext: $system_ext_size"
    echo -e "product: $product_size"
    echo -e "vendor: $vendor_size"
    echo -e "odm: $odm_size"
    echo -e "odm_dlkm: $odm_dlkm_size"
    echo -e "vendor_dlkm: $vendor_dlkm_size"
    echo -e "total size: $total_size"
}

create_super_image() {
    echo -e "${YELLOW}- Creating super image"
    # Note: Logic assumes A/B partition style as per original script
    "${GITHUB_WORKSPACE}/tools/lpmake" --metadata-size 65536 --super-name super --block-size 4096 --metadata-slots 3 \
        --device super:"${super_size}" --group main_a:"${total_size}" --group main_b:"${total_size}" \
        --partition system_a:readonly:"${system_size}":main_a --image system_a=./super_maker/system.img \
        --partition system_b:readonly:0:main_b \
        --partition system_ext_a:readonly:"${system_ext_size}":main_a --image system_ext_a=./super_maker/system_ext.img \
        --partition system_ext_b:readonly:0:main_b \
        --partition product_a:readonly:"${product_size}":main_a --image product_a=./super_maker/product.img \
        --partition product_b:readonly:0:main_b \
        --partition vendor_a:readonly:"${vendor_size}":main_a --image vendor_a=./super_maker/vendor.img \
        --partition vendor_b:readonly:0:main_b \
        --partition odm_dlkm_a:readonly:"${odm_dlkm_size}":main_a --image odm_dlkm_a=./super_maker/odm_dlkm.img \
        --partition odm_dlkm_b:readonly:0:main_b \
        --partition odm_a:readonly:"${odm_size}":main_a --image odm_a=./super_maker/odm.img \
        --partition odm_b:readonly:0:main_b \
        --partition vendor_dlkm_a:readonly:"${vendor_dlkm_size}":main_a --image vendor_dlkm_a=./super_maker/vendor_dlkm.img \
        --partition vendor_dlkm_b:readonly:0:main_b \
        --virtual-ab --sparse --output "${GITHUB_WORKSPACE}/super_maker/super.img" || exit
    echo -e "${BLUE}- Created super image"
}

move_super_image() {
    echo -e "${YELLOW}- Moving super image"
    mv -t "${GITHUB_WORKSPACE}/${DEVICE}/images" "${GITHUB_WORKSPACE}/super_maker/super.img" || exit
    sudo rm -rf "${GITHUB_WORKSPACE}/super_maker"
    echo -e "${BLUE}- Moved super image"
}

prepare_device_directory() {
    echo -e "${YELLOW}- Downloading and preparing ${DEVICE} fastboot working directory"

    LATEST_RELEASE_URL=$(curl -s https://api.github.com/repos/Jefino9488/Fastboot-Flasher/releases/latest | grep "browser_download_url.*zip" | cut -d '"' -f 4)
    aria2c -x16 -j"$(nproc)" -U "Mozilla/5.0" -o "fastboot_flasher_latest.zip" "${LATEST_RELEASE_URL}"

    unzip -q "fastboot_flasher_latest.zip" -d "${GITHUB_WORKSPACE}/zip"

    rm "fastboot_flasher_latest.zip"

    echo -e "${BLUE}- Downloaded and prepared ${DEVICE} fastboot working directory"
}

final_steps() {
    # Removed Magisk handling here
    
    if [ -d "${GITHUB_WORKSPACE}/new_firmware" ]; then
        mv -t "${GITHUB_WORKSPACE}/${DEVICE}/images" "${GITHUB_WORKSPACE}/new_firmware"/* || exit
        sudo rm -rf "${GITHUB_WORKSPACE}/new_firmware"
    fi

    mkdir -p "${GITHUB_WORKSPACE}/zip/images"

    cp "${GITHUB_WORKSPACE}/${DEVICE}/images"/* "${GITHUB_WORKSPACE}/zip/images/"

    cd "${GITHUB_WORKSPACE}/zip" || exit

    echo -e "${YELLOW}- Zipping fastboot files"
    zip -r "${GITHUB_WORKSPACE}/zip/${DEVICE}_fastboot.zip" . || true
    echo -e "${GREEN}- ${DEVICE}_fastboot.zip created successfully"
    rm -rf "${GITHUB_WORKSPACE}/zip/images"

    echo -e "${GREEN}- All done!"
}

# Main Execution
download_recovery_rom
set_permissions_and_create_dirs
extract_payload_bin
extract_images
move_images_and_calculate_sizes
create_super_image
move_super_image
prepare_device_directory
# patch_boot_image # Removed
final_steps
