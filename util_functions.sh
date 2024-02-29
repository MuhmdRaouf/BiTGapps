# This file is part of The BiTGApps Project

# Define Current Version
version="v2.7"
versionCode="27"

# Define Installation Size
CAPACITY="673528"

# Define Excluded Size
EXCLUDE="21128"

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
WebView
Markup
Maps
Chrome
Sandbox
Calculator
Calendar
Contacts
Gboard
DeskClock
GoogleCalendarSyncAdapter
GoogleContactsSyncAdapter
GoogleExtShared
Speech
Photos
ConfigUpdater
Gearhead
Dialer
GmsCoreSetupPrebuilt
GoogleBackupTransport
GoogleExtServices
GoogleLoginService
GoogleRestore
GoogleServicesFramework
Messaging
Services
Phonesky
PrebuiltGmsCore
SetupWizardPrebuilt
Velvet
Wellbeing
EOF
}

ch_con() { chcon -h u:object_r:${1}_file:s0 "$2"; }
