DEBUG="true"
RESERVED_SLOT=31
CLEVIS_CONFIG_RESERVED_SLOT="$RESERVED_SLOT: tpm2 '{\"hash\":\"sha256\",\"key\":\"ecc\"}'"
TRUE=0
FALSE=1
NEWLINE=$'\n'

#set -x

# log function. Takes 2 arguments:
# log level: debug or info
# string to print
log() {
    case $1 in
    "debug")
        echo "DEBUG - $2" >&2
        ;;
    "info")
        echo "INFO - $2" >&2
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

# return $TRUE id the temporary reserved slot is configured with a key (to disable PCR protection), returns $FALSE otherwise
isReservedSlotPresent() {
    RESULT=$(clevis luks list -d $1 -s $RESERVED_SLOT)
    if [ -n "$RESULT" ] && [ "$RESULT" == "$CLEVIS_CONFIG_RESERVED_SLOT" ]; then
        logDebug "reserved slot $RESERVED_SLOT is present"
        return $TRUE
    fi
    logDebug "reserved slot $RESERVED_SLOT is not present"
    return $FALSE
}

# create a temporary key in the reserved slot to disable PCR protection
addReservedSlot() {
    logInfo "reservedSlotPresent=$1 device=$2 slot=$3 with PCR IDs=$4 and clevis config=$5"
    if [ $1 == $TRUE ]; then
        logInfo "reserve slot already present, no need to add again"
        return
    fi
    logInfo "adding reserved slot on device=$device"
    ANYPASS="1234567890"
    echo -e "$ANYPASS\n" | clevis luks bind -s $RESERVED_SLOT -d $2 tpm2 '{}'
    clevis luks list -d $2
}

# remove the temporary key in the reserved slot to enable PCR protection
removeReservedSlot() {
    logInfo "removing luks reserved slot 31 in disk $1"
    echo "clevis luks unbind -s $RESERVED_SLOT -d $1 -f" | sed 's@/@\/@g' | bash
}

#gets the list of luks devices in the system
getLUKSDevices() {
    results=$(lsblk --fs -l | grep crypto_LUKS | awk '{printf "/dev/" $1 "|"}')
    logDebug "got luks devices across all drives: $results"
    echo $results
}

# create a list of slot configuration for all encrypted devices in the system
parseClevisConfig() {
    luksDevices=$1
    IFS="|"
    for device in $luksDevices; do
        logDebug "device=$device"
        isReservedSlotPresent $device
        isReserved=$?
        pcrSlots=$(getPcrSlotsForDevice $device)
        logDebug "pcrSlots=$pcrSlots"
        parseClevisRegex "$pcrSlots" $isReserved "$device"
    done
}

getPcrSlotsForDevice() {
    device=$1
    logDebug "getPcrSlotsForDevice, device=$device"
    clevis luks list -d $device | grep pcr_ids
}

parseClevisRegex() {
    IFS=$'\n'
    for line in $1; do
        logDebug "line=$line"
        echo "$line" | sed -E 's@([0-9]+)(:\s+.*+\s+'\'')(\{)(.*?"pcr_ids":")(.*)(".*)(\})('\''.*)@'$2'|'$3'|\1|\5|\3\4\5\6\7@'
    done
}

# executes a function pointer passed argument $1 for each slot configured with PCR and
# for every device in the system
processPCRentriesOnly() {
    luksDevices=$(getLUKSDevices)
    parsedClevis=$(parseClevisConfig $luksDevices)
    if [ "$parsedClevis" == "" ]; then
        logInfo "no pcr config detected, nothing to do for $1"
        return
    fi
    logInfo "parsed clevis for all drives: $parsedClevis"
    echo "$parsedClevis" | while IFS= read -r line; do
        logDebug "$line"
        IFS="|" read -ra values <<<"$line"
        reservedSlotPresent=${values[0]}
        device=${values[1]}
        slotNumber=${values[2]}
        pcrIDs=${values[3]}
        clevisConfig=${values[4]}
        logInfo "reservedSlot=$reservedSlotPresent device=$device slot=$slotNumber with PCR IDs=$pcrIDs and clevis config=$clevisConfig"
        if [ -n "$pcrIDs" ]; then
            $1 $reservedSlotPresent $device $slotNumber $pcrIDs $clevisConfig
        fi
    done
}

# initialize the array of upgrade detection methods serverUpdateDetectionMethods
initUpgradeDetectionMethods() {
    for f in $SCRIPT_DIR/hwupgrade-detection-methods/*.sh; do source $f; done
    logInfo "detected system upgrade detection:"
    for element in "${serverUpdateDetectionMethods[@]}"; do echo "$element"; done
}

# execute all hw upgrade detection functions in hwupgrade-detection-methods directory
# returns true if a hw upgrade is detected
# false otherwise
isSystemUpdating() {
    isUpdating=$FALSE
    # Iterate through the updated array and call each function
    for func in "${serverUpdateDetectionMethods[@]}"; do
        if $func; then
            isUpdating=$TRUE
            logInfo "detected update via $func"
        fi
    done
    return $isUpdating
}

#rebinds a given key slot that is configured with PCR for a given device
rebindPCRentriesOnly() {
    logInfo "Rebinding reservedSlotPresent=$1 device=$2 slot=$3 with PCR IDs=$4 and clevis config=$5"
    clevis-luks-edit -d $2 -s $3 -c "$5"
    removeReservedSlot $2
}
