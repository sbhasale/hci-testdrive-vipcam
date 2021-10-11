#!/usr/bin/env bash

####################################################################################################
# This script is designed for use as a deployment script in a template
# https://docs.microsoft.com/en-us/azure/azure-resource-manager/templates/deployment-script-template
#
# It expects the following environment variables
# $RESOURCE_GROUP			- The resource-group of the VM
# $IOTHUB                   - the name of the IoT Hub where the edge device is registered
# $EDGE_DEVICE              - the name of the edge device
# $AZ_SCRIPTS_OUTPUT_PATH   - file to write output (provided by the deployment script runtime) 
#
####################################################################################################

#sleep 2m

# automatically install any extensions
az config set extension.use_dynamic_install=yes_without_prompt

# check to see if the device already exists
if test -z "$(az iot hub device-identity list -n "$IOTHUB" | grep "deviceId" | grep "$EDGE_DEVICE")"; then
    # if not, we create a new edge enable device
    az iot hub device-identity create --hub-name "$IOTHUB" --device-id "$EDGE_DEVICE" --edge-enabled -o none
    # TODO check for errors
fi

# capture the connection string for the new edge device
DEVICE_CONNECTION_STRING=$(az iot hub device-identity connection-string show --device-id "$EDGE_DEVICE" --hub-name "$IOTHUB" --query='connectionString' -o tsv)

echo "{ \"deviceConnectionString\": $DEVICE_CONNECTION_STRING }" 

#creating folder and configuring connection string 

# SSHPASS
echo "Looking for sshpass command"

if ! command -v sshpass $> /dev/null
then
    echo "sshpass command not found"
	if ! command -v apk $> /dev/null
	then
		echo "Installing sshpass"
		sudo apt-get install sshpass
	else
		echo "Installing sshpass"
		apk add sshpass
	fi
fi

#echo "Updating az-cli"
#pip install --upgrade azure-cli
#pip install --upgrade azure-cli-telemetry

echo "installing azure iot extension"
az extension add --name azure-iot

EDGE_DEVICE_USERNAME="root"
EDGE_DEVICE_PASSWORD="p@ssw0rd"

EDGE_DEVICE_PUBLIC_IP=$(az vm show --show-details --resource-group "$RESOURCE_GROUP" --name "$EDGE_DEVICE" --query "publicIps" --output tsv)
#alternative method EDGE_DEVICE_PUBLIC_IP=$(az network public-ip list -g "$RESOURCE_GROUP" | grep "ipAddress" | xargs | cut -d' ' -f2)
USER_IP=$(curl -s https://ip4.seeip.org/)
NSG="-vnet-NRMS"
NSG_NAME=$EDGE_DEVICE$NSG

#Looking for vnet-NRMS rules
VNET_FOUND=$(az network nsg list -g "$RESOURCE_GROUP" --query "[?name=='$NSG_NAME']")

[ ${#VNET_FOUND} -eq 2 ] && NSGTEST="No VNET_FOUND" || NSGTEST=$(az network nsg rule create --name "AllowSSH" --nsg-name "$NSG_NAME" --priority 100 --resource-group "$RESOURCE_GROUP" --destination-port-ranges 22 --source-address-prefixes "$USER_IP" --output "none")
echo "$NSGTEST"

NSG="-nsg"
NSG_NAME=$EDGE_DEVICE$NSG

#Adding NSG RULE 
NSGTEST=$(az network nsg rule create --name "AllowSSH" --nsg-name "$NSG_NAME" --priority 100 --resource-group "$RESOURCE_GROUP" --destination-port-ranges 22 --source-address-prefixes "$USER_IP" --output "none")
echo "$NSGTEST"
#-----


# Replace placeholder connection string with actual value for Edge device
echo "$(info) Updating Config.yaml on edge device with the connection string from IoT Hub"
CONFIG_FILE_PATH="/etc/iotedge/config.yaml"
# Using sshpass and ssh to update the value on Edge device
Command="sudo sed -i -e '/device_connection_string:/ s#\"[^\"][^\"]*\"#\"$DEVICE_CONNECTION_STRING\"#' $CONFIG_FILE_PATH"
sshpass -p "$EDGE_DEVICE_PASSWORD" ssh "$EDGE_DEVICE_USERNAME"@"$EDGE_DEVICE_PUBLIC_IP" -o StrictHostKeyChecking=no "$Command"
sshpass -p "$EDGE_DEVICE_PASSWORD" ssh "$EDGE_DEVICE_USERNAME"@"$EDGE_DEVICE_PUBLIC_IP" -o StrictHostKeyChecking=no " cd /root && wget $MARINER_VM_FILE_URL"
#sshpass -p "$EDGE_DEVICE_PASSWORD" scp -o StrictHostKeyChecking=no https://storageavanalyzer.blob.core.windows.net/avademo2/mariner-vm-init.sh "$EDGE_DEVICE_USERNAME"@"$EDGE_DEVICE_PUBLIC_IP":/home/"$EDGE_DEVICE_USERNAME"
sshpass -p "$EDGE_DEVICE_PASSWORD" ssh "$EDGE_DEVICE_USERNAME"@"$EDGE_DEVICE_PUBLIC_IP" -o StrictHostKeyChecking=no "chmod +x mariner-vm-init.sh"
sshpass -p "$EDGE_DEVICE_PASSWORD" ssh "$EDGE_DEVICE_USERNAME"@"$EDGE_DEVICE_PUBLIC_IP" -o StrictHostKeyChecking=no "./mariner-vm-init.sh"