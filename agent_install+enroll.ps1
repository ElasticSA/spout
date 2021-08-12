 #
# Install and Enroll the Elastic Agent on a Windows system.
# This script reads and uses the following settings read from a file called
# "elastic_stack.config":
# - CLOUD_ID: Elastic Cloud (or ECE) deployment ID to connect to
# - STACK_VERSION: The version to install. e.g. 7.9.2
# - FLEET_TOKEN: The Fleet Agent Enroll Token to enroll with
# Please create this^ file before running this script 

#
# Reference: https://www.elastic.co/guide/en/ingest-management/current/elastic-agent-installation.html
#

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 

cd $PSScriptRoot

. ".\utilities.ps1"

#
# Grab the config settings
#
$config = Get-Content -Path "elastic_stack.config" | Out-String | ConvertFrom-StringData

# Unpack Cloud ID
$cloud_info = (b64dec($config.CLOUD_ID.Split(':')[1])).Split('$')
$es_url = "https://$($cloud_info[1]).$($cloud_info[0].Replace(':9243', ''))"
$kn_url = "https://$($cloud_info[2]).$($cloud_info[0].Replace(':9243', ''))"
$flt_url = $config.FLEET_SERVER

$stack_ver = $config.STACK_VERSION
$fleet_token = $config.FLEET_TOKEN

# Check config variables
If (
    [string]::IsNullOrWhiteSpace($stack_ver) -or 
    [string]::IsNullOrWhiteSpace($kn_url) -or
    [string]::IsNullOrWhiteSpace($flt_url) -or
    [string]::IsNullOrWhiteSpace($fleet_token)
) {
    Write-Error "Configuration missing" -ErrorAction Stop 
}

function install_pre-7-10 ()
{
    echo "--- Installing pre-7.10.0 ---"

    # Prepare some common used strings
    $agent_zip = "elastic-agent-${stack_ver}-windows-x86_64.zip"
    $agent_zip_url = "https://artifacts.elastic.co/downloads/beats/elastic-agent/$agent_zip"
    $agent_dir = "C:\Program Files\Elastic\Agent\$stack_ver"
    $download_dir = "C:\ProgramData\Elastic\Downloads"

    # Ensure d/l dir exists
    $ignore = (New-Item -Force -ItemType Directory -Path "$download_dir")

    # Iterate through any existing agent install directories and uninstall them
    Get-ChildItem "C:\Program Files\Elastic\Agent\" -Attributes Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $uninst = "C:\Program Files\Elastic\Agent\$_\uninstall-service-elastic-agent.ps1"
        If (Test-Path -Path "$uninst") {
            echo "Uninstalling existing: $_"

            Unblock-File -Path "$uninst"
            & "$uninst"

            # ElasticEndpoint can be left running (not uninstalled), so we'll uninstall it here...
            if (Get-Service ElasticEndpoint -ErrorAction SilentlyContinue) {
                $service = Get-WmiObject -Class Win32_Service -Filter "name='ElasticEndpoint'"
                $service.StopService()
                Start-Sleep -s 1
                $service.delete()
            }
        }
    }
    Remove-Item -Path "$agent_dir" -Recurse -Force -ErrorAction SilentlyContinue


    download_file "$agent_zip_url" "$download_dir\$agent_zip"

    # Unpack
    Expand-Archive -Path "$download_dir\$agent_zip" -DestinationPath "C:\Program Files\Elastic\Agent" -Force
    Rename-Item -Path "C:\Program Files\Elastic\Agent\elastic-agent-${stack_ver}-windows-x86_64" -NewName "$stack_ver" -Force
    
    #
    # Install and Enroll agent to ES/Kibana
    $ErrorActionPreference = "Continue" #Ignore STDERR 'errors' 
    & "$agent_dir\elastic-agent.exe" enroll "$kn_url" "$fleet_token" -f
    
    # This means no output, flying blind
    #Start-Process "$agent_dir\elastic-agent.exe" -ArgumentList @('enroll', $kn_url, $fleet_token, '-f' ) -Wait -NoNewWindow
    
    #
    # Install the Agent service
    Unblock-File -Path "$agent_dir\install-service-elastic-agent.ps1"
    & "$agent_dir\install-service-elastic-agent.ps1"
}

function install_post-7-10 ()
{
    echo "--- Installing 7.10.0 and/or above ---"

    # Prepare some common used strings
    $agent_zip = "elastic-agent-${stack_ver}-windows-x86_64.zip"
    $agent_zip_url = "https://artifacts.elastic.co/downloads/beats/elastic-agent/$agent_zip"
    #$agent_dir = "C:\Program Files\Elastic\Agent\$stack_ver"
    $download_dir = "C:\ProgramData\Elastic\Downloads"

    # Ensure d/l dir exists
    $ignore = (New-Item -Force -ItemType Directory -Path "$download_dir")


    If (Test-Path -Path "C:\Program Files\Elastic\Agent\elastic-agent.exe") {
        echo "Uninstalling existing"

	# Ignore failed uninstall
	$ErrorActionPreference = "Continue"
        & "C:\Program Files\Elastic\Agent\elastic-agent.exe" uninstall -f

        # ElasticEndpoint can be left running (not uninstalled), so we'll uninstall it here...
        if (Get-Service ElasticEndpoint -ErrorAction SilentlyContinue) {
            $service = Get-WmiObject -Class Win32_Service -Filter "name='ElasticEndpoint'"
            $service.StopService()
            Start-Sleep -s 1
            $service.delete()
        }

	$ErrorActionPreference = "Stop"
    }


    download_file "$agent_zip_url" "$download_dir\$agent_zip"

    # Unpack
    Expand-Archive -Path "$download_dir\$agent_zip" -DestinationPath "$download_dir" -Force

    #
    # Install and Enroll agent to ES/Kibana
    #
    if ([version]"7.13.0" -le [version]$stack_ver) {
        # Version 7.13.0 and above with Fleet server
        $ErrorActionPreference = "Continue" #Ignore STDERR output being treated as errors
        & "$download_dir\elastic-agent-${stack_ver}-windows-x86_64\elastic-agent.exe" install -f --url "$flt_url" -t "$fleet_token"
    }
    else {
        # Below version 7.13.0 
        $ErrorActionPreference = "Continue" #Ignore STDERR output being treated as errors
        & "$download_dir\elastic-agent-${stack_ver}-windows-x86_64\elastic-agent.exe" install -f -k "$kn_url" -t "$fleet_token"
    }
    

}

if ([version]"7.10.0" -le [version]$stack_ver) {
    install_post-7-10
}
else {
    install_pre-7-10
}
