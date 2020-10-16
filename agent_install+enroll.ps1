 
$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 

cd $PSScriptRoot

. ".\utilities.ps1"

$config = Get-Content -Path "elastic_stack.config" | Out-String | ConvertFrom-StringData

$cloud_info = (b64dec($config.CLOUD_ID.Split(':')[1])).Split('$')
$es_url = "https://$($cloud_info[1]).$($cloud_info[0].Replace(':9243', ''))"
$kn_url = "https://$($cloud_info[2]).$($cloud_info[0].Replace(':9243', ''))"
$stack_ver = $config.STACK_VERSION

#echo $config
#echo $cloud_info
#echo $es_url

If (
    [string]::IsNullOrWhiteSpace($stack_ver) -or 
    [string]::IsNullOrWhiteSpace($kn_url) -or
    [string]::IsNullOrWhiteSpace($config.AGENT_ENROLL_TOKEN)
) {
    Write-Error "Configuration missing" -ErrorAction Stop 
}

$agent_zip = "elastic-agent-$stack_ver-windows-x86_64.zip"
$agent_zip_url = "https://artifacts.elastic.co/downloads/beats/elastic-agent/$agent_zip"
$agent_dir = "C:\Program Files\Elastic\Agent\$stack_ver"
$download_dir = "C:\Program Files\Elastic\Downloads"

#echo $agent_zip_url

$ignore = (New-Item -Force -ItemType Directory -Path "$download_dir\logs")

Get-ChildItem "C:\Program Files\Elastic\Agent\" -Attributes Directory -ErrorAction SilentlyContinue | ForEach-Object {
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
Rename-Item -Path "C:\Program Files\Elastic\Agent\elastic-agent-$stack_ver-windows-x86_64" -NewName "$stack_ver" -Force

# FIXME elastic-agent appears broken with PS call cmd '&'
#& "$agent_dir\elastic-agent.exe" "@('enroll', $kn_url, $($config.AGENT_ENROLL_TOKEN), '-f' )"

# This means no output, flying blind
Start-Process "$agent_dir\elastic-agent.exe" -ArgumentList @('enroll', $kn_url, $config.AGENT_ENROLL_TOKEN, '-f' ) -Wait -NoNewWindow

Unblock-File -Path "$agent_dir\install-service-elastic-agent.ps1"
& "$agent_dir\install-service-elastic-agent.ps1"

