#
# Run at startup by Task Scheduler with Spout env. on Skytap
#

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 

cd $PSScriptRoot

. ".\utilities.ps1"

Start-Transcript -Path spout_beats_startup.log -Append

& .\fetch_skytap_config.ps1

$config = Get-Content -Path "elastic_stack.config" | Out-String | ConvertFrom-StringData

ForEach ($b in @('metricbeat', 'winlogbeat', 'packetbeat') ) {
    
    & .\beats_install.ps1 "$b" $config.STACK_VERSION
    Stop-Service -Name "$b"
    #Set-Service -Name "$b" -StartupType Manual

    & .\beats_configure.ps1 "$b"
    Restart-Service -Name "$b" -Force
}

Stop-Transcript 
