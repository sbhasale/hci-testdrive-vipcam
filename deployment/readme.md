# Azure Video Analyzer

The scripts in this folder are used to deploy the Azure Video Analyzer.  This deployment enables quickstarts and other samples for Video Analyzer.

- deploy-modules.sh - This script is used to deploy the IoT Edge modules to the IoT Edge device based off of the deployment manifest and update the toplogy for sample video
- form.json- custom deployment form used in Azure Portal
- iot-edge-setup.sh - Checks to see if an existing Edge device exist, if not it creates a new Edge device and captures the connection string. It also update the config.yaml file and run the mariner-vm-init.sh script in th VM using ssh command 
- iot.deploy.json - Deploys an IoT Hub
- mariner-vm.deploy.json - Depolys the Mariner VM from a managed disk 
- disk-setup.sh - Copy the VHD file into a managed disk nad than used in mariner-vm.deploy.json
- jwt-token-issuer.zip - this is the .Net application which genertaes the JWT token
- mariner-vm-init.sh - Configures the IoT Edge device with the required user and folder structures.
- simulated-device.deploy.json - Deploys a VM to be used as a simulated IoT Edge device.
- generate-token.sh - Generated the JWT token, that will included in the web app to display the video analyzer videos
- start.deploy.json - Master template and controls the flow between the rest of the deployment templates
- video-analyzer.deploy.json - Deploys storage, identities, and the Azure Video Analyzer resources.



> NOTE: Things like VM availability in the selected region will cause the deployment to fail.

