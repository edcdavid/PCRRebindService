#!/bin/bash

SPOKE_KUBECONFIG_PATH=/var/lib/kubelet/kubeconfig
HUB_SECRET_NAMESPACE=open-cluster-management-agent
HUB_SECRET_NAME=hub-kubeconfig-secret

# retrieves the kubeconfig for this spoke's cluster
getHubKubeconfig() {
    KUBECONFIG_DATA=$(oc --kubeconfig $1 get secret -n $2 $3 -o json | jq .data.kubeconfig | sed 's/"//g' | base64 -d)
    if [ -z "$KUBECONFIG_DATA" ]; then
        return $FALSE
    fi
    TLS_KEY=$(oc --kubeconfig $1 get secret -n $2 $3 -o json | jq '.data."tls.key"' | sed 's/"//g')
    TLS_CRT=$(oc --kubeconfig $1 get secret -n $2 $3 -o json | jq '.data."tls.crt"' | sed 's/"//g')
    echo "$KUBECONFIG_DATA" | sed -e "s/client-certificate: tls.crt/client-certificate-data: $TLS_CRT/g" | sed -e "s/client-key: tls.key/client-key-data: $TLS_KEY/g" >/tmp/kubeconfig-hub
    return $TRUE
}

# Retreives TALM's state in the hub cluster's managedCluster object. Takes one argument:
# done -> return $TRUE if the ztp-done label is set, $FALSE otherwise
# running -> return $TRUE if the ztp-running label is set, $FALSE otherwise
isZtpState() {
    RESULT=$FALSE
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
        return $FALSE
    fi
    logDebug "TALM $1 state is $RESULT"
    return $TRUE
}

isTALMUpdating() {
    if ! getHubKubeconfig $SPOKE_KUBECONFIG_PATH $HUB_SECRET_NAMESPACE $HUB_SECRET_NAME; then
        logInfo "TALM not available or hub kubeconfig is no ready yet at $SPOKE_KUBECONFIG_PATH path, cannot get spoke secret $HUB_SECRET_NAME in $HUB_SECRET_NAMESPACE namespace"
        return $FALSE
    fi
    isZtpState "running"
    return $?
}

# Add a new function to the array of update detection methods
serverUpdateDetectionMethods+=("isTALMUpdating")
