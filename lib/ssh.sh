#!/bin/bash

# SSH configuration for Liquid Galaxy nodes
# Runs as ROOT, executed directly by install-phase-two.sh

source /etc/lg-install-state.env
LG_USER="lg"
LG_HOME="/home/lg"

configure_ssh() {

    if [ "$IS_MASTER" = "true" ]; then
        echo ">>> Master: generating SSH keys..."

        
        sudo -u "$LG_USER" bash "$LG_HOME/tools/clean-ssh.sh"

        # Prepare SSH files zip for slave nodes to download
        rm -rf /tmp/ssh-files
        mkdir -p /tmp/ssh-files/etc /tmp/ssh-files/root /tmp/ssh-files/user

        # System files - root can read these directly now
        cp -r /etc/ssh /tmp/ssh-files/etc/
        cp -r /root/.ssh /tmp/ssh-files/root/ 2>/dev/null || true
        # lg user's own SSH files 
        cp -r "$LG_HOME/.ssh" /tmp/ssh-files/user/


        cd /tmp && zip -FSr "$LG_HOME/ssh-files.zip" ssh-files
        rm -rf /tmp/ssh-files
        cd - > /dev/null

        # the zip itself must belong to lg, since slaves scp it from lg's home
        chown "$LG_USER:$LG_USER" "$LG_HOME/ssh-files.zip"

    else
        echo ">>> Slave: syncing SSH files from master..."

        sshpass -p "$MASTER_PASSWORD" scp \
            -o StrictHostKeyChecking=no \
            "lg@${MASTER_IP}:/home/lg/ssh-files.zip" \
            "$LG_HOME/"

        # -d: dest
        unzip -o "$LG_HOME/ssh-files.zip" -d /tmp/ssh-unpack/ > /dev/null

        # System files 
        cp -r /tmp/ssh-unpack/ssh-files/etc/ssh /etc/
        cp -r /tmp/ssh-unpack/ssh-files/root/.ssh /root/ 2>/dev/null || true

        # lg user's own SSH files 
        rm -rf "$LG_HOME/.ssh"
        cp -r /tmp/ssh-unpack/ssh-files/user/.ssh "$LG_HOME/"

        rm -rf /tmp/ssh-unpack "$LG_HOME/ssh-files.zip"
    fi

    # lg user's own key permissions 
    chmod 0600 "$LG_HOME/.ssh/lg-id_rsa"      2>/dev/null || true
    chmod 0600 "$LG_HOME/.ssh/authorized_keys" 2>/dev/null || true

    # System files 
    chmod 0600 /root/.ssh/authorized_keys     2>/dev/null || true
    chmod 0600 /etc/ssh/ssh_host_ecdsa_key    2>/dev/null || true
    chmod 0600 /etc/ssh/ssh_host_rsa_key      2>/dev/null || true
    chmod 0600 /etc/ssh/ssh_host_ed25519_key  2>/dev/null || true

    # Create SSH ControlMaster socket directory 
    # create it as lg and set ownership explicitly
    mkdir -p "$LG_HOME/.ssh/ctl"
    chmod 700 "$LG_HOME/.ssh/ctl"

   
    # user's own .ssh directory must stay owned by lg
    chown -R "$LG_USER:$LG_USER" "$LG_HOME/.ssh"

    sed -i \
        's/^#*PermitRootLogin.*/PermitRootLogin prohibit-password/' \
        /etc/ssh/sshd_config
    systemctl restart ssh
}

configure_ssh