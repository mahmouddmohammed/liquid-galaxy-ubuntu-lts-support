#!/bin/bash

# x11 | wayland
get_display_server(){
    echo "$XDG_SESSION_TYPE"
}

# lightdm | gdm3
get_display_manager(){
    echo "$(cat /etc/X11/default-display-manager | cut -f 4 -d "/")"
}

# gnome | kde | xfce
get_desktop_environment(){
    echo "$XDG_CURRENT_DESKTOP"
}