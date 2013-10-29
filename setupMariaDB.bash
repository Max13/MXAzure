#!/bin/bash
#
# MariaDB installation script
#
# 0) Sanity setup check
# 1) Determine Aptitude or Yum directory
# 2) Add Maria DB GPG Key
# 3) Create MariaDB file in repo man directory
# 4) REPO update
# 5) Print package names
# 6) END OK

DRY_RUN=1
LAST_ERROR=
VERBOSE=1
Z=

SETUP_FILE=".MXGeneralSetup"
HOSTNAME="`hostname`"
SUDO="`which sudo`"
SUDOERS=("max13")
SUDOERS_FILE="/etc/sudoers"
SYS_USERS=(`cat "/etc/passwd" | cut -d: -f1 | tr "\n" " "`)
PUB_KEYS=("http://pastebin.com/raw.php?i=qxWwwmgW")
SSHD_CONF="/etc/ssh/sshd_config"
#APT_FILE="/etc/apt/sources.list.d/MariaDB.list"
#APT_CONT="# MariaDB 5.5 repository list - created `date "+%Y-%m-%d %H:%M"`\n# http://mariadb.org/mariadb/repositories/\ndeb http://ftp.igh.cnrs.fr/pub/mariadb/repo/5.5/ubuntu raring main\ndeb-src http://ftp.igh.cnrs.fr/pub/mariadb/repo/5.5/ubuntu raring main"

# Help
if [ "$1" == "-h" ] || [ "$1" == "--help" ]; then
    echo "Usage: `basename $0` [-h | --help] [hostname]"
    echo
    exit 0
fi
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
            echo -e "$LAST_ERROR"
        else
            echo -e "$1"
        fi
    fi

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

    # Check env
    [ -z "$HOME" ] && LAST_ERROR="Missing '$HOME' env variable." && return $LINENO
    [ -z "`which sudo`" ] && LAST_ERROR="Missing sudo excecutable,\nmake sure it's installed." && return $LINENO
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
        if [ ! -s "$HOME/$SETUP_FILE" ]; then
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
    unset Z
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
    [ -z "$host" ] && host=$HOSTNAME
    echo
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
write_finished_file || end_script $LAST_ERROR $LINENO
echo " OK"
# ---

echo "Server correctly set-up, congratulations !"
exit 0