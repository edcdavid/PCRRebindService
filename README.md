# PCRRebindService
A set of systemd services to rebind luks disks protected with tpmv2 PCR registers. Also contains previous proof of concept projects. This page only describes the coreos-generic folder.

# Overview
The PCRRebindService goal is to support luks disks encrypted with TPMv2 and PCR registers to protect against the "evil main" attack (https://en.wikipedia.org/wiki/Evil_maid_attack) in the context of cloud computing and with no user interactions. This service supports the case where the host is updated and the PCR registers values that were previously used are changed. The PCRRebindService disables PCR register protection(https://wiki.archlinux.org/title/Trusted_Platform_Module) in the limited scenario of firmware updates. Then after reboot, it refreshes the encrypted disk bindings with the new PCR register values and re-enables the PCR protection. 

# Firmware updates detection methods
The pcr-disable-shutdown.service systemd service monitors linux based systems for firmware updates via plugin methods listed in the hwupgrade-detection-methods directory:
- `talm.sh`: detects a ZTP TALM lifecycle update (https://github.com/openshift-kni/cluster-group-upgrades-operator) in spoke clusters 
- `ostree.sh`: detects an ostree update, which can include a microcode update affecting PCR 
- `fwup.sh`: detects an firmware upgrade trigged via the fwupmgr tool(https://github.com/fwupd/fwupd)
- `file.sh`: checks for the presence of the "/etc/host-hw-Updating.flag" file to assume a firmware upgrade. This could be used by other processes to disable PCR protection for the next reboot

# Services
The PCRRebindService is split in two short lived services to lower CPU utilization:
- `pcr-disable-shutdown.service`: this service is only triggered on reboot or shutdown. It checks if any firmware update is imminent based on the supported detection methods. If a firmware update is in progress, the service disables all PCR protection for disk encrypted and bound to PCR registers. This is achieved by adding a reserved slot(slot 31) to disks containing a slot with PCR configuration. This additional reserved slot is only configured with tmpv2 but no PCR registers, essentially disabling PCR protection
- `pcr-rebind-boot.service`: this service is triggered on boot. It checks for the presence of the reserved slot (31). If it is present, the service refreshes the luks binding to support any changes in PCR registers. Then The reserved slot is deleted, thus re-enabling the PCR protection for all disk that support it.

# Scripts
The following support scripts do the following: 
- `disablePcrOnRebootOrShutdown.sh`: bash script called by the pcr-disable-shutdown.service on shutdown
- `rebindDiskOnBoot.sh`: bash script called by the pcr-rebind-boot.service on boot
- `luks-helpers.sh`: bash script containing helper function used by disablePcrOnRebootOrShutdown.sh and rebindDiskOnBoot.sh
- `build.sh`: script rendering the PCRRebindService as a Machine Config manifest usable with the ZTP platform
- `pcr-protection.yaml`: rendered Machine Config manifest usable with ZTP
- `test.sh`: bash script running unit tests

#Notes: 
- only TPMv1 PCR 1 & 7 are tested at this time
- does not protect against all possible attack scenarios 
- the temporary passphrase should be changed