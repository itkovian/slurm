#!/bin/bash

set -e

VERSION=`grep "Version:.*[0-9]" slurm.spec | tr -s " " |  awk '{print $2;}'`
RELEASE=`grep "%global rel.*[-1-9]" slurm.spec | tr -s " " | awk '{print $3}'`

if [ ${RELEASE} != "1" ]; then
    SUFFIX=${VERSION}-${RELEASE}
else
    SUFFIX=${VERSION}
fi

GITTAG=$(git log --format=%ct.%h -1)

mkdir -p BUILD SOURCES SPECS RPMS BUILDROOT
git archive --format=tar.gz -o "SOURCES/slurm-${SUFFIX}.tar.gz" --prefix="slurm-${SUFFIX}/" HEAD
cp slurm.spec "SPECS"

# there's no option to pass nvml, it is only autodetected
# nvidia-driver-devel provides the libnividia-ml.so symlnk, the real .so.1 comes from nvidia-driver-NVML
# cuda-nvml-dev provides the nvml.h (put is part of the cuda rpms so has cud version in the name, hence the *)
# however, it's not in the default include paths nor the slurm hardcoded ones, so use CPATH
# nvml api is not really cuda specific, last API is from cuda 5, so any recent cuda will do

# TODO: what if more than one cuda is available/installed, then the * thingies will probably not work
# pmix-3 as rebuild from github src.rpm includes the devel rpms in the rpm
sudo yum install -y nvidia-driver-devel cuda-nvml-dev-* nvidia-driver-NVML ucx-devel pmix-devel-3.* numactl-devel hwloc-devel

# glob expansion in list
nvmls=(/usr/local/cuda*/targets/x86_64-linux/include)
if [ "${#nvmls[@]}" -ne 1 ]; then
    echo "0 or more than one nvml.h found: ${nvmls[@]}. Unsupported."
    exit 1
fi

rpmbuild --define "gittag ${GITTAG}" --define "_topdir $PWD" --with numa --with pmix --with hwloc --with x11 --with ucx -ba SPECS/slurm.spec --define "_configure ./configure CPATH=${nvmls[0]}" --define "_smp_mflags CPATH=${nvmls[0]}"
