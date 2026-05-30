#!/bin/bash 

# Loads all variables in the file
source /etc/os-release


get_distribution_name(){
    echo "$ID"
}

get_distribution_version() {
    echo "$VERSION_ID"
}

is_64_architecture(){
    [[ "$(getconf LONG_BIT)" == "64" ]]
}

is_supported() {
    local distro
    local version
    local supported_versions=("26.04" "24.04")   

    distro=$(get_distribution_name)
    version=$(get_distribution_version)

    
    is_64_architecture || return 1
    [[ "$distro" == "ubuntu" ]] || return 1

    local v
    for v in "${supported_versions[@]}"; do
        [[ "$version" == "$v" ]] && return 0
    done

    return 1
}
