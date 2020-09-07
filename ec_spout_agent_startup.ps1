 
$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 

cd $PSScriptRoot

Start-Transcript -Path ec_spout_agent_startup.log -Append

function b64dec ([string]$str)
{
    return [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($str))
}

function b64enc ([string]$str)
{
    return [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($str))
}

try {
    $skytap_data = ((Invoke-WebRequest -UseBasicParsing -Uri 'http://gw/skytap').Content | ConvertFrom-Json)
    $env_config = ($skytap_data.configuration_user_data | ConvertFrom-yaml)
    $vm_config = ($skytap_data.user_data | ConvertFrom-yaml)
}
catch {
     Write-Error "Skytap data fetch failed, maybe try again" -ErrorAction Stop
}

$cloud_info = (b64dec($env_config.cloud_id.Split(':')[1])).Split('$')
$es_url = "https://$($cloud_info[1]).$($cloud_info[0].Replace(':9243', ''))"
$kn_url = "https://$($cloud_info[2]).$($cloud_info[0].Replace(':9243', ''))"

#echo $env_config
#echo $cloud_info
#echo $es_url

If (
    [string]::IsNullOrWhiteSpace($env_config.stack_version) -or 
    [string]::IsNullOrWhiteSpace($kn_url) -or
    [string]::IsNullOrWhiteSpace($env_config.agent_enroll_token)
) {
    Write-Error "Configuration missing" -ErrorAction Stop 
}

$stack_ver = $env_config.stack_version
$agent_zip = "elastic-agent-$stack_ver-windows-x86_64.zip"
$agent_zip_url = "https://artifacts.elastic.co/downloads/beats/elastic-agent/$agent_zip"
$agent_dir = "C:\Program Files\Elastic\Agent\$stack_ver"
$download_dir = "C:\Program Files\Elastic\Downloads"

#echo $agent_zip_url

$ignore = (New-Item -Force -ItemType Directory -Path "$download_dir\logs")

Get-ChildItem "C:\Program Files\Elastic\Agent\" -Attributes Directory | ForEach-Object {
    $uninst = "C:\Program Files\Elastic\Agent\$_\uninstall-service-elastic-agent.ps1"
    If (Test-Path -Path "$uninst") {
        echo "Uninstalling existing: $_"
        Unblock-File -Path "$uninst"
        & "$uninst"
    }
}
Remove-Item -Path "$agent_dir" -Recurse -Force -ErrorAction SilentlyContinue

If (-Not (Test-Path -Path "$download_dir\$agent_zip" )){
    Invoke-WebRequest -UseBasicParsing -Uri "$agent_zip_url" -OutFile "$download_dir\$agent_zip"
}

Expand-Archive -Path "$download_dir\$agent_zip" -DestinationPath "C:\Program Files\Elastic\Agent" -Force
Rename-Item -Path "C:\Program Files\Elastic\Agent\elastic-agent-$stack_ver-windows-x86_64" -NewNAme "$stack_ver" -Force

# FIXME elastic-agent appears broken with PS call cmd '&'
#& "$agent_dir\elastic-agent.exe" "@('enroll', $kn_url, $($env_config.agent_enroll_token), '-f' )"

# This means no output, flying blind
Start-Process "$agent_dir\elastic-agent.exe" -ArgumentList @('enroll', $kn_url, $env_config.agent_enroll_token, '-f' ) -NoNewWindow

Unblock-File -Path "$agent_dir\install-service-elastic-agent.ps1"
& "$agent_dir\install-service-elastic-agent.ps1"

# Not coming up cleanly first time, so we give it a kick!
Start-Sleep -s 30
Restart-Service -Name elastic-agent -Force 

Stop-Transcript
