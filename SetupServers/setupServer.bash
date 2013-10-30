#!/bin/bash
#
# General installation script
#
# 0) Sanity setup check
# 1) Change Hostname: Ask for it or $1
# 2) Create users and public keys
# 3) Lock root
# 4) Set sshd_config/PermitRootLogin to withoutpassword
# 5) Create temp file to know general setup as been finished
# 6) END OK

DRY_RUN=
HOSTNAME=
LAST_ERROR=
USERS=()
VERBOSE=
Z=

CURRENT_HOSTNAME="`hostname`"
PUB_KEY="https://raw.github.com/%SUDO_USER%/%SUDO_USER%/master/%SUDO_USER%.pub"
SETUP_FILE=".MXGeneralSetup"
SSHD_CONF="/etc/ssh/sshd_config"
# SUDO="`which sudo`"
# SUDOERS=("max13")
SUDOERS_FILE="/etc/sudoers"
SYS_USERS=(`cat "/etc/passwd" | cut -d: -f1 | tr "\n" " "`)

# Positionnal parameters
getopts >/dev/null 2>&1
[ $? == 127 ]&& echo -e '"getopts" utility required... :/\n' >&2 && exit 1
while getopts ":a:hu:vz" opt; do
    case $opt in
        a)
            HOSTNAME="$OPTARG"
            ;;
        h)
            echo "Usage: `basename $0` -a <hostname> -u <username> [-hz]" >&2
            echo >&2
            echo "  -a <hostname>" >&2
            echo "              Set the hostname instead of prompting it" >&2
            echo
            echo "  -h          Show this help message" >&2
            echo
            echo "  -u <username>" >&2
            echo "              Create user and add to sudoers." >&2
            echo "              This option can be added more than one if multiple users." >&2
            echo "              The public key must be in a Github repo as:" >&2
            echo "              'username/username' as a file named 'username.pub'" >&2
            echo "              (Case sensitive, system username will always be lowercase)" >&2
            echo
            echo "  -v          Verbose mode"
            echo
            echo "  -z          Dry run mode (No system modification)" >&2
            echo
            exit 0
            ;;
        u)
            USERS+=("$OPTARG")
            ;;
        v)
            VERBOSE=1
            ;;
        z)
            DRY_RUN=1
            ;;
        \?)
            echo "Invalid option: -$OPTARG" >&2
            exit 1
            ;;
    esac
done
# ---

# Greetings
echo -n "Hello "
[ -n "$SUDO_USER" ] && echo -n "$SUDO_USER"
echo -e " !\n"
# ---

# Functions definitions
end_script() { # (string error)
    if [ -n "$VERBOSE" ]; then
        echo -en "\n\t" # echo -en "\nLast error: "
        if [ -z "$1" ]; then
            echo -e "$LAST_ERROR" >&2
        else
            echo -e "$1" >&2
        fi
    fi

    echo "Error"

    if [ -z $2 ]; then
        exit $LINENO
    else
        exit $2
    fi
}

check_sanity() {
    # Check if root (correct $HOME)
    [ "`whoami`" != "root" ] && LAST_ERROR="This script must be run as root (or with 'sudo -H ...')" && return $LINENO
    [ -n "$SUDO_USER" ] && [ "$HOME" == "`sudo -Hu \"$SUDO_USER\" env | grep HOME | sed \"s/HOME=//\"`" ] && LAST_ERROR="Wrong \$HOME path\nIt seems you didn't invoke sudo with the \"-H\" option...\nYou silly !" && return $LINENO
    # ---

    # Check parameters presence
    [ -z "$HOSTNAME" ] && LAST_ERROR="You must specify a hostname" && return $LINENO
    [ ${#USERS[@]} == 0 ] && LAST_ERROR="You must specify at one sudoer" && return $LINENO
    # ---

    # Check env
    [ -z "$HOME" ] && LAST_ERROR="Missing '$HOME' env variable." && return $LINENO
    [ -z "`which sudo`" ] && LAST_ERROR="Missing sudo excecutable,\nmake sure it's installed." && return $LINENO
    [ -z "`which wget`" ] && LAST_ERROR="Missing wget excecutable,\nmake sure it's installed." && return $LINENO
    # ---

    # Check if already set-up
    if [ -r "$HOME/$SETUP_FILE" ] && [ -s "$HOME/$SETUP_FILE" ]; then
        LAST_ERROR="This server has already been set-up on \"`cat $HOME/$SETUP_FILE`\".\nTo force it, please remove the file \"$HOME/$SETUP_FILE\" and restart this script"
        return $LINENO
    fi
    # ---

    # Create clean installation file
    if [ -z "$DRY_RUN" ]; then
        echo -n > "$HOME/$SETUP_FILE"
        if [ -s "$HOME/$SETUP_FILE" ]; then
            LAST_ERROR="Can't create installation file..."
            return $LINENO
        fi
    fi
    # ---

    return 0
}

set_hostname() { # (string hostname)
    [ -z "$1" ] && end_script "No hostname given." $LINENO

    echo -n "."
    if [ -z "$DRY_RUN" ]; then
        host "$1" > /dev/null 2>&1 || end_script "$1: ($?) Seems to be a wrong hostname."  $LINENO
    fi
    
    echo -n "."
    [ -z "$DRY_RUN" ] && hostname "$1" > /dev/null 2>&1 && [ "`hostname`" != "$1" ] && end_script "Can't set hostname"  $LINENO

    echo -n "."
    [ -z "$DRY_RUN" ] && [ -w "/etc/hostname" ] && echo "$1" > "/etc/hostname"

    echo -n " "
    return 0
}

new_user_as_sudo() { # (string username)
    ( [ -z "$1" ] || [ -z "$2" ] ) && end_script "Missing username or pubkey URL"  $LINENO

    # Find and add user
    echo -n "- $1: ."
    echo "  ${SYS_USERS[@]}" | grep "$1" > /dev/null 2>&1
    if [ $? != 0 ]; then
        if [ -z "$DRY_RUN" ]; then
            useradd -G "sudo" -m -U "$1" > /dev/null 2>&1
        else
            true
        fi
    fi
    Z=$?
    [ $Z != 0 ] && end_script "($Z) Can't create user"  $LINENO
    unset Z
    # ---

    # Add user in sudo group
    echo -n "."
    if [ -z "$DRY_RUN" ]; then
        usermod -G "sudo" -a "$1" > /dev/null 2>&1
    else
        true
    fi
    Z=$?
    [ $Z != 0 ] && end_script "($Z) Can't add user in sudo group"  $LINENO
    # ---

    # Create user and root .ssh directories
    echo -n "."
    if [ -z "$DRY_RUN" ]; then
        sudo -Hu "$1" mkdir -p "/home/$1/.ssh"
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
        sudo -Hu "$1" touch -p "/home/$1/.ssh/authorized_keys2"
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

write_finished_file() {
    if [ -z "$DRY_RUN" ]; then
        date "+%Y-%m-%d %H:%M" > "$HOME/$SETUP_FILE" 2>&1 || (LAST_ERROR="Can't write in setup file." && return $LINENO)
    fi

    return 0
}
# ---

# Check sanity
check_sanity || end_script "$LAST_ERROR" $?
# ---

# Hostname
echo -n "Setting up hostname: "
set_hostname "$HOSTNAME" && echo "OK" || echo "KO"
# ---

# Create users
echo "Creating users as sudoers:"
for (( i=0; i<${#USERS[@]}; i++ )); do
    new_user_as_sudo "${USERS[$i]}" "`echo \"$PUB_KEY\" | sed \"s/%SUDO_USER%/${USERS[$i]}/g\"`" && echo "OK" || echo "KO"
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
    cat "$Z" | sed "s/PermitRootLogin.*$/PermitRootLogin\twithout-password/g" | sed "s/PubkeyAuthentication.*/PubkeyAuthentication\tyes/g" > "$SSHD_CONF"
    echo -n "."
else
    true
fi
[ $? != 0 ] && end_script "($?) Can't rewrite sshd_config file" $LINENO
echo " OK"
# ---

# Create setup finished file
echo -n "Finishing setup: "
echo -n "."
write_finished_file || end_script "$LAST_ERROR" $LINENO
echo " OK"
# ---

echo -e "Server correctly set-up, congratulations !\n"
exit 0