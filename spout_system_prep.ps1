# Run once to prepare a EC Spout VM image

# Note on Win10: First run:  
#  Set-ExecutionPolicy RemoteSigned -Scope LocalMachine -Force
#  Unblock-File -Path .\spout_system_prep.ps1
 
$npcap_url = "https://nmap.org/npcap/dist/npcap-0.9997.exe"

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 
cd $PSScriptRoot

$dl_dir = "$env:USERPROFILE\Downloads"
$temp_dir = "$env:TEMP\spout_$(Get-Date -Format 'yyyy-MM-dd')"
$ignore = (New-Item -Force -ItemType Directory -Path "$temp_dir")

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
$sysmon_installer_url = "https://download.sysinternals.com/files/Sysmon.zip"
$sysmon_config_url = "https://raw.githubusercontent.com/olafhartong/sysmon-modular/master/sysmonconfig.xml"
$sysmon_config = "C:\Windows\sysmon.xml"



If (Test-Path "C:\Windows\Sysmon64.exe") {
    echo "Unistalling Sysmon..."
    Start-Process -WorkingDirectory "C:\Windows" -FilePath "Sysmon64" -ArgumentList "-u" -Wait -NoNewWindow
}

echo "Installing Sysmon..."

Invoke-WebRequest -UseBasicParsing -Uri $sysmon_config_url -OutFile $sysmon_config
Invoke-WebRequest -UseBasicParsing -Uri $sysmon_installer_url -OutFile "$temp_dir/Sysmon.zip"

Expand-Archive -Path $temp_dir/Sysmon.zip -DestinationPath $temp_dir -Force

Start-Process -FilePath "$temp_dir\Sysmon64.exe" -WorkingDirectory "$temp_dir" -ArgumentList "-accepteula -i $sysmon_config" -Wait -NoNewWindow

#Remove-Item -Path $temp_dir -Recurse -Force -ErrorAction SilentlyContinue
echo "Sysmon Installation Complete"

if ((Get-Command python.exe) -And (Get-Command pip.exe)) {
    & pip install requests pyyaml
}

# Mostly disable Windows Defender
Set-MpPreference -DisableArchiveScanning $True `
    -DisableAutoExclusions $True `
    -DisableBehaviorMonitoring $True `
    -DisableBlockAtFirstSeen $True `
    -DisableCatchupFullScan $True `
    -DisableCatchupQuickScan $True `
    -DisableCpuThrottleOnIdleScans $True `
    -DisableDatagramProcessing $True `
    -DisableEmailScanning $True `
    -DisableIntrusionPreventionSystem $True `
    -DisableIOAVProtection $True `
    -DisablePrivacyMode $True `
    -DisableRealtimeMonitoring $True `
    -DisableRemovableDriveScanning $True `
    -DisableRestorePoint $True `
    -DisableScanningMappedNetworkDrivesForFullScan $True `
    -DisableScanningNetworkFiles $True `
    -DisableScriptScanning $True


# Configure EC spout scripts

Unblock-File -Path utilities.ps1
Unblock-File -Path agent_install+enroll.ps1
Unblock-File -Path beats_configure.ps1
Unblock-File -Path beats_install.ps1
Unblock-File -Path spout_agent_startup.ps1
Unblock-File -Path spout_beats_startup.ps1
Unblock-File -Path spout_rta_startup.ps1
Unblock-File -Path fetch_skytap_config.ps1

# beats
$action = New-ScheduledTaskAction `
    -Execute "$PSHOME\powershell.exe" `
    -Argument "-NoProfile -NoLogo -NonInteractive -WindowStyle Hidden -File $PSScriptRoot\spout_beats_startup.ps1"
$trigger =  New-ScheduledTaskTrigger -AtStartup -RandomDelay 00:01:30
$settings = New-ScheduledTaskSettingsSet `
    -ExecutionTimeLimit 00:20:00 -RestartCount 3 -RestartInterval 00:01:00

Unregister-ScheduledTask -TaskName "ec_spout_beats_startup" -ErrorAction SilentlyContinue
Unregister-ScheduledTask -TaskName "spout_beats_startup" -ErrorAction SilentlyContinue
Register-ScheduledTask -Force `
    -TaskName "spout_beats_startup" -Description "ElasticSA Spout: Initialise all beats at startup" `
    -Action $action -Trigger $trigger -Settings $settings -User "System"

# agent
$action = New-ScheduledTaskAction `
    -Execute "$PSHOME\powershell.exe" `
    -Argument "-NoProfile -NoLogo -NonInteractive -WindowStyle Hidden -File $PSScriptRoot\spout_agent_startup.ps1"
$trigger =  New-ScheduledTaskTrigger -AtStartup -RandomDelay 00:01:30
$settings = New-ScheduledTaskSettingsSet `
    -ExecutionTimeLimit 00:20:00 -RestartCount 3 -RestartInterval 00:01:00

Unregister-ScheduledTask -TaskName "ec_spout_agent_startup" -ErrorAction SilentlyContinue
Unregister-ScheduledTask -TaskName "spout_agent_startup" -ErrorAction SilentlyContinue
Register-ScheduledTask -Force `
    -TaskName "spout_agent_startup" -Description "Elastic Cloud Spout: Initialise agent at startup" `
    -Action $action -Trigger $trigger -Settings $settings -User "System" 

# rta
$action = New-ScheduledTaskAction `
    -Execute "$PSHOME\powershell.exe" `
    -Argument "-NoProfile -NoLogo -NonInteractive -WindowStyle Hidden -File $PSScriptRoot\spout_rta_startup.ps1"
$trigger =  New-ScheduledTaskTrigger -AtStartup -RandomDelay 00:01:30
$trigger.Delay = 'PT5M'
$settings = New-ScheduledTaskSettingsSet `
    -ExecutionTimeLimit 01:30:00 -RestartCount 2 -RestartInterval 00:05:00

Unregister-ScheduledTask -TaskName "spout_rta_startup" -ErrorAction SilentlyContinue
Register-ScheduledTask -Force `
    -TaskName "spout_rta_startup" -Description "Elastic Cloud Spout: Initialise RTA TTP execution" `
    -Action $action -Trigger $trigger -Settings $settings -User "System" 

