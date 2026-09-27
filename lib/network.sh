#!/bin/bash 

NODE_IP=$(ip route | grep "default" | cut -f 9 -d " ")
NETWORK_GATEWAY_ADDR=$(ip route | grep "default" | cut -f 3 -d " ")
NETWORK_INTERFACE=$(ip route | grep "default" | cut -f 5 -d " ")
NETWORK_INTERFACE_MAC=$(ip link show "$NETWORK_INTERFACE" | grep "link/ether" | awk '{print $2}')
