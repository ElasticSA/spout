Param(
    [parameter(Position=0, Mandatory=$true)][string]$beat_name,
)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

. ".\utilities.ps1"

$config = Get-Content -Path "elastic_stack.config" | Out-String | ConvertFrom-StringData

$cloud_info = (b64dec($config.CLOUD_ID.Split(':')[1])).Split('$')
$es_url = "https://$($cloud_info[1]).$($cloud_info[0])"
$kn_url = "https://$($cloud_info[2]).$($cloud_info[0])" 

$stack_version = $config.STACK_VERSION
$beat_config_dir = "C:\ProgramData\Elastic\Beats\$beat_name"
$beat_exe = "C:\Program Files\Elastic\Beats\$stack_version\$beat_name\$beat_name.exe"

If (
    [string]::IsNullOrWhiteSpace($stack_version) -or 
    [string]::IsNullOrWhiteSpace($es_url) -or
    [string]::IsNullOrWhiteSpace($config.BEATS_AUTH)
) {
    Write-Error "Configuration missing" -ErrorAction Stop 
}

Copy-Item -Path "$beat_config_dir\$beat_name.example.yml" -Destination "$beat_config_dir\$beat_name.yml"

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

# Be sure to set the keystore values before adding to config!
Add-Content -Path "$beat_config_dir\$beat_name.yml" -Value $config_snippet

# If an alias for this beats version is found, we assume setup was already run
$headers = @{
    Authorization = "Basic " + (b64enc($config.BEATS_AUTH))
}
$check_alias = (Invoke-WebRequest -UseBasicParsing -Uri "$es_url/_cat/aliases/${beat_name}-${stack_version}" -Headers $headers).Content
echo $check_alias

If ( (-Not $check_alias.Contains($beat_name)) -or $($config.BEATS_FORCE_SETUP).Contains($beat_name) ) {
    & $beat_exe @(
    '--path.config', "$beat_config_dir",
        '--path.data', "$beat_config_dir\data",
        'setup'
    )
}
