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


IS_MASTER=false   # boolean flag 
# It will be needed for slaves
MASTER_IP=""
MASTER_PASSWORD=""

USER_IP=""
USER_PASSWORD=""
USER_USERNAME=$USER
USER_HOME_DIR=$HOME

MACHINE_ID="1"
MACHINE_NAME="lg"$MACHINE_ID
TOTAL_MACHINES="3"

LG_FRAMES="lg3 lg1 lg2"
OCTET="42"
SCREEN_ORIENTATION="V"

GITHUB_REPO_NAME="ubuntu-lts-support-gsoc2026"
GITHUB_REPO_URL="https://github.com/LiquidGalaxyLAB/ubuntu-lts-support-gsoc2026"

GOOGLE_EARTH_DIR="/opt/google/earth/pro/"


load_script(){
  source lib/compat.sh
  source lib/network.sh
  source lib/display.sh
  source lib/desktop.sh
  USER_IP=$NODE_IP
}

read_machine_id(){
  while true; do
      read -p "Machine id (i.e. 1 for lg1) (1 == master): " MACHINE_ID

      if [ "$(echo $MACHINE_ID | cut -c-2)" == "lg" ]; then
          MACHINE_ID="$(echo $MACHINE_ID | cut -c3-)"
      fi

      # check it's a number
      if [[ "$MACHINE_ID" =~ ^[0-9]+$ ]]; then
          break
      fi

      echo "Invalid input. Please enter a number."
  done
  MACHINE_NAME="lg$MACHINE_ID"
}

print_configuration(){
  cat << EOM

Liquid Galaxy will be installed with the following configuration:

IS THIS MACHINE THE MASTER: $IS_MASTER

LOCAL_USER: $USER_USERNAME

MACHINE_ID: $MACHINE_ID

MACHINE_NAME: $MACHINE_NAME 

TOTAL_MACHINES: $TOTAL_MACHINES

OCTET (UNIQUE NUMBER): $OCTET

GITHUB_REPO_URL: $GITHUB_REPO_URL

Repo folder name: $GITHUB_REPO_NAME

EARTH_FOLDER: $GOOGLE_EARTH_DIR

NETWORK_INTERFACE: $NETWORK_INTERFACE

NETWORK_MAC_ADDRESS: $NETWORK_INTERFACE_MAC

Is it correct? Press any key to continue or CTRL-C to exit

EOM

  read
}


configure_chromium(){
  # I need to register it in database to be able to set it 
  update-alternatives --install /usr/bin/x-www-browser x-www-browser /snap/bin/chromium 60
  update-alternatives --install /usr/bin/gnome-www-browser gnome-www-browser /snap/bin/chromium 60
  update-alternatives --set x-www-browser /snap/bin/chromium
  update-alternatives --set gnome-www-browser /snap/bin/chromium
  apt-get remove --purge -yq update-notifier*
}

setup_liquid_galaxy(){
  # I'm in ~/ubuntu-lts-support-gsoc2026
  cp -r earth ~
  sudo cp -r gnu_linux/home/lg/. ~   # copy all files in gnu_linux/home/lg/ to user home directory
  ln -s $GOOGLE_EARTH_DIR $HOME/earth/builds/latest
  awk '/LD_LIBRARY_PATH/{print "export LC_NUMERIC=en_US.UTF-8"}1' ~/earth/builds/latest/googleearth | sudo tee ~/earth/builds/latest/googleearth > /dev/null

  if [ $MASTER == false ]; then
    sudo sed -i -e 's/slave_x/slave_'${MACHINE_ID}'/g' ~/earth/kml/slave/myplaces.kml
    sudo sed -i -e 's/sync_nlc_x/sync_nlc_'${MACHINE_ID}'/g' ~/earth/kml/slave/myplaces.kml
  fi

  # make these files hidden
  for file in ~/dotfiles/*; do
    filename=$(basename "$file")
    sudo mv "$file" ~/dotfiles/."$filename"
  done


  
}


main(){

  # user need to run the script with sudo privilige as I didn't write sudo below
  if [ "$EUID" -ne 0 ]; then
    echo "Please run as root: sudo bash $0"
    exit 1
  fi

  # to to exit immediately if a command returns a non-zero exit status, instead of continuing to execute the rest of the script
  set -euo pipefail

  # clone the repo, if there is already the dir I will clone again because I don't know it's corrupted or not without checking the hash so i simply overwrite
  cd ~ 
  git clone "$GITHUB_REPO_URL"
  cd "$GITHUB_REPO_NAME"

  # load all lib scripts 
  load_script

  # first check it's compatibile or not 
  bash precheck.sh


  read_machine_id
  if [ $MACHINE_ID == "1" ]; then
    IS_MASTER=true
    echo "Save the IP ADDRESS of this machine: $USER_IP"
    read -p "Press any key to continue"
  else

    echo "Make sure Master machine (lg1) is connected to the network before proceding!"
    read -p "Master machine IP (i.e. 192.168.1.42): " MASTER_IP
    read -p "Master local user password (i.e. lg password): " MASTER_PASSWORD

  fi

  read -p "Total machines count (i.e. 3): " TOTAL_MACHINES

  read -p "Unique number that identifies your Galaxy (octet) (i.e. 42): " OCTET
  
  mid=$((TOTAL_MACHINES / 2))
  array=()
  for j in `seq $((mid + 2)) $TOTAL_MACHINES`;
  do
      array+=("lg"$j)
  done

  for j in `seq 1 $((mid+1))`;
  do
      array+=("lg"$j)
  done
  echo "${array[@]}"


  print_configuration

  export DEBIAN_FRONTEND=noninteractive

  echo ">>> Installing Needed Packages..."
  bash lib/packages.sh
  
  echo ">>> Configuring autologin..."
  configure_autologin "$USER_USERNAME"

  echo ">>> Configuring desktop settings..."
  configure_desktop_settings
  
  echo ">>> Installing Google Earth..."
  bash "lib/google_earth.sh"

  configure_chromium


  # apt upgrade -f # to fix any dependecies packages issue because that will install dependencies packages

}
