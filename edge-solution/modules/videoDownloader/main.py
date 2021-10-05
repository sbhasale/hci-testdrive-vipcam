# Copyright (c) Microsoft. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for
# full license information.

import time
import os
import sys
import asyncio
from six.moves import input
from azure.iot.device.aio import IoTHubModuleClient
from azure.iot.device import MethodResponse
import logging
import requests
import subprocess


# read path from the env variable
path = os.environ.get("VIDEO_INPUT_FOLDER_ON_DEVICE")
default_video_file = "https://unifiededgescenarios.blob.core.windows.net/static-assets/cafeteria.mkv"

async def download_file(link, name):
    # obtain the file by concating path and name
    video_file = os.path.join(path, name)

    # create response object
    r = requests.get(link, stream=True)

    print('Beginning video file download')

    # download started

    with open(video_file, 'wb') as f:
        for chunk in r.iter_content(chunk_size=1024*1024):
            if chunk:
                f.write(chunk)

    print("%s downloaded!\n" % video_file)


async def remove_files(filename):
    # The list of items
    files = os.listdir(path)
    # Loop to remove each file from the path
    filelist = [f for f in files if f.endswith(
        ".mkv") and not f.startswith(filename)]
    for f in filelist:
        os.remove(os.path.join(path, f))


def generate_rtsp_property(name, link):
    return {"rtsp": {"video_name": name, "video_url": link}}


async def update_reported_properties(module_client, properties):
    # update the reported properties
    await module_client.patch_twin_reported_properties(properties)


async def convert_video(temp_filename, filename, fps=15):
    input_file_name = os.path.join(path, temp_filename)
    output_file_name = os.path.join(path, filename)

    command = "ffmpeg -y -vsync 0 -hwaccel cuda -hwaccel_output_format cuda -c:v h264_cuvid -i {} -c:v h264 -filter:v fps={} {} &".format(
        input_file_name, fps, output_file_name)
    os.system(command)

async def execute_operations(module_client, filename, link):

    temp_filename = "temp-{}".format(filename)

    # download a file
    await download_file(link, temp_filename)

    # convert video to 15 fps
    await convert_video(temp_filename, filename, fps=15)

    # generate property schema and update reported properties
    reported_properties = generate_rtsp_property(filename, link)
    await update_reported_properties(module_client, reported_properties)

    # remove old files that have extension .mkv from dir
    await remove_files(filename)

async def main():
    try:
        if not sys.version >= "3.5.3":
            raise Exception(
                "The sample requires python 3.5.3+. Current version of Python: %s" % sys.version)
        print("IoT Hub Client for Python")

        # The client object is used to interact with your Azure IoT hub.
        module_client = IoTHubModuleClient.create_from_edge_environment()

        # connect the client.
        await module_client.connect()

        # update initial reported properties
        reported_properties = {"availableMethods": [
            "rtspVideoSet", "rtspVideoDelete", "rtspVideoReset"]}
        await update_reported_properties(module_client, reported_properties)

        async def method_request_handler(method_request):
            # Determine how to respond to the method request based on the method name
            if method_request.name == "rtspVideoSet":
                # obtain the file name and file link from the payload
                filename = method_request.payload["name"]
                link = method_request.payload["url"]

                await execute_operations(module_client, filename, link)

                payload = {"result": True}  # set response payload
                status = 200  # set return status code

                print("executed rtspVideoSet method")
            elif method_request.name == "rtspVideoDelete":
                # obtain the file name and file link from the payload
                filename = method_request.payload["name"]

                # obtain the file by concating path and name
                video_file = os.path.join(path, filename)

                if os.path.exists(video_file):
                    os.remove(video_file)
                else:
                    print("The file does not exist")

                payload = {"result": True}  # set response payload
                status = 200  # set return status code
                print("executed rtspVideoDelete method")
            elif method_request.name == "rtspVideoReset":
                # obtain the file name and file link from the payload if None then use default values
                filename = method_request.payload.get(
                    "name", "cafeteria.mkv")
                link = method_request.payload.get(
                    "url", default_video_file)

                await execute_operations(module_client, filename, link)

                payload = {"result": True}  # set response payload
                status = 200  # set return status code
            else:
                # set response payload
                payload = {"result": False, "data": "unknown method"}
                status = 400  # set return status code
                print("executed unknown method: " + method_request.name)

            # Send the response
            method_response = MethodResponse.create_from_method_request(
                method_request, status, payload)
            await module_client.send_method_response(method_response)

        # Set the method request handler on the client
        module_client.on_method_request_received = method_request_handler

        # define behavior for halting the application
        def stdin_listener():
            while True:
                try:
                    selection = input("Press Q to quit\n")
                    if selection == "Q" or selection == "q":
                        print("Quitting...")
                        break
                except:
                    time.sleep(10)

        # Run the stdin listener in the event loop
        loop = asyncio.get_event_loop()
        user_finished = loop.run_in_executor(None, stdin_listener)

        # Wait for user to indicate they are done listening for messages
        await user_finished

        # Finally, disconnect
        await module_client.disconnect()

    except Exception as e:
        print("Unexpected error %s " % e)
        raise

if __name__ == "__main__":
    # remote debugging (running in the container will listen on port 5678)
    debug = False

    if debug:

        logging.info("Please attach a debugger to port 56780")

        import ptvsd
        ptvsd.enable_attach(('0.0.0.0', 56780))
        ptvsd.wait_for_attach()
        ptvsd.break_into_debugger()

    loop = asyncio.get_event_loop()
    loop.run_until_complete(main())
    loop.close()

    # If using Python 3.7 or above, you can use following code instead:
    # asyncio.run(main())
