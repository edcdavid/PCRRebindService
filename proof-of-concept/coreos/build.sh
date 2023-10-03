#!/bin/bash

GOPATH=${GOPATH:-${HOME}/go}
GOBIN=${GOBIN:-${GOPATH}/bin}
MCMAKER=${MCMAKER:-${GOBIN}/mcmaker}
MCPROLE=${MCPROLE:-master}

${MCMAKER} -stdout -name 99-disk-encryption -mcp ${MCPROLE} \
	file -source disablePcrOnRebootOrShutdown.sh -path /usr/local/bin/disablePcrOnRebootOrShutdown.sh -mode 0755 \
	file -source rebindDiskOnBoot.sh -path /usr/local/bin/rebindDiskOnBoot.sh -mode 0755 \
	unit -source pcr-rebind-boot.service \
	unit -source pcr-disable-shutdown.service