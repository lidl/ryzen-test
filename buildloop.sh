#!/bin/sh

error() {
	echo $(date)" ${1} failed"
	exit 1
}

JOBS="$1"
NAME="$2"

CDIR="$(pwd)"
WDIR="${CDIR}/buildloop.d/${NAME}/"

PASS=0
while :
do
	cd "${CDIR}" || error "leave workdir"
	echo $(date)" start ${PASS}"
	[ -e "${WDIR}" ] && rm -rf "${WDIR}"
	mkdir -p "${WDIR}" || error "create workdir"
	cd "${WDIR}" || error "change to workdir"
	${CDIR}/gcc-7.1.0/configure --disable-multilib > configure.log 2>&1 || \
		error "configure"
	gmake -j "$JOBS" > build.log 2>&1 || error "build"
	PASS=$((PASS + 1))
done
