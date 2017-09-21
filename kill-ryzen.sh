#!/bin/sh

# globals
export LANG=C
UNAME=$(uname)
CLEAN_ON_EXIT=false # must be 'true' or 'false'
GCC_FILE=gcc-7.1.0.tar.bz2
export GCCDIR="$(pwd)"
BSCRIPT=buildloop.sh

# figure out how many CPUs to use, if not specified
set_NPROC() {
	case $UNAME in
	FreeBSD)
		NPROC=$(sysctl -n kern.smp.cpus)
		CPUINFO=$(sysctl -n hw.model)
		;;
	Linux)
		which nproc && :
		if [ $? -eq 0 ]; then
			NPROC=$(nproc)
		else
			NPROC=$(awk '/cpu cores/ {print $4}' < /proc/cpuinfo)
		fi
		CPUINFO=$(egrep "^model name" /proc/cpuinfo)
		;;
	esac
}

# mount a ram based filesystem for testing
mount_workspace() {
	local mountpoint workdir
	case $UNAME in
	FreeBSD)
		mountpoint=$(pwd)/workdir
		workdir=workdir
		mkdir -p $workdir || exit 1
		if ( mount | grep -q $workdir ); then
			sudo umount $workdir
		fi
		sudo mount -t tmpfs tmpfs $mountpoint || exit 1
		;;
	Linux)
		echo "Create compressed ramdisk"
		mountpoint=/mnt/ramdisk
		workdir=$mountpoint/workdir
		set -e
		sudo mkdir -p $mountpoint
		sudo modprobe zram num_devices=1
		echo 64G | sudo tee /sys/block/zram0/disksize
		sudo mkfs.ext4 -q -m 0 -b 4096 -O sparse_super -L zram /dev/zram0
		sudo mount -o relatime,nosuid,discard /dev/zram0 $mountpoint

		sudo mkdir -p $workdir
		sudo chmod 777 $workdir

		set -x
		;;
	esac
	# $mountpoint and $workdir should be set at this point
	cp ${BSCRIPT} $workdir/${BSCRIPT}
	cd $workdir
	mkdir tmpdir || exit 1

	# set some more environmental variables
	export TMPDIR="$(pwd)/tmpdir"
	export MOUNTPOINT=$mountpoint
}

cleanup() {
	case $UNAME in
	Linux)
		sudo rm -rf $MOUNTPOINT/*
		;;
	esac
	sudo umount $MOUNTPOINT
}

install_packages() {
	echo "Installing required packages..."
	if which apt-get >/dev/null 2>&1; then
		sudo apt-get install build-essential
	elif which dnf >/dev/null 2>&1; then
		sudo dnf install -y @development-tools
	elif which pkg >/dev/null 2>&1; then
		# only attempt to install if not present
		for pkg in mpfr mpc gmp
		do
			pkg info -q $pkg || sudo pkg install $pkg
		done
	else
		exit 1
	fi
}

download_gcc() {
	local url=https://ftp.gnu.org/gnu/gcc/gcc-7.1.0/${GCC_FILE}
	if [ -f ${GCC_FILE} ]; then
		return
	fi
	echo "Downloading GCC source file"
	if which wget >/dev/null 2>&1; then
		wget ${url} || exit 1
	elif which fetch >/dev/null 2>&1; then
		fetch ${url} || exit 1
	elif which curl >/dev/null 2>&1; then
		curl -O ${url} || exit 1
	else
		exit 1
	fi
}

show_machine_info() {
	echo "sudo dmidecode -t memory | grep -i -E \"(rank|speed|part)\" | grep -v -i unknown"
	sudo dmidecode -t memory | grep -i -E "(rank|speed|part)" | grep -v -i unknown
	echo "uname -a"
	uname -a
	echo $CPUINFO
}

os_kludges() {
	case $UNAME in
	FreeBSD)
		;;
	Linux)
		# start journal process in different working directory
		pushd /
		journalctl -kf | sed 's/^/[KERN] /' &
		popd
		;;
	esac
}

main() {
	NPROC=$1
	JOBS=$2

	[ -n "$NPROC" ] || set_NPROC
	[ -n "$JOBS" ] || JOBS=1

	$CLEAN_ON_EXIT && trap "cleanup" SIGHUP SIGINT SIGTERM EXIT

	download_gcc
	install_packages
	mount_workspace

	echo -n "Extracting GCC sources..."
	tar xf "$GCCDIR/gcc-7.1.0.tar.bz2" || exit 1
	echo " done."

	[ -d 'buildloop.d' ] && rm -r 'buildloop.d'
	mkdir -p buildloop.d || exit 1

	show_machine_info
	os_kludges

	echo "Using ${NPROC} parallel processes (JOBS: $JOBS)"

	START=$(date +%s)
	I=0
	while [ $I -lt $NPROC ]; do
		I=$((I + 1))
		(./${BSCRIPT} "$JOBS" "loop-$I" || echo "TIME TO FAIL: $(($(date +%s)-${START})) s") | sed "s/^/\[loop-${I}\] /" &
		sleep 1
	done
	wait
}

main "$@"
