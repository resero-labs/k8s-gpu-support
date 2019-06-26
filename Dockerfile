FROM debian:stretch-slim
# ^ Cannot be Alpine since it does not support systemctl
# ^ Systemctl is used to control systemd resources of the host

RUN apt-get update && \
  apt-get install -y -q --no-install-recommends curl systemd gcc libc-dev ca-certificates kmod build-essential && \
  apt-get -y clean && \
  apt-get -y autoremove

COPY files/* /nvidia-device-plugin/

RUN   cd /nvidia-device-plugin && \
    curl -L "http://us.download.nvidia.com/tesla/418.67/NVIDIA-Linux-x86_64-418.67.run" > NVIDIA-Linux-x86_64-418.67.run && \
    chmod a+x "NVIDIA-Linux-x86_64-418.67.run" 

COPY run.sh /run.sh


CMD [ "/bin/bash", "/run.sh" ]