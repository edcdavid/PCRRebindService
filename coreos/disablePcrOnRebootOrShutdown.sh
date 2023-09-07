#!/bin/bash
DEBUG=true
RESERVED_SLOT=31

# create a temporary key in the reserved slot to disable PCR protection
addReservedSlot() {
    ANYPASS="1234567890"
    echo -e "$ANYPASS\n" | clevis luks bind -s $RESERVED_SLOT -d /dev/disk/by-partlabel/root tpm2 '{}'
}

#set -x

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

isUpgradeOrDowngradeOnNextReboot() {
    RESULT=$(ostree admin status | grep -E "staged|pending")
    if [ "$RESULT" != "" ]; then
        return 0
    else
        return 1
    fi
}

isFWUpdateOnNextReboot() {
    EFI=$(efibootmgr)
    NEXT_BOOT=$(echo $EFI | grep "BootNext:" | awk {'print $2'})
    if [ "$NEXT_BOOT" == "" ]; then
        return 1
    fi
    FWUPD=$(echo $EFI | grep "Boot$NEXT_BOOT" | grep "fwupd")
    # if the next boot line contains the text "fwupd"
    if [ $? ]; then
        return 0
    fi
    return 1
}

logInfo "Shutting down or rebooting"

if isFWUpdateOnNextReboot; then
    logInfo "FW update detected, disabling PCR protection"
    addReservedSlot
    clevis luks list -d /dev/disk/by-partlabel/root
    exit 0
fi

if isUpgradeOrDowngradeOnNextReboot; then
    logInfo "CoreOS update detected, disabling PCR protection"
    addReservedSlot
    clevis luks list -d /dev/disk/by-partlabel/root
    exit 0
fi

logInfo "No FW or OS update detected, continue"
