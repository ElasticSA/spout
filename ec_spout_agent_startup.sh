#!/bin/sh

SCRIPTDIR=$(basename $0)
if [ "." = "$SCRIPTDIR" ]; then
  SCRIPTDIR=$(pwd)
fi

cd $SCRIPTDIR

exec >ec_spout_agent_startup.log 2>&1

for c in curl jq sed base64; do
  test -x "$(which $c)" || _fail "Programme '$c' appears to be missing"
done

SKYTAP_DATA=$(curl -qs http://gw/skytap)
ENV_CONFIG=$(echo -e $(echo $SKYTAP_DATA | jq .configuration_user_data))
VM_CONFIG=$(echo -e $(echo $SKYTAP_DATA | jq .user_data))

STACK_VER=$(echo $ENV_CONFIG | sed -Ene 's/^stack_version:\s*(.*)$/\1/ p')
CLOUD_ID=$(echo $ENV_CONFIG | sed -Ene 's/^cloud_id:\s*(.*)$/\1/ p')
AGENT_TOKEN=$(echo $ENV_CONFIG | sed -Ene 's/^agent_enroll_token:\s*(.*)$/\1/ p')

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


install_on_Debian() {

  # Test if we already added the elastic repository, and add it if not
  if ! test -f /etc/apt/sources.list.d/elastic-7.x.list ; then
  
    # Doc Ref: https://www.elastic.co/guide/en/beats/metricbeat/current/setup-repositories.html
    sudo DEBIAN_FRONTEND=noninteractive apt-get -y install apt-transport-https ca-certificates
  
    curl -fsSL https://artifacts.elastic.co/GPG-KEY-elasticsearch | sudo apt-key add -
  
    echo "deb https://artifacts.elastic.co/packages/7.x/apt stable main" \
      | sudo tee /etc/apt/sources.list.d/elastic-7.x.list >/dev/null
    
    sudo apt-get update
  fi
    
  # Install our list of beats
  sudo DEBIAN_FRONTEND=noninteractive apt-get --allow-downgrades -y install elastic-agent=$STACK_VER
  
  
} # End: install_on_Debian

# Same as debian
install_on_Ubuntu() { install_on_Debian; }


install_on_CentOS() {

  # Test if we already added the elastic repository, and add it if not
  if ! test -f /etc/yum.repos.d/elastic.repo ; then
  
    # Doc Ref: https://www.elastic.co/guide/en/beats/metricbeat/current/setup-repositories.html
    sudo rpm --import https://packages.elastic.co/GPG-KEY-elasticsearch

    # This "cat | sudo tee" construct is a way to write to a privileged files from a
    # non-privileged user, you will see this a lot in this script!
    cat <<_EOF_ |
[elastic-7.x]
name=Elastic repository for 7.x packages
baseurl=https://artifacts.elastic.co/packages/7.x/yum
gpgcheck=1
gpgkey=https://artifacts.elastic.co/GPG-KEY-elasticsearch
enabled=1
autorefresh=1
type=rpm-md
_EOF_
    sudo tee /etc/yum.repos.d/elastic.repo

    #sudo yum repolist
  fi
    
  # Install our list of beats
  sudo yum -y install elastic-agent-$STACK_VER
  
} # End: install_on_CentOS

# Same as CentOS 
install_on_RHEL() { install_on_CentOS; }

################################################################

if [ -x "$(which elastic-agent)" ]; do

  CURRENT_VER=$(elastic-agent version | sed -Ee 's/.*version (\S*) .*/\1/')
  if [ "$CURRENT_VER" != "$STACK_VER" ]; then
    install_on_$(lsb_release -is)
  fi
  
else
  install_on_$(lsb_release -is)
fi

systemctl disable elastic-agent
systemctl stop elastic-agent

elastic-agent enroll "$EC_KN_HOST.$EC_SUFFIX" "$AGENT_TOKEN" -f

systemctl start elastic-agent
