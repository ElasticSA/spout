 
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 

function b64dec ([string]$str)
{
    return [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($str))
}

function b64enc ([string]$str)
{
    return [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($str))
}

try {
    $skytap_data = ((Invoke-WebRequest -Uri 'http://gw/skytap').Content | ConvertFrom-Json)
}
catch { exit }

$env_config = ($skytap_data.configuration_user_data | ConvertFrom-yaml)

$cloud_info = (b64dec($env_config.cloud_id.Split(':')[1])).Split('$')
$es_url = "https://$($cloud_info[1]).$($cloud_info[0])"
$kn_url = "https://$($cloud_info[2]).$($cloud_info[0])"

#echo $env_config
#echo $cloud_info
#echo $es_url

If (
    [string]::IsNullOrWhiteSpace($env_config.stack_version) -or 
    [string]::IsNullOrWhiteSpace($es_url) -or
    [string]::IsNullOrWhiteSpace($env_config.cloud_auth)
) {
    echo "Configuration missing"
    exit 
}

# This function intends to be standalone, and could be copied to other scripts
function InstallBeat
{
    Param(
        [parameter(Position=0, Mandatory=$true)][string]$beat_name,
        [parameter(Position=1, Mandatory=$true)][string]$beat_ver,
        [string]$download_dir = "C:\Program Files\Elastic\Downloads"
    )

    $ignore = (New-Item -Force -ItemType Directory -Path "$download_dir\logs")

    If (Get-WmiObject -Class Win32_Product -Filter ("Vendor = 'Elastic' AND Name LIKE '%${beat_name}%' AND Version = '$beat_ver'")) {
        echo "$beat_name ($beat_ver) is already installed"
        return
    }

    $app = Get-WmiObject -Class Win32_Product -Filter ("Vendor = 'Elastic' AND Name LIKE '%${beat_name}%'")
    if ($null -ne $app) {
        echo "Uninstalling exising $beat_name"
        $app.Uninstall() | Out-Null
    }

    Write-Output "`n*** Installing $beat_name ($beat_ver) ****"
    $beat_install_msi = "${beat_name}-${beat_ver}-windows-x86_64.msi"
    $beat_artifact_uri = "https://artifacts.elastic.co/downloads/beats/$beat_name/$beat_install_msi"
    
    If (-Not (Test-Path -Path "$download_dir\$beat_install_msi" )){
        Invoke-WebRequest -Uri "$beat_artifact_uri" -OutFile "$download_dir\$beat_install_msi"
    }

    $MSIArguments = @(
        "/i"
        "$beat_install_msi"
        "/quiet"
        "/qn"
        "/norestart"
        "/log"
        "logs\${beat_name}_install.log"
    )
    Start-Process msiexec.exe -ArgumentList $MSIArguments -WorkingDirectory $download_dir -Wait -NoNewWindow

    # Create Beat Keystore
    & "C:\Program Files\Elastic\Beats\$beat_ver\$beat_name\$beat_name.exe" @(
        '--path.config', "C:\ProgramData\Elastic\Beats\$beat_name",
        '--path.data', "C:\ProgramData\Elastic\Beats\$beat_name\data",
        '-c', "$beat_name.example.yml",
        'keystore','create','--force'
    )

    Stop-Service -Name $beat_name
    Set-Service -Name $beat_name -StartupType Manual
}

# This func is using globals!
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
    echo $env_config.cloud_auth | & $beat_exe @(
        '--path.config', "$beat_config_dir",
        '--path.data', "$beat_config_dir\data",
        'keystore', 'add', 'CLOUD_AUTH', '--stdin', '--force'
    )

    # Be sure to set the keystore values before adding to config!
    Add-Content -Path "$beat_config_dir\$beat_name.yml" -Value $config_snippet

    # If an alias for this beats version is found, we assume setup was already run
    $headers = @{
        Authorization = "Basic " + (b64enc($env_config.cloud_auth))
    }
    $check_alias = (Invoke-WebRequest -Uri "$es_url/_cat/aliases/${beat_name}-${stack_version}" -Headers $headers).Content
    echo $check_alias

    If ( ($check_alias | Measure-Object).Count -lt 1 ) {
      & $beat_exe @(
        '--path.config', "$beat_config_dir",
         '--path.data', "$beat_config_dir\data",
          'setup'
      )
    }

    Restart-Service -Name $beat_name

}

InstallBeat "metricbeat" $env_config.stack_version
InstallBeat "winlogbeat" $env_config.stack_version
InstallBeat "packetbeat" $env_config.stack_version

InitialiseBeat("metricbeat")
InitialiseBeat("winlogbeat")
InitialiseBeat("packetbeat")
 
