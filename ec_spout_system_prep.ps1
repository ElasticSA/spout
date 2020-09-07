 # Run once to prepare a system

$npcap_url = "https://nmap.org/npcap/dist/npcap-0.9997.exe"

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 
cd $PSScriptRoot

# Install PS YAML parser
Install-Module powershell-yaml

# Install npcap (reboot before installing packetbeat for the first time!)
If (-Not (Get-Package -Name Npcap)) {
    $dl_dir = "$env:USERPROFILE\Downloads"
    $npcap_installer = ("$dl_dir\" + [System.io.Path]::GetFileName($npcap_url))

    Invoke-WebRequest -UseBasicParsing -Uri $npcap_url -OutFile $npcap_installer

    # The free version of the npcap installer does not allow non-interactive installs
    & $npcap_installer
}

# Configure EC spout scripts

Unblock-File -Path ec_spout_agent_startup.ps1
Unblock-File -Path ec_spout_beats_startup.ps1

# beats
$action = New-ScheduledTaskAction `
    -Execute "$PSHOME\powershell.exe" `
    -Argument "-NoProfile -NoLogo -NonInteractive -WindowStyle Hidden -File $PSScriptRoot\ec_spout_beats_startup.ps1"
$trigger =  New-ScheduledTaskTrigger -AtStartup -RandomDelay 00:00:30
$settings = New-ScheduledTaskSettingsSet `
    -ExecutionTimeLimit 00:20:00 -RestartCount 3 -RestartInterval 00:01:00
Register-ScheduledTask -Force `
    -TaskName "ec_spout_beats_startup" -Description "Elastic Cloud Spout: Initialise all beats at startup" `
    -Action $action -Trigger $trigger -Settings $settings -User "System"

# agent
$action = New-ScheduledTaskAction `
    -Execute "$PSHOME\powershell.exe" `
    -Argument "-NoProfile -NoLogo -NonInteractive -WindowStyle Hidden -File $PSScriptRoot\ec_spout_agent_startup.ps1"
$trigger =  New-ScheduledTaskTrigger -AtStartup -RandomDelay 00:00:30
$settings = New-ScheduledTaskSettingsSet `
    -ExecutionTimeLimit 00:20:00 -RestartCount 3 -RestartInterval 00:01:00
Register-ScheduledTask -Force `
    -TaskName "ec_spout_agent_startup" -Description "Elastic Cloud Spout: Initialise agent at startup" `
    -Action $action -Trigger $trigger -Settings $settings -User "System" 
