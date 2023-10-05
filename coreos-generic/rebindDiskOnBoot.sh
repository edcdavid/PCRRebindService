#!/bin/bash
SCRIPT_DIR=$(dirname "$0")
source $SCRIPT_DIR/luks-helpers.sh
#set -x

logInfo "booting... checking if rebinding disk needed"
processPCRentriesOnly rebindPCRentriesOnly
exit 0

logInfo "PCR configuration already present and reserved slot not present, continue boot"
