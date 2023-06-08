#!/bin/bash

if [ -z $1 ]; then
    echo "Usage: build-mos.sh <kernel-source root>"
    exit 1
fi

if ! [ -f $1/series.conf ]; then
    echo "$1 is not a kernel-source root directory"
    exit 1
else
    KSRCDIR=$(readlink -f $1)
fi

# Set base reference to mOS source root
RUNDIR=$(dirname $(readlink -f ${BASH_SOURCE[0]}))
MOSDIR=${RUNDIR%/mOS/_build}

source ${RUNDIR}/mOS.conf

# Check the kernel-source
cd ${KSRCDIR}
if ! [ "$(git rev-parse --short HEAD)" = "${KS_HEAD}" ]; then
    echo "Checking out kernel-source HEAD: ${KS_HEAD}"
    if ! git reset --hard; then
        echo "error: resetting repository for checking out ${KS_HEAD}"
        exit 1
    fi
    if ! git checkout ${KS_HEAD}; then
        echo "error: checking out ${KS_HEAD}"
        exit 1
    fi
fi

if ! [ -f linux-${KVER}.tar.xz ] || ! [ -f linux-${KVER}.tar.sign ]; then
    KVER_X="v`echo ${KVER} | cut -d"." -f1`.x"
	echo "Downloading linux-${KVER}.tar.xz..."
    if ! wget https://cdn.kernel.org/pub/linux/kernel/${KVER_X}/linux-${KVER}.tar.xz 2>/dev/null; then
        echo "error: downloading (.xz) source for kernel ${KVER}"
        exit 1
    fi
	echo "Downloading linux-${KVER}.tar.sign..."
    if ! wget https://cdn.kernel.org/pub/linux/kernel/${KVER_X}/linux-${KVER}.tar.sign 2>/dev/null; then
        echo "error: downloading signature for kernel ${KVER}"
        exit 1
    fi
fi

# Check the mOS source
cd $MOSDIR
#if ! [ "$(git rev-parse --short HEAD)" = "${MOS_HEAD}" ]; then
#    echo "Current mOS HEAD is incorrect, it must be ${MOS_HEAD}"
#    exit 1
#fi

# Create a new patch
git -p diff $KERNEL_HEAD -- ':!*mOS/_build*' > $KSRCDIR/patches.kabi/mOS.patch

# Copy the mOS kernel config as a new configuration flavor
cat config.mos > $KSRCDIR/config/x86_64/mOS

cd $KSRCDIR

# Update the build configuration
git checkout config.conf
printf "+x86_64\tx86_64/mOS\n" > config.conf

# Add the mOS patch to the list of kernel patches
if ! $(grep -q "/mOS.patch" series.conf); then
    printf "\tpatches.kabi/mOS.patch\n" >> series.conf
fi

# Update the description file
if ! $(grep -q "=== kernel-mOS ===" rpm/package-descriptions); then
    cat ${RUNDIR}/description >> rpm/package-descriptions
fi

# Update the specfile templates
git checkout rpm/kernel-binary.spec.in
sed -i "/^# The following is copied to the -base subpackage/e cat ${RUNDIR}/spec-requires" rpm/kernel-binary.spec.in
sed -i "/^%changelog/e cat ${RUNDIR}/spec-package" rpm/kernel-binary.spec.in

git checkout rpm/kernel-syms.spec.in
sed -i "/^Release:.*%kernel_source_release/d" rpm/kernel-syms.spec.in

# Generate the new kernel source tarball
./scripts/tar-up.sh -a x86_64 -f mOS -rs "$RELEASE+mOS_$MOS_HEAD"

# Prepare the local RPM build tree 
cp -a kernel-source/* $HOME/rpmbuild/SOURCES/
cd $HOME/rpmbuild
mv SOURCES/*.spec SPECS/
rpmbuild -bb --define "opensuse_bs 1" SPECS/kernel-syms.spec 
rpmbuild -bb SPECS/kernel-source.spec 
rpmbuild -bb SPECS/kernel-mOS.spec
