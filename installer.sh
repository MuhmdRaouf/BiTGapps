# This file is part of The BiTGApps Project

# List of GApps Packages
BITGAPPS="
tar/core/ConfigUpdater.tar.xz
tar/core/Gearhead.tar.xz
tar/core/Dialer.tar.xz
tar/core/GmsCoreSetupPrebuilt.tar.xz
tar/core/GoogleExtServices.tar.xz
tar/core/GoogleLoginService.tar.xz
tar/core/GoogleServicesFramework.tar.xz
tar/core/Phonesky.tar.xz
tar/core/PrebuiltGmsCore.tar.xz
tar/core/Velvet.tar.xz
tar/etc/Calendar.tar.xz
tar/etc/Contacts.tar.xz
tar/etc/Gboard.tar.xz
tar/etc/GoogleCalendarSyncAdapter.tar.xz
tar/etc/GoogleContactsSyncAdapter.tar.xz
tar/etc/GoogleExtShared.tar.xz
tar/etc/Speech.tar.xz
tar/Sysconfig.tar.xz
tar/Default.tar.xz
tar/Permissions.tar.xz
tar/Preferred.tar.xz
tar/overlay/PlayStoreOverlay.tar.xz"

# List of Extra Configs
FRAMEWORK="
tar/framework/DialerPermissions.tar.xz
tar/framework/DialerFramework.tar.xz
tar/framework/MapsPermissions.tar.xz
tar/framework/MapsFramework.tar.xz"

# List of SetupWizard Packages
SETUPWIZARD="
tar/core/GoogleBackupTransport.tar.xz
tar/core/GoogleRestore.tar.xz
tar/core/SetupWizardPrebuilt.tar.xz"

# Control Installation Process
if ksud -V; then KSUD="_update"; fi
KSU="true" && [ -z $KSUD ] && KSU="false"
MODDIR="/data/adb/modules$KSUD/BiTGApps"

# OTA Survival Script
ADDOND="70-bitgapps.sh"
TMPOTA="$TMP/$ADDOND"

# Local Environment
BB="$TMP/busybox-arm"
rm -rf "$TMP/bin"
install -d "$TMP/bin"
for i in $($BB --list); do
  ln -sf "$BB" "$TMP/bin/$i"
done
PATH="$TMP/bin:$PATH"

# Mounted Partitions
mount -o remount,rw,errors=continue / > /dev/null 2>&1
mount -o remount,rw,errors=continue /dev/root > /dev/null 2>&1
mount -o remount,rw,errors=continue /dev/block/dm-0 > /dev/null 2>&1
mount -o remount,rw,errors=continue /system > /dev/null 2>&1
mount -o remount,rw,errors=continue /product > /dev/null 2>&1
mount -o remount,rw,errors=continue /system_ext > /dev/null 2>&1

# Load utility functions
. $TMP/util_functions.sh

# Detect whether in boot mode
[ -z $BOOTMODE ] && ps | grep zygote | grep -qv grep && BOOTMODE=true
[ -z $BOOTMODE ] && ps -A | grep zygote | grep -qv grep && BOOTMODE=true
[ -z $BOOTMODE ] && BOOTMODE=false

# Strip leading directories
if $BOOTMODE; then
  DEST="-f5-"
else
  DEST="-f4-"
fi

# Helper Functions
ui_print() {
  if $BOOTMODE; then
    echo "$1"
  else
    echo -n -e "ui_print $1\n" >> /proc/self/fd/$OUTFD
    echo -n -e "ui_print\n" >> /proc/self/fd/$OUTFD
  fi
}

boot_actions() { $BOOTMODE && rm -rf $MODDIR; }

mk_debug_log() {
  $BOOTMODE && return 255
  NUM="$(( $RANDOM % 100 )).tar.gz"
  LOG="bitgapps_debug_logs_${NUM}"
  tar -czf "$LOG" "$TMP/recovery.log"
  cp -rf "$LOG" "/sdcard/$LOG"
  cp -rf "$LOG" "$SYSTEM/etc/$LOG"
}

is_mounted() {
  grep -q " $(readlink -f $1) " /proc/mounts 2>/dev/null
  return $?
}

setup_mountpoint() {
  test -L $1 && mv -f $1 ${1}_link
  if [ ! -d $1 ]; then
    rm -f $1
    mkdir $1
  fi
}

mount_apex() {
  $BOOTMODE && return 255
  test -d "$SYSTEM/apex" || return 255
  ui_print "- Mounting /apex"
  local apex context dest loop minorx num var
  setup_mountpoint /apex
  mount -t tmpfs tmpfs /apex -o mode=755 && touch /apex/apex
  context=$(cat /proc/self/attr/current)
  echo "u:r:su:s0" >> /proc/self/attr/current
  test -e /dev/block/loop1 && minorx=$(ls -l /dev/block/loop1 | awk '{ print $6 }') || minorx="1"
  num="0"
  for apex in $SYSTEM/apex/*; do
    dest=/apex/$(basename $apex | sed -E -e 's;\.apex$|\.capex$;;' -e 's;\.current$|\.release$;;');
    mkdir -p $dest
    case $apex in
      *.apex|*.capex)
        unzip -oq $apex original_apex -d /apex
        [ -f "/apex/original_apex" ] && apex="/apex/original_apex"
        unzip -oq $apex apex_payload.img -d /apex
        mv -f /apex/original_apex $dest.apex 2>/dev/null
        mv -f /apex/apex_payload.img $dest.img
        mount -t ext4 -o ro,noatime $dest.img $dest 2>/dev/null
        if [ $? != 0 ]; then
          while [ $num -lt 64 ]; do
            loop=/dev/block/loop$num
            (mknod $loop b 7 $((num * minorx))
            losetup $loop $dest.img) 2>/dev/null
            num=$((num + 1))
            losetup $loop | grep -q $dest.img && break
          done
          mount -t ext4 -o ro,loop,noatime $loop $dest 2>/dev/null
          if [ $? != 0 ]; then
            losetup -d $loop 2>/dev/null
            if [ $num -eq 64 -a $(losetup -f) == "/dev/block/loop0" ]; then break; fi
          fi
        fi
      ;;
      *) mount -o bind $apex $dest;;
    esac
  done
  echo "$context" >> /proc/self/attr/current
  for var in $(grep -o 'export .* /.*' /system_root/init.environ.rc | awk '{ print $2 }'); do
    eval OLD_${var}=\$$var
  done
  $(grep -o 'export .* /.*' /system_root/init.environ.rc | sed 's; /;=/;'); unset export
}

umount_apex() {
  $BOOTMODE && return 255
  test -d /apex || return 255
  local dest loop var
  for var in $(grep -o 'export .* /.*' /system_root/init.environ.rc | awk '{ print $2 }'); do
    if [ "$(eval echo \$OLD_$var)" ]; then
      eval $var=\$OLD_${var}
    else
      eval unset $var
    fi
    unset OLD_${var}
  done
  for dest in $(find /apex -type d -mindepth 1 -maxdepth 1); do
    loop=$(mount | grep $dest | grep loop | cut -d\  -f1)
    umount -l $dest; [ "$loop" ] && losetup -d $loop
  done
  [ -f /apex/apex ] && umount /apex
  rm -rf /apex 2>/dev/null
}

umount_all() {
  $BOOTMODE && return 255
  umount -l /system > /dev/null 2>&1
  umount -l /system_root > /dev/null 2>&1
  umount -l /product > /dev/null 2>&1
  umount -l /system_ext > /dev/null 2>&1
  umount -l /vendor > /dev/null 2>&1
  umount -l /persist > /dev/null 2>&1
}

mount_all() {
  $BOOTMODE && return 255
  [ "$slot" ] || slot=$(getprop ro.boot.slot_suffix)
  [ "$slot" ] || slot=$(grep -o 'androidboot.slot_suffix=.*$' /proc/cmdline | cut -d\  -f1 | cut -d= -f2)
  [ "$slot" ] || slot=$(grep -o 'androidboot.slot=.*$' /proc/cmdline | cut -d\  -f1 | cut -d= -f2)
  mount -o bind /dev/urandom /dev/random
  if ! is_mounted /cache; then
    mount /cache > /dev/null 2>&1
  fi
  if ! is_mounted /data; then
    mount /data > /dev/null 2>&1
  fi
  mount -o ro -t auto /vendor > /dev/null 2>&1
  mount -o ro -t auto /persist > /dev/null 2>&1
  mount -o ro -t auto /product > /dev/null 2>&1
  mount -o ro -t auto /system_ext > /dev/null 2>&1
  [ "$ANDROID_ROOT" ] || ANDROID_ROOT="/system"
  setup_mountpoint $ANDROID_ROOT
  if ! is_mounted $ANDROID_ROOT; then
    mount -o ro -t auto $ANDROID_ROOT > /dev/null 2>&1
  fi
  case $ANDROID_ROOT in
    /system_root) setup_mountpoint /system;;
    /system)
      if ! is_mounted /system && ! is_mounted /system_root; then
        setup_mountpoint /system_root
        mount -o ro -t auto /system_root
      elif [ -f "/system/system/build.prop" ]; then
        setup_mountpoint /system_root
        mount --move /system /system_root
        mount -o bind /system_root/system /system
      fi
      if [ $? != 0 ]; then
        umount -l /system > /dev/null 2>&1
      fi
    ;;
  esac
  case $ANDROID_ROOT in
    /system)
      if ! is_mounted $ANDROID_ROOT && [ -e /dev/block/mapper/system$slot ]; then
        mount -o ro -t auto /dev/block/mapper/system$slot /system_root > /dev/null 2>&1
        mount -o ro -t auto /dev/block/mapper/product$slot /product > /dev/null 2>&1
        mount -o ro -t auto /dev/block/mapper/system_ext$slot /system_ext > /dev/null 2>&1
        mount -o ro -t auto /dev/block/mapper/vendor$slot /vendor > /dev/null 2>&1
      fi
      if ! is_mounted $ANDROID_ROOT && [ -e /dev/block/bootdevice/by-name/system$slot ]; then
        mount -o ro -t auto /dev/block/bootdevice/by-name/system$slot /system_root > /dev/null 2>&1
        mount -o ro -t auto /dev/block/bootdevice/by-name/product$slot /product > /dev/null 2>&1
        mount -o ro -t auto /dev/block/bootdevice/by-name/system_ext$slot /system_ext > /dev/null 2>&1
        mount -o ro -t auto /dev/block/bootdevice/by-name/vendor$slot /vendor > /dev/null 2>&1
      fi
    ;;
  esac
  if is_mounted /system_root; then
    if [ -f "/system_root/build.prop" ]; then
      mount -o bind /system_root /system
    else
      mount -o bind /system_root/system /system
    fi
  fi
  for block in system product system_ext vendor; do
    for slot in "" _a _b; do
      blockdev --setrw /dev/block/mapper/$block$slot > /dev/null 2>&1
    done
  done
  mount -o remount,rw -t auto / > /dev/null 2>&1
  ui_print "- Mounting /system"
  if [ "$(grep -wo '/system' /proc/mounts)" ]; then
    mount -o remount,rw -t auto /system > /dev/null 2>&1
    is_mounted /system || on_abort "! Cannot mount /system"
  fi
  if [ "$(grep -wo '/system_root' /proc/mounts)" ]; then
    mount -o remount,rw -t auto /system_root > /dev/null 2>&1
    is_mounted /system_root || on_abort "! Cannot mount /system_root"
  fi
  ui_print "- Mounting /product"
  mount -o remount,rw -t auto /product > /dev/null 2>&1
  ui_print "- Mounting /system_ext"
  mount -o remount,rw -t auto /system_ext > /dev/null 2>&1
  ui_print "- Mounting /vendor"
  mount -o remount,rw -t auto /vendor > /dev/null 2>&1
  # System is writable
  if ! touch $SYSTEM/.rw 2>/dev/null; then
    on_abort "! Read-only file system"
  fi
  if is_mounted /product; then
    ln -sf /product /system
  fi
  # Dedicated V3 Partitions
  P="/product /system_ext"
}

unmount_all() {
  $BOOTMODE && return 255
  ui_print "- Unmounting partitions"
  umount -l /system > /dev/null 2>&1
  umount -l /system_root > /dev/null 2>&1
  umount -l /product > /dev/null 2>&1
  umount -l /system_ext > /dev/null 2>&1
  umount -l /vendor > /dev/null 2>&1
  umount -l /persist > /dev/null 2>&1
  umount -l /dev/random > /dev/null 2>&1
}

f_cleanup() {
  find .$TMP -mindepth 1 -maxdepth 1 -type f -not -name 'recovery.log' -not -name 'busybox-arm' -exec rm -rf {} +
}

d_cleanup() {
  find .$TMP -mindepth 1 -maxdepth 1 -type d -exec rm -rf {} +
}

on_abort() {
  ui_print "$*"
  boot_actions
  $BOOTMODE && exit 1
  mk_debug_log
  umount_apex
  unmount_all
  f_cleanup
  d_cleanup
  ui_print "! Installation failed"
  ui_print " "
  true
  sync
  exit 1
}

on_installed() {
  mk_debug_log
  umount_apex
  unmount_all
  f_cleanup
  d_cleanup
  ui_print "- Installation complete"
  ui_print " "
  true
  sync
  exit "$?"
}

get_file_prop() { grep -m1 "^$2=" "$1" | cut -d= -f2; }

get_prop() {
  for f in $PROPFILES; do
    if [ -e "$f" ]; then
      prop="$(get_file_prop "$f" "$1")"
      if [ -n "$prop" ]; then
        break
      fi
    fi
  done
  if [ -z "$prop" ]; then
    getprop "$1" | cut -c1-
  else
    printf "$prop"
  fi
}

is_root() { if $1 -V; then MAGISK="$2"; c="c 0 0"; fi; }

extracted() {
  file_list="$(find "$UNZIP_DIR/" -mindepth 1 -type f | cut -d/ ${DEST})"
  dir_list="$(find "$UNZIP_DIR/" -mindepth 1 -type d | cut -d/ ${DEST})"
  for file in $file_list; do
    install -D "$UNZIP_DIR/${file}" "$ROOTFS/${file}"
    chmod 0644 "$ROOTFS/${file}"
    ch_con system "$ROOTFS/${file}"
    # Overlays require different SELinux context
    case $file in
      */overlay/*) ch_con vendor_overlay "$ROOTFS/${file}";;
    esac
  done
  for dir in $dir_list; do
    chmod 0755 "$ROOTFS/${dir}"
    ch_con system "$ROOTFS/${dir}"
  done
}

is_rro() { mv -f $SYSTEM/$1/$2 $MODDIR/$1/$2 && rm -rf $SYSTEM/$1; }

override() {
  $SYSTEMLESS || return 255
  install -d $SYSTEM/$1/$i $SYSTEM/$2/$i
  install -d $SYSTEM/$3/$1/$i $SYSTEM/$3/$2/$i
  install -d $SYSTEM/$4/$1/$i $SYSTEM/$4/$2/$i
  $5 $SYSTEM/$1/$i/$6; $5 $SYSTEM/$2/$i/$6
  $5 $SYSTEM/$3/$1/$i/$6; $5 $SYSTEM/$3/$2/$i/$6
  $5 $SYSTEM/$4/$1/$i/$6; $5 $SYSTEM/$4/$2/$i/$6
}

backward() {
  $SYSTEMLESS || return 255
  install -d $SYSTEM/$1 $SYSTEM/$2
  install -d $MODDIR/$3/$1 $MODDIR/$3/$2
  install -d $MODDIR/$4/$1 $MODDIR/$4/$2
  $5 $SYSTEM/$1/$i $c; $5 $SYSTEM/$2/$i $c
  $5 $MODDIR/$3/$1/$i $c; $5 $MODDIR/$3/$2/$i $c
  $5 $MODDIR/$4/$1/$i $c; $5 $MODDIR/$4/$2/$i $c
}

# Begin installation
print_title "BiTGApps $version Installer"

# Helper Functions
umount_all
mount_all
mount_apex

# Sideload Optional Configuration
unzip -oq "$ZIPFILE" "bitgapps.conf" -d "$TMP"

# Optional Configuration
for d in /sdcard /sdcard1 /external_sd /data/media/0 /tmp /dev/tmp; do
  for f in $(find $d -type f -iname "bitgapps.conf" 2>/dev/null); do
    if [ -f "$f" ]; then BITGAPPS_CONFIG="$f"; fi
  done
done

# Common Build Properties
PROPFILES="$SYSTEM/build.prop $BITGAPPS_CONFIG"

# Detect Super Partitions
DYNAMIC="$(getprop ro.boot.dynamic_partitions)"

# Current Package Variables
android_sdk="$(get_prop "ro.build.version.sdk")"
supported_sdk="34"
android_version="$(get_prop "ro.build.version.release")"
supported_version="14"
device_architecture="$(get_prop "ro.product.cpu.abi")"
supported_architecture="arm64-v8a"

# Check Android SDK
if [ "$android_sdk" = "$supported_sdk" ]; then
  ui_print "- Android SDK version: $android_sdk"
else
  on_abort "! Unsupported Android SDK version"
fi

# Check Android Version
if [ "$android_version" = "$supported_version" ]; then
  ui_print "- Android version: $android_version"
else
  on_abort "! Unsupported Android version"
fi

# Check Device Platform
if [ "$device_architecture" = "$supported_architecture" ]; then
  ui_print "- Android platform: $device_architecture"
else
  on_abort "! Unsupported Android platform"
fi

# Check Systemless Installation
supported_module_config="false"
if [ -f "$BITGAPPS_CONFIG" ]; then
  supported_module_config="$(get_prop "ro.config.systemless")"
  # Re-write missing configuration
  if [ -z "$supported_module_config" ]; then
    supported_module_config="false"
  fi
  SYSTEMLESS="$supported_module_config"
fi
# Bail out if not Magisk or KernelSU
if [ "$BOOTMODE" = "false" ]; then
  supported_module_config="false"
fi
SYSTEMLESS="$supported_module_config"
$SYSTEMLESS && SYSTEM="$MODDIR/system"
$SYSTEMLESS && export ROOTFS="$SYSTEM"

# Check SetupWizard Installation
supported_setup_config="false"
if [ -f "$BITGAPPS_CONFIG" ]; then
  supported_setup_config="$(get_prop "ro.config.setupwizard")"
  # Re-write missing configuration
  if [ -z "$supported_setup_config" ]; then
    supported_setup_config="false"
  fi
fi
# Override Excluded Size
$supported_setup_config && EXCLUDE="0"

# Always override previous installation
rm -rf $MODDIR && install -d $MODDIR/system

if $BOOTMODE; then
  # System is writable
  if ! touch $SYSTEM/.rw 2>/dev/null; then
    on_abort "! Read-only file system"
  fi
  if is_mounted /product; then
    ln -sf /product /system
  fi
  # Dedicated V3 Partitions
  P="/product /system_ext"
fi
# Handle V3 Partitions
$supported_module_config && unset P

# Do not source utility functions
UF="/data/adb/magisk/util_functions.sh"
if [ -f "$UF" ] && $BOOTMODE; then
  UF="/data/adb/magisk/util_functions.sh"
  grep -w 'MAGISK_VER_CODE' $UF >> $TMP/VER_CODE
  chmod 0755 $TMP/VER_CODE && . $TMP/VER_CODE
  if [ "$MAGISK_VER_CODE" -lt "26100" ]; then
    on_abort "! Please install Magisk v26.1+"
  fi
fi

# Compressed Packages
ZIP_FILE="$TMP/tar"
# Extracted Packages
mkdir $TMP/untar
# Initial link
UNZIP_DIR="$TMP/untar"
# Create links
TMP_SYS="$UNZIP_DIR/app"
TMP_PRIV="$UNZIP_DIR/priv-app"
TMP_FRAMEWORK="$UNZIP_DIR/framework"
TMP_FSVERITY="$UNZIP_DIR/etc/security/fsverity"
TMP_SYSCONFIG="$UNZIP_DIR/etc/sysconfig"
TMP_DEFAULT="$UNZIP_DIR/etc/default-permissions"
TMP_PERMISSION="$UNZIP_DIR/etc/permissions"
TMP_PREFERRED="$UNZIP_DIR/etc/preferred-apps"
TMP_OVERLAY="$UNZIP_DIR/product/overlay"

# Create dir
for d in \
  $UNZIP_DIR/app \
  $UNZIP_DIR/priv-app \
  $UNZIP_DIR/framework \
  $UNZIP_DIR/etc/security/fsverity \
  $UNZIP_DIR/etc/sysconfig \
  $UNZIP_DIR/etc/default-permissions \
  $UNZIP_DIR/etc/permissions \
  $UNZIP_DIR/etc/preferred-apps \
  $UNZIP_DIR/product/overlay; do
  install -d "$d"
  chmod -R 0755 $TMP
done

# Extract survival script
unzip -oq "$ZIPFILE" "$ADDOND" -d "$TMP"

# Exclude Reclaimed GApps Space
list_files | while read FILE CLAIMED; do
  PKG="$(find /system -type d -iname $FILE)"
  CLAIMED="$(du -sxk "$PKG" | cut -f1)"
  # Reclaimed GApps Space in KB's
  echo "$CLAIMED" >> $TMP/RAW
done
# Remove White Spaces
sed -i '/^[[:space:]]*$/d' $TMP/RAW
# Reclaimed Removal Space in KB's
if ! grep -soEq '[0-9]+' "$TMP/RAW"; then
  # When raw output of claimed is empty
  CLAIMED="0"
else
  CLAIMED="$(grep -soE '[0-9]+' "$TMP/RAW" | paste -sd+ | bc)"
fi

# Get the available space left on the device
size=$(df -k /system | tail -n 1 | tr -s ' ' | cut -d' ' -f4)
# Disk space in human readable format (k=1024)
ds_hr=$(df -h /system | tail -n 1 | tr -s ' ' | cut -d' ' -f4)

# Check Required Space
CAPACITY="$(($CAPACITY-$CLAIMED-$EXCLUDE))"
# FIXIT: NEGATIVE INTEGER
CAPACITY="${CAPACITY#-}" # END OF 2K23
$SYSTEMLESS && size="1" && CAPACITY="0"
[ -z $DYNAMIC ] && DYNAMIC="false"
[ -z $PRODUCT ] && PRODUCT="false"
if [ "$size" -gt "$CAPACITY" ]; then
  ui_print "- System Space: $ds_hr"
  sed -i -r 's/^@ROOTFS@//' "$TMPOTA"
elif [ "$android_sdk" -lt "34" ]; then
  ui_print "! Insufficient partition size"
  on_abort "! Current space: $ds_hr"
else
  PRODUCT="true" && rm -rf "$TMP/RAW"
fi

# FIXIT: NO ARM SUPER
OLD_PRODUCT="$PRODUCT"

# Must have Super Partition
$DYNAMIC || PRODUCT="false"

# Exclude Reclaimed GApps Space
list_files | while read FILE CLAIMED; do
  PKG="$(find /product -type d -iname $FILE)"
  CLAIMED="$(du -sxk "$PKG" | cut -f1)"
  # Reclaimed GApps Space in KB's
  echo "$CLAIMED" >> $TMP/RAW
done
# Remove White Spaces
sed -i '/^[[:space:]]*$/d' $TMP/RAW
# Reclaimed Removal Space in KB's
if ! grep -soEq '[0-9]+' "$TMP/RAW"; then
  # When raw output of claimed is empty
  CLAIMED="0"
else
  CLAIMED="$(grep -soE '[0-9]+' "$TMP/RAW" | paste -sd+ | bc)"
fi

# Get the available space left on the device
size=$(df -k /product | tail -n 1 | tr -s ' ' | cut -d' ' -f4)
# Disk space in human readable format (k=1024)
ds_hr=$(df -h /product | tail -n 1 | tr -s ' ' | cut -d' ' -f4)
# Checkout required free space for GApps
grep -w 'CAPACITY' "$TMP/util_functions.sh" >> $TMP/CAP

if $PRODUCT && [ "$android_sdk" = "34" ]; then
  if ! is_mounted /product; then
    on_abort "! Cannot mount /product"
  fi
  [ -f "$TMP/CAP" ] && . $TMP/CAP
  CAPACITY="$(($CAPACITY-$CLAIMED-$EXCLUDE))"
  # FIXIT: NEGATIVE INTEGER
  CAPACITY="${CAPACITY#-}" # END OF 2K23
  if [ "$size" -gt "$CAPACITY" ]; then
    ui_print "- Product Space: $ds_hr"
    sed -i "s|@ROOTFS@|product/|g" "$TMPOTA"
  else
    ui_print "! Insufficient partition size"
    on_abort "! Current space: $ds_hr"
  fi
  if ! touch /product/.rw 2>/dev/null; then
    on_abort "! Read-only file system"
  fi
  rm -rf "$UNZIP_DIR/product"
  $SYSTEMLESS || ROOTFS="/product"
  TMP_OVERLAY="$UNZIP_DIR/overlay"
  install -d "$UNZIP_DIR/overlay"
fi

# Abort installation on ARM Platform
! $DYNAMIC && $OLD_PRODUCT && UDC="true"
if $UDC && [ "$android_sdk" = "34" ]; then
  ui_print "! Insufficient partition size"
  on_abort "! Current space: $ds_hr"
fi

# Delete Runtime Permissions
RTP="$(find /data -type f -iname "runtime-permissions.xml")"
if [ -e "$RTP" ]; then
  if ! grep -qwo 'com.android.vending' $RTP; then
    rm -rf "$RTP"
  fi
fi

# Pathmap
SYSTEM_ADDOND="$SYSTEM/addon.d"
SYSTEM_APP="$SYSTEM/app"
SYSTEM_PRIV_APP="$SYSTEM/priv-app"
SYSTEM_ETC_CONFIG="$SYSTEM/etc/sysconfig"
SYSTEM_ETC_DEFAULT="$SYSTEM/etc/default-permissions"
SYSTEM_ETC_PERM="$SYSTEM/etc/permissions"
SYSTEM_ETC_PREF="$SYSTEM/etc/preferred-apps"
SYSTEM_FRAMEWORK="$SYSTEM/framework"
SYSTEM_OVERLAY="$SYSTEM/product/overlay"

# FIXIT: REPLACE PATHMAP
CALENDAR="$SYSTEM/app/Calendar"
CONTACTS="$SYSTEM/app/Contacts"
DESKCLOCK="$SYSTEM/app/DeskClock"
DIALER="$SYSTEM/priv-app/Dialer"

# Cleanup
rm -rf $SYSTEM_APP/ExtShared
rm -rf $SYSTEM_APP/FaceLock
rm -rf $SYSTEM_APP/Google*
rm -rf $SYSTEM_PRIV_APP/ConfigUpdater
rm -rf $SYSTEM_PRIV_APP/ExtServices
rm -rf $SYSTEM_PRIV_APP/*Gms*
rm -rf $SYSTEM_PRIV_APP/Google*
rm -rf $SYSTEM_PRIV_APP/Phonesky
rm -rf $SYSTEM_ETC_CONFIG/*google*
rm -rf $SYSTEM_ETC_DEFAULT/default-permissions.xml
rm -rf $SYSTEM_ETC_DEFAULT/bitgapps-permissions.xml
rm -rf $SYSTEM_ETC_DEFAULT/bitgapps-permissions-q.xml
rm -rf $SYSTEM_ETC_PERM/*google*
rm -rf $SYSTEM_ETC_PREF/google.xml
rm -rf $SYSTEM_OVERLAY/PlayStoreOverlay.apk
rm -rf $SYSTEM_ADDOND/70-bitgapps.sh

# Cleanup
if $PRODUCT && [ "$android_sdk" = "34" ]; then
  find $P -type d -iname 'ExtShared' -exec rm -rf {} +
  find $P -type d -iname '*Google*' -exec rm -rf {} +
  find $P -type f -iname '*Google*' -exec rm -rf {} +
  find $P -type d -iname 'ConfigUpdater' -exec rm -rf {} +
  find $P -type d -iname 'ExtServices' -exec rm -rf {} +
  find $P -type d -iname '*Gms*' -exec rm -rf {} +
  find $P -type d -iname 'Phonesky' -exec rm -rf {} +
  find $P -type f -iname '*PlayStore*' -exec rm -rf {} +
  find $P -type f -iname '*bitgapps*' -exec rm -rf {} +
fi

# Cleanup
for f in $SYSTEM $SYSTEM/product $SYSTEM/system_ext $P; do
  find $f -type d -iname 'Calendar' -exec rm -rf {} +
  find $f -type d -iname 'Etar' -exec rm -rf {} +
  find $f -type d -iname 'Contacts' -exec rm -rf {} +
  find $f -type d -iname 'Gboard' -exec rm -rf {} +
  find $f -type d -iname 'LatinIME' -exec rm -rf {} +
  find $f -type d -iname 'Speech' -exec rm -rf {} +
  find $f -type d -iname 'Gearhead' -exec rm -rf {} +
  find $f -type d -iname 'Velvet' -exec rm -rf {} +
  find $f -type d -iname '*Dialer*' -exec rm -rf {} +
done

# Google Apps Packages
ui_print "- Installing GApps"
for f in $BITGAPPS; do unzip -oq "$ZIPFILE" "$f" -d "$TMP"; done
tar -xf $ZIP_FILE/etc/Calendar.tar.xz -C $TMP_SYS
tar -xf $ZIP_FILE/etc/Contacts.tar.xz -C $TMP_SYS
tar -xf $ZIP_FILE/etc/Gboard.tar.xz -C $TMP_SYS
tar -xf $ZIP_FILE/etc/GoogleCalendarSyncAdapter.tar.xz -C $TMP_SYS
tar -xf $ZIP_FILE/etc/GoogleContactsSyncAdapter.tar.xz -C $TMP_SYS
tar -xf $ZIP_FILE/etc/GoogleExtShared.tar.xz -C $TMP_SYS
tar -xf $ZIP_FILE/etc/Speech.tar.xz -C $TMP_SYS
tar -xf $ZIP_FILE/core/ConfigUpdater.tar.xz -C $TMP_PRIV
tar -xf $ZIP_FILE/core/Gearhead.tar.xz -C $TMP_PRIV
tar -xf $ZIP_FILE/core/Dialer.tar.xz -C $TMP_PRIV
tar -xf $ZIP_FILE/core/GmsCoreSetupPrebuilt.tar.xz -C $TMP_PRIV 2>/dev/null
tar -xf $ZIP_FILE/core/GoogleExtServices.tar.xz -C $TMP_PRIV
tar -xf $ZIP_FILE/core/GoogleLoginService.tar.xz -C $TMP_PRIV 2>/dev/null
tar -xf $ZIP_FILE/core/GoogleServicesFramework.tar.xz -C $TMP_PRIV
tar -xf $ZIP_FILE/core/Phonesky.tar.xz -C $TMP_PRIV
tar -xf $ZIP_FILE/core/PrebuiltGmsCore.tar.xz -C $TMP_PRIV
tar -xf $ZIP_FILE/core/Velvet.tar.xz -C $TMP_PRIV
tar -xf $ZIP_FILE/Sysconfig.tar.xz -C $TMP_SYSCONFIG
tar -xf $ZIP_FILE/Default.tar.xz -C $TMP_DEFAULT
tar -xf $ZIP_FILE/Permissions.tar.xz -C $TMP_PERMISSION
tar -xf $ZIP_FILE/Preferred.tar.xz -C $TMP_PREFERRED
tar -xf $ZIP_FILE/overlay/PlayStoreOverlay.tar.xz -C $TMP_OVERLAY 2>/dev/null
# Remove Compressed Packages
for f in $BITGAPPS; do rm -rf $TMP/$f; done

# REQUEST NETWORK SCORES
if [ "$android_sdk" -le "28" ]; then
  rm -rf $TMP_DEFAULT/bitgapps-permissions-q.xml
fi
if [ "$android_sdk" -ge "29" ]; then
  rm -rf $TMP_DEFAULT/bitgapps-permissions.xml
fi

# Additional Components
for f in $FRAMEWORK; do unzip -oq "$ZIPFILE" "$f" -d "$TMP"; done
tar -xf $ZIP_FILE/framework/DialerPermissions.tar.xz -C $TMP_PERMISSION
tar -xf $ZIP_FILE/framework/DialerFramework.tar.xz -C $TMP_FRAMEWORK
tar -xf $ZIP_FILE/framework/MapsPermissions.tar.xz -C $TMP_PERMISSION
tar -xf $ZIP_FILE/framework/MapsFramework.tar.xz -C $TMP_FRAMEWORK

# Install OTA Survival Script
if [ -d "$SYSTEM_ADDOND" ]; then
  ui_print "- Installing OTA survival script"
  # Install OTA survival script
  rm -rf $SYSTEM_ADDOND/$ADDOND
  cp -f $TMP/$ADDOND $SYSTEM_ADDOND/$ADDOND
  chmod 0755 $SYSTEM_ADDOND/$ADDOND
  ch_con system "$SYSTEM_ADDOND/$ADDOND"
fi

# Character (unbuffered) file MAJOR and MINOR
$SYSTEMLESS || MAGISK="false"
$SYSTEMLESS && is_root ksud false
$SYSTEMLESS && is_root magisk true

# Install SetupWizard Components
if [ "$supported_setup_config" = "true" ]; then
  ui_print "- Installing SetupWizard"
  for f in $SYSTEM $SYSTEM/product $SYSTEM/system_ext $P; do
    find $f -type d -iname '*Provision*' -exec rm -rf {} +
    find $f -type d -iname '*GoogleBackup*' -exec rm -rf {} +
    find $f -type d -iname '*GoogleRestore*' -exec rm -rf {} +
    find $f -type d -iname '*SetupWizard*' -exec rm -rf {} +
  done
  for i in ManagedProvisioning Provision LineageSetupWizard; do
    $MAGISK && override app priv-app product system_ext touch .replace
    $MAGISK || backward app priv-app product system_ext mknod
  done
  for f in $SETUPWIZARD; do unzip -oq "$ZIPFILE" "$f" -d "$TMP"; done
  if [ -f "$ZIP_FILE/core/GoogleBackupTransport.tar.xz" ]; then
    tar -xf $ZIP_FILE/core/GoogleBackupTransport.tar.xz -C $TMP_PRIV
  fi
  if [ -f "$ZIP_FILE/core/GoogleRestore.tar.xz" ]; then
    tar -xf $ZIP_FILE/core/GoogleRestore.tar.xz -C $TMP_PRIV
  fi
  tar -xf $ZIP_FILE/core/SetupWizardPrebuilt.tar.xz -C $TMP_PRIV
  # Remove Compressed Packages
  for f in $SETUPWIZARD; do rm -rf $TMP/$f; done
  # Allow SetupWizard to survive OTA upgrade
  sed -i -e 's/"false"/"true"/g' $SYSTEM_ADDOND/$ADDOND
fi

# Integrity Signing Certificate
unzip -oq "$ZIPFILE" "tar/Certificate.tar.xz" -d "$TMP"
tar -xf $ZIP_FILE/Certificate.tar.xz -C "$TMP_FSVERITY"

# Helper Functions
extracted

# Override
for i in Dialer Calendar Etar Contacts LatinIME; do
  $MAGISK && override app priv-app product system_ext touch .replace
  $MAGISK || backward app priv-app product system_ext mknod
done

# FIXIT: OVERRIDE REPLACE
for f in $CALENDAR $CONTACTS $DESKCLOCK $DIALER; do
  find $f -type f -iname '.replace' -exec rm -rf {} +
done

# FIXIT: RRO MIGRATION
$SYSTEMLESS && $KSU && mkdir "$MODDIR/product"
$SYSTEMLESS && $KSU && is_rro product overlay

# Uninstaller
unzip -oq "$ZIPFILE" "uninstall.sh" -d "$MODDIR"

# Internal Configuration
echo -e "id=BiTGApps-Android" >> $MODDIR/module.prop
echo -e "name=BiTGApps for Android" >> $MODDIR/module.prop
echo -e "version=$version" >> $MODDIR/module.prop
echo -e "versionCode=$versionCode" >> $MODDIR/module.prop
echo -e "author=TheHitMan7" >> $MODDIR/module.prop
echo -e "description=Google Apps Package" >> $MODDIR/module.prop

# FIXIT: CANNOT DISABLE MODULE
sed -i -e 's/\-Android//g' $MODDIR/module.prop

# FIXIT: NO MODULE
$SYSTEMLESS || rm -rf $MODDIR

# Remove unused module
rm -rf "$MODDIR-Android"

# FIXIT: HANDLE ENCRYPTION
NVBASE="/data/adb" && MODDIR="$NVBASE/modules"
[ "$(ls -A $MODDIR)" ] || rm -rf "$MODDIR"
[ "$(ls -A $NVBASE)" ] || rm -rf "$NVBASE"

# Enable Doze Mode for GMS
DOZE='/allow-in-power-saver package="com.google.android.gms"/d'
sed -i -e "$DOZE" /system/etc/sysconfig/*.xml 2>/dev/null
sed -i -e "$DOZE" /system/product/etc/sysconfig/*.xml 2>/dev/null
sed -i -e "$DOZE" /system/system_ext/etc/sysconfig/*.xml 2>/dev/null
sed -i -e "$DOZE" /product/etc/sysconfig/*.xml 2>/dev/null
sed -i -e "$DOZE" /system_ext/etc/sysconfig/*.xml 2>/dev/null
# FIXIT: SYSCONFIG IN PRIVILEGED PERMISSIONS
sed -i -e "$DOZE" /system/etc/permissions/*.xml 2>/dev/null
sed -i -e "$DOZE" /system/product/etc/permissions/*.xml 2>/dev/null
sed -i -e "$DOZE" /system/system_ext/etc/permissions/*.xml 2>/dev/null
sed -i -e "$DOZE" /product/etc/permissions/*.xml 2>/dev/null
sed -i -e "$DOZE" /system_ext/etc/permissions/*.xml 2>/dev/null
# FIXIT: OVERRIDE MODULE CONFIGURATION
sed -i -e "$DOZE" $SYSTEM/etc/sysconfig/*.xml 2>/dev/null

# End installation
on_installed
