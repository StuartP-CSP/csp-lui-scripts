###############################################
#       Get-LuiServerStatus.ps1
#
# This script is intended to utilise the Citrix Cloud licensing
# API to display the current LUI Server Status.
#
# https://developer.cloud.com/index.html
# https://licensing.citrixworkspacesapi.net/Help
#
# USE AT OWN RISK - NO WARANTY PROVIDED
#
# Author. Stuart Parkington, Lead SE, CSP EMEA
#
#

param (
  [string]$output  = ""                             # "notreporting"  Servers not reporting currently
                                                    # "never"         Servers that have never reported
                                                    # "flag"          Servers with any warning or error flag set
                                                    # "notfound"      Servers not found in back office
                                                    # "noncsp"        Servers hosting non CSP licenses
                                                    # "ccu"           Servers utilising CCU licensing
                                                    # "expired"       Servers hosting expired licenses
                                                    # "expiring"      Servers with expiring licenses
                                                    # "free"          Servers flagged as free serverStatus
                                                    # "all"           All listed servers (Default option if nothing is specified)
)

# Read Citrix Cloud API credentials from cccrreds.json file or request via user input 
if ( test-path ./cccreds.json) {
  $objCreds = Get-Content ./cccreds.json | ConvertFrom-Json 
} else {

  $customerId = Read-Host -Prompt "CustomerID"        # Request customerID
  $clientId = Read-Host -Prompt "ClientID"            # Request clientId
  $clientSecret = Read-Host -Prompt "Client Secret"   # Request clientSecret

  $objCreds = New-Object -TypeName psobject
  $objCreds | Add-Member -MemberType NoteProperty -Name customerID -Value $customerId
  $objCreds | Add-Member -MemberType NoteProperty -Name clientId -Value $clientId
  $objCreds | Add-Member -MemberType NoteProperty -Name clientSecret -Value $clientSecret
}

# Variables - do not change
$csvfilepath = $csvfilepath + "LUI_ServerStatus_" + $customerId + "_" + (Get-Date).year + "-" + (Get-Date).month.ToString("00") + ".csv"


# Grab API Bearer Token
function GetBearerToken {
  param (
    [Parameter(Mandatory=$true)]
    [string] $clientId,
    [Parameter(Mandatory=$true)]
    [string] $clientSecret
  )

  $postHeaders = @{"Content-Type"="application/json"}
  $body = @{
    "ClientId"=$clientId;
    "ClientSecret"=$clientSecret
  }
  $trustUrl = "https://trust.citrixworkspacesapi.net/root/tokens/clients"

  try {
    $response = Invoke-RestMethod -Uri $trustUrl -Method POST -Body (ConvertTo-Json $body) -Headers $postHeaders
  } catch {
    # Dig into the exception to get the Response details.
    # Note that value__ is not a typo.
    write-host "Error making REST request to:`n" $restUrl -ForegroundColor Red
    Write-Host "`nStatus Code:" $_.Exception.Response.StatusCode.value__ -ForegroundColor Red
    Write-Host "Status Description:" $_.Exception.Response.StatusDescription -ForegroundColor Red
    exit
  }

  $bearerToken = $response.token

  return $bearerToken;
}

# Retrieve current License Server Data. Usage returned as JSON
function GetCspLuiServerStatus {
  param (
    [Parameter(Mandatory=$true)]
    [string] $customerId
  )

  $postHeaders = @{
    "Content-Type"="application/json";
    "Authorization"="CwsAuth bearer=$($bearerToken)"
  }
  $Url = "https://licensing.citrixworkspacesapi.net/$($customerId)/licenseservers"

  try {
    $serverStatus = Invoke-RestMethod -Uri $Url -Method GET -Headers $postHeaders
  } catch {
    # Dig into the exception to get the Response details.
    # Note that value__ is not a typo.
    write-host "Error making REST request to:`n" $restUrl -ForegroundColor Red
    Write-Host "`nStatus Code:" $_.Exception.Response.StatusCode.value__ -ForegroundColor Red
    Write-Host "Status Description:" $_.Exception.Response.StatusDescription -ForegroundColor Red
    exit
  }

  if ( $serverStatus.licenseServersStatus -eq $null ) {
    write-host "No server status information available for customer" $customerId "."  -ForegroundColor White -BackgroundColor Red
    exit
  }

  return $serverStatus
}


## MAIN
$bearerToken = GetBearerToken $objCreds.clientId $objCreds.clientSecret

$serverStatus = GetCspLuiServerStatus $objCreds.customerId

Switch ( $output ) {
  "flag" { $outObj = $serverStatus.licenseServersStatus |
            where-object { 
              $_.isPhoningHome -eq $False -or
              $_.isFoundInBackOffice -eq $True -or 
              $_.isNonCspLicenseInstalled -eq $true -or
              $_.isCcu -eq $True -or
              $_.isExpired -eq $True -or
              $_.daysToExpire -le 90 -or
              $_.isCompliant -eq $False
            } | Format-Table -Property hostID, fqdn, isPhoningHome, isFoundInBackOffice, isCcu, isExpired, daysToExpire
          }
  "notreporting" { $outObj = $serverStatus.licenseServersStatus | where-object { $_.isPhoningHome -eq $False } | Format-Table -Property hostID, fqdn, isPhoningHome, lastPhoningHomeTime }
  "never" { $outObj = $serverStatus.licenseServersStatus | where-object { $_.isEverReported -eq $False } | Format-Table -Property hostID, isEverReported }
  "notfound" { $outObj = $serverStatus.licenseServersStatus | where-object { $_.isFoundInBackOffice -eq $False } | Format-Table -Property hostID, fqdn, isFoundInBackOffice }
  "noncsp" { $outObj = $serverStatus.licenseServersStatus | where-object { $_.isNonCspLicenseInstalled -eq $True } | Format-Table -Property hostID, fqdn, isNonCspLicenseInstalled }
  "ccu" { $outObj = $serverStatus.licenseServersStatus | where-object { $_.isCcu -eq $True } | Format-Table -Property hostID, fqdn, isCcu}
  "expired" { $outObj = $serverStatus.licenseServersStatus | where-object { $_.isExpired -eq $True } | Format-Table -Property hostID, fqdn, isExpired } 
  "expiring" { $outObj = $serverStatus.licenseServersStatus | where-object { $_.daysToExpire -le 90 } | Format-Table -Property hostID, fqdn, licenseExpirationDate, daysToExpire }
  "free" { $outObj = $serverStatus.licenseServersStatus | where-object { $_.isLicenseServerFree -eq $True } | Format-Table -Property hostID, fqdn, isLicenseServerFree }
  "all" { $outObj = $serverStatus.licenseServersStatus | Format-Table }
  default { $outObj = $serverStatus.licenseServersStatus | Format-Table } 
}

write-output $outObj

