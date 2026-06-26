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
  • ./install.sh

Press Ctrl+C now to abort.
-------------------------------------------------------------
EOM

# =============================================================================
# GLOBAL VARIABLES
# =============================================================================

# It will be needed for slaves
IS_MASTER=false   # boolean flag 
MASTER_IP=""
MASTER_PASSWORD=""

LG_USER="lg"
LG_HOME="/home/lg"

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


# =============================================================================
# LOAD LIBRARY SCRIPTS
# =============================================================================
 
load_script(){
  source lib/compat.sh
  source lib/network.sh
  source lib/display.sh
  source lib/desktop.sh
  USER_IP="$NODE_IP"
}

# =============================================================================
# READ MACHINE ID
# =============================================================================
 
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

# =============================================================================
# PRINT CONFIGURATION SUMMARY
# =============================================================================
 

print_configuration(){
  cat << EOM

Liquid Galaxy will be installed with the following configuration:

IS THIS MACHINE THE MASTER : $IS_MASTER
LOCAL_USER                 : $USER_USERNAME
USER_HOME_DIR              : $USER_HOME_DIR
MACHINE_ID                 : $MACHINE_ID
MACHINE_NAME               : $MACHINE_NAME
TOTAL_MACHINES             : $TOTAL_MACHINES
LG_FRAMES                  : $LG_FRAMES
OCTET (UNIQUE NUMBER)      : $OCTET
GITHUB_REPO_URL            : $GITHUB_REPO_URL
EARTH_FOLDER               : $GOOGLE_EARTH_DIR
NETWORK_INTERFACE          : $NETWORK_INTERFACE
NETWORK_MAC_ADDRESS        : $NETWORK_INTERFACE_MAC

Is it correct? Press any key to continue or CTRL-C to exit

EOM

  read
}

# =============================================================================
# USER MANAGEMENT
# NOT USED YET
# =============================================================================
 
check_lg_user() {
    local username
    username=$(cut -d: -f1 /etc/passwd | grep -w "lg" || true)
    if [[ -z "$username" ]]; then
        echo ">>> Creating lg user..."
        create_lg_user
    else
        echo ">>> lg user already exists, SWITCH"
    fi
}
 
create_lg_user() {
    sudo useradd lg -m -s /bin/bash -c "Liquid Galaxy System User"
}

# =============================================================================
# CHROMIUM CONFIGURATION
# =============================================================================
configure_chromium(){
  # I need to register it in database to be able to set it 
  sudo update-alternatives --install /usr/bin/x-www-browser x-www-browser /snap/bin/chromium 60
  sudo update-alternatives --install /usr/bin/gnome-www-browser gnome-www-browser /snap/bin/chromium 60
  sudo update-alternatives --set x-www-browser /snap/bin/chromium
  sudo update-alternatives --set gnome-www-browser /snap/bin/chromium
  sudo apt-get remove --purge -yq update-notifier*
}


setup_display_desktop(){

  # Install display manager(lightdm) and window manager(openbox)
  sudo apt install -y lightdm openbox unclutter-xfixes feh

  # disable current display manager (gdm3) and enable lightdm
  sudo systemctl disable gdm3 || true
  sudo systemctl enable lightdm || true

  # Set LightDM as the default display manager
  echo "/usr/sbin/lightdm" | sudo tee /etc/X11/default-display-manager > /dev/null

  # Configure LightDM: autologin as lg, use openbox X11 session
  sudo tee /etc/lightdm/lightdm.conf > /dev/null << 'EOF'
# /etc/lightdm/lightdm.conf - Liquid Galaxy display configuration
[LightDM]

[Seat:*]
user-session=openbox
autologin-user=lg
autologin-user-timeout=0
autologin-session=openbox
EOF

  # Set lg user session preference
  cat > $LG_HOME/.dmrc << 'EOF'
[Desktop]
Session=openbox
EOF
  sudo chown lg:lg $LG_HOME/.dmrc            
  

  mkdir -p $LG_HOME/.config/openbox
  chmod 755 $LG_HOME/.config/openbox
  touch $LG_HOME/.config/openbox/autostart
  

  cat > $LG_HOME/.config/openbox/autostart << 'EOF'
# Liquid Galaxy Openbox autostart
# Runs as lg user every time Openbox starts
 
# Load X resources
xrdb -merge ~/.Xresources &
 
# Hide cursor when idle
unclutter --idle 7 --jitter 6 --root &
 
# Compositor - prevents screen tearing, enables shadows
picom --daemon &
 
# Set blue background (no wallpaper on display nodes)
feh --bg-solid "#0000FF" &
 
EOF

  sudo chown -R lg:lg $LG_HOME/.config/openbox
  chmod 644 $LG_HOME/.config/openbox/autostart
  
  # Install picom compositor for modern window rendering
  sudo apt install -y picom

  # Create GTK theme configuration so apps look modern
  mkdir -p $LG_HOME/.config/gtk-3.0
  mkdir -p $LG_HOME/.config/gtk-4.0
 
  cat > $LG_HOME/.config/gtk-3.0/settings.ini << 'EOF'
[Settings]
gtk-theme-name=Yaru
gtk-icon-theme-name=Yaru
gtk-font-name=Ubuntu 11
gtk-cursor-theme-name=Yaru
gtk-xft-antialias=1
gtk-xft-hinting=1
gtk-xft-hintstyle=hintfull
EOF
 
  cat > $LG_HOME/.config/gtk-4.0/settings.ini << 'EOF'
[Settings]
gtk-theme-name=Yaru
gtk-icon-theme-name=Yaru
gtk-font-name=Ubuntu 11
gtk-cursor-theme-name=Yaru
EOF
 
  chown -R lg:lg $LG_HOME/.config/gtk-3.0
  chown -R lg:lg $LG_HOME/.config/gtk-4.0

  # run installation phase two automatically after reboot
  register_phase2

  echo ">>> Display setup DONE. Rebooting in 5 seconds..."
  sleep 5
  reboot
}


register_phase2(){

  # Save all variables needed by phase 2 to a state file
  STATE_FILE="/etc/lg-install-state.env"  
  sudo tee "$STATE_FILE" > /dev/null << EOF
IS_MASTER=$IS_MASTER
MASTER_IP=$MASTER_IP
MASTER_PASSWORD=$MASTER_PASSWORD
USER_USERNAME=$USER_USERNAME
USER_HOME_DIR=$USER_HOME_DIR
MACHINE_ID=$MACHINE_ID
MACHINE_NAME=$MACHINE_NAME
TOTAL_MACHINES=$TOTAL_MACHINES
LG_FRAMES="${LG_FRAMES}"
OCTET=$OCTET
GITHUB_REPO_NAME=$GITHUB_REPO_NAME
GITHUB_REPO_URL=$GITHUB_REPO_URL
GOOGLE_EARTH_DIR=$GOOGLE_EARTH_DIR
NETWORK_INTERFACE=${NETWORK_INTERFACE:-}
NETWORK_INTERFACE_MAC=${NETWORK_INTERFACE_MAC:-}
EOF
  sudo chmod 600 "$STATE_FILE"


  # Register as systemd one-shot that runs after display manager starts
  sudo tee /etc/systemd/system/lg-install-phase2.service > /dev/null << EOF
[Unit]
Description=Liquid Galaxy Installation Phase 2 (runs once after reboot)
After=lightdm.service graphical.target network-online.target
Wants=graphical.target network-online.target
 
[Service]
Type=oneshot
EnvironmentFile=$STATE_FILE    
ExecStart=$LG_HOME/$GITHUB_REPO_NAME/install-phase-two.sh
User=root
StandardOutput=journal
StandardError=journal
TimeoutStartSec=600
RemainAfterExit=no
 
[Install]
WantedBy=graphical.target
EOF
 
  sudo systemctl daemon-reload
  sudo systemctl enable lg-install-phase2.service
  echo ">>> Phase 2 registered - will run automatically after reboot"
}



main(){

  # clone the repo, if there is already the dir I will clone again because I don't know it's corrupted or not without checking the hash so i simply overwrite
  cd ~ 
  rm -rf "$GITHUB_REPO_NAME" || true
  git clone "$GITHUB_REPO_URL"
  cd "$GITHUB_REPO_NAME"

  # to to exit immediately if a command returns a non-zero exit status, instead of continuing to execute the rest of the script
  set -euo pipefail 

  # first check it's compatibile or not 
  bash precheck.sh

  # load all lib scripts 
  load_script

  # Get machine ID from user
  read_machine_id

  if [ "$MACHINE_ID" == "1" ]; then
    IS_MASTER=true
    echo ">>> This machine is the MASTER (lg1)"
    echo "Save the IP ADDRESS of this machine: $USER_IP"
    read -p "Press any key to continue"
  else
    echo ">>> This machine is a SLAVE"
    echo "Make sure Master machine (lg1) is connected to the network before proceding!"
    read -p "Master machine IP (i.e. 192.168.1.42): " MASTER_IP
    read -s -p "Master local user password: " MASTER_PASSWORD
    echo
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
  LG_FRAMES="${array[*]}"
  echo "${array[@]}"


  print_configuration

  export DEBIAN_FRONTEND=noninteractive

  echo ">>> Installing Needed Packages..."
  bash lib/packages.sh

  echo ">>> Installing Google Earth..."
  bash lib/google_earth.sh

  configure_chromium
  
  echo ">>> Configuring desktop settings..."
  setup_display_desktop
  
}

main 