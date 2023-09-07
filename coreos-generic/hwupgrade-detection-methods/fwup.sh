#!/bin/bash

isFwupUpdating() {
    EFI=$(efibootmgr)
    NEXT_BOOT=$(echo $EFI | grep "BootNext:" | awk {'print $2'})
    if [ "$NEXT_BOOT" == "" ]; then
        return 1
    fi
    FWUPD=$(echo $EFI | grep "Boot$NEXT_BOOT" | grep "fwupd")
    # if the next boot line contains the text "fwupd"
    if [ $? ]; then
        return $TRUE
    fi
    return $FALSE
}

# Add a new function to the array of update detection methods
serverUpdateDetectionMethods+=("isFwupUpdating")
