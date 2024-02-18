#!/sbin/sh
#
# This file is part of The BiTGApps Project

# ADDOND_VERSION=3

if [ -z "$backuptool_ab" ]; then
  SYS="$S"
  TMP=/tmp
else
  SYS="/postinstall/system"
  TMP="/postinstall/tmp"
fi

# Required for SetupWizard
setup_config="false"

# Dedicated V3 Partitions
P="/product /system_ext /postinstall/product /postinstall/system_ext"

. /tmp/backuptool.functions

# Output function
trampoline() {
  # update-binary|updater <RECOVERY_API_VERSION> <OUTFD> <ZIPFILE>
  OUTFD=$(ps | grep -v 'grep' | grep -oE 'update(.*) 3 [0-9]+' | cut -d" " -f3)
  [ -z $OUTFD ] && OUTFD=$(ps -Af | grep -v 'grep' | grep -oE 'update(.*) 3 [0-9]+' | cut -d" " -f3)
  # update_engine_sideload --payload=file://<ZIPFILE> --offset=<OFFSET> --headers=<HEADERS> --status_fd=<OUTFD>
  [ -z $OUTFD ] && OUTFD=$(ps | grep -v 'grep' | grep -oE 'status_fd=[0-9]+' | cut -d= -f2)
  [ -z $OUTFD ] && OUTFD=$(ps -Af | grep -v 'grep' | grep -oE 'status_fd=[0-9]+' | cut -d= -f2)
  ui_print() { echo -e "ui_print $1\nui_print" >> /proc/self/fd/$OUTFD; }
}

print_title() {
  local LEN ONE TWO BAR
  ONE=$(echo -n $1 | wc -c)
  TWO=$(echo -n $2 | wc -c)
  LEN=$TWO
  [ $ONE -gt $TWO ] && LEN=$ONE
  LEN=$((LEN + 2))
  BAR=$(printf "%${LEN}s" | tr ' ' '*')
  ui_print "$BAR"
  ui_print " $1 "
  [ "$2" ] && ui_print " $2 "
  ui_print "$BAR"
}

list_files() {
cat <<EOF
@ROOTFS@app/GoogleCalendarSyncAdapter/GoogleCalendarSyncAdapter.apk
@ROOTFS@app/GoogleContactsSyncAdapter/GoogleContactsSyncAdapter.apk
@ROOTFS@app/GoogleExtShared/GoogleExtShared.apk
@ROOTFS@app/Speech/Speech.apk
@ROOTFS@priv-app/ConfigUpdater/ConfigUpdater.apk
@ROOTFS@priv-app/Gearhead/Gearhead.apk
@ROOTFS@priv-app/GmsCoreSetupPrebuilt/GmsCoreSetupPrebuilt.apk
@ROOTFS@priv-app/GoogleBackupTransport/GoogleBackupTransport.apk
@ROOTFS@priv-app/GoogleExtServices/GoogleExtServices.apk
@ROOTFS@priv-app/GoogleLoginService/GoogleLoginService.apk
@ROOTFS@priv-app/GoogleRestore/GoogleRestore.apk
@ROOTFS@priv-app/GoogleServicesFramework/GoogleServicesFramework.apk
@ROOTFS@priv-app/Phonesky/Phonesky.apk
@ROOTFS@priv-app/PrebuiltGmsCore/PrebuiltGmsCore.apk
@ROOTFS@priv-app/SetupWizardPrebuilt/SetupWizardPrebuilt.apk
@ROOTFS@priv-app/Velvet/Velvet.apk
@ROOTFS@etc/default-permissions/default-permissions.xml
@ROOTFS@etc/default-permissions/bitgapps-permissions.xml
@ROOTFS@etc/default-permissions/bitgapps-permissions-q.xml
@ROOTFS@etc/permissions/android.ext.services.xml
@ROOTFS@etc/permissions/com.google.android.dialer.support.xml
@ROOTFS@etc/permissions/com.google.android.maps.xml
@ROOTFS@etc/permissions/privapp-permissions-google.xml
@ROOTFS@etc/permissions/split-permissions-google.xml
@ROOTFS@etc/permissions/variants-permissions-google.xml
@ROOTFS@etc/preferred-apps/google.xml
@ROOTFS@etc/sysconfig/google.xml
@ROOTFS@etc/sysconfig/google_build.xml
@ROOTFS@etc/sysconfig/google_exclusives_enable.xml
@ROOTFS@etc/sysconfig/google-hiddenapi-package-whitelist.xml
@ROOTFS@etc/sysconfig/google-initial-package-stopped-states.xml
@ROOTFS@etc/sysconfig/google-install-constraints-allowlist.xml
@ROOTFS@etc/sysconfig/google-rollback-package-whitelist.xml
@ROOTFS@etc/sysconfig/google-staged-installer-whitelist.xml
@ROOTFS@etc/security/fsverity/gms_fsverity_cert.der
@ROOTFS@etc/security/fsverity/play_store_fsi_cert.der
@ROOTFS@framework/com.google.android.dialer.support.jar
@ROOTFS@framework/com.google.android.maps.jar
product/overlay/PlayStoreOverlay.apk
EOF
}

case "$1" in
  backup)
    trampoline
    print_title "BiTGApps Backup Complete"
    list_files | while read FILE DUMMY; do
      backup_file $S/"$FILE"
    done
  ;;
  restore)
    trampoline
    print_title "BiTGApps Restore Complete"
    if [ "$setup_config" = "true" ]; then
      for f in $SYS $SYS/product $SYS/system_ext $P; do
        find $f -type d -iname '*Provision*' -exec rm -rf {} +
        find $f -type d -iname '*SetupWizard*' -exec rm -rf {} +
      done
    fi
    list_files | while read FILE REPLACEMENT; do
      R=""
      [ -n "$REPLACEMENT" ] && R="$S/$REPLACEMENT"
      [ -f "$C/$S/$FILE" ] && restore_file $S/"$FILE" "$R"
    done
    rm -rf $SYS/app/ExtShared $SYS/priv-app/ExtServices
    for i in $(list_files); do
      chown root:root "$SYS/$i" 2>/dev/null
      chmod 644 "$SYS/$i" 2>/dev/null
      chmod 755 "$(dirname "$SYS/$i")" 2>/dev/null
    done
  ;;
esac
