#!/system/bin/sh
#
# This file is part of The BiTGApps Project

# Remove Application Data
rm -rf /data/app/com.android.vending*
rm -rf /data/app/com.google.android*
rm -rf /data/app/*/com.android.vending*
rm -rf /data/app/*/com.google.android*
rm -rf /data/data/com.android.vending*
rm -rf /data/data/com.google.android*
# Purge Runtime Permissions
rm -rf $(find /data -type f -iname "runtime-permissions.xml")
# Remove BiTGApps Module
rm -rf /data/adb/modules/BiTGApps
