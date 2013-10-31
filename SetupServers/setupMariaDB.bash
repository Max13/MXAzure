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

DRY_RUN=
HOSTNAME=
LSB_RELEASE="`which lsb_release 2>/dev/null`"
USERS=()
VERBOSE=
Z=

SETUP_FILE=".MXMariaDBSetup"
SUPPORTED_OS=("CentOS 5" "CentOS 6" "Debian 6" "Debian 7" "Ubuntu 13")
SUPPORTED_ARCH=("32" "64")
SUPPORTED_MDB=("5.5" "10.0")
APT_FILE="/etc/apt/sources.list.d/MariaDB.list"
APT_CONTENT="# MariaDB %MDB_VERSION% repository list - created on `date "+%Y-%m-%d %H:%M"`\n# http://mariadb.org/mariadb/repositories/\ndeb http://ftp.igh.cnrs.fr/pub/mariadb/repo/%MDB_VERSION%/%MDB_OS_NAME% %MDB_OS_CODENAME% main\ndeb-src http://ftp.igh.cnrs.fr/pub/mariadb/repo/%MDB_VERSION%/%MDB_OS_NAME% %MDB_OS_CODENAME% main"
APT_GPG_CMD="apt-key adv --recv-keys --keyserver keyserver.ubuntu.com 0xcbcb082a1bb943db"
YUM_FILE="/etc/yum.repos.d/MadiaDB.repo"
YUM_CONTENT="# MariaDB %MDB_VERSION% CentOS repository list - created on `date "+%Y-%m-%d %H:%M"`\n# http://mariadb.org/mariadb/repositories/\n[mariadb]\nname = MariaDB\nbaseurl = http://yum.mariadb.org/%MDB_VERSION%/%MDB_OS_NAME%%MDB_OS_VERSION%-%MDB_OS_ARCH%\ngpgkey=https://yum.mariadb.org/RPM-GPG-KEY-MariaDB\ngpgcheck=1"
CURRENT_OS_NAME=
CURRENT_OS_CODENAME=
CURRENT_OS_VERSION=
CURRENT_OS_ARCH=
MDB_VERSION=

# Positionnal parameters
getopts >/dev/null 2>&1
[ $? == 127 ] && echo -e '"getopts" utility required... :/\n' >&2 && exit 1
while getopts ":hlvz" opt; do
    case $opt in
        h)
            echo "Usage: `basename $0` [-hlvz]" >&2
            echo >&2
            echo "  -h      Show this help message" >&2
            echo >&2
            echo "  -l      List supported OS" >&2
            echo >&2
            echo "  -v      Verbose mode"
            echo >&2
            echo "  -z      Dry run mode (No system modification)" >&2
            echo >&2
            exit 1
            ;;
        l)
            echo "Supported OS:"
            for (( i=0, n=${#SUPPORTED_OS[@]}; i<$n; i++ )); do
                echo -e "\t- ${SUPPORTED_OS[$i]}"
            done
            echo
            exit 0
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

init_os_info() {
    CURRENT_OS_ARCH="`getconf LONG_BIT`"
    local LSB_RELEASE="`which lsb_release`"
    local OS_RELEASE_FILE="`ls -1 /etc/*-release 2>/dev/null | head -n1`"
    local OS_COMPLETE_NAME=
    local OS_SUPPORTED=0

    echo -n "."
    if [ -n "$LSB_RELEASE" ]; then          # Debian based ?
        CURRENT_OS_NAME="`$LSB_RELEASE -is`"
        CURRENT_OS_VERSION="`$LSB_RELEASE -rs`"
        CURRENT_OS_CODENAME="`$LSB_RELEASE -cs`"
    elif [ -r "$OS_RELEASE_FILE" ]; then    # Redhat based ?
        local readonly CURRENT_OS_RELEASE="`head -n1 $OS_RELEASE_FILE`"
        CURRENT_OS_NAME="`echo $CURRENT_OS_RELEASE | cut -d' ' -f1`"
        CURRENT_OS_VERSION="`echo $CURRENT_OS_RELEASE | cut -d' ' -f3`"
        unset CURRENT_OS_CODENAME
    else                                    # Not supported >_>'
        LAST_ERROR="Unsupported OS"
        return $LINENO
    fi

    echo -n "."
    for (( i=0, n=${#SUPPORTED_ARCH[@]}; i<$n; i++ )); do
        if [ "${SUPPORTED_ARCH[$i]}" == "$CURRENT_OS_ARCH" ]; then
            OS_SUPPORTED=1
            break
        fi
    done
    [ $OS_SUPPORTED == 0 ] && LAST_ERROR="Arch unsupported" && return $LINENO
    OS_SUPPORTED=0

    echo -n "."
    for (( i=0, n=${#SUPPORTED_OS[@]}; i<$n; i++ )); do
        if [ "${SUPPORTED_OS[$i]}" == "$CURRENT_OS_NAME `echo $CURRENT_OS_VERSION | cut -d. -f1`" ]; then
            OS_SUPPORTED=1
            break
        fi
    done
    [ $OS_SUPPORTED == 0 ] && LAST_ERROR="OS unsupported" && return $LINENO

    CURRENT_OS_NAME=`echo "$CURRENT_OS_NAME" | tr "[:upper:]" "[:lower:]"`

    return 0
}

check_sanity() {
    # Check if root (correct $HOME)
    [ "`whoami`" != "root" ] && LAST_ERROR="This script must be run as root (or with 'sudo -H ...')" && return $LINENO
    # ---

    # Check if already set-up
    if [ -r "$HOME/$SETUP_FILE" ] && [ -s "$HOME/$SETUP_FILE" ]; then
        LAST_ERROR="This server has already been set-up on \"`cat $HOME/$SETUP_FILE`\".\n\tTo force it, please remove the file \"$HOME/$SETUP_FILE\" and restart this script"
        return $LINENO
    fi
    # ---

    # Create clean installation file
    if [ -z "$DRY_RUN" ]; then
        echo -n > "$HOME/$SETUP_FILE" 2>/dev/null
        if [ -s "$HOME/$SETUP_FILE" ]; then
            LAST_ERROR="Can't create installation file..."
            return $LINENO
        fi
    fi
    # ---

    return 0
}

select_maria_version() {
    echo -e "Please select the version of MariaDB\nyou want to install:\n"

    PS3="Choice: "
    select VERSION in ${SUPPORTED_MDB[@]}; do
        [ -n "$VERSION" ] && break
    done
    MDB_VERSION="$VERSION"

    return 0
}

write_repo_file() {
    # Determine Packet Manager
    echo -n "."
    if [ -x "`which apt-get 2>/dev/null`" ]; then
        if [ -z "$DRY_RUN" ]; then
            echo -e "$APT_CONTENT" | sed "s/%MDB_VERSION%/$MDB_VERSION/g" | sed "s/%MDB_OS_NAME%/$CURRENT_OS_NAME/g" | sed "s/%MDB_OS_CODENAME%/$CURRENT_OS_CODENAME/g" > "$APT_FILE"
            [ $? != 0 ] && LAST_ERROR="Can't write APT file" && return $LINENO
            ($APT_GPG_CMD > /dev/null 2>&1) || (LAST_ERROR="Can't add GPG key" && return $LINENO)
            Z="To install MariaDB with apt-get, please check this page:\n\thttps://mariadb.com/kb/en/installing-mariadb-deb-files/#installing-mariadb-with-apt-get\n"
        fi
    elif [ -x "`which yum 2>/dev/null`" ]; then
        if [ -z "$DRY_RUN" ]; then
            local ARCH="`([ \"$ARCH\" == \"32\" ] && echo 'x86') || [ \"$ARCH\" == \"64\" ] && echo 'amd64'`"
            echo -e "$YUM_CONTENT" | sed "s/%MDB_VERSION%/$MDB_VERSION/g" | sed "s/%MDB_OS_NAME%/$CURRENT_OS_NAME/g" | sed "s/%MDB_OS_VERSION%/$(echo \"$CURRENT_OS_VERSION\" | cut -d. -f1)/g" | sed "s/%MDB_OS_ARCH%/$ARCH/g" > "$YUM_FILE"
            [ $? != 0 ] && LAST_ERROR="Can't write YUM file" && return $LINENO
            Z="To install MariaDB with yum, please check this page:\n\thttps://mariadb.com/kb/en/installing-mariadb-with-yum/#installing-mariadb-with-yum\n"
        fi
    else
        LAST_ERROR="Can't find apt-get or yum... Buggy ?"
        return $LINENO
    fi
    # ---

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

# Init OS info
init_os_info || end_script "$LAST_ERROR" $?
# ---

# Select MariaDB Version
select_maria_version
# ---

# Write repo file
write_repo_file || end_script "$LAST_ERROR" $?
# ---

# Create setup finished file
echo -n "Finishing setup: "
echo -n "."
write_finished_file || end_script "$LAST_ERROR" $LINENO
echo " OK"
# ---

echo "MariaDB repositories correctly set-up, congratulations !"
echo -e "$Z"
exit 0