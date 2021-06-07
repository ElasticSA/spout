#!/bin/bash

# So that the other scripts can be used outside of SkyTap
# they take their config from an 'elastic_stack.config' file
# This script generates that file from the skytap environment metadata
# The goal being to allow the other scripts to be useful for other automation environments
# by decoupling them from anything Skytap specific

set -e

SCRIPTDIR=$(dirname $0)
if [ "." = "$SCRIPTDIR" ]; then
  SCRIPTDIR=$(pwd)
fi

cd $SCRIPTDIR

. ./utilities.sh

SKYTAP_DATA=''
while [ -z "$SKYTAP_DATA" ]; do
    SKYTAP_DATA=$(curl -qs http://gw/skytap)
    test 0 -ne "$?" && sleep 20s
done

ENV_CONFIG=$(echo "$SKYTAP_DATA" | jq -r .configuration_user_data)
VM_CONFIG=$(echo "$SKYTAP_DATA" | jq -r .user_data)

FLEET_TOKEN=

if [ -z $(echo "$ENV_CONFIG" | yq r - fleet_token.${HOSTNAME,,}) ]; then
    FLEET_TOKEN=$(echo "$ENV_CONFIG" | yq r - fleet_token.linux)
else
    FLEET_TOKEN=$(echo "$ENV_CONFIG" | yq r - fleet_token.${HOSTNAME,,})
fi

# Workaround for agent default port behaviour, use explicit ports in URL to avoid
FLEET_SERVER=$(echo "$ENV_CONFIG" | yq r - fleet_server)
if ! echo $FLEET_SERVER | grep -Eq ':[0-9]+$'; then
    FLEET_SERVER="$FLEET_SERVER:443"
fi

# Truncate existing
echo "# $(date)" >elastic_stack.config

if [[ "$ENV_CONFIG" == ---* ]]; then
    echo "STACK_VERSION=$(     echo "$ENV_CONFIG" | yq r - stack_version)"      >>elastic_stack.config
    echo "CLOUD_ID=$(          echo "$ENV_CONFIG" | yq r - cloud_id)"           >>elastic_stack.config
    echo "BEATS_AUTH=$(        echo "$ENV_CONFIG" | yq r - beats_auth)"         >>elastic_stack.config
    echo "BEATS_SETUP_AUTH=$(  echo "$ENV_CONFIG" | yq r - beats_setup_auth)"   >>elastic_stack.config
    echo "FLEET_TOKEN=${FLEET_TOKEN}"   >>elastic_stack.config
    echo "FLEET_SERVER=${FLEET_SERVER}" >>elastic_stack.config
fi

if [[ "$VM_CONFIG" == ---* ]]; then
    echo "BEATS_FORCE_SETUP=$(  echo "$VM_CONFIG" | yq r - beats_force_setup)"  >>elastic_stack.config
fi
