#
# Run at startup by Task Scheduler with Spout env. on Skytap
#

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 

cd $PSScriptRoot

Start-Transcript -Path spout_agent_startup.log -Append

echo "Calling fetch_skytap_config"
& .\fetch_skytap_config.ps1

$config = Get-Content -Path "elastic_stack.config" | Out-String | ConvertFrom-StringData

If ($config.STACK_VERSION -And $config.FLEET_TOKEN) {
    echo "Calling agent_install+enroll"
    & .\agent_install+enroll.ps1
}

# Not coming up cleanly first time, so we give it a kick!
#Start-Sleep -s 30
#Restart-Service -Name elastic-agent -Force 

Stop-Transcript
