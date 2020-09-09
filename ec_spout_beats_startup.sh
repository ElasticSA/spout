#!/bin/sh

SCRIPTDIR=$(basename $0)
if [ "." = "$SCRIPTDIR" ]; then
  SCRIPTDIR=$(pwd)
fi

cd $SCRIPTDIR

exec >ec_spout_beats_startup.log 2>&1

for c in curl jq sed; do
  test -x "$(which $c)" || _fail "Programme '$c' appears to be missing"
done

SKYTAP_DATA=$(curl -qs http://gw/skytap)
ENV_CONFIG=$(echo -e $(echo $SKYTAP_DATA | jq .configuration_user_data))
VM_CONFIG=$(echo -e $(echo $SKYTAP_DATA | jq .user_data))

STACK_VER=$(echo $ENV_CONFIG | sed -Ene 's/^stack_version:\s*(.*)$/\1/ p')
CLOUD_ID=$(echo $ENV_CONFIG | sed -Ene 's/^cloud_id:\s*(.*)$/\1/ p')
BEATS_AUTH=$(echo $ENV_CONFIG | sed -Ene 's/^beats_auth:\s*(.*)$/\1/ p')

CLOUD_INFO=$(echo ${CLOUD_ID#*:} | base64 -d -)

EC_SUFFIX=$(echo $CLOUD_INFO | cut -d $ -f1)
EC_SUFFIX=${EC_SUFFIX%:9243}

EC_ES_HOST=$(echo $CLOUD_INFO | cut -d $ -f2)
EC_KN_HOST=$(echo $CLOUD_INFO | cut -d $ -f3)

for V in STACK_VER CLOUD_ID BEATS_AUTH AGENT_TOKEN EC_ES_HOST EC_SUFFIX; do
  if [ -n "$$V" ]; then
    echo "Variable $V missing!"
    exit 1
  fi
done

initialise_beat()
{
    BEAT_NAME=$1
    
    cp /etc/$BEAT_NAME/$BEAT_NAME.example.yml /etc/$BEAT_NAME/$BEAT_NAME.yml
    
    CONF_SNIPPET=<<'_EOM_'

cloud.id: ${CLOUD_ID}
cloud.auth: ${CLOUD_AUTH}

processors:
  - add_host_metadata: ~
  - add_cloud_metadata: ~

xpack.monitoring.enabled: true

_EOM_

    echo $CLOUD_ID | $BEAT_NAME keystore add CLOUD_ID --stdin --force
    echo $BEATS_AUTH | $BEAT_NAME keystire add CLOUD_AUTH --stdin --force
    
    echo $CONF_SNIPPET >>/etc/$BEAT_NAME/$BEAT_NAME.yml
    
    CHECK_ALIAS=$(curl -qks "$EC_ES_HOST.$EC_SUFFIX/_cat/aliases/$BEAT_NAME-$STACK_VER")
    echo CHECK_ALIAS=$CHECK_ALIAS

    if [ $(echo $CHECK_ALIAS|wc -l) -lt 1 ]; then
      $BEAT_NAME setup
    fi
    
    systemctl restart $BEAT_NAME
}

./beats_install.sh "metricbeat" $STACK_VER
./beats_install.sh "auditbeat" $STACK_VER
./beats_install.sh "filebeat" $STACK_VER
./beats_install.sh "packetbeat" $STACK_VER

initialise_beat "metricbeat"
initialise_beat "auditbeat"
initialise_beat "filebeat"
initialise_beat "packetbeat"
