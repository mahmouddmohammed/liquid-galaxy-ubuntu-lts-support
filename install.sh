#!/bin/bash

cat << "EOM"
 _ _             _     _               _
| (_) __ _ _   _(_) __| |   __ _  __ _| | __ ___  ___   _
| | |/ _` | | | | |/ _` |  / _` |/ _` | |/ _` \ \/ / | | |
| | | (_| | |_| | | (_| | | (_| | (_| | | (_| |>  <| |_| |
|_|_|\__, |\__,_|_|\__,_|  \__, |\__,_|_|\__,_/_/\_\\__, |
        |_|                |___/                    |___/

Liquid Galaxy Installer

-------------------------------------------------------------
This script will:
  • Verify OS compatibility
  • Install required dependencies
  • Configure Liquid Galaxy components
  • Apply system settings

Supported systems:
  • Ubuntu 24.04 LTS (64-bit)
  • Ubuntu 26.04 LTS (64-bit)

Run as:
  • sudo ./install.sh

Press Ctrl+C now to abort.
-------------------------------------------------------------
EOM

# load all lib scripts 
source lib/compat.sh
source lib/network.sh
#source lib/packages.sh


apt-get update -y && apt-get upgrade -y
