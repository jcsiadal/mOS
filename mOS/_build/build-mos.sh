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
    echo "Current kernel-source HEAD is incorrect, it must be ${KS_HEAD}"
    exit 1
elif ! [ -f linux-${KVER}.tar.xz ] || ! [ -f linux-${KVER}.tar.sign ]; then
    echo "Missing (.xz) source or signature for kernel ${KVER}"
    exit 1
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
if ! [ -f config.backup ]; then
    cp config{.conf,.backup}
fi
if [ -f config.backup ]; then
    printf "+x86_64\tx86_64/mOS\n" > config.conf
fi

# Add the mOS patch to the list of kernel patches
if ! $(grep -q "/mOS.patch" series.conf); then
    printf "\tpatches.kabi/mOS.patch\n" >> series.conf
fi

# Update the description file
if ! $(grep -q "=== kernel-mOS ===" rpm/package-descriptions); then
    cat ${RUNDIR}/description >> rpm/package-descriptions
fi

# Update the specfile templates
if ! [ -f rpm/kernel-binary.spec.backup ]; then
    cp rpm/kernel-binary.spec.{in,backup}
fi
if [ -f rpm/kernel-binary.spec.backup ]; then
    rm -f rpm/kernel-binary.spec.in
    cp rpm/kernel-binary.spec.{backup,in}
    sed -ni "/^# The following is copied to the -base subpackage/e cat ${RUNDIR}/spec-requires" rpm/kernel-binary.spec.in
    sed -ni "/^%changelog/e cat ${RUNDIR}/spec-package" rpm/kernel-binary.spec.in
fi
if ! [ -f rpm/kernel-syms.spec.backup ]; then
    cp rpm/kernel-syms.spec.{in,backup}
fi
if [ -f rpm/kernel-syms.spec.backup ]; then
    rm -f rpm/kernel-syms.spec.in
    cp rpm/kernel-syms.spec.{backup,in}
    sed -ni "/^Release:.*%kernel_source_release/d" rpm/kernel-syms.spec.in
fi

# Generate the new kernel source tarball
./scripts/tar-up.sh -a x86_64 -f mOS -rs "$RELEASE+mOS_$MOS_HEAD"

# Prepare the local RPM build tree 
cp -a kernel-source/* $HOME/rpmbuild/SOURCES/
cd $HOME/rpmbuild
mv SOURCES/*.spec SPECS/
rpmbuild -bb --define "opensuse_bs 1" SPECS/kernel-syms.spec 
rpmbuild -bb SPECS/kernel-source.spec 
rpmbuild -bb SPECS/kernel-mOS.spec
