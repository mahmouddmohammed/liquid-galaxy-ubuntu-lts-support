#!/bin/bash
# =============================================================================
# Liquid Galaxy - NetworkManager Dispatcher Script
# =============================================================================
# Replaces: dhclient-script-nm (legacy ISC dhclient hook)
#
# HOW IT WORKS:
#   NetworkManager calls this script automatically on every network event.
#   It receives two arguments:
#     $1 = interface name  (e.g. eth0, enp3s0)
#     $2 = action          (up, down, dhcp4-change, dhcp6-change, hostname...)
#
#   NM also pre-populates environment variables with all DHCP/IP info:
#     IP4_ADDRESS_0       = "192.168.1.10/24 192.168.1.1"
#     IP4_GATEWAY         = "192.168.1.1"
#     IP4_NAMESERVERS     = "8.8.8.8 8.8.4.4"
#     IP4_DOMAINS         = "liquidgalaxy.local"
#     DHCP4_HOST_NAME     = "lg2"
#     DHCP4_SUBNET_MASK   = "255.255.255.0"
#     IP6_ADDRESS_0, IP6_NAMESERVERS, DHCP6_* ... (same pattern for IPv6)
#
# NO dhclient needed. NM handles IP assignment, routing, DNS natively.
# =============================================================================

INTERFACE="$1"
ACTION="$2"

# -----------------------------------------------------------------------------
# Logging helper — writes to systemd journal (view with: journalctl -t lg-dispatcher)
# -----------------------------------------------------------------------------
log() {
    local level="$1"
    shift
    echo "$*" | systemd-cat -t lg-dispatcher -p "$level" 2>/dev/null \
        || logger -p "daemon.${level}" "lg-dispatcher: $*"
}

log info "Event received: interface=${INTERFACE} action=${ACTION}"

# -----------------------------------------------------------------------------
# Only act on the physical LAN interface — skip loopback, VPN, etc.
# Edit LG_IFACE if your LAN interface has a different name.
# You can also set it to "*" to match all interfaces.
# -----------------------------------------------------------------------------
LG_IFACE="${LG_IFACE:-*}"   # default: handle all interfaces
                              # override: LG_IFACE=eth0 in /etc/environment

if [ "$LG_IFACE" != "*" ] && [ "$INTERFACE" != "$LG_IFACE" ]; then
    log debug "Ignoring interface ${INTERFACE} (not LG_IFACE=${LG_IFACE})"
    exit 0
fi

# =============================================================================
# HELPER: Set hostname from DHCP
# NM sets DHCP4_HOST_NAME env var automatically when DHCP server provides it.
# In Liquid Galaxy, the DHCP server assigns each node its identity:
#   lg1, lg2, lg3 ... based on MAC address reservations.
# =============================================================================
set_lg_hostname() {
    local new_hostname="${DHCP4_HOST_NAME}"

    if [ -z "$new_hostname" ]; then
        log info "No DHCP hostname provided, skipping hostname update"
        return 0
    fi

    local current_hostname
    current_hostname=$(hostname 2>/dev/null)

    if [ "$current_hostname" = "$new_hostname" ]; then
        log info "Hostname already set to ${new_hostname}, no change needed"
        return 0
    fi

    # Set the running hostname
    hostname "$new_hostname"

    # Persist it across reboots
    echo "$new_hostname" > /etc/hostname

    # Update /etc/hosts to avoid 'unable to resolve host' warnings
    if grep -q "^127\.0\.1\.1" /etc/hosts; then
        sed -i "s/^127\.0\.1\.1.*/127.0.1.1\t${new_hostname}/" /etc/hosts
    else
        echo "127.0.1.1	${new_hostname}" >> /etc/hosts
    fi

    log info "Hostname set to: ${new_hostname}"
}

# =============================================================================
# HELPER: Configure DNS via resolvectl (systemd-resolved native API)
# NetworkManager already handles basic DNS — this function adds
# Liquid Galaxy specific domain search entries on top.
# =============================================================================
set_lg_dns() {
    if ! command -v resolvectl >/dev/null 2>&1; then
        log warning "resolvectl not found, skipping DNS config"
        return 0
    fi

    # Add liquidgalaxy.local to search domains so nodes find each other
    # by short name (lg1, lg2) rather than lg1.liquidgalaxy.local
    local search_domains="${IP4_DOMAINS} liquidgalaxy.local"

    resolvectl domain "${INTERFACE}" ${search_domains} 2>/dev/null \
        && log info "DNS search domains set: ${search_domains}" \
        || log warning "resolvectl domain failed for ${INTERFACE}"

    # Apply nameservers from DHCP if provided
    if [ -n "$IP4_NAMESERVERS" ]; then
        resolvectl dns "${INTERFACE}" ${IP4_NAMESERVERS} 2>/dev/null \
            && log info "DNS nameservers set: ${IP4_NAMESERVERS}" \
            || log warning "resolvectl dns failed for ${INTERFACE}"
    fi

    # Same for IPv6
    if [ -n "$IP6_NAMESERVERS" ]; then
        resolvectl dns "${INTERFACE}" ${IP6_NAMESERVERS} 2>/dev/null \
            && log info "IPv6 DNS nameservers set: ${IP6_NAMESERVERS}" \
            || log warning "resolvectl dns (v6) failed for ${INTERFACE}"
    fi
}

# =============================================================================
# HELPER: Log full network info for debugging Liquid Galaxy node identity
# =============================================================================
log_node_identity() {
    log info "--- Liquid Galaxy Node Identity ---"
    log info "  Interface : ${INTERFACE}"
    log info "  IP Address: ${IP4_ADDRESS_0}"
    log info "  Gateway   : ${IP4_GATEWAY}"
    log info "  Hostname  : $(hostname)"
    log info "  DHCP Name : ${DHCP4_HOST_NAME}"
    log info "  DNS       : ${IP4_NAMESERVERS}"
    log info "-----------------------------------"
}

# =============================================================================
# HELPER: Revert DNS when interface goes down
# =============================================================================
revert_lg_dns() {
    if command -v resolvectl >/dev/null 2>&1; then
        resolvectl revert "${INTERFACE}" 2>/dev/null \
            && log info "DNS reverted for ${INTERFACE}" \
            || log warning "resolvectl revert failed for ${INTERFACE}"
    fi
}

# =============================================================================
# MAIN EVENT DISPATCHER
# Maps NetworkManager events to Liquid Galaxy actions.
# NM already handles: IP assignment, routing, basic DNS.
# We only add what LG needs on top.
# =============================================================================

# Actions can be "up", "dhcp4-change", "dhcp6-change", "down" , "pre-down", "hostname", "connectivity change"
case "$ACTION" in

    # -------------------------------------------------------------------------
    # Interface came UP with a full IP address assigned
    # -------------------------------------------------------------------------
    up)
        log info "Interface ${INTERFACE} is UP"
        set_lg_hostname
        set_lg_dns
        log_node_identity
        ;;

    # -------------------------------------------------------------------------
    # DHCP lease renewed or rebound — IP/DNS may have changed
    # -------------------------------------------------------------------------
    dhcp4-change)
        log info "DHCPv4 lease changed on ${INTERFACE}"
        set_lg_hostname
        set_lg_dns
        ;;

    # -------------------------------------------------------------------------
    # DHCPv6 lease changed
    # -------------------------------------------------------------------------
    dhcp6-change)
        log info "DHCPv6 lease changed on ${INTERFACE}"
        # Apply IPv6 DNS
        if [ -n "$IP6_NAMESERVERS" ] && command -v resolvectl >/dev/null 2>&1; then
            resolvectl dns "${INTERFACE}" ${IP6_NAMESERVERS} 2>/dev/null
        fi
        ;;

    # -------------------------------------------------------------------------
    # Interface going DOWN — clean up DNS entries
    # -------------------------------------------------------------------------
    down|pre-down)
        log info "Interface ${INTERFACE} is going DOWN"
        revert_lg_dns
        ;;

    # -------------------------------------------------------------------------
    # Hostname changed event (NM notifies when hostname is updated)
    # -------------------------------------------------------------------------
    hostname)
        log info "System hostname changed to: $(hostname)"
        ;;

    # -------------------------------------------------------------------------
    # Connectivity state changed (online/offline detection)
    # -------------------------------------------------------------------------
    connectivity-change)
        log info "Connectivity changed: ${CONNECTIVITY_STATE}"
        ;;

    *)
        # All other events (vpn-up, vpn-down, etc.) — nothing to do
        log debug "Unhandled action: ${ACTION} on ${INTERFACE}"
        ;;

esac

exit 0