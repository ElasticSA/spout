#!/bin/sh

SCRIPTDIR=$(dirname $0)
if [ "." = "$SCRIPTDIR" ]; then
  SCRIPTDIR=$(pwd)
fi

cd $SCRIPTDIR

YQ_PKG_URL="https://github.com/mikefarah/yq/releases/download/3.4.0/yq_linux_amd64"

install_with_apt()
{
  DEBIAN_FRONTEND=noninteractive apt-get -y install lsb-release curl jq
}

install_with_yum()
{
  yum -y install redhat-lsb-core curl jq
}



#####################################################

if [ -x "$(which apt-get)" ]; then
  install_with_apt
fi

if [ -x "$(which yum)" ]; then
  install_with_yum
fi

cat >/etc/systemd/system/ec_spout_beats.service <<_EOM_
[Unit]
Description=EC Spout: Initialise Beats 
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=$SCRIPTDIR/ec_spout_beats_startup.sh

#CentOS' systemd does not allow this (too old I guess)
#Restart=on-failure
#RestartSec=60

[Install]
WantedBy=multi-user.target

_EOM_

cat >/etc/systemd/system/ec_spout_agent.service <<_EOM_
[Unit]
Description=EC Spout: Initialise Agent
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=$SCRIPTDIR/ec_spout_agent_startup.sh

#CentOS' systemd does not allow this (too old I guess)
#Restart=on-failure
#RestartSec=60

[Install]
WantedBy=multi-user.target

_EOM_

systemctl daemon-reload

systemctl enable ec_spout_beats.service
systemctl enable ec_spout_agent.service

curl -qL "$YQ_PKG_URL" -o /usr/local/bin/yq
chmod +x /usr/local/bin/yq
