#!/sbin/sh
#
# This file is part of The BiTGApps Project

# Default Permission
umask 022

# Manipulate SELinux State
setenforce 0

# Control and customize installation process
SKIPUNZIP=1

# Set environmental variables in the global environment
export OUTFD="$2"
export TMP="/tmp"
export ASH_STANDALONE=1
export SYSTEM="/system"
export ROOTFS="$SYSTEM"
export UDC="false"

# Detect whether in boot mode
[ -z $BOOTMODE ] && BOOTMODE="false"

# Store Installer Files
if $BOOTMODE; then
  TMP="/dev/tmp"
  install -d $TMP
fi

# Set Installer Source
if [ -f "/data/adb/magisk/busybox" ]; then
  ZIPFILE="/data/user/0/*/cache/flash/install.zip"
elif [ -f "/data/adb/ksu/bin/busybox" ]; then
  ZIPFILE="/data/user/0/*/cache/module.zip"
fi

# Handle Backend Package ID
for f in $ZIPFILE; do
  echo "$f" >> $TMP/ZIPFILE
done

# Extend Globbing Package ID
export ZIPFILE="$(cat $TMP/ZIPFILE)"

# Override Installer Source
$BOOTMODE || export ZIPFILE="$3"

# Extract bundled busybox
unzip -o "$ZIPFILE" "busybox-arm" -d "$TMP"
chmod +x "$TMP/busybox-arm"

# Extract utility script
unzip -o "$ZIPFILE" "util_functions.sh" -d "$TMP"
chmod +x "$TMP/util_functions.sh"

# Extract installer script
unzip -o "$ZIPFILE" "installer.sh" -d "$TMP"
chmod +x "$TMP/installer.sh"

# Execute installer script
exec $TMP/busybox-arm sh "$TMP/installer.sh" "$@"

# Exit
exit "$?"
