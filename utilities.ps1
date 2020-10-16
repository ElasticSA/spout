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
