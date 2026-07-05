#!/bin/bash
# Liquid Galaxy race breaker - migrated from /etc/init/galaxy.conf pre-start script.
# Called by galaxy.service (systemd) instead of running inline in Upstart.

##Use to Debug
#exec 2>/tmp/galaxy-out
#set -x

ready=no
timeout=1

while [ "$ready" = "no" ] && [ $timeout -le 180 ]; do
    logger -p local3.info "race breaker: timeout = \"$timeout\""
    timeoutsleep=1

    
    # if [ -n "$( pgrep -f 'sbin/squid' )" ] && \
    #    ( wget -q -t 1 -T 6 -O /dev/null --header='Host: www.endpoint.com' \
    #      "http://127.0.0.1/robots.txt" ); then
# 
    #     logger -p local3.info "race breaker: squid-ok"
    #     touch /run/galaxy-squid-ok
# 
    # else
    #     if [ $timeout -ge 30 ]; then
    #         logger -p local3.info "race breaker: squid-restart"
    #         systemctl restart squid &
    #         timeoutsleep=12
    #     fi
    #     timeout=$((${timeout}+${timeoutsleep}))
    #     sleep ${timeoutsleep}
    #     continue
    # fi

    if [ -f /home/lg/personavars.txt ]; then
        OCTET="$( awk -F '=' '/^DHCP_OCTET/ { print $NF }' /home/lg/personavars.txt )"
        
        if ip addr show | grep -qE "inet [0-9]+\.[0-9]+\.${OCTET}\.[0-9]+/"; then
            logger -p local3.info "race breaker: persona-ok"
            touch /run/galaxy-persona-ok
        else
            logger -p local3.info "race breaker: persona-no"
            timeout=$((${timeout}+${timeoutsleep}))
            sleep ${timeoutsleep}
            continue
        fi
    else
        logger -p local3.info "race breaker: personavars.txt missing, skipping persona check"
        ready=yes
        logger -p local3.info "race breaker: galaxy-ok (persona check skipped)"
        touch /run/galaxy-ok
        break
    fi

    ready=yes
    logger -p local3.info "race breaker: galaxy-ok"
    touch /run/galaxy-ok
    # galaxy.service exits 0 here -> RemainAfterExit=yes marks it active
    # display-manager.service (After=galaxy.service) will then start
done

if [ "$ready" = "no" ]; then
    logger -p local3.err "race breaker: timed out after 180s - galaxy NOT ready"
    exit 1
fi