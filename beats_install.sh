#!/bin/bash

# Install givn beat and version
# Will replace any old/new version already installed

BEAT_NAME=$1
STACK_VER=$2

_fail() {
  echo $@ >&2
  exit 1
}

# Test that programmes we are going to use are installed
for c in curl lsb_release sed base64; do
  test -x "$(which $c)" || _fail "Programme '$c' appears to be missing"
done

test -n "$BEAT_NAME" && _fail "Beat name argument misssing"
test -n "$STACK_VER" && _fail "Stack version argument missing"

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

  test -f /etc/$BEAT_NAME/$BEAT_NAME.yml && 
    mv /etc/$BEAT_NAME/$BEAT_NAME.yml /etc/$BEAT_NAME/$BEAT_NAME.old.yml 
    
  # Install our list of beats
  sudo DEBIAN_FRONTEND=noninteractive apt-get --allow-downgrades -y -o Dpkg::Options::="--force-confask,confnew,confmiss" install $BEAT_NAME=$STACK_VER
  
  cp /etc/$BEAT_NAME/$BEAT_NAME.yml /etc/$BEAT_NAME/$BEAT_NAME.example.yml
  
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

  test -f /etc/$BEAT_NAME/$BEAT_NAME.yml && 
    mv /etc/$BEAT_NAME/$BEAT_NAME.yml /etc/$BEAT_NAME/$BEAT_NAME.old.yml 
    
  # Install our list of beats
  sudo yum -y install $BEAT_NAME-$STACK_VER
  
  cp /etc/$BEAT_NAME/$BEAT_NAME.yml /etc/$BEAT_NAME/$BEAT_NAME.example.yml
} # End: install_on_CentOS

# Same as CentOS 
install_on_RHEL() { install_on_CentOS; }

#########################################################################

if [ -x "$(which $BEAT_NAME)" ]; do

  CURRENT_VER=$($BEAT_NAME version | sed -Ee 's/.*version (\S*) .*/\1/')
  if [ "$CURRENT_VER" != "$STACK_VER" ]; then
    install_on_$(lsb_release -is)
  fi
  
else
  install_on_$(lsb_release -is)
fi

$BEAT_NAME -c "$BEAT_NAME.example.yml" keystore create --force

# Will be started by the ec spout startup script
systemctl disable $BEAT_NAME
systemctl stop $BEAT_NAME
