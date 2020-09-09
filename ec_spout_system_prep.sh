#!/bin/sh

SCRIPTDIR=$(basename $0)
if [ "." = "$SCRIPTDIR" ]; then
  SCRIPTDIR=$(pwd)
fi

cd $SCRIPTDIR

install_on_Debian()
{
  DEBIAN_FRONTEND=noninteractive apt-get -y install lsb-release curl jq
}

install_on_Ubuntu() { install_on_Debian; }

install_on_CentOS()
{
  yum -y install lsb-release curl jq
}

install_on_RHEL() { install_on_CentOS; }


#####################################################

install_on_$(lsb_release -is)

cat >/etc/systemd/system/ec_spout_beats.service <<_EOM_
[Unit]
Description=EC Spout: Initialise Beats 

[Service]
Type=oneshot
ExecStart=$SCRIPTDIR/ec_spout_beats_startup.sh

[Install]
WantedBy=multi-user.target

_EOM_

cat >/etc/systemd/system/ec_spout_agent.service <<_EOM_
[Unit]
Description=EC Spout: Initialise Agent

[Service]
Type=oneshot
ExecStart=$SCRIPTDIR/ec_spout_agent_startup.sh

[Install]
WantedBy=multi-user.target

_EOM_

systemctl daemon-reload

systemctl enable ec_spout_beats_startup
systemctl enable ec_spout_agent_startup
