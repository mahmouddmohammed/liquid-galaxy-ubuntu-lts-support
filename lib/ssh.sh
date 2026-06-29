#!/bin/bash

# SSH configuration for Liquid Galaxy nodes
# Runs as the calling user (NOT root)
# Requires sudo for system file operations

sudo source /etc/lg-install-state.env
LG_USER="lg"
LG_HOME="/home/lg"

configure_ssh() {
    
    if [ "$IS_MASTER" = "true" ]; then
        echo ">>> Master: generating SSH keys..."

        # clean-ssh.sh manages ~/.ssh which belongs to current user (lg)
        bash "$HOME/tools/clean-ssh.sh"

        # Prepare SSH files zip for slave nodes to download
        rm -rf /tmp/ssh-files
        mkdir -p /tmp/ssh-files/etc /tmp/ssh-files/root /tmp/ssh-files/user

        # System files need sudo
        sudo cp -r /etc/ssh /tmp/ssh-files/etc/
        sudo cp -r /root/.ssh /tmp/ssh-files/root/ 2>/dev/null || true
        # User files - no sudo needed
        cp -r "$HOME/.ssh" /tmp/ssh-files/user/

        # $HOME: /home/lg
        cd /tmp && zip -FSr "$HOME/ssh-files.zip" ssh-files
        rm -rf /tmp/ssh-files
        cd - > /dev/null


    else
        echo ">>> Slave: syncing SSH files from master..."

        sshpass -p "$MASTER_PASSWORD" scp \
            -o StrictHostKeyChecking=no \
            "lg@${MASTER_IP}:/home/lg/ssh-files.zip" \
            "$HOME/"

        # -d: dest
        unzip -o "$HOME/ssh-files.zip" -d /tmp/ssh-unpack/ > /dev/null

        # System files need sudo
        sudo cp -r /tmp/ssh-unpack/ssh-files/etc/ssh /etc/
        sudo cp -r /tmp/ssh-unpack/ssh-files/root/.ssh /root/ 2>/dev/null || true

        # User files - no sudo
        # delete old first
        rm -rf "$HOME/.ssh"
        cp -r /tmp/ssh-unpack/ssh-files/user/.ssh "$HOME/"

        rm -rf /tmp/ssh-unpack "$HOME/ssh-files.zip"
    fi

    # Fix SSH key permissions - user files, no sudo needed
    chmod 0600 "$HOME/.ssh/lg-id_rsa"          2>/dev/null  || true
    chmod 0600 "$HOME/.ssh/authorized_keys"     2>/dev/null || true

    # System files need sudo
    sudo chmod 0600 /root/.ssh/authorized_keys          2>/dev/null || true
    sudo chmod 0600 /etc/ssh/ssh_host_ecdsa_key         2>/dev/null || true
    sudo chmod 0600 /etc/ssh/ssh_host_rsa_key           2>/dev/null || true
    sudo chmod 0600 /etc/ssh/ssh_host_ed25519_key       2>/dev/null || true
    

    # Create SSH ControlMaster socket directory
    mkdir -p "$HOME/.ssh/ctl"
    chmod 700 "$HOME/.ssh/ctl"

    
    chown -R "$(whoami):$(whoami)" "$HOME/.ssh"

    
    sudo sed -i \
        's/^#*PermitRootLogin.*/PermitRootLogin prohibit-password/' \
        /etc/ssh/sshd_config
    sudo systemctl restart ssh

    #echo ">>> SSH configuration complete"
}

configure_ssh