#!/bin/bash
DEBUG=true
CLEVIS_CONFIG_ROOT='{"t":1,"pins":{"tpm2":[{"hash":"sha256","key":"ecc","pcr_bank":"sha256","pcr_ids":"1,7"}]}}'

RESERVED_SLOT=31
ROOT_SLOT=1
CLEVIS_CONFIG_RESERVED_SLOT="$RESERVED_SLOT: tpm2 '{\"hash\":\"sha256\",\"key\":\"ecc\"}'"
CLEVIS_CONFIG_ROOT_SLOT="$ROOT_SLOT: sss '$CLEVIS_CONFIG_ROOT'"

# return true id the temporary reserved slot is configured with a key (to disable PCR protection), returns false otherwise
isReservedSlotPresent() {
    RESULT=$(clevis luks list -d /dev/disk/by-partlabel/root -s $RESERVED_SLOT)
    if [ -n "$RESULT" ] && [ "$RESULT" == "$CLEVIS_CONFIG_RESERVED_SLOT" ]; then
        logDebug "reserved slot $RESERVED_SLOT is present"
        return 0
    fi
    logDebug "reserved slot $RESERVED_SLOT is not present"
    return 1
}

# remove the temporary key in the reserved slot to enable PCR protection
removeReservedSlot() {
    clevis luks unbind -s $RESERVED_SLOT -d /dev/disk/by-partlabel/root -f
}

# rebind the root disk with PCR 1 and 7 protection
rebindWithPcr() {
    clevis-luks-edit -d /dev/disk/by-partlabel/root -s $ROOT_SLOT -c "$CLEVIS_CONFIG_ROOT"
}

# return true if the root disk is bound with PCR, false otherwise
isRootBoundToPcr() {
    RESULT=$(clevis luks list -d /dev/disk/by-partlabel/root -s $ROOT_SLOT)
    if [ "$RESULT" == "$CLEVIS_CONFIG_ROOT_SLOT" ]; then
        logDebug "root disk is encrypted and bound with TPMv2 PCR"
        return 0
    fi
    logDebug "root disk is not bound with TPMv2 PCR"
    return 1
}

# log function. Takes 2 arguments:
# log level: debug or info
# string to print
log() {
    case $1 in
    "debug")
        echo "DEBUG - $2"
        ;;
    "info")
        echo "INFO - $2"
        ;;
    *)
        # Code to execute when no patterns match
        ;;
    esac
}

# logs a string with a debug level
logDebug() {
    if ! [ -v DEBUG ] || ([ -v DEBUG ] && [ "$DEBUG" == "true" ]); then
        log "debug" "$1"
    fi
}

# logs a string with a info level
logInfo() {
    log "info" "$1"
}

main() {
    logInfo "booting checking if rebinding disk needed"
    clevis luks list -d /dev/disk/by-partlabel/root -s $RESERVED_SLOT
    if isReservedSlotPresent; then
        logInfo "reserved slot $RESERVED_SLOT detected, removing and rebinding root disk"
        removeReservedSlot
        rebindWithPcr
        exit 0
    fi

    if ! isRootBoundToPcr; then
        logInfo "PCR configuration missing in clevis, rebinding with PCR"
        rebindWithPcr
        exit 0
    fi

    logInfo "PCR configuration already present and reserved slot not present, continue boot"
}

if [[ "${BASH_SOURCE[0]}" = "${0}" ]]; then
    main "${@}"
    exit $?
fi
