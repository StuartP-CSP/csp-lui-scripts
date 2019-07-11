###############################################
#       Write-LuiServerStatus.ps1
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
# Accept command line parameters of -Detail to include detail
# status to screen.
param (
  [switch]$detail = $false,                         # Switch to toggle detailed report
  [string]$output  = "",                            # Set to blank string for all server. Valid options for output are:
                                                    #  "flag"     Any server with any flag set
                                                    #  "warning"  Servers with a warning indicator
                                                    #  "error"    Servers with a error warning
                                                    #  "ccu"      Servers utilising CCU licensing
                                                    #  "expiring" Servers with expiring licenses
  [switch]$csv = $false,                            # Switch to toggle CSV file output
  [string]$csvfilepath = "./",                      # Set default path for CSV export to current working directory
  [switch]$quiet = $false                           # Switch to toggle screen output 
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

function CheckLsStatus {
  param (
    [Parameter(Mandatory=$true)]
    [object] $ls
  )

  # foreach ( $ls in $serverStatus.licenseServersStatus ) {
    # Set report line colour to red (i.e. Not Reporting)
    $reportColor = "Red"

    # If server never reported set $lastReportDate to "Never reported"
    if ( $ls."isEverReported" -eq $false ) {
      $lastReportDate = "Never reported"
    } else {
      $lastReportDate = $ls."lastPhoningHomeTime"
    }

    # Test for warnings. Build array of warnings per server  
    if ( $ls."isFoundInBackOffice" -eq $false) {
      [array]$warningList += "Not found in back office"
    }
    if ( $ls."isNonCspLicenseInstalled" -eq $true) {
      [array]$warningList +=  "Non CSP Licenses Installed"
    }
    if ( $ls."isCcu" -eq $true) {
      [array]$warningList +=  "CCU Licenses in use"
      foreach ( $ccuReport in $ls.ccuFeatureStatistics ) {
        foreach ( $ccuId in $ccuReport) {
          [array]$warningList += " -- " + $ccuID.featureID + " Max usage:" + $ccuID.usageCount
        }
      }
    }
    if ( $ls."isExpired" -eq $true) {
      [array]$warningList +=  "License expired"
      [boolean]$expireFlag = $true
    }
    if ( [int]$ls."daysToExpire" -le 30) {
      [array]$warningList +=  "Licenses expire in " + $ls."daysToExpire" + " days."
      [boolean]$expireFlag = $true
    }

    if (( [int]$ls."daysToExpire" -le 90 ) -and ( [int]$ls."daysToExpire" -ge 31)) {
      # Test for indication messages. Build array of indication messages per server
      [array]$indicatorList +=  "Licenses expire in " + $ls."daysToExpire" + " days."
      [boolean]$expireFlag = $true
    }
    
    if ( $ls."isPhoningHome" -eq $true ) {
      $reportColor = "Green"
    }

    # Set report colour DarkGray if there are indicator messages against server,providing it is reporting
    if (( $ls."isPhoningHome" -eq $true ) -and ( $indicatorList -ne $null )) {
      $reportColor = "Gray"
    }


    # Set report colour Yellow if there are warnings against server, providing it is reporting
    if (( $ls."isPhoningHome" -eq $true ) -and ( $warningList -ne $null )) {
      $reportColor = "DarkYellow"
    }


    [object]$returnObj=[pscustomobject]@{
                          hostid = $ls.hostID
                          fqdn = $ls.fqdn
                          lastReportDate = $lastReportDate
                          reportColor = $reportColor
                          warnlist = $warningList
                          indicatorlist = $indicatorList
                          ccuInUse = $ls.isCcu
                          ccuStats = $ls.ccuFeatureStatistics
                          expireFlag = $expireFlag
                          daysToExpire = $ls.daysToExpire
                        }

    return $returnObj 
}

function WriteStatusOutput {
  param (
    [object] $line
  )
    if ( $quiet -eq $false ) {
      write-host $line.hostid "(" $line.fqdn  ") - Last Reported:" $line.lastReportDate -ForegroundColor $line.reportColor
      if ( $detail -eq $true) {
        if ( $line.warnList -ne $null ) {
          foreach ( $msg in $line.warnList ) {
            write-host "  * " $msg -ForegroundColor $line.reportColor
          }
        }
        if ( $line.indicatorlist -ne $null ) {
          foreach ( $msg in $line.indicatorlist ) {
            write-host "  * " $msg -ForegroundColor $line.reportColor
          }
        }
      }
    }

  # Write CSV output file required at path specified by variable $csvfilepath
  if ( $csv -eq $true) {
    $csvStatus = @(
        [pscustomobject]@{
          HostID = $line.hostID
          FQDN = $line.fqdn
          LastReportDate = $line.lastReportDate
          RAG_Status = $line.reportColor
        }
      )
    $csvStatus | Export-Csv -Path $csvfilepath -Append -NoTypeInformation
  }

}

function DisplayLuiLsStatus {
 param (
    [Parameter(Mandatory=$true)]
    [object] $serverStatus
  )

foreach ( $ls in $serverStatus.licenseServersStatus ) {
  [object]$sr = CheckLsStatus $ls

  switch ( $output ) {
    "flag" { if (( $sr.reportColor -eq "Red" ) -or ( $sr.reportColor -eq "DarkYellow" ) -or ( $sr.reportColor -eq "Gray" )) { WriteStatusOutput $sr } }
    "warning" { if (( $sr.reportColor -eq "Red" ) -or ( $sr.reportColor -eq "DarkYellow" )) { WriteStatusOutput $sr } }
    "error" { if ( $sr.reportColor -eq "Red" ) { WriteStatusOutput $sr } }
    "ccu" { if ( $sr.ccuInUse -eq $true ) { WriteStatusOutput $sr } }
    "expiring" { if ( $sr.expireflag -eq $true ) { WriteStatusOutput $sr } }
    default { WriteStatusOutput $sr }
  }
 }
}


$bearerToken = GetBearerToken $objCreds.clientId $objCreds.clientSecret

$serverStatus = GetCspLuiServerStatus $objCreds.customerId

write-host
write-host "CSP LUI Server Status for" $objCreds.customerId 

DisplayLuiLsStatus $serverStatus
