 
$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 

cd $PSScriptRoot

Start-Transcript -Path ec_spout_beats_startup.log -Append

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
$es_url = "https://$($cloud_info[1]).$($cloud_info[0])"
$kn_url = "https://$($cloud_info[2]).$($cloud_info[0])"

#echo $env_config
#echo $cloud_info
#echo $es_url

If (
    [string]::IsNullOrWhiteSpace($env_config.stack_version) -or 
    [string]::IsNullOrWhiteSpace($es_url) -or
    [string]::IsNullOrWhiteSpace($env_config.beats_auth)
) {
    echo "Configuration missing"
    exit 
}

function InitialiseBeat ([string]$beat_name)
{
   $stack_version = $env_config.stack_version
   $beat_config_dir = "C:\ProgramData\Elastic\Beats\$beat_name"
   $beat_exe = "C:\Program Files\Elastic\Beats\$stack_version\$beat_name\$beat_name.exe"

   Copy-Item -Path "$beat_config_dir\$beat_name.example.yml" -Destination "$beat_config_dir\$beat_name.yml"

   $config_snippet = @'

cloud.id: ${CLOUD_ID}
cloud.auth: ${CLOUD_AUTH}

processors:
  - add_host_metadata: ~
  - add_cloud_metadata: ~

xpack.monitoring.enabled: true

'@

    echo $env_config.cloud_id | & $beat_exe @(
        '--path.config', "$beat_config_dir",
        '--path.data', "$beat_config_dir\data",
        'keystore', 'add', 'CLOUD_ID', '--stdin', '--force'
    )
    echo $env_config.beats_auth | & $beat_exe @(
        '--path.config', "$beat_config_dir",
        '--path.data', "$beat_config_dir\data",
        'keystore', 'add', 'CLOUD_AUTH', '--stdin', '--force'
    )

    # Be sure to set the keystore values before adding to config!
    Add-Content -Path "$beat_config_dir\$beat_name.yml" -Value $config_snippet

    # If an alias for this beats version is found, we assume setup was already run
    $headers = @{
        Authorization = "Basic " + (b64enc($env_config.beats_auth))
    }
    $check_alias = (Invoke-WebRequest -UseBasicParsing -Uri "$es_url/_cat/aliases/${beat_name}-${stack_version}" -Headers $headers).Content
    echo $check_alias

    If ( ($check_alias | Measure-Object).Count -lt 1 -or @($vm_config.beats_force_setup).Contains($beat_name) ) {
      & $beat_exe @(
        '--path.config', "$beat_config_dir",
         '--path.data', "$beat_config_dir\data",
          'setup'
      )
    }

    Restart-Service -Name $beat_name
}

& .\beats_install.ps1 "metricbeat" $env_config.stack_version
& .\beats_install.ps1 "winlogbeat" $env_config.stack_version
& .\beats_install.ps1 "packetbeat" $env_config.stack_version

InitialiseBeat("metricbeat")
InitialiseBeat("winlogbeat")
InitialiseBeat("packetbeat")

Stop-Transcript 
