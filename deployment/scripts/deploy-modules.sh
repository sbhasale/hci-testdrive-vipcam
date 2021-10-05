#!/usr/bin/env bash
# shellcheck disable=SC2154,SC2188,SC2129

#######################################################################################################
# This script is designed for use as a deployment script in a template
# https://docs.microsoft.com/en-us/azure/azure-resource-manager/templates/deployment-script-template
#
# It expects the following environment variables
# $DEPLOYMENT_MANIFEST_TEMPLATE_URL - the location of a template of an IoT Edge deployment manifest
# $PROVISIONING_TOKEN               - the token used for provisioing the edge module
# $HUB_NAME                         - the name of the IoT Hub where the edge device is registered
# $DEVICE_ID                        - the name of the edge device on the IoT Hub
# $VIDEO_OUTPUT_FOLDER_ON_DEVICE    - the folder where the file sink will store clips
# $VIDEO_INPUT_FOLDER_ON_DEVICE     - the folder where where rtspsim will look for sample clips
# $APPDATA_FOLDER_ON_DEVICE         - the folder where Video Analyzer module will store state
# $AZURE_STORAGE_ACCOUNT            - the storage where the deployment manifest will be stored
# $AZ_SCRIPTS_OUTPUT_PATH           - file to write output (provided by the deployment script runtime) 
# $RESOURCE_GROUP                   - the resouce group that you are deploying in to
# $REGESTRY_PASSWORD                - the password for the container registry
# $REGISTRY_USER_NAME               - the user name for the container registry
# $IOT_HUB_CONNECTION_STRING        - the IoT Hub connection string
# $IOT_EDGE_MODULE_NAME             - the IoT avaedge module name
# $COGNITIVE_API_KEY
# $COGNITIVE_BILLING_ENDPOINT
#######################################################################################################

set -e

# Define helper function for logging
info() {
    echo "$(date +"%Y-%m-%d %T") [INFO]"
}

# Define helper function for logging. This will change the Error text color to red
error() {
    echo "$(date +"%Y-%m-%d %T") [ERROR]"
}

exitWithError() {
    # Reset console color
    exit 1
}

# automatically install any extensions
az config set extension.use_dynamic_install=yes_without_prompt

# download the deployment manifest file
echo "$(info) downloading $DEPLOYMENT_MANIFEST_TEMPLATE_URL"                     # the template is general-sample-setup.modules.json
curl -s "$DEPLOYMENT_MANIFEST_TEMPLATE_URL" > deployment.json

# update the values in the manifest
echo "$(info) replacing value in manifest"
sed -i "s@\$AVA_PROVISIONING_TOKEN@${PROVISIONING_TOKEN}@g" deployment.json
sed -i "s@\$VIDEO_OUTPUT_FOLDER_ON_DEVICE@${VIDEO_OUTPUT_FOLDER_ON_DEVICE}@g" deployment.json
sed -i "s@\$VIDEO_INPUT_FOLDER_ON_DEVICE@${VIDEO_INPUT_FOLDER_ON_DEVICE}@g" deployment.json
sed -i "s@\$APPDATA_FOLDER_ON_DEVICE@${APPDATA_FOLDER_ON_DEVICE}@g" deployment.json

sed -i "s@\$COGNITIVE_API_KEY@${COGNITIVE_API_KEY}@g" deployment.json
sed -i "s@\$COGNITIVE_BILLING_ENDPOINT@${COGNITIVE_BILLING_ENDPOINT}@g" deployment.json

sed -i "s@\$CONTAINER_REGISTRY_USERNAME_myacr@${REGISTRY_USER_NAME}@g" deployment.json
sed -i "s@\$CONTAINER_REGISTRY_PASSWORD_myacr@${REGISTRY_PASSWORD}@g" deployment.json
sed -i "s@\$CONTAINER_REGISTRY_PASSWORD_myacr@${REGISTRY_PASSWORD}@g" deployment.json

# Add a file to build env.txt file from
> env.txt
echo "SUBSCRIPTION_ID=$SUBSCRIPTION_ID" >> env.txt
echo "RESOUCE_GROUP=$RESOURCE_GROUP" >> env.txt
echo "AVA_PROVISIONING_TOKEN=$PROVISIONING_TOKEN">> env.txt
echo "VIDEO_INPUT_FOLDER_ON_DEVICE=$VIDEO_INPUT_FOLDER_ON_DEVICE">> env.txt
echo "VIDEO_OUTPUT_FOLDER_ON_DEVICE=$VIDEO_OUTPUT_FOLDER_ON_DEVICE" >> env.txt
echo "APPDATA_FOLDER_ON_DEVICE=$APPDATA_FOLDER_ON_DEVICE" >> env.txt
echo "CONTAINER_REGISTRY_PASSWORD_myacr=$REGISTRY_PASSWORD" >> env.txt
echo "CONTAINER_REGISTRY_USERNAME_myacr=$REGISTRY_USER_NAME" >> env.txt
# > appsettings.json
# echo "{" >> appsettings.json
# echo "\"IoThubConnectionString\": \"$IOT_HUB_CONNECTION_STRING\"," >> appsettings.json
# echo "\"deviceId\": \"$DEVICE_ID\"," >> appsettings.json
# echo "\"moduleId\": \"$IOT_EDGE_MODULE_NAME\"" >> appsettings.json
# echo "}" >> appsettings.json


# deploy the manifest to the iot hub
echo "$(info) deploying manifest to $DEVICE_ID on $HUB_NAME"
az iot edge set-modules --device-id "$DEVICE_ID" --hub-name "$HUB_NAME" --content deployment.json --only-show-error -o table

# store the manifest for later reference
echo "$(info) storing manifest for reference"
az storage share create --name deployment-output --account-name "$AZURE_STORAGE_ACCOUNT"
az storage file upload --share-name deployment-output --source deployment.json --account-name "$AZURE_STORAGE_ACCOUNT"
az storage file upload --share-name deployment-output --source env.txt --account-name "$AZURE_STORAGE_ACCOUNT"
# az storage file upload --share-name deployment-output --source appsettings.json --account-name "$AZURE_STORAGE_ACCOUNT"



# waiting for module to running state

MODULE_RUNNING="Failed"
for ((i=1; i<=15; i++)); do

    if [ ! "$MODULE_RUNNING" == "Running" ]; then
        MODULE_RUNNING=$( az iot hub query -n "$HUB_NAME" -q "select properties.reported.State from devices.modules where devices.modules.moduleId = 'avaedge' and devices.deviceId = '$DEVICE_ID'" | jq -r '.[].State')
        sleep 1m
    fi
done

sleep 2m

# updating topology 

curl -s "$AVA_TOPOLOGY_FILE_URL" > person-count-operation-topology.json
curl -s "$AVA_PIPELINE_FILE_URL" > person-count-pipeline.json


echo "$(info) Setting AVA graph topology"

GRAPH_TOPOLOGY=$(< person-count-operation-topology.json jq '.name = "'"$GRAPH_TOPOLOGY_NAME"'"')
az iot hub invoke-module-method \
    -n "$HUB_NAME" \
    -d "$DEVICE_ID" \
    -m avaedge \
    --mn pipelineTopologySet \
    --mp "$GRAPH_TOPOLOGY" \
    --timeout 120

echo "$(info) Getting AVA graph topology status"
TOPOLOGY_STATUS=$(az iot hub invoke-module-method -n "$HUB_NAME" -d "$DEVICE_ID" -m avaedge --mn pipelineTopologyGet \
    --mp '{"@apiVersion": "1.0","name": "'"$GRAPH_TOPOLOGY_NAME"'"}')
if [ "$(echo "$TOPOLOGY_STATUS" | jq -r '.payload.name' )" == "$GRAPH_TOPOLOGY_NAME" ]; then
    echo "$(info) Graph Topology has been set on device"
else
    echo "$(error) Graph Topology has not been set on device"
    exitWithError
fi


echo "$(info) Creating a new AVA graph instance"
 

# shellcheck disable=2016
GRAPH_INSTANCE=$(< person-count-pipeline.json jq '.name = "'"$GRAPH_PIPELINE_NAME"'"' | 
    jq '.properties.topologyName = "'"$GRAPH_TOPOLOGY_NAME"'"' )

INSTANCE_LIST=$(az iot hub invoke-module-method -n "$HUB_NAME" -d "$DEVICE_ID" -m avaedge --mn livePipelineGet \
    --mp '{"@apiVersion": "1.0","name": "'"$GRAPH_PIPELINE_NAME"'"}')
if [ "$(echo "$INSTANCE_LIST" | jq -r '.payload.name')" == "$GRAPH_PIPELINE_NAME" ]; then
    echo "$(info) Graph Instance already exist"
    echo "$(info) Deactivating LVA graph instance..."
    az iot hub invoke-module-method \
        -n "$HUB_NAME" \
        -d "$DEVICE_ID" \
        -m avaedge \
        --mn livePipelineDeactivate \
        --mp '{"@apiVersion": "1.0","name": "'"$GRAPH_PIPELINE_NAME"'"}' --timeout 120
fi
echo "$(info) Setting AVA graph instance"
az iot hub invoke-module-method \
    -n "$HUB_NAME" \
    -d "$DEVICE_ID" \
    -m avaedge \
    --mn livePipelineSet \
    --mp "$GRAPH_INSTANCE" \
    --timeout 120


echo "$(info) Getting AVA graph instance status..."
INSTANCE_STATUS=$(az iot hub invoke-module-method -n "$HUB_NAME" -d "$DEVICE_ID" -m avaedge --mn livePipelineGet \
    --mp '{"@apiVersion": "1.0","name": "'"$GRAPH_PIPELINE_NAME"'"}')

if [ "$(echo "$INSTANCE_STATUS" | jq -r '.payload.name')" == "$GRAPH_PIPELINE_NAME" ]; then
    echo "$(info) Graph Instance has been created on device."
else
    echo "$(error) Graph Instance has not been created on device"
    exitWithError
fi

echo "$(info) Activating AVA graph instance"
INSTANCE_RESPONSE=$(az iot hub invoke-module-method \
    -n "$HUB_NAME" \
    -d "$DEVICE_ID" \
    -m avaedge \
    --mn livepipelineActivate \
    --mp '{"@apiVersion" : "1.0","name" : "'"$GRAPH_PIPELINE_NAME"'"}')


if [ "$(echo "$INSTANCE_RESPONSE" | jq '.status')" == 200 ]; then
    echo "$(info) Graph Instance has been activated on device."
else
    echo "$(error) Failed to activate Graph Instance on device."
    echo "ERROR CODE: $(echo "$INSTANCE_RESPONSE" | jq '.payload.error.code')"
    echo "ERROR MESSAGE: $(echo "$INSTANCE_RESPONSE" | jq '.payload.error.message')"
    exitWithError
fi
