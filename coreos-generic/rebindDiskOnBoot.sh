#!/bin/bash
SCRIPT_DIR=$(dirname "$0")
source $SCRIPT_DIR/luks-helpers.sh
#set -x

logInfo "booting... checking if rebinding disk needed"
clevis luks list -d /dev/disk/by-partlabel/root -s $RESERVED_SLOT
processPCRentriesOnly rebindPCRentriesOnly
exit 0

logInfo "PCR configuration already present and reserved slot not present, continue boot"
