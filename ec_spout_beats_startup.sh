#!/bin/sh
#
# Run at startup by systemd with EC Spout env. on Skytap
#

set -e

SCRIPTDIR=$(dirname $0)
if [ "." = "$SCRIPTDIR" ]; then
  SCRIPTDIR=$(pwd)
fi

cd $SCRIPTDIR

exec >ec_spout_beats_startup.log 2>&1

. ./utilities.sh

for c in curl jq sed base64; do
  test -x "$(which $c)" || _fail "Programme '$c' appears to be missing"
done

./fetch_skytap_config.sh

. ./elastic_stack.config

for B in metricbeat auditbeat filebeat packetbeat; do

  echo "$(date) Installing $B ($STACK_VERSION)"
  ./beats_install.sh $B $STACK_VERSION || _fail "Installing $B failed!"

  echo "$(date) Initialising $B ($STACK_VERSION)"
  ./beats_configure.sh $B
  
  echo "$(date) Starting $B ($STACK_VERSION)"
  systemctl restart "$B"
  
done
