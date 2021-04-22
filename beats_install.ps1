#
# Install an Elastic Beat on a Windows system.
# This script takes the following arguments:
# - beat_name: The name of the beat to install (metricbeat, filebeat, winlogbeat, etc)
# - beat_ver: The version to install. e.g. 7.9.2

Param(
    [parameter(Position=0, Mandatory=$true)][string]$beat_name,
    [parameter(Position=1, Mandatory=$true)][string]$beat_ver
)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 

. ".\utilities.ps1"

# Setup some varables
$download_dir = "C:\ProgramData\Elastic\Downloads"
$beat_home = "C:\ProgramData\Elastic\Beats\$beat_name"

$beat_install_msi = "${beat_name}-${beat_ver}-windows-x86_64.msi"
$beat_artifact_uri = "https://artifacts.elastic.co/downloads/beats/$beat_name/$beat_install_msi"

# Ensure these dirs exist
$ignore = (New-Item -Force -ItemType Directory -Path "$download_dir")
$ignore = (New-Item -Force -ItemType Directory -Path "$beat_home\logs")

# Look to see if same beat AND same version are already install (Do nothing if yes)
If (Get-WmiObject -Class Win32_Product -Filter ("Vendor = 'Elastic' AND Name LIKE '%${beat_name}%' AND Version = '$beat_ver'")) {
    echo "$beat_name ($beat_ver) is already installed"
    exit
}

# Look to see if same beat, but (implied) different version installed (Uninstall it if yes)
$app = Get-WmiObject -Class Win32_Product -Filter ("Vendor = 'Elastic' AND Name LIKE '%${beat_name}%'")
if ($null -ne $app) {
    echo "Uninstalling exising $beat_name"
    $app.Uninstall() | Out-Null
}

Write-Output "*** Installing $beat_name ($beat_ver) ***"

# # Download MSI
# If (-Not (Test-Path -Path "$download_dir\$beat_install_msi" )){
#     Invoke-WebRequest -UseBasicParsing -Uri "$beat_artifact_uri" -OutFile "$download_dir\$beat_install_msi"
# }
# 
# # Verify MSI is correct
# Invoke-WebRequest -UseBasicParsing -Uri "${beat_artifact_uri}.sha512" -OutFile "$download_dir\${beat_install_msi}.sha512"
# $hashA = (Get-Content -Path "$download_dir\${beat_install_msi}.sha512").Split(' ')[0]
# $hashB = (Get-FileHash -Algorithm SHA512 -Path "$download_dir\$beat_install_msi").hash
# if ($hashA -ne $hashB) {
#     Remove-Item -Path "$download_dir\$beat_install_msi" -Force
#     Remove-Item -Path "$download_dir\${beat_install_msi}.sha512" -Force
#     Write-Error "File download corrupted, mismatching hash"
#     # Will stop execution here due to $ErrorActionPreference ^^
# } 

download_file("$beat_artifact_uri", "$download_dir\$beat_install_msi")

# Run MSI installer
$MSIArguments = @(
    "/i"
    "$beat_install_msi"
    "/quiet"
    "/qn"
    "/norestart"
    "/log"
    "$beat_home\logs\${beat_name}_install.log"
)
Start-Process msiexec.exe -ArgumentList $MSIArguments -WorkingDirectory $download_dir -Wait -NoNewWindow

# Create Beat Keystore
& "C:\Program Files\Elastic\Beats\$beat_ver\$beat_name\$beat_name.exe" @(
    '--path.config', "$beat_home",
    '--path.data', "$beat_home\data",
    '-c', "$beat_name.example.yml",
    'keystore','create','--force'
)

 
