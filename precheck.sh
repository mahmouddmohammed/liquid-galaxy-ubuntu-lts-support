#!/bin/bash

source lib/compat.sh

if [ $EUID -eq 0 ]; then
echo "Do not run it as root!" 1>&2
exit 1
fi

is_supported

if [ "$USER" != "lg" ]; then
    echo "Error: This script must be run as the 'lg' user."
    echo "Please create "lg" user and switch users first: sudo su - lg"
    exit 1
fi

