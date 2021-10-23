#!/usr/bin/env bash

###################################################################################################
# This script is designed to be executed on an edge device
#
# It expects the following environment variables
# $DEVICE_CONNECTION_STRING 		- the connection string for the edge device found in IoT Hub
#
###################################################################################################

set -e



# Restart the iotedge runtime
sudo systemctl restart iotedge

###########################################################
# NVIDIA Drivers
###########################################################

# check that the GPU is visible. If not, throw an error
NVIDIA_DEVICE=$(lspci | grep  NVIDIA)

if [ ! -z "$NVIDIA_DEVICE" ];
then
	echo "device found: $NVIDIA_DEVICE"
else
	echo "no device found $NVIDIA_DEVICE"
fi

# install the NVIDIA drivers
# need to run NVIDIA.sh in RPM-Script-0513
echo "Looking for nvidia-smi command"

if ! command -v nvidia-smi $> /dev/null
then
    echo "nvidia-smi command not found"
	
	echo "Locating Nvidia drivers on VM"
	DRIVER_DIR=$(ls -d -- *RPM-Script-*)

	if [ ! -z "$DRIVER_DIR" ];
	then
		echo "Nvidia drivers found in $DRIVER_DIR"
		echo "Installing Nvidia drivers"
		cd "$DRIVER_DIR"
		./NVIDIA.sh	
	else
		echo "No Nvidia drivers located"
	fi
	
else
    echo "Existing nvidia driver installation found"
	nvidia-smi
fi

###########################################################
# Edge Module Prerequisites
###########################################################

# create the local group and user for the edge module
# these are mapped from host to container in the deployment manifest in the desired properties for the module
sudo groupadd -g 1010 localedgegroup
sudo useradd --home-dir /home/localedgeuser --uid 1010 --gid 1010 localedgeuser
sudo mkdir -p /home/localedgeuser

# create folders to be used by the rtspsim module
sudo mkdir -p /home/localedgeuser/samples
sudo mkdir -p /home/localedgeuser/samples/input


sudo curl "https://unifiededgescenarios.blob.core.windows.net/static-assets/cafeteria.mkv" --output /home/localedgeuser/samples/input/cafeteria.mkv 

# give the local user access
sudo chown -R localedgeuser:localedgegroup /home/localedgeuser/

# set up folders for use by the Video Analyzer module
# these are mounted in the deployment manifest

# !NOTE! these folder locations are must match the folders used in `deploy-modules.sh` and ultimately the IoT edge deployment manifest

# general app data for the module
sudo mkdir -p /var/lib/videoanalyzer 
sudo chown -R localedgeuser:localedgegroup /var/lib/videoanalyzer/
sudo mkdir -p /var/lib/videoanalyzer/tmp/ 
sudo chown -R localedgeuser:localedgegroup /var/lib/videoanalyzer/tmp/
sudo mkdir -p /var/lib/videoanalyzer/logs
sudo chown -R localedgeuser:localedgegroup /var/lib/videoanalyzer/logs

# output folder for file sink
sudo mkdir -p /var/media
sudo chown -R localedgeuser:localedgegroup /var/media/
