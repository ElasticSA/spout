# So that the other scripts can be used outside SkyTap
# they take their config from an 'elastic_stack.config' file
# This script generates that file from the skytap environment metadata
# The goal being to allow the other scripts to be useful for other automation environments
# by decoupling them from anything Skytap specific

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 

cd $PSScriptRoot

$skytap_data = $Null
$hostname = $($env:COMPUTERNAME).ToLower()

do {
    $failed = $False
    try {
        $skytap_data = ((Invoke-WebRequest -UseBasicParsing -Uri 'http://gw/skytap' -TimeoutSec 60 ).Content | ConvertFrom-Json)
    }
    catch {
         Write-Error "Skytap data fetch failed, trying again" -ErrorAction SilentlyContinue 
         $failed = $True
         Start-Sleep -Seconds 20
    }
} while ($failed)

$env_config = ($skytap_data.configuration_user_data | ConvertFrom-yaml)
$vm_config = ($skytap_data.user_data | ConvertFrom-yaml)

$fleet_token = $Null
if ([string]::IsNullOrWhiteSpace($env_config.fleet_token.$hostname)) {
    $fleet_token = $env_config.fleet_token.windows
}
else {
    $fleet_token = $env_config.fleet_token.$hostname
}
        
$config = @{
    STACK_VERSION      = $env_config.stack_version;
    CLOUD_ID           = $env_config.cloud_id;
    BEATS_AUTH         = $env_config.beats_auth;
    BEATS_SETUP_AUTH   = $env_config.beats_setup_auth;
    BEATS_FORCE_SETUP  = $vm_config.beats_force_setup;
    FLEET_TOKEN        = $fleet_token;
    FLEET_SERVER       = $env_config.fleet_server;
}

$config.GetEnumerator() | ForEach-Object { "$($_.Name)=$($_.Value)" } | Out-File -FilePath elastic_stack.config -Encoding utf8 -Force
 
