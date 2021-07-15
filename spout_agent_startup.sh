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

. ./elastic_stack.config

if [ -n "$STACK_VERSION" -a -n "$FLEET_TOKEN" ]; then
    ./agent_install+enroll.sh
fi

# Only start via this script, not systemd directly
#systemctl disable elastic-agent

#systemctl restart elastic-agent
