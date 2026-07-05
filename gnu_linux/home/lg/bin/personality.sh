#!/bin/bash
# Copyright 2010 Google Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# personality.sh - Sets machine identity for a Liquid Galaxy node.
# Rewritten for Ubuntu 24/26 LTS: uses nmcli instead of ifupdown aliases,
# which no longer work under NetworkManager.
#
# Usage: personality.sh <machine_id> [octet]
#   machine_id : 1..8  (1 = master/lg1)
#   octet      : third IP octet, default 42  → LG subnet 10.42.<octet>.0/24

if [[ $UID -ne 0 ]]; then
    echo "You must run this as root."
    exit 1
fi

SCREEN=$1
TUPLE=${2:-42}

if [[ -z "$SCREEN" ]] || [[ ! "$SCREEN" =~ ^[0-9]+$ ]] || \
   [[ $SCREEN -lt 1 ]] || [[ $SCREEN -gt 8 ]]; then
    echo "Invalid or missing screen number: '$SCREEN'"
    echo "Please choose a number 1..8"
    exit 2
fi

if [[ -z "$TUPLE" ]]; then
    echo "No octet specified, using default 42 → 10.42.42.0/24"
    TUPLE=42
fi

LG_ALIAS_IP="10.42.${TUPLE}.${SCREEN}"
LG_ALIAS_CIDR="${LG_ALIAS_IP}/24"

# =============================================================================
# 1. Set hostname
# =============================================================================
hostnamectl set-hostname "lg${SCREEN}"
echo "Hostname set to: lg${SCREEN}"

# =============================================================================
# 2. Add the LG alias IP via NetworkManager (replaces old ifupdown eth0:0 alias)
#
# WHY: The old code wrote /etc/network/if-up.d/<octet>-lg_alias which ran
# "ifconfig eth0:0 10.42.x.y". That mechanism only works with ifupdown.
# On Ubuntu 24/26, NetworkManager manages interfaces and never calls if-up.d
# scripts. The alias IP was silently never applied → race breaker persona-no.
#
# HOW: nmcli modifies the active NM connection profile directly. NM saves it
# to /etc/NetworkManager/system-connections/ and re-applies it every boot.
# No interface rename or reboot needed — takes effect immediately.
# =============================================================================

# Find the active NM connection on the first non-loopback interface
ACTIVE_CON=$(nmcli -g NAME,DEVICE connection show --active \
    | grep -v ":lo" | head -1 | cut -d: -f1)

if [[ -z "$ACTIVE_CON" ]]; then
    echo "ERROR: No active NetworkManager connection found."
    echo "Cannot set LG alias IP. Check: nmcli connection show --active"
    exit 1
fi

echo "Active NM connection: '$ACTIVE_CON'"
echo "Adding LG alias IP: $LG_ALIAS_CIDR"

# Read existing addresses on the profile so we don't wipe them
EXISTING=$(nmcli -g ipv4.addresses connection show "$ACTIVE_CON" 2>/dev/null)

# Check if the alias IP is already there (idempotent)
if echo "$EXISTING" | grep -qF "$LG_ALIAS_IP"; then
    echo "Alias IP $LG_ALIAS_IP already present in profile, skipping add."
else
    # Build new address list: keep existing + add the LG alias
    if [[ -z "$EXISTING" || "$EXISTING" == "--" ]]; then
        NEW_ADDRS="$LG_ALIAS_CIDR"
    else
        # nmcli accepts comma-separated list
        NEW_ADDRS="${EXISTING},${LG_ALIAS_CIDR}"
    fi

    nmcli connection modify "$ACTIVE_CON" \
        ipv4.addresses "$NEW_ADDRS" \
        ipv4.method auto \
        || { echo "ERROR: nmcli modify failed"; exit 1; }

    nmcli connection up "$ACTIVE_CON" \
        || { echo "ERROR: nmcli connection up failed"; exit 1; }

    echo "Alias IP applied successfully."
fi

# Verify
if ip addr show | grep -qF "$LG_ALIAS_IP"; then
    echo "Verified: $LG_ALIAS_IP is live on interface."
else
    echo "WARNING: IP was added to NM profile but not yet visible in ip addr."
    echo "It will appear after the connection is re-activated or on next boot."
fi

# =============================================================================
# 3. Write screen/frame files (used by personavars.txt and Earth launcher)
# =============================================================================
FRAME=$(( SCREEN - 1 ))
echo "$SCREEN" > /home/lg/screen
echo "$FRAME"  > /home/lg/frame
chown lg:lg /home/lg/screen /home/lg/frame
echo "Screen=$SCREEN Frame=$FRAME written to /home/lg/"

# =============================================================================
# 4. Remove legacy ifupdown alias script if present
# =============================================================================
OLD_ALIAS="/etc/network/if-up.d/${TUPLE}-lg_alias"
if [[ -f "$OLD_ALIAS" ]]; then
    rm -f "$OLD_ALIAS"
    echo "Removed legacy ifupdown alias: $OLD_ALIAS"
fi

echo ""
echo "personality.sh complete for lg${SCREEN} (octet=${TUPLE}, IP=${LG_ALIAS_IP})"
echo ""
echo "You may want to verify/update:"
echo "  /etc/hosts"
echo "  /etc/hosts.squid"
echo "  /etc/iptables.conf"
echo "  /etc/ssh/ssh_known_hosts"