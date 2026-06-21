#!/bin/bash 

apt-get update -y && apt-get upgrade -y
apt-get install -y git bzip2 tar gcc make perl ca-certificates curl gpg xdg-utils python3 python3-pip tcpdump git nautilus openssh-server sshpass apache2 xdotool unclutter chromium-browser \
                   xdotool wmctrl x11-utils # for xwayland (x11 tools) to manipulate
