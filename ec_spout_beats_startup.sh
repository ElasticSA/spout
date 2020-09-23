#!/bin/sh

set -e

SCRIPTDIR=$(dirname $0)
if [ "." = "$SCRIPTDIR" ]; then
  SCRIPTDIR=$(pwd)
fi

cd $SCRIPTDIR

exec >ec_spout_beats_startup.log 2>&1

_fail() {
  echo $@ >&2
  exit 1
}

for c in curl jq sed base64; do
  test -x "$(which $c)" || _fail "Programme '$c' appears to be missing"
done

SKYTAP_DATA=$(curl -qs http://gw/skytap||_fail "curl skytap failed")

ENV_CONFIG=$(echo "$SKYTAP_DATA" | jq -r .configuration_user_data)
VM_CONFIG=$(echo "$SKYTAP_DATA" | jq -r .user_data)

STACK_VER=$(echo "$ENV_CONFIG" | sed -Ene 's/^stack_version:\s*(.*)$/\1/ p')
CLOUD_ID=$(echo "$ENV_CONFIG" | sed -Ene 's/^cloud_id:\s*(.*)$/\1/ p')
BEATS_AUTH=$(echo "$ENV_CONFIG" | sed -Ene 's/^beats_auth:\s*(.*)$/\1/ p')

CLOUD_INFO=$(echo ${CLOUD_ID#*:} | base64 -d -)

EC_SUFFIX=$(echo $CLOUD_INFO | cut -d $ -f1)
EC_SUFFIX=${EC_SUFFIX%:9243}

EC_ES_HOST=$(echo $CLOUD_INFO | cut -d $ -f2)
EC_KN_HOST=$(echo $CLOUD_INFO | cut -d $ -f3)

for V in STACK_VER CLOUD_ID BEATS_AUTH EC_ES_HOST EC_SUFFIX; do
  VAL=$(eval "echo \${$V}")
  if [ -z "$VAL" ]; then
    _fail "Variable $V missing!"
  fi
  echo "$V=$VAL"
done

initialise_beat()
{
    BEAT_NAME=$1
    
    cp -f /etc/$BEAT_NAME/$BEAT_NAME.example.yml /etc/$BEAT_NAME/$BEAT_NAME.yml
    
    CONF_SNIPPET=$(cat <<'_EOM_'

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
        
    CHECK_ALIAS=$(curl -qks -u "$BEATS_AUTH" "https://$EC_ES_HOST.$EC_SUFFIX/_cat/aliases/$BEAT_NAME-$STACK_VER"||_fail "curl alias check failed")
    echo "CHECK_ALIAS=$CHECK_ALIAS"

    if echo "$CHECK_ALIAS"|grep -qv "$BEAT_NAME-$STACK_VER" ; then
      echo "$(date) Running $BEAT_NAME setup"
      #Log failure and continue
      $BEAT_NAME setup || echo "FAILED: $BEAT_NAME setup"
    fi
    
    echo "$(date) Starting $BEAT_NAME ($STACK_VER)"
    systemctl restart $BEAT_NAME
}

for B in metricbeat auditbeat filebeat packetbeat; do

  echo "$(date) Installing $B ($STACK_VER)"
  ./beats_install.sh $B $STACK_VER || _fail "Installing $B failed!"

  echo "$(date) Initialising $B ($STACK_VER)"
  initialise_beat $B
  
done
