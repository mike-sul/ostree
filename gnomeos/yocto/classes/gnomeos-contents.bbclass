#
# Copyright (C) 2011 Colin Walters <walters@verbum.org>
#
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COREBASE}/LICENSE;md5=3f40d7994397109285ec7b81fdeb3b58 \
                    file://${COREBASE}/meta/COPYING.MIT;md5=3da9cfbcb788c80a0384361b4de20420"

inherit rootfs_${IMAGE_PKGTYPE}

IMAGE_INSTALL = "libuuid1 \
	         libblkid1 \
		 e2fsprogs-blkid \
		 e2fsprogs-fsck \
		 e2fsprogs-e2fsck \
		 e2fsprogs-mke2fs \
		 e2fsprogs-tune2fs \
		 libtiff3 \
		 libjpeg8 \
		 libltdl7 \
                 libstdc++6 \
                 libgnutls26 \
                 libogg0 \
		 eglibc-gconvs \
		 eglibc-binaries \
		 pam-plugin-cracklib \
		 pam-plugin-env \
		 pam-plugin-keyinit \
		 pam-plugin-limits \
		 pam-plugin-localuser \
		 pam-plugin-loginuid \
		 pam-plugin-unix \
		 pam-plugin-rootok \
		 pam-plugin-succeed-if \
		 pam-plugin-permit \
		 pam-plugin-nologin \
		 ncurses-terminfo-base \
		 "

RDEPENDS += "tiff \
	     libogg \
	     libvorbis \
	     speex \
	     libatomics-ops \
	     "

RECIPE_PACKAGES = "task-core-boot \
		   coreutils \
		   ostree \
		   strace \
		   bash \
		   tar \
		   grep \
		   gawk \
		   gzip \
		   less \
		   curl \
		   tzdata \
		   libsndfile1 \
		   icu \
		   procps \
		   libpam \
		   ncurses \
		   libvorbis \
		   speex \
		   python-modules \
		   python-misc \
		   openssh \
		   "

PACKAGE_INSTALL = "${RECIPE_PACKAGES} ${IMAGE_INSTALL}"

RDEPENDS += "${RECIPE_PACKAGES}"
DEPENDS += "makedevs-native virtual/fakeroot-native"

EXCLUDE_FROM_WORLD = "1"

do_rootfs[nostamp] = "1"
do_rootfs[dirs] = "${TOPDIR}"
do_rootfs[lockfiles] += "${IMAGE_ROOTFS}.lock"
do_build[nostamp] = "1"
do_rootfs[umask] = 022

def gnomeos_get_devtable_list(d):
    return bb.which(d.getVar('BBPATH', 1), 'files/device_table-minimal.txt')

# Must call real_do_rootfs() from inside here, rather than as a separate
# task, so that we have a single fakeroot context for the whole process.
fakeroot do_rootfs () {
        set -x
	rm -rf ${IMAGE_ROOTFS}
	rm -rf ${MULTILIB_TEMP_ROOTFS}
	mkdir -p ${IMAGE_ROOTFS}
	mkdir -p ${DEPLOY_DIR_IMAGE}

	rootfs_${IMAGE_PKGTYPE}_do_rootfs

	# We use devtmpfs
	rm -f ${IMAGE_ROOTFS}/etc/init.d/udev-cache
	rm -f ${IMAGE_ROOTFS}/etc/rc*.d/*udev-cache*

	rm -f ${IMAGE_ROOTFS}/etc/rcS.d/S03udev
	rm -f ${IMAGE_ROOTFS}/etc/rcS.d/*networking

	# The default fstab has /, which we don't want, and we do want /sys and /dev/shm
	cat > ${IMAGE_ROOTFS}/etc/fstab << EOF
tmpfs                   /dev/shm                tmpfs   mode=1777,nosuid,nodev 0 0
devpts                  /dev/pts                devpts  gid=5,mode=620  0 0
sysfs                   /sys                    sysfs   defaults        0 0
proc                    /proc                   proc    defaults        0 0
EOF

	# Kill the Debian netbase stuff - we use NetworkManager
	rm -rf ${IMAGE_ROOTFS}/etc/network
	rm -f ${IMAGE_ROOTFS}/etc/init.d/networking

	ln -sf /var/run/resolv.conf ${IMAGE_ROOTFS}/etc/resolv.conf

	# The passwd database is stored in /var.
	rm -f ${IMAGE_ROOTFS}/etc/passwd
	ln -s /var/passwd ${IMAGE_ROOTFS}/etc/passwd
	rm -f ${IMAGE_ROOTFS}/etc/shadow ${IMAGE_ROOTFS}/etc/shadow-
	ln -s /var/shadow ${IMAGE_ROOTFS}/etc/shadow
	rm -f ${IMAGE_ROOTFS}/etc/group
	ln -s /var/group ${IMAGE_ROOTFS}/etc/group

	TOPROOT_BIND_MOUNTS="home root tmp"
	OSTREE_BIND_MOUNTS="var"
	OSDIRS="dev proc mnt media run sys sysroot"
	READONLY_BIND_MOUNTS="bin etc lib sbin usr"
	
	rm -rf ${WORKDIR}/gnomeos-contents
	mkdir ${WORKDIR}/gnomeos-contents
        cd ${WORKDIR}/gnomeos-contents
	for d in $TOPROOT_BIND_MOUNTS $OSTREE_BIND_MOUNTS $OSDIRS; do
	    mkdir $d
	done
	chmod a=rwxt tmp

	for d in $READONLY_BIND_MOUNTS; do
            mv ${IMAGE_ROOTFS}/$d .
	done
	rm -rf ${IMAGE_ROOTFS}
	mv ${WORKDIR}/gnomeos-contents ${IMAGE_ROOTFS}

	DEST=${IMAGE_NAME}.rootfs.tar.gz
	(cd ${IMAGE_ROOTFS} && tar -zcv -f ${WORKDIR}/$DEST .)
	echo "Created $DEST"
	mv ${WORKDIR}/$DEST ${DEPLOY_DIR_IMAGE}/
	cd ${DEPLOY_DIR_IMAGE}/
	rm -f ${DEPLOY_DIR_IMAGE}/${IMAGE_LINK_NAME}.tar.gz
	ln -s ${IMAGE_NAME}.rootfs.tar.gz ${DEPLOY_DIR_IMAGE}/${IMAGE_LINK_NAME}.tar.gz
	echo "Created ${DEPLOY_DIR_IMAGE}/${IMAGE_LINK_NAME}.tar.gz"

	set -x

	if echo ${IMAGE_LINK_NAME} | grep -q -e -runtime; then
	   ostree_target=runtime
	else
	   ostree_target=devel
	fi
	if test x${MACHINE_ARCH} = xqemux86; then
	   ostree_machine=i686
	else
	  if test x${MACHINE_ARCH} = xqemux86_64; then
	    ostree_machine=x86_64
	  else
	    echo "error: unknown machine from ${MACHINE_ARCH}"; exit 1
	  fi
	fi
	buildroot=gnomeos-3.4-${ostree_machine}-${ostree_target}
	base=bases/yocto/${buildroot}
	repo=${DEPLOY_DIR_IMAGE}/repo
	if ! test -d ${repo}; then
	   mkdir ${repo}
	   ostree --repo=${repo} init --archive
        fi
	ostree --repo=${repo} commit -s "${IMAGE_LINK_NAME}" --skip-if-unchanged "Build" -b ${base} --tree=tar=${DEPLOY_DIR_IMAGE}/${IMAGE_LINK_NAME}.tar.gz
	ostree --repo=${repo} diff "${base}" || true
	ostree --repo=${repo} compose -s "Initial compose" -b ${buildroot} ${base}:/
}

log_check() {
	true
}

do_fetch[noexec] = "1"
do_unpack[noexec] = "1"
do_patch[noexec] = "1"
do_configure[noexec] = "1"
do_compile[noexec] = "1"
do_install[noexec] = "1"
do_populate_sysroot[noexec] = "1"
do_package[noexec] = "1"
do_package_write_ipk[noexec] = "1"
do_package_write_deb[noexec] = "1"
do_package_write_rpm[noexec] = "1"

addtask rootfs before do_build
