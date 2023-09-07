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

main() {
    logInfo "Shutting down or rebooting"
    if ! getHubKubeconfig $SPOKE_KUBECONFIG_PATH $HUB_SECRET_NAMESPACE $HUB_SECRET_NAME; then
        logInfo "hub kubeconfig is no ready yet at $SPOKE_KUBECONFIG_PATH path, cannot get spoke secret $HUB_SECRET_NAME in $HUB_SECRET_NAMESPACE namespace"
        exit 1
    fi
    if isZtpState "running"; then
        logInfo "TALM state is running, disabling PCR protection"
        addReservedSlot
        clevis luks list -d /dev/disk/by-partlabel/root
        exit 0
    fi

    logInfo "TALM state is not running (assuming done), continue with PCR protection"
}

if [[ "${BASH_SOURCE[0]}" = "${0}" ]]; then
    main "${@}"
    exit $?
fi
