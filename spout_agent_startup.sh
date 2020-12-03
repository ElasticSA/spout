#!/bin/sh
#
# Run at startup by systemd with Spout env. on Skytap
#

set -e

SCRIPTDIR=$(dirname $0)
if [ "." = "$SCRIPTDIR" ]; then
  SCRIPTDIR=$(pwd)
fi

cd $SCRIPTDIR

exec >spout_agent_startup.log 2>&1

. ./utilities.sh

./fetch_skytap_config.sh

./agent_install+enroll.sh

# Only start via this script, not systemd directly
systemctl disable elastic-agent

#systemctl restart elastic-agent
