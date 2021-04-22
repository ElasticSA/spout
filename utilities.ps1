#
# Utility functions
#

function b64dec ([string]$str)
{
    return [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($str))
}

function b64enc ([string]$str)
{
    return [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($str))
}

 # Spout tends to hang on skytype while downloading, here we try to bulletproof that
function download_file ([string]$url, [string]$dest, [bool]$check=$True)
{
    $timeout = 120
    
    do {
        $fail = $False
    
        try {
            If (-Not (Test-Path -Path "$dest" )){
                Write-Output "--- Downloading $url => $dest ---"
                Invoke-WebRequest -UseBasicParsing -Uri "$url" -OutFile "$dest" -TimeoutSec $timeout
            }
    
            If ($check) {
                Write-Output "--- Downloading hash ---"
                Remove-Item -Path "${dest}.sha512" -Force -EA Ignore
                Invoke-WebRequest -UseBasicParsing -Uri "${url}.sha512" -OutFile "${dest}.sha512" -TimeoutSec $([int]($timeout/2))
            }
        }
        catch {
            Write-Error "File Download FAILED $url => $dest" -ErrorAction SilentlyContinue 
            $fail = $True
        }
        
        If ($check -And -Not $fail) {
            Write-Output "--- Checking hash ---"
            $hashA = (Get-Content -Path "${dest}.sha512").Split(' ')[0]
            $hashB = (Get-FileHash -Algorithm SHA512 -Path "$dest").hash
            if ($hashA -ne $hashB) {
                Remove-Item -Path "$dest" -Force -EA Ignore
                Remove-Item -Path "${dest}.sha512" -Force -EA Ignore
                Write-Error "File download corrupted, mismatching hash" -ErrorAction SilentlyContinue 
                $fail = $True
            } 
        }
        
        If ($fail) {
            Start-Sleep -Seconds 10
        }
    } while ($fail)
} 
