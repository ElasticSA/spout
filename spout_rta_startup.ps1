 # Will run a sequence of RTA TTPs as defined in the Skytap env. config

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 

cd $PSScriptRoot

Start-Transcript -Path spout_beats_startup.log -Append

if (-Not (Get-Command python.exe -ErrorAction SilentlyContinue)) {
    Write-Warning "Not python installed, exiting"
    exit
} 

$skytap_data = $Null

do {
    $failed = $False
    try {
        $skytap_data = ((Invoke-WebRequest -UseBasicParsing -Uri 'http://gw/skytap').Content | ConvertFrom-Json)
    }
    catch {
         Write-Error "Skytap data fetch failed, trying again" -ErrorAction SilentlyContinue 
         $failed = $True
         Start-Sleep -Seconds 20
    }
} while ($failed)

$env_config = ($skytap_data.configuration_user_data | ConvertFrom-yaml)
$vm_config = ($skytap_data.user_data | ConvertFrom-yaml)

#$env_config | ConvertTo-Yaml 

If (-Not ($env_config.win_rta_config -And $env_config.win_rta_sequence)) {
    Write-Warning "No RTA definition found"
    exit #Exit successfully to not be retried / rescheduled
}

$start_delay = $(If ($env_config.win_rta_config.start_delay) { $env_config.win_rta_config.start_delay -as [int] } else { 180 } )
$step_delay = $(If ($env_config.win_rta_config.step_delay) { $env_config.win_rta_config.step_delay -as [int] } else { 20 } )

echo "Start delay: $start_delay (Step delay: $step_delay)"
Start-Sleep -Seconds $start_delay

ForEach ($rta in $env_config.win_rta_sequence) {
    Start-Sleep -Seconds $step_delay

    echo "--- Executing RTA: $($rta.name) ---"
    echo $rta

    & python.exe 'rta_ttp.py' `
        '-s' "$($env_config.stack_version)" `
        '-t' "$($rta.ttps -join ',')" `
        "$(If ($rta.dry_run) {'-d'})" `
        "$(If ($rta.shuffle) {'-r'})" `
        "$(If ($rta.wait) {"-w $($rta.wait)"})"
    echo "--- Completed RTA: $($rta.name) ---`n"
} 

Stop-Transcript 
