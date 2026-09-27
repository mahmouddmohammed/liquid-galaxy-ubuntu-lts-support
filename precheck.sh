#!/bin/bash

LG_USER="lg"
LG_HOME="/home/lg"

source lib/compat.sh

if [ $EUID -eq 0 ]; then
echo "Do not run it as root!" 1>&2
exit 1
fi

is_supported

# I can check it this way or through /etc/passwd and grep on "lg" and extract home directory and check if variable is empty or not and if it's equal to /home/lg , all of that in one if condition instead of two

if [ "$USER" != "$LG_USER" ]; then
    echo "Error: This script must be run as the 'lg' user."
    echo "Please create "lg" user and switch users first: sudo su - lg"
    exit 1
fi

if [ "$HOME" != "$LG_HOME" ]; then
    echo "Error: "lg" user home directory must be /home/lg"
    echo "Please change it and try again"
    exit 1 
fi 

