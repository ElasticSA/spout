Param(
    [parameter(Position=0, Mandatory=$true)][string]$beat_name,
    [parameter(Position=1, Mandatory=$true)][string]$beat_ver,
    [string]$download_dir = "C:\Program Files\Elastic\Downloads"
)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 

#. ".\utilities.ps1"

$ignore = (New-Item -Force -ItemType Directory -Path "$download_dir\logs")

If (Get-WmiObject -Class Win32_Product -Filter ("Vendor = 'Elastic' AND Name LIKE '%${beat_name}%' AND Version = '$beat_ver'")) {
    echo "$beat_name ($beat_ver) is already installed"
    exit
}

$app = Get-WmiObject -Class Win32_Product -Filter ("Vendor = 'Elastic' AND Name LIKE '%${beat_name}%'")
if ($null -ne $app) {
    echo "Uninstalling exising $beat_name"
    $app.Uninstall() | Out-Null
}

Write-Output "*** Installing $beat_name ($beat_ver) ***"

$beat_install_msi = "${beat_name}-${beat_ver}-windows-x86_64.msi"
$beat_artifact_uri = "https://artifacts.elastic.co/downloads/beats/$beat_name/$beat_install_msi"
    
If (-Not (Test-Path -Path "$download_dir\$beat_install_msi" )){
    Invoke-WebRequest -UseBasicParsing -Uri "$beat_artifact_uri" -OutFile "$download_dir\$beat_install_msi"
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

 
