#!/bin/sh
#
# Install and Enroll the Elastic Agent on a Linux system.
# This script reads and uses the following settings read from a file called
# "elastic_stack.config":
# - CLOUD_ID: Elastic Cloud (or ECE) deployment ID to connect to
# - STACK_VERSION: The version to install. e.g. 7.9.2
# - AGENT_ENROLL_TOKEN: The Fleet Agent Enroll Token to enroll with
# Please create this^ file before running this script 
#

set -e

SCRIPTDIR=$(dirname $0)
if [ "." = "$SCRIPTDIR" ]; then
  SCRIPTDIR=$(pwd)
fi

cd $SCRIPTDIR

. ./utilities.sh

for c in curl jq sed lsb_release base64; do
  test -x "$(which $c)" || _fail "Programme '$c' appears to be missing"
done

. ./elastic_stack.config

CLOUD_INFO=$(echo ${CLOUD_ID#*:} | base64 -d -)

EC_SUFFIX=$(echo $CLOUD_INFO | cut -d $ -f1)
EC_SUFFIX=${EC_SUFFIX%:9243}

EC_ES_HOST=$(echo $CLOUD_INFO | cut -d $ -f2)
EC_KN_HOST=$(echo $CLOUD_INFO | cut -d $ -f3)

for V in STACK_VERSION CLOUD_ID AGENT_ENROLL_TOKEN EC_ES_HOST EC_SUFFIX; do
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
  
  DEBIAN_FRONTEND=noninteractive apt-get --allow-downgrades -y install elastic-agent=$STACK_VERSION
  
  
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
  
  yum -y install elastic-agent-$STACK_VERSION
  
} # End: install_on_CentOS

# Same as CentOS 
install_on_RHEL() { install_on_CentOS; }

################################################################

if [ -x "$(which elastic-agent)" ]; then

  CURRENT_VER=$(elastic-agent version | sed -Ee 's/.*version (\S*) .*/\1/')
  if [ "$CURRENT_VER" != "$STACK_VERSION" ]; then
    systemctl stop elastic-agent
    install_on_$(lsb_release -is) remove
  fi
  
else
  install_on_$(lsb_release -is)
fi

systemctl stop elastic-agent

elastic-agent enroll "https://$EC_KN_HOST.$EC_SUFFIX" "$AGENT_ENROLL_TOKEN" -f

systemctl start elastic-agent
