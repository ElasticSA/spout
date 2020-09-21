#!/bin/sh

set -e

SCRIPTDIR=$(dirname $0)
if [ "." = "$SCRIPTDIR" ]; then
  SCRIPTDIR=$(pwd)
fi

cd $SCRIPTDIR

exec >ec_spout_agent_startup.log 2>&1

_fail() {
  echo $@ >&2
  exit 1
}

for c in curl jq sed lsb_release base64; do
  test -x "$(which $c)" || _fail "Programme '$c' appears to be missing"
done

SKYTAP_DATA=$(curl -qs http://gw/skytap||_fail "curl skytap failed")

ENV_CONFIG=$(echo -e $(echo $SKYTAP_DATA | jq .configuration_user_data))
ENV_CONFIG="${ENV_CONFIG%\"}"
ENV_CONFIG="${ENV_CONFIG#\"}"

VM_CONFIG=$(echo -e $(echo $SKYTAP_DATA | jq .user_data))
VM_CONFIG="${VM_CONFIG%\"}"
VM_CONFIG="${VM_CONFIG#\"}"

STACK_VER=$(echo "$ENV_CONFIG" | sed -Ene 's/^stack_version:\s*(.*)$/\1/ p')
CLOUD_ID=$(echo "$ENV_CONFIG" | sed -Ene 's/^cloud_id:\s*(.*)$/\1/ p')
AGENT_TOKEN=$(echo "$ENV_CONFIG" | sed -Ene 's/^agent_enroll_token:\s*(.*)$/\1/ p')

CLOUD_INFO=$(echo ${CLOUD_ID#*:} | base64 -d -)

EC_SUFFIX=$(echo $CLOUD_INFO | cut -d $ -f1)
EC_SUFFIX=${EC_SUFFIX%:9243}

EC_ES_HOST=$(echo $CLOUD_INFO | cut -d $ -f2)
EC_KN_HOST=$(echo $CLOUD_INFO | cut -d $ -f3)

for V in STACK_VER CLOUD_ID AGENT_TOKEN EC_ES_HOST EC_SUFFIX; do
  VAL=$(eval "echo \${$V}")
  if [ -z "$VAL" ]; then
    _fail "Variable $V missing!"
  fi
  echo "$V=$VAL"
done

install_on_Debian() {

  # Test if we already added the elastic repository, and add it if not
  if ! test -f /etc/apt/sources.list.d/elastic-7.x.list ; then
  
    DEBIAN_FRONTEND=noninteractive apt-get -y install apt-transport-https ca-certificates
  
    curl -fsSL https://artifacts.elastic.co/GPG-KEY-elasticsearch | apt-key add -
  
    echo "deb https://artifacts.elastic.co/packages/7.x/apt stable main" \
      > /etc/apt/sources.list.d/elastic-7.x.list
    
    apt-get update
  fi

  if [ "$1" = "remove" ]; then
    DEBIAN_FRONTEND=noninteractive apt-get -y purge elastic-agent
    rm -rf "/etc/elastic-agent"
  fi
  
  DEBIAN_FRONTEND=noninteractive apt-get --allow-downgrades -y install elastic-agent=$STACK_VER
  
  
} # End: install_on_Debian

# Same as debian
install_on_Ubuntu() { install_on_Debian; }


install_on_CentOS() {

  # Test if we already added the elastic repository, and add it if not
  if ! test -f /etc/yum.repos.d/elastic.repo ; then
  
    rpm --import https://packages.elastic.co/GPG-KEY-elasticsearch

    cat >/etc/yum.repos.d/elastic.repo <<_EOF_
[elastic-7.x]
name=Elastic repository for 7.x packages
baseurl=https://artifacts.elastic.co/packages/7.x/yum
gpgcheck=1
gpgkey=https://artifacts.elastic.co/GPG-KEY-elasticsearch
enabled=1
autorefresh=1
type=rpm-md
_EOF_

    #yum repolist
  fi

  if [ "$1" = "remove" ]; then
    yum -y remove elastic-agent
    rm -rf "/etc/elastic-agent"
  fi
  
  yum -y install elastic-agent-$STACK_VER
  
} # End: install_on_CentOS

# Same as CentOS 
install_on_RHEL() { install_on_CentOS; }

################################################################

if [ -x "$(which elastic-agent)" ]; then

  CURRENT_VER=$(elastic-agent version | sed -Ee 's/.*version (\S*) .*/\1/')
  if [ "$CURRENT_VER" != "$STACK_VER" ]; then
    install_on_$(lsb_release -is) remove
  fi
  
else
  install_on_$(lsb_release -is)
fi

systemctl disable elastic-agent
systemctl stop elastic-agent

elastic-agent enroll "https://$EC_KN_HOST.$EC_SUFFIX" "$AGENT_TOKEN" -f

systemctl start elastic-agent
