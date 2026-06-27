#!/bin/bash

# Runs once after reboot to continue LG installation
# Self-destructs after completion
# This script runs by root

source /etc/lg-install-state.env  # Load state from phase 1
LOGFILE="/var/log/lg-install-phase2.log"
LG_USER="lg"
LG_HOME="/home/lg"
REPO_DIR="$LG_HOME/$GITHUB_REPO_NAME"


exec > >(tee -a "$LOGFILE") 2>&1  # for logging
echo "[Phase 2] Starting...."

export DEBIAN_FRONTEND=noninteractive # this script runs as systemd service (background process), there is no stdin for interactive
# =============================================================================
# Verify display setup 
# =============================================================================
echo " Verifying display setup..."
sleep 15   # wait for session to fully initialize
 
# check display server:x11, display manager: lightdm and window manager: openbox
#SESSION_TYPE=$(su - lg -c 'echo $XDG_SESSION_TYPE')
#SESSION_DESKTOP=$(su - lg -c 'echo $XDG_SESSION_DESKTOP')
SESSION_ID=$(loginctl list-sessions --no-legend | awk '$4=="seat0" {print $1}')
SESSION_TYPE=$(loginctl show-session "$SESSION_ID" -p Type --value)
SESSION_DESKTOP="$(pgrep -x openbox)"
DISPLAY_MANAGER_LIGHTDM="$(systemctl is-active lightdm)"

if [[ "$SESSION_TYPE" == "x11" && "$DISPLAY_MANAGER_LIGHTDM" == "active" && -n $SESSION_DESKTOP ]]; then
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
    "$LG_HOME/earth/builds/latest/googleearth" \
    > /tmp/googleearth.tmp
mv /tmp/googleearth.tmp "$LG_HOME/earth/builds/latest/googleearth"
chmod +x "$LG_HOME/earth/builds/latest/googleearth"

# Configure slave KML files
if [ "$IS_MASTER" = "false" ]; then
    sed -i -e "s/slave_x/slave_${MACHINE_ID}/g" \
        "$LG_HOME/earth/kml/slave/myplaces.kml"
    sed -i -e "s/sync_nlc_x/sync_nlc_${MACHINE_ID}/g" \
        "$LG_HOME/earth/kml/slave/myplaces.kml"
fi
 
# Copy all lg home files /home/lg from repo
cp -r gnu_linux/home/lg/. "$LG_HOME/"
 
# Make files in dotfiles directory hidden files 
# there are files and directories
for file in "$LG_HOME/dotfiles/"*; do
    filename=$(basename "$file")
    mv "$file" "$LG_HOME/dotfiles/.${filename}"
done

# copy /etc and /usr/local/sbin from repo
cp -r gnu_linux/etc/ gnu_linux/usr/ /
 

#chown -R lg:lg "$LG_HOME"

# =============================================================================
# Network configuration 
# =============================================================================

echo " Configuring network..."
 
# Write yml file netplan config for network interfaces
cat > /etc/netplan/10-lg-network.yaml << EOF
network:
  version: 2
  renderer: NetworkManager
  ethernets:
    eth0:
      dhcp4: true
      dhcp-identifier: mac
EOF
chmod 600 /etc/netplan/10-lg-network.yaml
 
# Install NetworkManager dispatcher for LG network events
chmod 755 /etc/NetworkManager/dispatcher.d/99-liquid-galaxy
chown root:root /etc/NetworkManager/dispatcher.d/99-liquid-galaxy
 
# Apply netplan
netplan apply 2>/dev/null || true
 
# udev rule to rename network interface to eth0
# This ensures the interface name is always 'eth0' regardless of hardware
echo "SUBSYSTEM==\"net\",ACTION==\"add\",ATTR{address}==\"${NETWORK_INTERFACE_MAC}\",KERNEL==\"${NETWORK_INTERFACE}\",NAME=\"eth0\"" \
    > /etc/udev/rules.d/10-lg-network.rules
 
# Update /etc/hosts with LG node IPs
sed -i '/10\.42\./d' /etc/hosts

cat >> /etc/hosts << EOF
10.42.${OCTET}.1  lg1
10.42.${OCTET}.2  lg2
10.42.${OCTET}.3  lg3
10.42.${OCTET}.4  lg4
10.42.${OCTET}.5  lg5
10.42.${OCTET}.6  lg6
10.42.${OCTET}.7  lg7
10.42.${OCTET}.8  lg8
EOF
 
# Update /etc/hosts.squid (used by squid for local name resolution)
sed -i '/10\.42\./d' /etc/hosts.squid 2>/dev/null || true
cat >> /etc/hosts.squid << EOF
10.42.${OCTET}.1  lg1
10.42.${OCTET}.2  lg2
10.42.${OCTET}.3  lg3
10.42.${OCTET}.4  lg4
10.42.${OCTET}.5  lg5
10.42.${OCTET}.6  lg6
10.42.${OCTET}.7  lg7
10.42.${OCTET}.8  lg8
EOF

# =============================================================================
# Firewall configuration 
# =============================================================================

echo " Configuring firewall..."
 
# iptables rules file
# These are loaded by lg-firewall.service at boot 
# Uses iptables-nft backend (iptables syntax over nftables kernel)
cat > /etc/iptables.conf << EOF
*filter
:INPUT ACCEPT [0:0]
:FORWARD ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
-A INPUT -i lo -j ACCEPT
-A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT
-A INPUT -p icmp -j ACCEPT
-A INPUT -p tcp -m multiport --dports 22 -j ACCEPT
-A INPUT -s 10.42.0.0/16 -p udp -m udp --dport 161 -j ACCEPT
-A INPUT -s 10.42.0.0/16 -p udp -m udp --dport 3401 -j ACCEPT
-A INPUT -p tcp -m multiport --dports 81,8111,8112 -j ACCEPT
-A INPUT -p udp -m multiport --dports 8113 -j ACCEPT
-A INPUT -s 10.42.${OCTET}.0/24 -p tcp -m multiport --dports 80,3128,3130 -j ACCEPT
-A INPUT -s 10.42.${OCTET}.0/24 -p udp -m multiport --dports 80,3128,3130 -j ACCEPT
-A INPUT -s 10.42.${OCTET}.0/24 -p tcp -m multiport --dports 9335 -j ACCEPT
-A INPUT -s 10.42.${OCTET}.0/24 -d 10.42.${OCTET}.255/32 -p udp -j ACCEPT
-A INPUT -j DROP
-A FORWARD -j DROP
COMMIT
*nat
:PREROUTING ACCEPT [0:0]
:INPUT ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
:POSTROUTING ACCEPT [0:0]
COMMIT
EOF
 
# Install lg-firewall.service (replaces /etc/network/if-pre-up.d/iptables)
cat > /usr/local/sbin/lg-firewall-load.sh << 'EOF'
#!/bin/sh
IPTABLES_CMD=$(which iptables-restore)
IPTABLES_CFG=/etc/iptables.conf
SYSLOG_FACILITY=kern.warning
if [ ! -x "$IPTABLES_CMD" ]; then
    logger -p $SYSLOG_FACILITY "firewall: cannot execute $IPTABLES_CMD"
    exit 1
fi
if [ ! -f "$IPTABLES_CFG" ]; then
    logger -p $SYSLOG_FACILITY "firewall: no config $IPTABLES_CFG"
    exit 1
fi
$IPTABLES_CMD < $IPTABLES_CFG
logger -p $SYSLOG_FACILITY "firewall: rules loaded"
EOF
chmod +x /usr/local/sbin/lg-firewall-load.sh
 
cat > /etc/systemd/system/lg-firewall.service << 'EOF'
[Unit]
Description=Liquid Galaxy Firewall Rules
Before=network-pre.target
Wants=network-pre.target
DefaultDependencies=no
 
[Service]
Type=oneshot
ExecStart=/usr/local/sbin/lg-firewall-load.sh
RemainAfterExit=yes
 
[Install]
WantedBy=multi-user.target
EOF
 
systemctl daemon-reload
systemctl enable lg-firewall.service

# =============================================================================
# Personavars configuration 
# =============================================================================

echo " Writing personavars.txt..."
# I think frame file in home directory is added by another lg script
cat > "$LG_HOME/personavars.txt" << EOF
DHCP_LG_FRAMES="${LG_FRAMES}"
DHCP_LG_FRAMES_MAX=${TOTAL_MACHINES}

FRAME_NO=\$(cat \$LG_HOME/frame 2>/dev/null)
DHCP_LG_SCREEN="\$(( \${FRAME_NO:-0} + 1 ))"
DHCP_LG_SCREEN_COUNT=1
DHCP_OCTET=${OCTET}
DHCP_LG_PHPIFACE="http://lg1:81/"

DHCP_EARTH_PORT=45678
DHCP_EARTH_BUILD="latest"
DHCP_EARTH_QUERY="/tmp/query.txt"

DHCP_MPLAYER_PORT=45680
EOF
chown lg:lg "$LG_HOME/personavars.txt"
 
# Run personality script to set machine-specific values
"$LG_HOME/bin/personality.sh" "$MACHINE_ID" "$OCTET" > /dev/null 2>&1 || true

# =============================================================================
# SSH configuration 
# =============================================================================

echo " Configuring SSH..."

su - lg -c "$REPO_DIR/lib/ssh.sh"
 
# =============================================================================
# Galaxy systemd service 
# =============================================================================
 
echo " Enabling galaxy.service (race breaker)..."
chmod +x /usr/local/sbin/galaxy-race-breaker.sh
systemctl enable galaxy.service 2>/dev/null || \
    echo " WARNING: galaxy.service not found - install manually"
 
# /tmp permissions 
chmod 777 /tmp/

# =============================================================================
# write-event utility of Space Navigator
# =============================================================================

echo " Compiling write-event..."
gcc -o "$LG_HOME/write-event" \
    "$LG_HOME/$GITHUB_REPO_NAME/input_event/write-event.c" 2>/dev/null 
chmod 755 "$LG_HOME/write-event" 2>/dev/null || true

# =============================================================================
# Sudoers permissions 
# =============================================================================

echo " Setting sudoers permissions..."
chmod 440 /etc/sudoers.d/42-lg
chmod 440 /etc/sudoers.d/44-benchmark 2>/dev/null || true

# =============================================================================
# Disables the AppArmor security profile for the DHCP client
# =============================================================================

if [ -f /etc/apparmor.d/sbin.dhclient ]; then
    ln -sf /etc/apparmor.d/sbin.dhclient /etc/apparmor.d/disable/ 2>/dev/null || true
    apparmor_parser -R /etc/apparmor.d/sbin.dhclient 2>/dev/null || true
    systemctl restart apparmor 2>/dev/null || true
fi

# =============================================================================
# uinput device permissions 
# =============================================================================

chmod 666 /dev/uinput 2>/dev/null || true
 
# =============================================================================
# Web interface 
# =============================================================================

if [ "$IS_MASTER" = "true" ]; then
    echo " Installing web interface (master only)..."

    rm -f /var/www/html/index.html
    cp -r "$REPO_DIR/php-interface/." /var/www/html/
    #chown -R lg:lg /var/www/html/
    chown -R www-data:www-data /var/www/html/
    chmod -R 755 /var/www/html/
 
    systemctl enable apache2
    systemctl start apache2
fi
 
# make lg owns everything in lg home, -R: Recursive
chown -R lg:lg "$LG_HOME"
chown lg:lg "$LG_HOME/earth/builds/latest/drivers.ini" 2>/dev/null || true

# =============================================================================
# Google Earth autostart 
# =============================================================================
 
echo "bash /home/lg/earth/scripts/launch-earth.sh &" \
    >> /home/lg/.config/openbox/autostart

chown lg:lg /home/lg/.config/openbox/autostart

# =============================================================================
# Make ImageMagick be able to process GIF files 
# =============================================================================

if [ -f /etc/ImageMagick-6/policy.xml ]; then
    sed -i 's/rights="none" pattern="GIF"/rights="read|write" pattern="GIF"/' \
        /etc/ImageMagick-6/policy.xml
fi
 
# =============================================================================
# Cleanup and Self Destruction
# =============================================================================
echo " Cleaning up..."
apt autoremove -y
rm -f /etc/lg-install-state.env
 
# Self-destruct this service so it never runs again
systemctl disable lg-install-phase2.service
rm -f /etc/systemd/system/lg-install-phase2.service
systemctl daemon-reload
 
echo "[Phase 2] Installation complete"
echo " Log saved to $LOGFILE"
echo " Rebooting in 10 seconds for final boot..."
sleep 10
reboot