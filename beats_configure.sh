#!/bin/sh
#
# Configure an Elastic Beat on a Linux system.
#
# This script takes the following arguments:
# 1. BEAT_NAME: The name of the beat to configure (metricbeat, filebeat, winlogbeat, etc)
#
# This script reads and uses the following settings read from a file called
# "elastic_stack.config":
# - CLOUD_ID: Elastic Cloud (or ECE) deployment ID to connect to
# - STACK_VERSION: The version to install. e.g. 7.9.2
# - BEATS_AUTH: The credentials needed to connect to Elasticsearch
# Please create this^ file before running this script 
#

set -e

SCRIPTDIR=$(dirname $0)
if [ "." = "$SCRIPTDIR" ]; then
  SCRIPTDIR=$(pwd)
fi

cd $SCRIPTDIR

. ./utilities.sh

for c in curl jq sed base64; do
  test -x "$(which $c)" || _fail "Programme '$c' appears to be missing"
done

. ./elastic_stack.config

CLOUD_INFO=$(echo ${CLOUD_ID#*:} | base64 -d -)

EC_SUFFIX=$(echo $CLOUD_INFO | cut -d $ -f1)
EC_SUFFIX=${EC_SUFFIX%:9243}

EC_ES_HOST=$(echo $CLOUD_INFO | cut -d $ -f2)
EC_KN_HOST=$(echo $CLOUD_INFO | cut -d $ -f3)

BEAT_NAME=$1

for V in BEAT_NAME STACK_VERSION CLOUD_ID BEATS_AUTH EC_ES_HOST EC_SUFFIX; do
  VAL=$(eval "echo \${$V}")
  if [ -z "$VAL" ]; then
    _fail "Variable $V missing!"
  fi
  echo "$V=$VAL"
done


cp -f /etc/$BEAT_NAME/$BEAT_NAME.example.yml /etc/$BEAT_NAME/$BEAT_NAME.yml

CONF_SNIPPET=$(cat <<'_EOM_'
# *** Scripted content appended here ***

output.elasticsearch: ~

cloud.id: ${CLOUD_ID}
cloud.auth: ${CLOUD_AUTH}

processors:
  - add_host_metadata: ~
  - add_cloud_metadata: ~

xpack.monitoring.enabled: true

_EOM_
)

echo $CLOUD_ID | $BEAT_NAME keystore add CLOUD_ID --stdin --force
echo $BEATS_AUTH | $BEAT_NAME keystore add CLOUD_AUTH --stdin --force

echo "$CONF_SNIPPET" >>/etc/$BEAT_NAME/$BEAT_NAME.yml
    
CHECK_ALIAS=$(curl -qks -u "$BEATS_AUTH" "https://$EC_ES_HOST.$EC_SUFFIX/_cat/aliases/$BEAT_NAME-$STACK_VERSION"||_fail "curl alias check failed")
echo "CHECK_ALIAS=$CHECK_ALIAS"

if echo "$CHECK_ALIAS"|grep -qv "$BEAT_NAME-$STACK_VERSION" ; then
    echo "$(date) Running $BEAT_NAME setup"
    #Log failure and continue
    $BEAT_NAME setup || echo "FAILED: $BEAT_NAME setup"
fi

case "$BEAT_NAME" in
"metricbeat")
    metricbeat modules enable system linux 
;;
"filebeat")
    filebeat modules enable system iptables 
;;
esac


