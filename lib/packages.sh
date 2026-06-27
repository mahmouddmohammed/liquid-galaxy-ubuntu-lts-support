#!/bin/bash 

sudo apt-get update -y && sudo apt-get upgrade -y
sudo ubuntu-drivers install
sudo apt-get install -y git bzip2 tar gcc make perl ca-certificates curl gpg xdg-utils python3 python3-pip tcpdump nautilus unclutter chromium-browser \
                   xdotool wmctrl x11-utils \
                   snmpd \
                   nftables \
                   librsvg2-bin bc equivs screen \
                   python3-evdev tk mplayer imagemagick x11-apps caca-utils \
                   isc-dhcp-client \
                   openssh-server sshpass \
                   php php-cgi libapache2-mod-php apache2 \