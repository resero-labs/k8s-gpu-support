# k8s GPU Support
This docker container downloads GPU drivers from nvidia which get installed on the host 
in the file "01-aws-nvidia-driver.sh" which is run through systemd. 
To update the drivers to be installed change lines 27-28 in the dockerfile and 
line 92 in 01-aws-nvidia-driver.sh

nvidia-docker is also installed during this process.

The docker images with version tags can be found here: https://hub.docker.com/r/resero/nvidia-device-plugin