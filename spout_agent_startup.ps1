#
# Run at startup by Task Scheduler with EC Spout env. on Skytap
#

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 

cd $PSScriptRoot

Start-Transcript -Path ec_spout_agent_startup.log -Append

& .\fetch_skytap_config.ps1

& .\agent_install+enroll.ps1

# Not coming up cleanly first time, so we give it a kick!
#Start-Sleep -s 30
#Restart-Service -Name elastic-agent -Force 

Stop-Transcript
