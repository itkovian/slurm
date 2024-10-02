#!/bin/bash

set -e  # exit whenever command in pipeline fails
set -x  # print commands as they are executed

VERSION=`grep "Version:.*[0-9]" slurm.spec | tr -s " " |  awk '{print $2;}'`
RELEASE=`grep "%define rel.*[-1-9]" slurm.spec | tr -s " " | awk '{print $3}'`

if [ "${RELEASE}" != "1" ]; then
    SUFFIX=${VERSION}-${RELEASE}
else
    SUFFIX=${VERSION}
fi

GITTAG=$(git log --format=%ct.%h -1)

SCRIPT=$(readlink -f "${BASH_SOURCE[0]}")
ORIGIN=$(dirname "$SCRIPT")

# which version to download from github
SLURM_VERSION=${VERSION:-24.05.3}
UPSTREAM_REL=${UPSTREAM_REL:-1}

# which release should be used for our RPMs
OUR_RELEASE=${OUR_RELEASE:-1}

# NVML
# allow _empty_ version, which is used in pipeline

if grep "release 8.8" /etc/redhat-release; then
   NVIDIA_DRIVER=${NVIDIA_DRIVER-550.90.07}
   NVDRV_NVML_PKG="nvidia-driver-NVML${NVIDIA_DRIVER:+-$NVIDIA_DRIVER}"
   CUDA_VERSION=${CUDA_VERSION:-12.6}
   CUDA_NVML_PKG="cuda-nvml-devel-${CUDA_VERSION//./-}"
elif grep "release 9.4" /etc/redhat-release; then
    NVDRV_NVML_PKG="libnvidia-ml"
    CUDA_VERSION=${CUDA_VERSION:-12.6}
    CUDA_NVML_PKG="cuda-nvml-devel-${CUDA_VERSION//./-}"
fi

# Prepare directory structure
rm -Rf $ORIGIN/rpmbuild/ $ORIGIN/dist/
mkdir -p $ORIGIN/rpmbuild/{BUILD,RPMS,SRPMS,SOURCES} $ORIGIN/dist
echo "Building source tarball"

# archive git repo
echo "archive suffix: ${SUFFIX}"
git archive --format=tar.gz -o "rpmbuild/SOURCES/slurm-${SUFFIX}.tar.gz" --prefix="slurm-${SUFFIX}/" HEAD

cp slurm.spec "SPECS"

# Patch sources
#for src_patch in $ORIGIN/src-patches/*.patch; do
    #echo "Patching $src_patch"
    #git am $src_patch
#done

# Patch spec file
#for spec_patch in $ORIGIN/spec-patches/*.patch; do
    #echo "Patching $spec_patch"
    #patch -p1 -b -i $spec_patch
#done

# Install dependencies
# see https://slurm.schedmd.com/quickstart_admin.html#build_install

echo "Installing specfile requires"
# this goes first because it might install undesired stuff related to `--with` options
sudo dnf -y builddep slurm.spec

echo "Installing dependencies"
# - features: basic
sudo dnf -y install lua-devel mariadb-devel lz4-devel
# - features: authentication (MUNGE: yes, JWT: yes, PAM: yes)
sudo dnf -y install munge-devel libjwt-devel pam-devel
# - features: slurmrestd
sudo dnf -y install http-parser-devel json-c-devel libyaml-devel
# - features: Nvidia NVML
sudo dnf -y autoremove cuda-nvml-* nvidia-driver-NVML-* nvidia-driver* libnvidia-ml*
sudo dnf -y install "$CUDA_NVML_PKG" "$NVDRV_NVML_PKG"
# - plugins: MPI
sudo dnf -y install pmix ucx-devel
# - plugins: cgroup/v2
# see https://slurm.schedmd.com/cgroup_v2.html
sudo dnf -y install kernel-headers dbus-devel
# - plugins: task/cgroup, task/affinity
sudo dnf -y install hwloc-devel numactl-devel
# - plugins: acct_gather_profile/hdf5
sudo dnf -y install hdf5-devel

# Build defines
RPM_DEFINES=( --define "gittag ${GITTAG}" --define "_topdir $ORIGIN/rpmbuild" )

# Build options
SLURM_BUILDOPTS=( --with slurmrestd --without debug )
# basic features
SLURM_BUILDOPTS+=( --with lua --with mysql --with x11 )
# plugins
SLURM_BUILDOPTS+=( --with numa --with hwloc --with pmix --with ucx )
# authentication
SLURM_BUILDOPTS+=( --with pam --with jwt )

echo "Running rpmbuild (without nvml)"
rpmbuild -ba "${RPM_DEFINES[@]}" "${SLURM_BUILDOPTS[@]}" --without nvml \
    slurm.spec 2>&1 | tee rpmbuild-without-nvml.out


echo "Doing rpm rebuild (without nvml)"
for rpm in $ORIGIN/rpmbuild/RPMS/x86_64/slurm-*$SUFFIX*.rpm ; do
    rpmrebuild --release=${OUR_RELEASE}.${GITTAG}.$(rpm -E '%dist').nogpu.ug -d $ORIGIN/dist -p $rpm
done


echo "Running rpmbuild (with nvml)"
RPM_DEFINES+=( --define "_cuda_version $CUDA_VERSION" )
rpmbuild -ba "${RPM_DEFINES[@]}" "${SLURM_BUILDOPTS[@]}" --with nvml \
    slurm.spec 2>&1 | tee rpmbuild-with-nvml.out

echo "Doing rpm rebuild (with nvml)"
for rpm in $ORIGIN/rpmbuild/RPMS/x86_64/slurm-*$SUFFIX*.rpm ; do
    rpmrebuild --release=${OUR_RELEASE}.${GITTAG}.$(rpm -E '%dist').ug -d $ORIGIN/dist -p $rpm
done

# strip out torque binaries/wrapper from slurm-torque
rpmrebuild -d $ORIGIN/dist --change-spec-files="sed '/\(pbsnodes\|mpiexec\|bin\/q.\+\)/d'" -p $ORIGIN/dist/x86_64/slurm-torque-*-$GITTAG.$OUR_RELEASE.nogpu.$(rpm -E '%dist').*.rpm
rpmrebuild -d $ORIGIN/dist --change-spec-files="sed '/\(pbsnodes\|mpiexec\|bin\/q.\+\)/d'" -p $ORIGIN/dist/x86_64/slurm-torque-*-$GITTAG.$OUR_RELEASE.$(rpm -E '%dist').*.rpm

# get the RPMs out of the subdirectories
find $ORIGIN/dist/ -type f -name '*.rpm' -print0 | xargs -0 -I{} mv {} $ORIGIN/dist/
