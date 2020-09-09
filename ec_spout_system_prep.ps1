 # Run once to prepare a system

# Note one Win10: First run:  
#  Set-ExecutionPolicy RemoteSigned -Scope LocalMachine -Force
#  Unblock-File -Path .\ec_spout_system_prep.ps1
 
$npcap_url = "https://nmap.org/npcap/dist/npcap-0.9997.exe"

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 
cd $PSScriptRoot

$dl_dir = "$env:USERPROFILE\Downloads"

# Install PS YAML parser
Install-Module powershell-yaml

# Install npcap (reboot before installing packetbeat for the first time!)
If (-Not (Get-Package -Name Npcap -ErrorAction SilentlyContinue)) {

    $npcap_installer = ("$dl_dir\" + [System.io.Path]::GetFileName($npcap_url))

    Invoke-WebRequest -UseBasicParsing -Uri $npcap_url -OutFile $npcap_installer

    # The free version of the npcap installer does not allow non-interactive installs
    & $npcap_installer
}

# Install sysmon
$sysmon_temp_dir = "C:\Windows\Temp\ec_spout_sysmon"
$sysmon_installer_url = "https://download.sysinternals.com/files/Sysmon.zip"
$sysmon_config_url = "https://raw.githubusercontent.com/olafhartong/sysmon-modular/master/sysmonconfig.xml"
$sysmon_config = "C:\Windows\sysmon.xml"

$ignore = (New-Item -Force -ItemType Directory -Path "$sysmon_temp_dir")

If (Test-Path "C:\Windows\Sysmon64.exe") {
    echo "Unistalling Sysmon..."
    Start-Process -WorkingDirectory "C:\Windows" -FilePath "Sysmon64" -ArgumentList "-u" -Wait -NoNewWindow
}

echo "Installing Sysmon..."

Invoke-WebRequest -UseBasicParsing -Uri $sysmon_config_url -OutFile $sysmon_config
Invoke-WebRequest -UseBasicParsing -Uri $sysmon_installer_url -OutFile "$sysmon_temp_dir/Sysmon.zip"

Expand-Archive -Path $sysmon_temp_dir/Sysmon.zip -DestinationPath $sysmon_temp_dir -Force

Start-Process -FilePath "$sysmon_temp_dir\Sysmon64.exe" -WorkingDirectory "$sysmon_temp_dir" -ArgumentList "-accepteula -i $sysmon_config" -Wait -NoNewWindow

Remove-Item -Path $sysmon_temp_dir -Recurse -Force -ErrorAction SilentlyContinue
echo "Sysmon Installation Complete"

# Configure EC spout scripts

Unblock-File -Path beats_install.ps1
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
