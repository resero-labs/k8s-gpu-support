# Copyright 2017 The Kubernetes Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

#!/bin/bash
set -euo pipefail
set -x

#################################################
# Settings

# A place on the host machine to cache 1.6GB+ downloads in-between reboots.

CACHE_DIR=/nvidia-device-plugin

# AWS Instance Types to Nvidia Card Mapping (cut and pasted from AWS docs)
# Load the correct driver for the correct instance type
#   Instances  Product Type  Product Series  Product
#   G2         GRID          GRID Series     GRID K520 (deprecated)
#   G3         Tesla         M-Series        M-60
#   G3S        Tesla         M-Series        M-60
#   P2         Tesla         K-Series        K-80
#   P3         Tesla         V-Series        V100
# http://www.nvidia.com/Download/index.aspx
declare -a class_to_driver_file
classes=( \
    "g2" \
    "g3" \
    "g3s" \
    "p2" \
    "p3" \
)

containsElement () { for e in "${@:2}"; do [[ "$e" = "$1" ]] && return 0; done; return 1; }

#################################################
# Ensure that we are on a proper AWS GPU Instance

apt-get -y update
apt-get -y --no-upgrade install curl jq

AWS_INSTANCE_TYPE=$(curl -m 2 -fsSL http://169.254.169.254/latest/dynamic/instance-identity/document | jq -r ".instanceType" || true) # eg: p2.micro
AWS_INSTANCE_CLASS=$(echo $AWS_INSTANCE_TYPE | cut -d . -f 1 || true) # e.g. p2

if [[ -z $AWS_INSTANCE_TYPE ]] || [[ -z $AWS_INSTANCE_CLASS ]]; then
  echo "This machine is not an AWS instance"
  echo "  Exiting without installing GPU drivers"
  exit 1
fi

classnames=${!class_to_driver_file[@]} # e.g. [ "g2", "g3", "g3s", "p2", "p3" ]
if ! containsElement $AWS_INSTANCE_CLASS $classnames; then
  echo "This machine is an AWS instance, but not a GPU instance"
  echo "  Exiting without installing GPU drivers"
  exit 1
fi

echo "Identified machine as AWS_INSTANCE_TYPE[$AWS_INSTANCE_TYPE] AWS_INSTANCE_CLASS[$AWS_INSTANCE_CLASS]"

#################################################
# Install dependencies

# Install GCC and linux headers on the host machine
#   The NVIDIA driver build must be compiled with the same version of GCC as
#   the kernel.  In addition, linux-headers are machine image specific.
#   Install with --no-upgrade so that the c-libs are not upgraded, possibly
#   breaking programs and requiring restart
apt-get -y update
apt-get -y --no-upgrade install gcc libc-dev linux-headers-$(uname -r)
apt-get -y clean
apt-get -y autoremove

#################################################
# Unload open-source nouveau driver if it exists
#   The nvidia drivers won't install otherwise
#   "g3" instances in particular have this module auto-loaded
modprobe -r nouveau || true

#################################################
# install the Nvidia drivers

driver_filename="NVIDIA-Linux-x86_64-418.67.run"
driver_path="${CACHE_DIR}/${driver_filename}"

$driver_path --accept-license --silent

#################################################
# Output GPU info for debugging
nvidia-smi --list-gpus

#################################################
# Configure and Optimize Nvidia cards now that things are installed
#   AWS Optimizization Doc
#     https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/optimize_gpu.html
#   Nvidia Doc
#     http://developer.download.nvidia.com/compute/DCGM/docs/nvidia-smi-367.38.pdf

# Common configurations
nvidia-smi -pm 1
nvidia-smi --auto-boost-default=0
nvidia-smi --auto-boost-permission=0

# Custom configurations per class of nvidia video card
case "$AWS_INSTANCE_CLASS" in
"g2" | "g3" | "g3s")
  nvidia-smi -ac 2505,1177
  ;;
"p2")
  nvidia-smi -ac 2505,875
  nvidia-smi -acp 0
  ;;
"p3")
  nvidia-smi -ac 877,1530
  nvidia-smi -acp 0
  ;;
*)
  ;;
esac

#################################################
# Load the Kernel Module

if ! /sbin/modprobe nvidia-uvm; then
  echo "Unable to modprobe nvidia-uvm"
  exit 1
fi

# Ensure that the device node exists
if ! test -e /dev/nvidia-uvm; then
  # Find out the major device number used by the nvidia-uvm driver
  D=`grep nvidia-uvm /proc/devices | awk '{print $1}'`
  mknod -m 666 /dev/nvidia-uvm c $D 0
fi