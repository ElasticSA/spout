# So that the other scripts can be used outside SkyTap
# they take their config from an 'elastic_stack.config' file
# This script generates that file from the skytap environment metadata
# The goal being to allow the other scripts to be useful for other automation environments
# by decoupling them from anything Skytap specific

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 

cd $PSScriptRoot

do {
    $failed = $False
    try {
        $skytap_data = ((Invoke-WebRequest -UseBasicParsing -Uri 'http://gw/skytap').Content | ConvertFrom-Json)
        $env_config = ($skytap_data.configuration_user_data | ConvertFrom-yaml)
        $vm_config = ($skytap_data.user_data | ConvertFrom-yaml)
    }
    catch {
         Write-Error "Skytap data fetch failed, trying again"
         $failed = $True
         Start-Sleep -Seconds 20
    }
} while ($failed)

$config = @{
    STACK_VERSION      = $env_config.stack_version;
    CLOUD_ID           = $env_config.cloud_id;
    BEATS_AUTH         = $env_config.beats_auth;
    BEATS_SETUP_AUTH   = $env_config.beats_setup_auth;
    BEATS_FORCE_SETUP  = $vm_config.beats_force_setup;
    AGENT_ENROLL_TOKEN = $env_config.agent_enroll_token;
}

$config.GetEnumerator() | ForEach-Object { "$($_.Name)=$($_.Value)" } | Out-File -FilePath elastic_stack.config -Encoding utf8 -Force
