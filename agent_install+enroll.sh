#!/bin/sh
#
# Install and Enroll the Elastic Agent on a Linux system.
# This script reads and uses the following settings read from a file called
# "elastic_stack.config":
# - CLOUD_ID: Elastic Cloud (or ECE) deployment ID to connect to
# - STACK_VERSION: The version to install. e.g. 7.9.2
# - FLEET_TOKEN: The Fleet Agent Enroll Token to enroll with
# Please create this^ file before running this script 
#

#
# Reference: https://www.elastic.co/guide/en/ingest-management/current/elastic-agent-installation.html
#

set -e

SCRIPTDIR=$(dirname $0)
if [ "." = "$SCRIPTDIR" ]; then
  SCRIPTDIR=$(pwd)
fi

cd $SCRIPTDIR

. ./utilities.sh

for c in curl jq sed lsb_release base64 sort; do
  test -x "$(which $c)" || _fail "Programme '$c' appears to be missing"
done

#
# Grab config settings
#
. ./elastic_stack.config

CLOUD_INFO=$(echo ${CLOUD_ID#*:} | base64 -d -)

EC_SUFFIX=$(echo $CLOUD_INFO | cut -d $ -f1)
EC_SUFFIX=${EC_SUFFIX%:9243}

EC_ES_HOST=$(echo $CLOUD_INFO | cut -d $ -f2)
EC_KN_HOST=$(echo $CLOUD_INFO | cut -d $ -f3)

# Check config variables
for V in STACK_VERSION CLOUD_ID FLEET_TOKEN FLEET_SERVER EC_ES_HOST EC_SUFFIX; do
  VAL=$(eval "echo \${$V}")
  if [ -z "$VAL" ]; then
    _fail "Variable $V missing!"
  fi
  echo "$V=$VAL"
done

# Using Elastic Agent install allows the inline upgrade feature
# Used for 7.10.0 and above
install_on_Generic() {
  AGENT_PAC="elastic-agent-${STACK_VERSION}-linux-$(uname -m)"
  AGENT_URL="https://artifacts.elastic.co/downloads/beats/elastic-agent/${AGENT_PAC}.tar.gz"
  DL_DIR=/opt/Elastic/downloads
  
  mkdir -p $DL_DIR
  test -n "$DL_DIR" && rm -rf "$DL_DIR/elastic-agent*" || true
  cd $DL_DIR
  
  curl -qLO "$AGENT_URL"
  curl -qLO "$AGENT_URL.sha512"
  
  sha512sum --check <"${AGENT_PAC}.tar.gz.sha512" || _fail "SHA512 sum mismatch"
  
  tar zxvf "${AGENT_PAC}.tar.gz"
  
  if [ "$1" = "remove" ]; then
    /usr/bin/elastic-agent uninstall -f
  fi
  
  # Assuming we use install_on_Generic for 7.10.0 and up
  cd $AGENT_PAC
  if [ "7.13.0" = "$(echo -e 7.13.0\\n$STACK_VERSION | sort -V | head -n1)" ]; then 
    # 7.13.0 and up
    ./elastic-agent install -f --url "https://$FLEET_SERVER" -t "$FLEET_TOKEN"
  else
    # Below 7.13.0
    ./elastic-agent install -f -k "https://$EC_KN_HOST.$EC_SUFFIX" -t "$FLEET_TOKEN"
  fi

}

# Package installer disabled the inline upgrade feature
# Used for pre 7.10.0
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
  
  systemctl stop elastic-agent

  # Assuming we use package installation on versions below 7.10.0
  elastic-agent enroll "https://$EC_KN_HOST.$EC_SUFFIX" "$FLEET_TOKEN" -f
  
} # End: install_on_Debian

# Same as debian
install_on_Ubuntu() { install_on_Debian; }

# Package installer disabled the inline upgrade feature
# Used for pre 7.10.0
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
  
  systemctl stop elastic-agent

  # Assuming we use package installation on versions below 7.10.0
  elastic-agent enroll "https://$EC_KN_HOST.$EC_SUFFIX" "$FLEET_TOKEN" -f
  
} # End: install_on_CentOS

# Same as CentOS 
install_on_RHEL() { install_on_CentOS; }

################################################################
#
# Main script starts here

INST_TARGET=''
if [ "7.10.0" = "$(echo -e 7.10.0\\n$STACK_VERSION | sort -V | head -n1)" ]; then 
  # 7.10.0 and up
  INST_TARGET=Generic
else
  # Below 7.10.0
  INST_TARGET=$(lsb_release -is)
fi

# Is agent already installed?
if [ -x "$(which elastic-agent)" ]; then

  # Is an agent of the same version installed?
  CURRENT_VER=$(elastic-agent version | sed -Ee 's/.*version (\S*) .*/\1/')
  if [ "$CURRENT_VER" != "$STACK_VERSION" ]; then
    systemctl stop elastic-agent
    install_on_$INST_TARGET remove
  fi
  
else
  install_on_$INST_TARGET
fi

sleep 20s
systemctl restart elastic-agent
