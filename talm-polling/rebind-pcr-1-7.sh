#!/bin/bash
DEBUG=true
RESERVED_SLOT=31
ROOT_SLOT=1

SPOKE_KUBECONFIG_PATH=/var/lib/kubelet/kubeconfig
HUB_SECRET_NAMESPACE=open-cluster-management-agent
HUB_SECRET_NAME=hub-kubeconfig-secret

# retrieves the kubeconfig for this spoke's cluster
getHubKubeconfig() {
    KUBECONFIG_DATA=$(oc --kubeconfig $1 get secret -n $2 $3 -o json | jq .data.kubeconfig | sed 's/"//g' | base64 -d)
    if [ -z "$KUBECONFIG_DATA" ]; then
        return 1
    fi
    TLS_KEY=$(oc --kubeconfig $1 get secret -n $2 $3 -o json | jq '.data."tls.key"' | sed 's/"//g')
    TLS_CRT=$(oc --kubeconfig $1 get secret -n $2 $3 -o json | jq '.data."tls.crt"' | sed 's/"//g')
    echo "$KUBECONFIG_DATA" | sed -e "s/client-certificate: tls.crt/client-certificate-data: $TLS_CRT/g" | sed -e "s/client-key: tls.key/client-key-data: $TLS_KEY/g" >/tmp/kubeconfig-hub
    return 0
}

# Retreives TALM's state in the hub cluster's managedCluster object. Takes one argument:
# done -> return true if the ztp-done label is set, false otherwise
# running -> return true if the ztp-running label is set, false otherwise
isZtpState() {
    RESULT=false
    case $1 in
    "running")
        RESULT=$(KUBECONFIG=/tmp/kubeconfig-hub oc get managedcluster sno2 -ojson | jq '.metadata.labels["ztp-running"]!=null')
        ;;
    "done")
        RESULT=$(KUBECONFIG=/tmp/kubeconfig-hub oc get managedcluster sno2 -ojson | jq '.metadata.labels["ztp-done"]!=null')
        ;;
    *)
        # Code to execute when no patterns match
        ;;
    esac
    if [ "$RESULT" == "false" ]; then
        logDebug "TALM $1 state is $RESULT"
        return 1
    fi
    logDebug "TALM $1 state is $RESULT"
    return 0
}

# return true id the temporary reserved slot is configured with a key (to disable PCR protection), returns false otherwise
isReservedSlotPresent() {
    RESULT=$(clevis luks list -d /dev/disk/by-partlabel/root -s $RESERVED_SLOT)
    if [ "$RESULT" == "31: tpm2 '{\"hash\":\"sha256\",\"key\":\"ecc\"}'" ]; then
        logDebug "reserved slot $RESERVED_SLOT is present"
        return 0
    fi
    logDebug "reserved slot $RESERVED_SLOT is not present"
    return 1
}

# create a temporary key in the reserved slot to disable PCR protection
addReservedSlot() {
    ANYPASS="1234567890"
    echo -e "$ANYPASS\n" | clevis luks bind -s $RESERVED_SLOT -d /dev/disk/by-partlabel/root tpm2 '{}'
}

# remove the temporary key in the reserved slot to enable PCR protection
removeReservedSlot() {
    clevis luks unbind -s $RESERVED_SLOT -d /dev/disk/by-partlabel/root -f
}

# rebind the root disk with PCR 1 and 7 protection
rebindWithPcr1And7() {
    clevis-luks-edit -d /dev/disk/by-partlabel/root -s $ROOT_SLOT -c '{"t":1,"pins":{"tpm2":[{"hash":"sha256","key":"ecc","pcr_bank":"sha256","pcr_ids":"1,7"}]}}'
}

# return true if the root disk is bound with PCR 1 and 7 protection, false otherwise
isRootBoundToPcr1And7() {
    RESULT=$(clevis luks list -d /dev/disk/by-partlabel/root -s $ROOT_SLOT)
    if [ "$RESULT" == "1: sss '{\"t\":1,\"pins\":{\"tpm2\":[{\"hash\":\"sha256\",\"key\":\"ecc\",\"pcr_bank\":\"sha256\",\"pcr_ids\":\"1,7\"}]}}'" ]; then
        logDebug "root disk is encrypted and bound with TPMv2 PCR 1 and 7"
        return 0
    fi
    logDebug "root disk is not bound with TPMv2 PCR 1 and 7 properly"
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

# logs a state transition between 2 states only when state changes
logState() {
    if [ "$1" != "$2" ]; then
        logInfo "entering $2 STATE"
    fi
}

CURRENT_STATE="INIT"
PREVIOUS_STATE="NIL"

logState $PREVIOUS_STATE $CURRENT_STATE
PREVIOUS_STATE=$CURRENT_STATE

while [ true ]; do

    sleep 5

    case $CURRENT_STATE in
    "INIT")
        logState $PREVIOUS_STATE $CURRENT_STATE
        PREVIOUS_STATE=$CURRENT_STATE
        if ! getHubKubeconfig $SPOKE_KUBECONFIG_PATH $HUB_SECRET_NAMESPACE $HUB_SECRET_NAME; then
            logInfo "hub kubeconfig is no ready yet at $SPOKE_KUBECONFIG_PATH path, cannot get spoke secret $HUB_SECRET_NAME in $HUB_SECRET_NAMESPACE namespace"
            continue
        fi
        CURRENT_STATE="KUBECONFIG_READY"
        ;;
    "KUBECONFIG_READY")
        logState $PREVIOUS_STATE $CURRENT_STATE
        PREVIOUS_STATE=$CURRENT_STATE
        if isRootBoundToPcr1And7 && ! isReservedSlotPresent; then
            CURRENT_STATE="PCR_PROTECTED"
        else
            CURRENT_STATE="PCR_UNPROTECTED"
        fi
        ;;
    "PCR_PROTECTED")
        logState $PREVIOUS_STATE $CURRENT_STATE
        PREVIOUS_STATE=$CURRENT_STATE
        if isZtpState "running"; then
            addReservedSlot
            CURRENT_STATE="PCR_UNPROTECTED"
        fi
        ;;
    "PCR_UNPROTECTED")
        logState $PREVIOUS_STATE $CURRENT_STATE
        PREVIOUS_STATE=$CURRENT_STATE
        if isZtpState "done" && ! isZtpState "running"; then
            rebindWithPcr1And7
            if isReservedSlotPresent; then
                removeReservedSlot
            fi
            CURRENT_STATE="PCR_PROTECTED"
        fi
        ;;
    *)
        # Code to execute when no patterns match
        ;;
    esac

done
