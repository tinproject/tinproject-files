#!/usr/bin/env bash

## Download and install Hashicorp applications
#  Usage = $0 <product> <version> \n
#   - product = Hasicorp product, e.g.: packer
#   - version = build version, e.g.: 0.12.

USAGE="Usage = $0 <product> <version>"

## Issues & not implemented things:
#  - Other platforms different from linux
#  - Get latest by default
#  - Has to have write permissions on the parent of $BASE_FOLDER
#  - Treat Vagrant as a special option, downloads a -deb not a .zip

## Rerurn codes
#  0 - Product installed
#  1 - Calling with bad parameters
#  2 - Problems verifying files
#  3 - Lack of prerequisites

PRODUCT="non_valid_product"
VERSION="non_valid_version"
OS="linux"
ARCH="amd64"

BASE_URL="https://releases.hashicorp.com"
GPG_LONG_ID="51852D87348FFC4C"
GPG_KEY_FINGERPRINT="91A6E7F85D05C65630BEF18951852D87348FFC4C"
GPG_KEYSERVER="hkp://keys.gnupg.net/"
GPG_KEYSERVER="hkp://keyserver.ubuntu.com/"

JQ_NULL="null"

function exit_if_error() {
    if [ -n ${S2} ]; then
        echo $2
    fi
    if [ -n ${TEMP_FOLDER} -a -d ${TEMP_FOLDER} ]; then
        #echo "Removing temp folder."
        rm -rf ${TEMP_FOLDER}
    fi
    exit $1
}

JQ=$(which jq)
CURL=$(which curl)
WGET=$(which wget)

if [ -z "$JQ" -o -z "$CURL" -o -z "$WGET" ]; then
  exit_if_error 3 "This script requires jq, curl, & wget"
fi

# test parameters
if [ -z $1 ]; then
    echo ${USAGE}
    exit_if_error 1 "Product not specified"
fi
PRODUCT="${1}"
if [ -z $2 ]; then
    echo ${USAGE}
    exit_if_error 1 "Version not specified"
fi
VERSION="${2}"

BASE_FOLDER="${BASE_FOLDER:=${HOME}/Programs}"
INSTALL_FOLDER="${BASE_FOLDER}/${PRODUCT}"

echo "* Searching for ${PRODUCT} version ${VERSION}..."

set -e
# Download data from Hashicorp API. See: https://www.hashicorp.com/blog/hashicorp-and-fastly.html
hashi_json=$(curl -s ${BASE_URL}/index.json | jq .)

product_json=$(echo ${hashi_json} | jq -r --arg product ${PRODUCT} '.[$product].versions')
if [[ "${product_json}" == "${JQ_NULL}" ]]; then
    echo "Could not locate the Hashicorp product ${PRODUCT}."
    echo "Must be one of this:"
    vars=( $(echo ${hashi_json} | jq -r 'keys | @sh' ) )
    for f in "${vars[@]}"; do echo "$f" ; done
    exit 1
fi

version_json=$(echo ${product_json} | jq -r --arg version ${VERSION} '.[$version]')
if [[ "${version_json}" == "${JQ_NULL}" ]]; then
    echo "Could not locate version ${VERSION} for product ${PRODUCT}."
    echo "Must be one of this:"
    vars=( $(echo ${product_json} | jq -r 'keys | @sh' ) )
    for f in "${vars[@]}"; do echo "$f" ; done
    exit 1
fi

build_json=$(echo ${version_json} | jq -r --arg os ${OS} '.builds | .[] | select(.os == $os)')
if [[ "${build_json}" == "" ]]; then
    echo "Could not find OS ${OS} for product ${PRODUCT} ${VERSION}."
    echo "Must be one of this:"
    vars=( $(echo ${version_json} | jq -r '[.builds | .[].os]  | unique | @sh' ) )
    for f in "${vars[@]}"; do echo "$f" ; done
    exit 1
fi

release_json=$(echo ${build_json} | jq -r --arg arch ${ARCH} 'select(.arch == $arch)')
if [[ "${release_json}" == "" ]]; then
    echo "Could not find arch ${ARCH} for product ${PRODUCT} ${VERSION} for ${OS}."
    echo "Must be one of this:"
    vars=( $(echo ${build_json} | jq -r '[.arch] | unique | @sh') )
    for f in "${vars[@]}"; do echo "$f" ; done
    exit 1
fi


file_url=$(echo ${release_json} | jq -r '.url')
file_name=$(echo ${release_json} | jq -r '.filename')
shasums=$(echo ${version_json} | jq -r '.shasums')
shasums_signature=$(echo ${version_json} | jq -r '.shasums_signature')

TEMP_FOLDER=$(mktemp -d)

export GNUPGHOME="${TEMP_FOLDER}"

echo "* Downloading files..."

wget -q -O "${TEMP_FOLDER}/${file_name}" --https-only "${file_url}"
echo "${BASE_URL}/${PRODUCT}/${VERSION}/${shasums}"
wget -q -O "${TEMP_FOLDER}/${shasums}" --https-only "${BASE_URL}/${PRODUCT}/${VERSION}/${shasums}"
wget -q -O "${TEMP_FOLDER}/${shasums_signature}" --https-only "${BASE_URL}/${PRODUCT}/${VERSION}/${shasums_signature}"

echo "* Obtaining gpg keys..."
set +e
gpg -q --keyserver ${GPG_KEYSERVER} --recv-keys ${GPG_KEY_FINGERPRINT} > /dev/null

echo "* Veryifying signatures..."
gpg -q --batch --trusted-key "0x${GPG_LONG_ID}" --verify "${TEMP_FOLDER}/${shasums_signature}" "${TEMP_FOLDER}/${shasums}" 2> /dev/null
rv=$?
if [ ${rv} != 0 ]; then
    exit_if_error 2 "Error verifying shasum signature."
fi

echo "* Veryifying checksums..."
cat "${TEMP_FOLDER}/${shasums}" | grep "${file_name}" > "${TEMP_FOLDER}/shasum"
(cd ${TEMP_FOLDER} && sha256sum --status --check "${TEMP_FOLDER}/shasum")
rv=$?
if [ ${rv} != 0 ]; then
    exit_if_error 2 "Error verifying file checksums."
fi

echo "* Installing ${PRODUCT} ${VERSION}..."
if [ ! -d INSTALL_FOLDER ]; then
    mkdir -p ${INSTALL_FOLDER}
fi

unzip -q -o -d "${INSTALL_FOLDER}" "${TEMP_FOLDER}/${file_name}"

echo "* Installation finished: ${PRODUCT} ${VERSION} installed on ${INSTALL_FOLDER}"
echo "To run ${PRODUCT} you need to add to the path, or create a link to the executable:"
echo "- Create a link: \$sudo ln -s ${INSTALL_FOLDER}/${PRODUCT} /usr/bin/${PRODUCT}"
echo "- Add install folder to \$PATH on ~/.bashrc: PATH${INSTALL_FOLDER}:\$PATH"
exit_if_error 0
