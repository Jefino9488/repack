#!/bin/bash -l

set -e

# Environment Variables
URL="${ROM_URL}"
DEVICE="${DEVICE_NAME}"
COMPATIBLE="${COMPATIBLE_LIST}"
PRELOADER_URL="${PRELOADER_URL:-}"
DISABLE_VERITY="${DISABLE_VERITY:-yes}"

# Backwards compatibility
if [ -z "${URL}" ] && [ -n "$1" ]; then
    URL="$1"
    [ -n "$3" ] && DEVICE="$3"
    [ -n "$5" ] && FIRMWARE_URL="$5"
fi

RED='\033[1;31m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
GREEN='\033[1;32m'
NC='\033[0m'

# Helper function to download files
download_file() {
    local url="$1"
    local output="$2"
    local directory="${3:-$GITHUB_WORKSPACE}"

    echo -e "${YELLOW}- Downloading ${output}..."
    
    # Check if URL is Google Drive
    if [[ "$url" =~ "drive.google.com" ]]; then
        echo -e "${BLUE}- Detected Google Drive link, using gdown..."
        cwd_bkp=$(pwd)
        cd "$directory"
        gdown -O "$output" "$url"
        local ret=$?
        cd "$cwd_bkp"
        return $ret
    else
        echo -e "${BLUE}- Using aria2c..."
        aria2c -x16 -j"$(nproc)" -U "Mozilla/5.0" -d "$directory" -o "$output" "$url"
        return $?
    fi
}

download_and_extract_firmware() {
    if [ -n "${FIRMWARE_URL}" ]; then
        cd "${GITHUB_WORKSPACE}"
        
        # Use new download helper
        download_file "${FIRMWARE_URL}" "firmware.zip" "${GITHUB_WORKSPACE}"
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
    
    if [ -z "${URL}" ]; then
        echo -e "${RED}- Error: ROM_URL is empty!"
        exit 1
    fi
    
    download_file "${URL}" "recovery_rom.zip" "${GITHUB_WORKSPACE}"
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}- Error: Failed to download recovery ROM"
        exit 1
    fi
    
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

handle_preloader() {
    echo -e "${YELLOW}- Checking for preloader..."
    
    # Check if preloader exists in extracted images
    PRELOADER_FILE=$(find "${GITHUB_WORKSPACE}/${DEVICE}/images" -name "preloader*.bin" -o -name "preloader*.img" 2>/dev/null | head -1)
    
    if [ -n "$PRELOADER_FILE" ]; then
        PRELOADER_NAME=$(basename "$PRELOADER_FILE")
        echo -e "${GREEN}- Found preloader in ROM: ${PRELOADER_NAME}"
    elif [ -n "$PRELOADER_URL" ]; then
        echo -e "${YELLOW}- Downloading preloader from URL..."
        
        # Logic to determine filename:
        # 1. Try to get basename if it looks like a file (has extension)
        # 2. Otherwise default to preloader.bin to avoid saving as ID (like LxZ6FyrC)
        
        local url_base
        url_base=$(basename "$PRELOADER_URL")
        
        if [[ "$url_base" == *.* ]]; then
             PRELOADER_NAME="$url_base"
        else
             PRELOADER_NAME="preloader.bin"
        fi
        
        echo -e "${BLUE}- Determined preloader name: ${PRELOADER_NAME}"

        download_file "$PRELOADER_URL" "$PRELOADER_NAME" "${GITHUB_WORKSPACE}/${DEVICE}/images"
        
        if [ $? -ne 0 ]; then
             echo -e "${RED}- Failed to download preloader!"
             exit 1
        fi

        echo -e "${GREEN}- Downloaded preloader: ${PRELOADER_NAME}"
    else
        PRELOADER_NAME=""
        echo -e "${YELLOW}- No preloader found and no URL provided. Skipping preloader."
    fi
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

generate_config() {
    echo -e "${YELLOW}- Generating config.txt"
    
    # Build the list of images from the images directory
    cd "${GITHUB_WORKSPACE}/${DEVICE}/images"
    IMAGE_LIST=$(ls -1 *.img *.bin 2>/dev/null | tr '\n' ',' | sed 's/,$//')
    
    # Write config file
    cat > "${GITHUB_WORKSPACE}/zip/config.txt" << EOF
# Fastboot Flasher Configuration
# Auto-generated by repack workflow

DEVICE=${DEVICE}
COMPATIBLE=${COMPATIBLE}
PRELOADER=${PRELOADER_NAME}
DISABLE_VERITY=${DISABLE_VERITY}
IMAGES=${IMAGE_LIST}
EOF
    
    echo -e "${GREEN}- Config generated:"
    cat "${GITHUB_WORKSPACE}/zip/config.txt"
}

upload_to_gofile() {
    echo -e "${YELLOW}- Uploading ${DEVICE}_fastboot.zip to Gofile.io"
    
    # Upload file
    RESPONSE=$(curl -s -F "file=@${GITHUB_WORKSPACE}/zip/${DEVICE}_fastboot.zip" https://upload.gofile.io/uploadfile)
    
    # Check if curl failed
    if [ $? -ne 0 ]; then
        echo -e "${RED}- Upload failed!"
        return 1
    fi

    # Extract download page URL
    DOWNLOAD_PAGE=$(echo "$RESPONSE" | grep -o '"downloadPage":"[^"]*' | cut -d'"' -f4)

    if [ -n "$DOWNLOAD_PAGE" ]; then
        echo -e "${GREEN}- Upload successful!"
        echo -e "${GREEN}- Download link: ${DOWNLOAD_PAGE}"
        
        # Save to file for GitHub Actions to read
        echo "${DOWNLOAD_PAGE}" > "${GITHUB_WORKSPACE}/gofile_link.txt"
    else
        echo -e "${RED}- Failed to parse upload response."
        echo -e "Response: $RESPONSE"
    fi
}

final_steps() {
    if [ -d "${GITHUB_WORKSPACE}/new_firmware" ]; then
        mv -t "${GITHUB_WORKSPACE}/${DEVICE}/images" "${GITHUB_WORKSPACE}/new_firmware"/* || exit
        sudo rm -rf "${GITHUB_WORKSPACE}/new_firmware"
    fi

    mkdir -p "${GITHUB_WORKSPACE}/zip/images"

    cp "${GITHUB_WORKSPACE}/${DEVICE}/images"/* "${GITHUB_WORKSPACE}/zip/images/"

    # Generate config.txt
    generate_config

    cd "${GITHUB_WORKSPACE}/zip" || exit

    echo -e "${YELLOW}- Zipping fastboot files"
    zip -r "${GITHUB_WORKSPACE}/zip/${DEVICE}_fastboot.zip" . || true
    echo -e "${GREEN}- ${DEVICE}_fastboot.zip created successfully"
    rm -rf "${GITHUB_WORKSPACE}/zip/images"

    upload_to_gofile

    echo -e "${GREEN}- All done!"
}

# Main Execution
download_recovery_rom
set_permissions_and_create_dirs
extract_payload_bin
extract_images
handle_preloader
move_images_and_calculate_sizes
create_super_image
move_super_image
prepare_device_directory
final_steps
