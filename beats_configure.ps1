#
# Configure an Elastic Beat on a Windows system.
#
# This script takes the following arguments:
# - beat_name: The name of the beat to configure (metricbeat, filebeat, winlogbeat, etc)
#
# This script reads and uses the following settings read from a file called
# "elastic_stack.config":
# - CLOUD_ID: Elastic Cloud (or ECE) deployment ID to connect to
# - STACK_VERSION: The version to install. e.g. 7.9.2
# - BEATS_AUTH: The credentials needed to connect to Elasticsearch
# Please create this^ file before running this script 

Param(
    [parameter(Position=0, Mandatory=$true)][string]$beat_name
)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

. ".\utilities.ps1"

# 
# Read script configuration file
# and setup variables
#
$config = Get-Content -Path "elastic_stack.config" | Out-String | ConvertFrom-StringData

$cloud_info = (b64dec($config.CLOUD_ID.Split(':')[1])).Split('$')
$es_url = "https://$($cloud_info[1]).$($cloud_info[0])"
$kn_url = "https://$($cloud_info[2]).$($cloud_info[0])" 

$stack_version = $config.STACK_VERSION
$beat_config_dir = "C:\ProgramData\Elastic\Beats\$beat_name"
$beat_exe = "C:\Program Files\Elastic\Beats\$stack_version\$beat_name\$beat_name.exe"

#
# Check variables
#
If (
    [string]::IsNullOrWhiteSpace($stack_version) -or 
    [string]::IsNullOrWhiteSpace($es_url) -or
    [string]::IsNullOrWhiteSpace($config.BEATS_AUTH)
) {
    Write-Error "Configuration missing" -ErrorAction Stop 
}

#
# Overwrite any existing beat config. to always start from a known state
#
Copy-Item -Path "$beat_config_dir\$beat_name.example.yml" -Destination "$beat_config_dir\$beat_name.yml"

#
# This is the beat config we will append to the config file
#
$config_snippet = @'
# *** Scripted content appended here ***

output.elasticsearch: ~

# These values are fetched from the beats keystore
cloud.id: ${CLOUD_ID}
cloud.auth: ${CLOUD_AUTH}

processors:
  - add_host_metadata: ~
  - add_cloud_metadata: ~

xpack.monitoring.enabled: true

'@

#
# Add Cloud connection and auth info to the beats keystore
#
echo $config.CLOUD_ID | & $beat_exe @(
    '--path.config', "$beat_config_dir",
    '--path.data', "$beat_config_dir\data",
    'keystore', 'add', 'CLOUD_ID', '--stdin', '--force'
)
echo $config.BEATS_AUTH | & $beat_exe @(
    '--path.config', "$beat_config_dir",
    '--path.data', "$beat_config_dir\data",
    'keystore', 'add', 'CLOUD_AUTH', '--stdin', '--force'
)

#
# Now we append our config
# After ensuring the keystore is setup ^
#
Add-Content -Path "$beat_config_dir\$beat_name.yml" -Value $config_snippet

#
# If this is a new beat (type+version) we need to run 'setup' at least once
# If an alias for this beats version is found, we assume setup was already run
#
If ( -Not [string]::IsNullOrWhiteSpace($config.BEATS_SETUP_AUTH) ){
    # Fetch Alias listings
    $headers = @{
        Authorization = "Basic " + (b64enc($config.BEATS_SETUP_AUTH))
    }
    $check_alias = (Invoke-WebRequest -UseBasicParsing -Uri "$es_url/_cat/aliases/${beat_name}-${stack_version}" -Headers $headers).Content
    echo $check_alias

    # Run setup if alias is missing
    If ( (-Not $check_alias.Contains($beat_name)) -or $($config.BEATS_FORCE_SETUP).Contains($beat_name) ) {
        & $beat_exe @(
            '--path.config', "$beat_config_dir",
            '--path.data', "$beat_config_dir\data",
            '-E', "cloud.auth=$($config.BEATS_SETUP_AUTH)",
            'setup'
        )
    }
}

# 
# Enable Beat and OS specific integration modules
#
Switch ($beat_name){

"metricbeat" {
    & $beat_exe @(
        '--path.config', "$beat_config_dir", '--path.data', "$beat_config_dir\data",
        'modules', 'enable', 'system', 'windows'
    )
}

"filebeat" {
    & $beat_exe @(
        '--path.config', "$beat_config_dir", '--path.data', "$beat_config_dir\data",
        'modules', 'enable', 'microsoft'
    )
}

} #Switch
 
