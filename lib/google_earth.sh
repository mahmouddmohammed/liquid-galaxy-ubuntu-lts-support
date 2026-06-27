#!/bin/bash

# Install Google Earth Pro via APT repo (Ubuntu 22.04+ / 26.04 LTS, amd64)

set -euo pipefail

# 1. Dependencies
sudo apt install -y ca-certificates curl gpg xdg-utils

# 2. GPG key 
curl -fsSL https://dl.google.com/linux/linux_signing_key.pub \
  | sudo gpg --dearmor --yes -o /usr/share/keyrings/google-earth.gpg

# 3. APT source in DEB822 format
sudo tee /etc/apt/sources.list.d/google-earth.sources > /dev/null <<EOF
Types: deb
URIs: https://dl.google.com/linux/earth/deb/
Suites: stable
Components: main
Architectures: amd64
Signed-By: /usr/share/keyrings/google-earth.gpg
EOF

# 4. Prevent Google's postinst from re-adding legacy repo entries
sudo tee /etc/default/google-earth-pro > /dev/null <<EOF
repo_add_once="false"
repo_reenable_on_distupgrade="false"
EOF

# 5. Remove legacy repo files if they exist (from old installs or Google's post-installation)
sudo rm -f /etc/apt/sources.list.d/google-earth-pro.list \
           /etc/apt/trusted.gpg.d/google-earth-pro.gpg

# Refresh package lists
sudo apt update

# 6. Install
sudo apt install -y google-earth-pro-stable