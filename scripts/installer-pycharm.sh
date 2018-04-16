#!/usr/bin/env bash

## Issues & not implemented things:
#  - Other platforms different from linux
#  - Get a different release, only latest
#  - Has to have write permissions on the parent of $INSTALL_FOLDER

## Rerurn codes
#  0 - Product installed
#  1 - Cancel by user
#  2 - Problems downloading or verifying files
#  3 - Lack of prerequisites

JQ=$(which jq)
CURL=$(which curl)
WGET=$(which wget)

if [ -z "$JQ" -o -z "$CURL" -o -z "$WGET" ]; then
  echo "This script requires jq, curl, & wget"
  exit 3
fi

set -e

PRODUCT_NAME="PyCharm"
PRODUCT="${PRODUCT_NAME,,}"
PRODUCT_CODE="PCP"  # PCP -> PyCharm Professional
RELEASE_TYPE="release"  # release | eap
RELEASE_LATEST="true"  # true | false -> Only the latest release or all
PLATFORM="linux"

TMP_FOLDER="/tmp/installer/jetbrains"
DOWNLOAD_FOLDER="${TMP_FOLDER}/${PRODUCT}"
INSTALL_FOLDER="/opt/${PRODUCT}"
BUILD_FILE="${INSTALL_FOLDER}/build.txt"

# query Jetbrains data services
echo "Downloading information for ${PRODUCT} latest release"

json=$(curl -s "https://data.services.jetbrains.com/products/releases?code=${PRODUCT_CODE}&latest=${RELEASE_LATEST}&type=${RELEASE_TYPE}")

release_obj=$(echo ${json} | jq -r .[][])

# Extract data from retrieved json
declare -r rel_build=$(echo ${release_obj} | jq -r '.build')
declare -r rel_version=$(echo ${release_obj} | jq -r '.version')
declare -r rel_major=$(echo ${release_obj} | jq -r '.majorVersion')
declare -r rel_date=$(echo ${release_obj} | jq -r '.date')
declare -r rel_type=$(echo ${release_obj} | jq -r '.type')
declare -r rel_file_url=$(echo ${release_obj} | jq -r ".downloads.${PLATFORM}.link")
declare -r rel_shasum_url=$(echo ${release_obj} | jq -r ".downloads.${PLATFORM}.checksumLink")
declare -r rel_file_size=$(echo ${release_obj} | jq -r ".downloads.${PLATFORM}.size")

declare -r rel_file="${rel_file_url##*/}"
declare -r rel_shasum="${rel_shasum_url##*/}"

# Check if product is already installed
if [ -d "${INSTALL_FOLDER}" ]; then
    if [ -f "${BUILD_FILE}"]; then
      cur_build=$(cat ${INSTALL_FOLDER}/build.txt)
      cur_build="${cur_build##PY-}"
    else
      cur_build="0"
    fi
    echo "Currently installed build: ${cur_build} on ${INSTALL_FOLDER}."
    if [[ "${cur_build}" < "${rel_build}" ]]; then
        echo "New ${PRODUCT_NAME} version available: ${rel_version}, build: ${rel_build}"
        # Ask if want to install the new version, only if there is an already installed version
        while true; do
            read -p "Do you want to install the new version? [Y/n]"
            case $REPLY in
                [Yy]* ) break;;
                "" ) break;;
                [Nn]* ) exit 1;;
            esac
        done
    else
        echo "Latest version of ${PRODUCT_NAME} installed."
        exit 0
    fi
else
    mkdir -p "${INSTALL_FOLDER}"
fi

set +e

function exit_on_file_error() {
    #rm ${DOWNLOAD_FOLDER}/${rel_file}
    exit 2
}

echo "Downloading ${PRODUCT_NAME} ${rel_version}"
# Create download folder, this folders wont be removed for cache
mkdir -p ${DOWNLOAD_FOLDER}

wget -nc -q -O "${DOWNLOAD_FOLDER}/${rel_file}" --https-only "${rel_file_url}"
if [[ "$(wc -c < ${DOWNLOAD_FOLDER}/${rel_file})" != "${rel_file_size}" ]]; then
    echo "Error: downloaded file don't have the correct size, exiting."
    exit_on_file_error
fi

wget -q -O "${DOWNLOAD_FOLDER}/${rel_shasum}" --https-only "${rel_shasum_url}"

echo "- Verifying files..."
( cd ${DOWNLOAD_FOLDER} && sha256sum --status -c "${DOWNLOAD_FOLDER}/${rel_shasum}" )
rv=$?
if [ ${rv} != 0 ]; then
    echo "Error: the file don't have the correct checksum, exiting."
    exit_on_file_error
fi

set -e

echo "Extracting ${PRODUCT_NAME} ${rel_version}"
tar  -C "${DOWNLOAD_FOLDER}" -xzf "${DOWNLOAD_FOLDER}/${rel_file}"
if [ ! -d "${DOWNLOAD_FOLDER}/${PRODUCT}-${rel_version}" ]; then
    echo "Error: fail at product extraction."
    exit_on_file_error
fi

echo "Installing ${PRODUCT_NAME} ${rel_version}"
# rename current install folder
mv "${INSTALL_FOLDER}" "${INSTALL_FOLDER}.old" || true
# install new version
mv "${DOWNLOAD_FOLDER}/${PRODUCT}-${rel_version}" "${INSTALL_FOLDER}"
#remove old version
rm -rf "${INSTALL_FOLDER}.old"

exit 0
