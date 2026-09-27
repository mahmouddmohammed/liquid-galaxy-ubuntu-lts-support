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

# wait for session to fully initialize
echo " Waiting 15 seconds for session to fully initialize..."
sleep 15  

# =============================================================================
# Verify display setup 
# =============================================================================

echo " Verifying display setup..."
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
chmod +x -R "$LG_HOME/earth/scripts/"
# Configure slave KML files
if [ "$IS_MASTER" = "false" ]; then
    sed -i -e "s/slave_x/slave_${MACHINE_ID}/g" \
        "$LG_HOME/earth/kml/slave/myplaces.kml"
    sed -i -e "s/sync_nlc_x/sync_nlc_${MACHINE_ID}/g" \
        "$LG_HOME/earth/kml/slave/myplaces.kml"
fi

# To make google earth react to /tmp/query.txt , ViewSync/send = true, ViewSync/queryFile = /tmp/query.txt
cp /home/lg/earth/config/drivers_template.ini-7.1 /home/lg/earth/config/drivers_template.ini
#bash /home/lg/earth/scripts/write-drivers-ini.sh

# lg is the owner of the file: no need for sudo
#chmod 666 /tmp/query.txt
 
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

chmod +x /home/lg/bin/*
# =============================================================================
# Network configuration 
# =============================================================================

echo " Configuring network..."
 
# Write a minimal netplan file (renderer declaration + MAC-based match so the
# interface rename to eth0 works regardless of what kernel named the NIC).
# This is a safety net; the actual alias IP is set via nmcli below.
cat > /etc/netplan/10-lg-network.yaml << EOF
network:
  version: 2
  renderer: NetworkManager
  ethernets:
    eth0:
      match:
        macaddress: ${NETWORK_INTERFACE_MAC}
      set-name: eth0
      dhcp4: true
      dhcp-identifier: mac
EOF
chmod 600 /etc/netplan/10-lg-network.yaml
 
# Remove conflicting installer netplan files that cause
# "Cannot find unique matching interface" errors (I think maybe it's because of cloning base machine in vbox it creates conflicts)
for f in /etc/netplan/00-installer-config.yaml \
          /etc/netplan/01-network-manager-all.yaml; do
    [ -f "$f" ] && rm -f "$f" && echo "Removed conflicting netplan: $f"
done
 
netplan apply || echo "WARNING: netplan apply had errors (non-fatal, NM manages the interface)"

ACTIVE_CON=""
for i in $(seq 1 30); do
    ACTIVE_CON=$(nmcli -g NAME,DEVICE connection show --active \
        | grep -v ":lo" | head -1 | cut -d: -f1)
    [[ -n "$ACTIVE_CON" ]] && break
    sleep 1
done

if [[ -z "$ACTIVE_CON" ]]; then
    echo "ERROR: No active NM connection found after 30s — cannot set LG alias IP." 
fi

# --- Add the LG alias IP via NetworkManager ---
# This is the IP the race breaker checks for (10.42.<OCTET>.<MACHINE_ID>).
# nmcli modifies the active connection profile persistently.
 
LG_ALIAS_IP="10.42.${OCTET}.${MACHINE_ID}"
LG_ALIAS_CIDR="${LG_ALIAS_IP}/24"
 
ACTIVE_CON=$(nmcli -g NAME,DEVICE connection show --active \
    | grep -v ":lo" | head -1 | cut -d: -f1)
 
if [[ -z "$ACTIVE_CON" ]]; then
    echo "ERROR: No active NM connection found — cannot set LG alias IP."
    echo "       The race breaker will fail (persona-no) until this is fixed."
    echo "       Run after reboot: sudo nmcli connection show --active"
else
    echo "Active NM connection: '$ACTIVE_CON'"
    EXISTING=$(nmcli -g ipv4.addresses connection show "$ACTIVE_CON" 2>/dev/null)
 
    if echo "$EXISTING" | grep -qF "$LG_ALIAS_IP"; then
        echo "Alias IP $LG_ALIAS_IP already in NM profile."
    else
        if [[ -z "$EXISTING" || "$EXISTING" == "--" ]]; then
            NEW_ADDRS="$LG_ALIAS_CIDR"
        else
            NEW_ADDRS="${EXISTING},${LG_ALIAS_CIDR}"
        fi
 
        nmcli connection modify "$ACTIVE_CON" \
            ipv4.addresses "$NEW_ADDRS" \
            ipv4.method auto \
            && echo "Alias IP $LG_ALIAS_CIDR added to NM profile." \
            || echo "WARNING: nmcli modify failed — alias IP not set."
 
        nmcli connection up "$ACTIVE_CON" \
            && echo "NM connection reactivated." \
            || echo "WARNING: nmcli connection up failed."
    fi
 
    # Verify
    if ip addr show | grep -qF "$LG_ALIAS_IP"; then
        echo "Verified: $LG_ALIAS_IP is live."
    else
        echo "WARNING: $LG_ALIAS_IP not yet visible in ip addr (may need reboot)."
    fi
fi
 
# Install NetworkManager dispatcher
chmod 755 /etc/NetworkManager/dispatcher.d/99-liquid-galaxy
chown root:root /etc/NetworkManager/dispatcher.d/99-liquid-galaxy
 
# udev rule to rename interface to eth0 (takes effect on next cold boot)
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
 

# =============================================================================
# Firewall configuration
# =============================================================================
echo "Configuring firewall"
 
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
# Personavars
# =============================================================================
echo "Writing personavars.txt"
 
cat > "$LG_HOME/personavars.txt" << EOF
DHCP_LG_FRAMES="${LG_FRAMES}"
DHCP_LG_FRAMES_MAX=${TOTAL_MACHINES}
 
FRAME_NO=\$(cat /home/lg/frame 2>/dev/null)
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
echo "personavars.txt written. DHCP_OCTET=$(grep DHCP_OCTET $LG_HOME/personavars.txt)"
 
# Run personality script (sets hostname, alias IP, screen/frame files)
echo "Running personality.sh $MACHINE_ID $OCTET ..."
chmod +x "$LG_HOME/bin/personality.sh"
"$LG_HOME/bin/personality.sh" "$MACHINE_ID" "$OCTET" \
    || echo "WARNING: personality.sh exited non-zero — check output above"
 
# =============================================================================
# SSH configuration
# =============================================================================
echo "Configuring SSH"
bash "$REPO_DIR/lib/ssh.sh" \
    || echo "WARNING: ssh.sh exited non-zero"
 
# =============================================================================
# Galaxy systemd service (race breaker)
# =============================================================================
echo "Enabling galaxy.service"
chmod +x /usr/local/sbin/galaxy-race-breaker.sh
systemctl enable galaxy.service \
    || echo "WARNING: galaxy.service not found — install manually"
 
chmod 777 /tmp/
 
# =============================================================================
# Squid configuration
# =============================================================================
# echo "Configuring Squid..."
# SQUID_CONF="/etc/squid/squid.conf"
 
# if [ -f "$SQUID_CONF" ]; then
#     # aufs → ufs (aufs removed in Squid 6)
#     sed -i 's/cache_dir aufs/cache_dir ufs/' "$SQUID_CONF"
#  
#     # remove http_reply_access (directive removed in Squid 6)
#     sed -i '/http_reply_access/d' "$SQUID_CONF"
#  
#     # Verify config parses cleanly
#     echo "Validating squid.conf..."
#     squid -k parse 2>&1 | grep -E "ERROR|FATAL" \
#         && echo "WARNING: squid.conf has errors — check above" \
#         || echo "squid.conf OK"
#  
#     # Rebuild cache dir (required after any config or storage change)
#     systemctl stop squid 2>/dev/null || true
#     rm -rf /var/spool/squid
#     mkdir -p /var/spool/squid
#     chown proxy:proxy /var/spool/squid
#     squid -z
#     systemctl enable squid
#     systemctl start squid \
#         && echo "Squid started successfully." \
#         || echo "WARNING: squid failed to start — check: systemctl status squid"
# else
#     echo "WARNING: $SQUID_CONF not found — squid may not be installed yet"
# fi
 
# =============================================================================
# write-event utility (Space Navigator)
# =============================================================================
echo "Compiling write-event"
gcc -o "$LG_HOME/write-event" \
    "$LG_HOME/$GITHUB_REPO_NAME/input_event/write-event.c" \
    && chmod 755 "$LG_HOME/write-event" \
    || echo "WARNING: write-event compilation failed"
 
# =============================================================================
# Sudoers permissions
# =============================================================================
echo "Setting sudoers permissions"
chmod 440 /etc/sudoers.d/42-lg \
    || echo "WARNING: /etc/sudoers.d/42-lg not found"
chmod 440 /etc/sudoers.d/44-benchmark 2>/dev/null \
    || echo "INFO: /etc/sudoers.d/44-benchmark not present, skipping"
 
# =============================================================================
# Disable AppArmor profile for DHCP client
# =============================================================================
if [ -f /etc/apparmor.d/sbin.dhclient ]; then
    ln -sf /etc/apparmor.d/sbin.dhclient /etc/apparmor.d/disable/ 2>/dev/null || true
    apparmor_parser -R /etc/apparmor.d/sbin.dhclient 2>/dev/null || true
    systemctl restart apparmor 2>/dev/null || true
    echo "AppArmor dhclient profile disabled."
fi
 
# =============================================================================
# uinput permissions
# =============================================================================
chmod 666 /dev/uinput 2>/dev/null || true
 
# =============================================================================
# Web interface (master only)
# =============================================================================
if [ "$IS_MASTER" = "true" ]; then
    echo "Installing web interface (master only)"
    rm -f /var/www/html/index.html
    cp -r "$REPO_DIR/php-interface/." /var/www/html/
    usermod -aG www-data lg # add user "lg" to "www-data" group to have write permissions instead of making it 777 for security reasons
    chown -R www-data:www-data /var/www/html/
    chmod -R 775 /var/www/html/
    systemctl enable apache2
    systemctl start apache2 \
        && echo "Apache started." \
        || echo "WARNING: apache2 failed to start"
fi
 
# =============================================================================
# Fix ownership of entire lg home
# =============================================================================
chown -R lg:lg "$LG_HOME"
chown lg:lg "$LG_HOME/earth/builds/latest/drivers.ini" 2>/dev/null || true
 
# =============================================================================
# Google Earth autostart
# =============================================================================
# bash /home/lg/earth/scripts/write-drivers-ini.sh
sudo -u lg -H bash /home/lg/earth/scripts/write-drivers-ini.sh

# lg is the owner of the file: no need for sudo
chmod 666 /tmp/query.txt

echo "Configuring Google Earth autostart"
echo "bash /home/lg/earth/scripts/launch-earth.sh &" \
    >> /home/lg/.config/openbox/autostart
chown lg:lg /home/lg/.config/openbox/autostart
echo "Earth launch added to openbox autostart."
 
# =============================================================================
# ImageMagick GIF support
# =============================================================================
if [ -f /etc/ImageMagick-6/policy.xml ]; then
    sed -i 's/rights="none" pattern="GIF"/rights="read|write" pattern="GIF"/' \
        /etc/ImageMagick-6/policy.xml
    echo "ImageMagick GIF policy updated."
fi
 
# =============================================================================
# Final verification summary
# =============================================================================
echo "Installation verification"
echo "Hostname        : $(hostname)"
echo "Alias IP live   : $(ip addr show | grep "10.42.${OCTET}." | awk '{print $2}' || echo 'NOT FOUND')"
echo "Squid status    : $(systemctl is-active squid)"
echo "Galaxy service  : $(systemctl is-enabled galaxy.service 2>/dev/null)"
echo "Firewall service: $(systemctl is-enabled lg-firewall.service 2>/dev/null)"
echo "DHCP_OCTET      : $(grep DHCP_OCTET $LG_HOME/personavars.txt)"
 
 
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
