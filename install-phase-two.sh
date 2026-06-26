#!/bin/bash

# Runs once after reboot to continue LG installation
# Self-destructs after completion
# This script runs by root

LOGFILE="/var/log/lg-install-phase2.log"
LG_HOME="/home/lg"
REPO_DIR="$LG_HOME/$GITHUB_REPO_NAME"
source /etc/lg-install-state.env  # Load state from phase 1

exec > >(tee -a "$LOGFILE") 2>&1  # for logging
echo "[Phase 2] Starting...."
 
# =============================================================================
# Verify display setup 
# =============================================================================
echo " Verifying display setup..."
sleep 15   # wait for session to fully initialize
 
# check display server:x11, display manager: lightdm and window manager: openbox
if [[ "$XDG_SESSION_TYPE" == "x11" && \
      "$XDG_SESSION_DESKTOP" == "openbox" ]] && \
      grep -q "lightdm" /etc/X11/default-display-manager; then
    echo " OK: Display stack verified (LightDM + Openbox + X11)"
else
    echo " WARNING: Display issues detected - check $LOGFILE"
    exit 1
fi

# =============================================================================
# Setup Liquid Galaxy files 
# =============================================================================

echo " Setting up Liquid Galaxy files..."
cd "$REPO_DIR" || { echo " FAIL: repo dir not found at $REPO_DIR"; exit 1; }
 
# Copy earth directory to lg home
cp -r earth "$LG_HOME/"
 
# Symlink Google Earth installation
ln -sf "$GOOGLE_EARTH_DIR" "$LG_HOME/earth/builds/latest"
 
# LC_NUMERIC fix into Google Earth launcher to ensure decimal points work correctly in non-US locales
awk '/LD_LIBRARY_PATH/{print "export LC_NUMERIC=en_US.UTF-8"}1' \
    "$LG_HOME/earth/builds/latest/googleearth" | \
    tee "$LG_HOME/earth/builds/latest/googleearth" > /dev/null
 
# Copy all lg home files from repo
cp -r gnu_linux/home/lg/. "$LG_HOME/"
 
# Make files in dotfiles directory hidden files 
# there are files and directories
for file in "$LG_HOME/dotfiles/"*; do
    filename=$(basename "$file")
    mv "$file" "$LG_HOME/dotfiles/.${filename}"
done
 
# Configure slave KML files
if [ "$IS_MASTER" = "false" ]; then
    sed -i -e "s/slave_x/slave_${MACHINE_ID}/g" \
        "$LG_HOME/earth/kml/slave/myplaces.kml"
    sed -i -e "s/sync_nlc_x/sync_nlc_${MACHINE_ID}/g" \
        "$LG_HOME/earth/kml/slave/myplaces.kml"
fi
 
# make lg owns everything in lg home, -R: Recursive
chown -R lg:lg "$LG_HOME"
 
