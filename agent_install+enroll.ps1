#
# Install and Enroll the Elastic Agent on a Windows system.
# This script reads and uses the following settings read from a file called
# "elastic_stack.config":
# - CLOUD_ID: Elastic Cloud (or ECE) deployment ID to connect to
# - STACK_VERSION: The version to install. e.g. 7.9.2
# - AGENT_ENROLL_TOKEN: The Fleet Agent Enroll Token to enroll with
# Please create this^ file before running this script 

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 

cd $PSScriptRoot

. ".\utilities.ps1"

$config = Get-Content -Path "elastic_stack.config" | Out-String | ConvertFrom-StringData

# Unpack Cloud ID
$cloud_info = (b64dec($config.CLOUD_ID.Split(':')[1])).Split('$')
$es_url = "https://$($cloud_info[1]).$($cloud_info[0].Replace(':9243', ''))"
$kn_url = "https://$($cloud_info[2]).$($cloud_info[0].Replace(':9243', ''))"

$stack_ver = $config.STACK_VERSION
$agent_token = $config.AGENT_ENROLL_TOKEN

If (
    [string]::IsNullOrWhiteSpace($stack_ver) -or 
    [string]::IsNullOrWhiteSpace($kn_url) -or
    [string]::IsNullOrWhiteSpace($agent_token)
) {
    Write-Error "Configuration missing" -ErrorAction Stop 
}

$agent_zip = "elastic-agent-$stack_ver-windows-x86_64.zip"
$agent_zip_url = "https://artifacts.elastic.co/downloads/beats/elastic-agent/$agent_zip"
$agent_dir = "C:\Program Files\Elastic\Agent\$stack_ver"
$download_dir = "C:\ProgramData\Elastic\Downloads"

#echo $agent_zip_url

$ignore = (New-Item -Force -ItemType Directory -Path "$download_dir")

Get-ChildItem "C:\Program Files\Elastic\Agent\" -Attributes Directory -ErrorAction SilentlyContinue | ForEach-Object {
    $uninst = "C:\Program Files\Elastic\Agent\$_\uninstall-service-elastic-agent.ps1"
    If (Test-Path -Path "$uninst") {
        echo "Uninstalling existing: $_"

        Unblock-File -Path "$uninst"
        & "$uninst"

        # This is left running (not uninstalled), so we'll do it here...
        if (Get-Service ElasticEndpoint -ErrorAction SilentlyContinue) {
            $service = Get-WmiObject -Class Win32_Service -Filter "name='ElasticEndpoint'"
            $service.StopService()
            Start-Sleep -s 1
            $service.delete()
        }
    }
}
Remove-Item -Path "$agent_dir" -Recurse -Force -ErrorAction SilentlyContinue

If (-Not (Test-Path -Path "$download_dir\$agent_zip" )){
    Invoke-WebRequest -UseBasicParsing -Uri "$agent_zip_url" -OutFile "$download_dir\$agent_zip"
}

Expand-Archive -Path "$download_dir\$agent_zip" -DestinationPath "C:\Program Files\Elastic\Agent" -Force
Rename-Item -Path "C:\Program Files\Elastic\Agent\elastic-agent-$stack_ver-windows-x86_64" -NewName "$stack_ver" -Force

# FIXME elastic-agent appears broken with PS call cmd '&'
#& "$agent_dir\elastic-agent.exe" "@('enroll', $kn_url, $agent_token, '-f' )"

# This means no output, flying blind
Start-Process "$agent_dir\elastic-agent.exe" -ArgumentList @('enroll', $kn_url, $agent_token, '-f' ) -Wait -NoNewWindow

Unblock-File -Path "$agent_dir\install-service-elastic-agent.ps1"
& "$agent_dir\install-service-elastic-agent.ps1"

 
