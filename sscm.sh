#!/bin/bash
#
# Owner: Ali Jabir
# Email: syedalijabir@gmail.com
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Color codes
ERROR='\033[1;31m'
GREEN='\033[0;32m'
TORQ='\033[0;96m'
HEAD='\033[44m'
INFO='\033[0;33m'
NORM='\033[0m'

function log() {
  echo -e "[$(basename $0)] $@"
}

function tryexec() {
  "$@"
  retval=$?
  [[ $retval -eq 0 ]] && return 0

  log 'A command has failed:'
  log "  $@"
  log "Value returned: ${retval}"
  print_stack
  exit $retval
}

function print_stack() {
  local i
  local stack_size=${#FUNCNAME[@]}
  log "Stack trace (most recent call first):"
  # to avoid noise we start with 1, to skip the current function
  for (( i=1; i<$stack_size ; i++ )); do
    local func="${FUNCNAME[$i]}"
    [[ -z "$func" ]] && func='MAIN'
    local line="${BASH_LINENO[(( i - 1 ))]}"
    local src="${BASH_SOURCE[$i]}"
    [[ -z "$src" ]] && src='UNKNOWN'

    log "  $i: File '$src', line $line, function '$func'"
  done
}

# Usage function for the script
function usage () {
  cat << DELIM__
usage: $(basename $0) [options] [parameter]
Options:
  --ca                  Create root CA
  --client <name>       Name of the client (for keeping track only)      
  -h, --help            Display help menu
DELIM__
}

# read the options
TEMP=$(getopt -o fh --long force,ca,client:,help -n 'sscm.sh' -- "$@")
if [[ $? -ne 0 ]]; then
  usage
  exit 1
fi
eval set -- "$TEMP"

# extract options
while true ; do
  case "$1" in
    --ca) CA=true; shift 1 ;;
    --client) CLIENT=$2; shift 2 ;;
    -f|--force) FORCE=true; shift 1 ;;
    -h|--help)  usage ; exit 1 ;;
    --) shift ; break ;;
    *) usage ; exit 1 ;;
  esac
done

CA=${CA:-}
CLIENT=${CLIENT:-} 
FORCE=${FORCE:-} 
SCRIPTPATH="$( cd "$(dirname "$0")" ; pwd -P )"
CLIENT_SERIAL_FILE=${SCRIPTPATH}/.client_serial
CA_DIR=${SCRIPTPATH}/ca

if [[ ${CA} == "true" ]]; then
  if [[ ! -d ${CA_DIR} ]]; then
    mkdir -p ${CA_DIR}
    openssl genrsa -aes256 -passout pass:admin -out ${CA_DIR}/ca.pass.key 4096
    openssl rsa -passin pass:admin -in ${CA_DIR}/ca.pass.key -out ${CA_DIR}/ca.key
    rm ${CA_DIR}/ca.pass.key
    log "${INFO}Generating root CA. Provide the required information.${NORM}"
    openssl req -new -x509 -days 3650 -key ${CA_DIR}/ca.key -out ${CA_DIR}/ca.pem
    log "${GREEN}CA structure created.${NORM}"
    exit 0
  else
    log "${INFO}CA already exists.${NORM}"
  fi
fi

if [[ -z ${CLIENT} ]]; then
  log log "${ERROR}Client parameter cannot be empty.${NORM}"
  usage
  exit 2
fi

if [[ ! -f ${CLIENT_SERIAL_FILE} ]]; then
  echo "1" > ${CLIENT_SERIAL_FILE}
  log "${INFO}Created client_serial file [${CLIENT_SERIAL_FILE}].${NORM}"
fi
CLIENT_SERIAL=$(cat ${CLIENT_SERIAL_FILE})
CLIENT_ID="${CLIENT_SERIAL}-${CLIENT}"
CLIENT_DIR=${SCRIPTPATH}/clients/${CLIENT}

if [[ ! -d ${CLIENT_DIR} ]]; then
  mkdir -p ${CLIENT_DIR}
else
  if [[ ${FORCE} == "true" ]]; then
    rm -rf ${CLIENT_DIR}
    mkdir -p ${CLIENT_DIR}
  else
    log "${INFO}${CLIENT_DIR} already exists.${NORM}"
    exit 1
  fi
fi

# rsa
openssl genrsa -aes256 -passout pass:admin -out ${CLIENT_DIR}/${CLIENT_ID}.pass.key 4096
openssl rsa -passin pass:admin -in ${CLIENT_DIR}/${CLIENT_ID}.pass.key -out ${CLIENT_DIR}/${CLIENT_ID}.key
rm ${CLIENT_DIR}/${CLIENT_ID}.pass.key
# generate the CSR
openssl req -new -key ${CLIENT_DIR}/${CLIENT_ID}.key -out ${CLIENT_DIR}/${CLIENT_ID}.csr


# issue this certificate, signed by the CA root we made in the previous section
openssl x509 -req -days 3650 -in ${CLIENT_DIR}/${CLIENT_ID}.csr -CA ${CA_DIR}/ca.pem -CAkey ${CA_DIR}/ca.key -set_serial ${CLIENT_SERIAL} -out ${CLIENT_DIR}/${CLIENT_ID}.pem
# bundle
cat ${CLIENT_DIR}/${CLIENT_ID}.key ${CLIENT_DIR}/${CLIENT_ID}.pem ${CA_DIR}/ca.pem > ${CLIENT_DIR}/${CLIENT_ID}.bundle.pem

# update client_serial
CLIENT_SERIAL=$((CLIENT_SERIAL+1))
echo ${CLIENT_SERIAL} > ${CLIENT_SERIAL_FILE}

log "${INFO}TLS credentials created under [${CLIENT_DIR}/]${NORM}"

exit 0
