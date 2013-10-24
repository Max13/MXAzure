#!/bin/bash
#
# General installation script
#
# 1) Change Hostname: Ask for it or $1
# 2) Create users and public keys
# 3) Lock root
# 4) Set sshd_config/PermitRootLogin to withoutpassword
# 5) END OK

DRY_RUN=1
VERBOSE=1
Z=

LAST_ERROR=
HOSTNAME="`hostname`"
SUDO="`which sudo`"
SUDOERS=("max13")
SUDOERS_FILE="/etc/sudoers"
SYS_USERS=(`cat "/etc/passwd" | cut -d: -f1 | tr "\n" " "`)
PUB_KEYS=("http://pastebin.com/raw.php?i=qxWwwmgW")
SSHD_CONF="/etc/ssh/sshd_config"
APT_FILE="/etc/apt/sources.list.d/MariaDB.list"
APT_CONT="# MariaDB 5.5 repository list - created `date "+%Y-%m-%d %H:%M"`\n# http://mariadb.org/mariadb/repositories/\ndeb http://ftp.igh.cnrs.fr/pub/mariadb/repo/5.5/ubuntu raring main\ndeb-src http://ftp.igh.cnrs.fr/pub/mariadb/repo/5.5/ubuntu raring main"

# Help
if [ "$1" == "-h" ] || [ "$1" == "--help" ]; then
    echo "Usage: `basename $0` [-h | --help] [hostname]"
    echo
    exit 0
fi
# ---

# Functions definitions
end_script() { # (string error)
    [ -n "$VERBOSE" ] && echo -e "\nLast error: $1"

    if [ -z $2 ]; then
        exit $LINENO
    else
        exit $2
    fi
}

set_hostname() { # (string hostname)
    [ -z "$1" ] && end_script "No hostname given." $LINENO

    echo -n "."
    host "$1" > /dev/null 2>&1 || end_script "$1: ($?) Seems to be a wrong hostname."  $LINENO
    
    echo -n "."
    [ -z "$DRY_RUN" ] && hostname "$1" > /dev/null 2>&1 && [ "`hostname`" != "$1" ] && end_script "Can't set hostname"  $LINENO

    echo -n "."
    [ -z "$DRY_RUN" ] && [ -w "/etc/hostname" ] && echo "$1" > "/etc/hostname"

    echo -n " "
    return 0
}

new_user_as_sudo() { # (string username, string pubkey-url)
    ( [ -z "$1" ] || [ -z "$2" ] ) && end_script "Missing username or pubkey URL"  $LINENO

    # Find and add user
    echo -n "- $1: ."
    echo "${SYS_USERS[@]}" | grep "$1" > /dev/null 2>&1
    if [ $? != 0 ]; then
        if [ -z "$DRY_RUN" ]; then
            useradd -G "sudo" -m -U "$1" > /dev/null 2>&1
        else
            true
        fi
    fi
    Z=$?
    [ $Z != 0 ] && end_script "($Z) Can't create user"  $LINENO
    unset z
    # ---

    # Add user in sudo group
    echo -n "."
    if [ -z "$DRY_RUN" ]; then
        usermod -G "sudo" -a "$SUDOERS[$i]" > /dev/null 2>&1
    else
        true
    fi
    Z=$?
    [ $Z != 0 ] && end_script "($Z) Can't add user in sudo group"  $LINENO
    # ---

    # Create user and root .ssh directories
    echo -n "."
    if [ -z "$DRY_RUN" ]; then
        sudo -u "$1" mkdir -p "/home/$1/.ssh"
    else
        true
    fi
    [ $? != 0 ] && end_script "Can't create user .ssh dir"

    echo -n "."
    if [ -z "$DRY_RUN" ]; then
        mkdir -p "$HOME/.ssh"
    else
        true
    fi
    [ $? != 0 ] && end_script "Can't create root .ssh dir"
    # ---

    # Create user and root authorized file
    echo -n "."
    if [ -z "$DRY_RUN" ]; then
        sudo -u "$1" touch -p "/home/$1/.ssh/authorized_keys2"
    else
        true
    fi
    [ $? != 0 ] && end_script "Can't touch user authorized_keys2 file"

    echo -n "."
    if [ -z "$DRY_RUN" ]; then
        touch -p "$HOME/.ssh/authorized_keys2"
    else
        true
    fi
    [ $? != 0 ] && end_script "Can't touch root authorized_keys2 file"
    # ---

    # Download and write pub key
    echo -n "."
    if [ -z "$DRY_RUN" ]; then
        Z=$(tempfile) || end_script "($?) Can't create tempfile" $LINENO
        wget -qO- "$2" > "$Z" || end_script "($?) Can't download pub key" $LINENO
        ssh-keygen -l -f "$Z" > /dev/null 2>&1 || rm "$Z" || end_script "($?) Not a valid pub key" $LINENO

        echo -n "."
        grep "`cat \"$Z\" | sed 's/^[ ]//g' | sed 's/[ ]$//g'`" "/home/$1/.ssh/authorized_keys2" /dev/null 2>&1
        if [ $? != 0 ]; then
            echo -e "\n`cat \"$Z\"`\n" >> "/home/$1/.ssh/authorized_keys2" || end_script "($?) Can't append public key in user auth file" $LINENO
        fi

        echo -n "."
        grep "`cat \"$Z\" | sed 's/^[ ]//g' | sed 's/[ ]$//g'`" "$HOME/.ssh/authorized_keys2" /dev/null 2>&1
        if [ $? != 0 ]; then
            echo -e "\n`cat \"$Z\"`\n" >> "$HOME/.ssh/authorized_keys2" || end_script "($?) Can't append public key in root auth file" $LINENO
        fi
    fi
    # ---

    echo -n " "
    return 0
}
# ---

# Check if root
# if [ "`whoami`" != "root" ]; then
#     echo "This script must be run as root (or with 'sudo')"
#     exit $LINENO
# fi
# ---

# Check if sudo and wget exists
if [ -z "$SUDO" ] || [ -z "`which wget`" ] || [ -z "$HOME" ]; then
    echo -e "This script requires your system to have 'sudo' and 'wget',\nplease install them."
    exit $LINENO
fi
# ---

# Hostname
if [ -z "$1" ]; then
    echo -en "Enter the desired hostname (FQDN)\nwithout trailing dot [$HOSTNAME]: "
    read host
else
    host=$1
fi
echo -n "Hostname: "
set_hostname $host
[ $? == 0 ] && echo "OK" || echo "KO"
# ---

# Create users
echo "Creating users as sudoers:"
for (( i=0; i<${#SUDOERS[@]}; i++ )); do
    new_user_as_sudo "${SUDOERS[$i]}" "${PUB_KEYS[$i]}"
    [ $? == 0 ] && echo "OK" || echo "KO"
done
# ---

# Lock root
echo -n "Locking root account: "
echo -n "."
if [ -z "$DRY_RUN" ]; then
    usermod -L "root" > /dev/null 2>&1
else
    true
fi
Z=$?
[ $Z == 0 ] || end_script "($Z) Can't lock root" $LINENO
echo " OK"
# ---

# Set PermitRootLogin to "without-password"
echo -n "Allowing root login with pubkey only: "
echo -n "."
if [ -z "$DRY_RUN" ]; then
    Z=`tempfile` > /dev/null 2>&1 || end_script "($?) Can't create temp file for root login" $LINENO
    echo -n "."
    cp "$SSHD_CONF" "$Z" > /dev/null 2>&1 || end_script "($?) Can't copy temp file for root login" $LINENO
    echo -n "."
    cat "$Z" | sed "s/PermitRootLogin.*$/PermitRootLogin\twithout-password/" | sed "s/PubkeyAuthentication.*/PubkeyAuthentication\tyes/" > "$SSHD_CONF"
    echo -n "."
else
    true
fi
[ $? != 0 ] && end_script "($?) Can't rewrite sshd_config file" $LINENO
echo " OK"
# ---

echo "FINISHED !"
exit 0