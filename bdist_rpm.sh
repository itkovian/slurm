#!/bin/bash

set -e
set -x

echo "BUILDING GPU VERSION"

VERSION=`grep "Version:.*[0-9]" slurm.spec | tr -s " " |  awk '{print $2;}'`
RELEASE=`grep "%define rel.*[-1-9]" slurm.spec | tr -s " " | awk '{print $3}'`

if [ "${RELEASE}" != "1" ]; then
    SUFFIX=${VERSION}-${RELEASE}
else
    SUFFIX=${VERSION}
fi

GITTAG=$(git log --format=%ct.%h -1)

rm -Rf BUILD SOURCES SPECS SRPMS RPMS BUILDROOT
mkdir -p BUILD SOURCES SPECS SRPMS RPMS BUILDROOT

git archive --format=tar.gz -o "SOURCES/slurm-${SUFFIX}.tar.gz" --prefix="slurm-${SUFFIX}/" HEAD
cp slurm.spec "SPECS"

# remove json-c12 -> use plain json-c?
sudo yum install -y json-c-devel json-c
if $(grep "release 7" /etc/redhat-release); then
  #   json-c is only needed for restd and burstbuffer
    sudo yum install -y json-c12-devel json-c12
fi

# TODO? also, specify python2 as python to require

sudo yum install -y ucx-devel "pmix-devel > 3.0.0" numactl-devel hwloc-devel

# there's no option to pass nvml, it is only autodetected
# nvidia-driver-devel provides the libnividia-ml.so symlnk, the real .so.1 comes from nvidia-driver-NVML
# cuda-nvml-dev provides the nvml.h (put is part of the cuda rpms so has cud version in the name, hence the *)
# however, it's not in the default include paths nor the slurm hardcoded ones, so use CPATH
# nvml api is not really cuda specific, last API is from cuda 5, so any recent cuda will do

# TODO: what if more than one cuda is available/installed, then the * thingies will probably not work
# pmix-3 as rebuild from github src.rpm includes the devel rpms in the rpm
sudo yum remove -y cuda-nvml-dev-10-1
sudo yum install -y nvidia-driver-devel cuda-nvml-dev-10-2 nvidia-driver-NVML

# glob expansion in list
nvmls=(/usr/local/cuda*/targets/x86_64-linux/include)
if [ "${#nvmls[@]}" -ne 1 ]; then
    echo "0 or more than one nvml.h found: ${nvmls[@]}. Unsupported."
    exit 1
fi

rpmbuild --define "gittag ${GITTAG}" --define "_topdir $PWD" --with numa --with pmix --with hwloc --with mysql --with x11 --with ucx -ba SPECS/slurm.spec --define "_configure ./configure CPATH=${nvmls[0]}" --define "_smp_mflags CPATH=${nvmls[0]}"


echo "BUILDING NON GPU VERSION"


# there's no option to pass nvml, it is only autodetected
# nvidia-driver-devel provides the libnividia-ml.so symlnk, the real .so.1 comes from nvidia-driver-NVML
# cuda-nvml-dev provides the nvml.h (put is part of the cuda rpms so has cud version in the name, hence the *)
# however, it's not in the default include paths nor the slurm hardcoded ones, so use CPATH
# nvml api is not really cuda specific, last API is from cuda 5, so any recent cuda will do

# TODO: what if more than one cuda is available/installed, then the * thingies will probably not work
# pmix-3 as rebuild from github src.rpm includes the devel rpms in the rpm
sudo yum remove -y nvidia-driver-devel cuda-nvml-dev-10-2 nvidia-driver-NVML cuda-nvml-dev-10-1


rpmbuild --define "gittag ${GITTAG}" --define "_topdir $PWD" --with pmix --with numa --with hwloc --with mysql --with x11 --with ucx --define "gpu .nogpu" -ba SPECS/slurm.spec
