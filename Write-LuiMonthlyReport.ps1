###############################################
#       Write-LuiMonthlyReport.ps1
#
# This script is intended to utilise the Citrix Cloud licensing
# API to display the reported LUI license usage, for a given partner,
# for a given month.
#
# https://developer.cloud.com/index.html
# https://licensing.citrixworkspacesapi.net/Help
#
# USE AT OWN RISK - NO WARANTY PROVIDED
#
# Author. Stuart Parkington, Lead SE, CSP EMEA
#

# Accept command line parameters of -Year and/or -Month
# If none are supplied, defaults to the previous month.
# The parameter -Detail will provide reporting per server
# per month. 
param (
  [int]$year = (Get-Date).year,                     # Set default year as current Year
  [int]$month = (Get-Date).month-1,                 # Set default month to current month - 1
  [switch]$detail = $false,                         # Switch to toggle detail report
  [switch]$csv = $false,                            # Switch to toggle CSV file output
  [string]$csvfilepath = "./",                      # Set default path for CSV export to current working directory
  [switch]$quiet = $false,                          # Switch to toggle screen output
  [switch]$send = $false
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

# Correct month and date, if previous month is in previous year (e.g. January)
if ( $month -eq 0 ) {
    $month = 12
    $year = $year - 1
}

# Variables - do not change
$firstcall = $true
$csvfilepath = $csvfilepath + "LUI_Report_" + $customerId + "_" + $year + "-" + $month + ".csv"


# Create date string for API call, padding month with 0's if required 
[string]$reportdate = $year.ToString() + "-" + $month.ToString("00")


# Grab API Bearer Token
function GetBearerToken {
  param (    [Parameter(Mandatory=$true)]
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

# Retrieve all License Usage Data for given month. Usage returned as JSON
function GetCSPLicenseUsageData {
  param (
    [Parameter(Mandatory=$true)]
    [string] $customerId,
    [Parameter(Mandatory=$true)]
    [string] $reportdate
  )

  $postHeaders = @{
    "Content-Type"="application/json";
    "Authorization"="CwsAuth bearer=$($bearerToken)"
  }

  $Url = "https://licensing.citrixworkspacesapi.net/$($customerId)/licenseusagedata?date=$($reportdate)"

  try {
    $licenseUsage = Invoke-RestMethod -Uri $Url -Method GET -Headers $postHeaders
  } catch {
    # Dig into the exception to get the Response details.
    # Note that value__ is not a typo.
    write-host "Error making REST request to:`n" $restUrl -ForegroundColor Red
    Write-Host "`nStatus Code:" $_.Exception.Response.StatusCode.value__ -ForegroundColor Red
    Write-Host "Status Description:" $_.Exception.Response.StatusDescription -ForegroundColor Red
    exit
  }

  if ( $licenseUsage.skus.skuId -eq $null ) {
    write-host "No user information available for the selected month ($($reportdate))." -ForegroundColor White -BackgroundColor Red
    exit
  }

  return $licenseUsage
}

# Extract simple useage counts for each SKU specified, by featureID (e.g. XDT_PLT_UD)
# Returns an object
function GetUsagePerSku {
  Param (
    [Parameter(Mandatory=$true)]
    [string] $featureID
  )

  $sku = $usage.skus.features | Where-Object {$_.'featureID' -eq $featureID}

  if ( [int]$sku."count" -le 0 ) {
    $freePercent = "0"
  } else {
    $freePercent = [int](([int]$sku."freeUsersCount"/[int]$sku."count") * 100)
  }

  $retValue = @(
        [pscustomobject]@{
          edition = $sku.featureDescription                           # featureDescription (e.g. Premium/Base/VDI)
          totalUsers =$sku.count                                      # Total user count
          paidUsers = [int]$sku.count - [int]$sku.freeUsersCount      # Paid user count (e.g. total - free)
          freeUsers = $sku.freeUsersCount                             # Free user count
          freeUserPercent = $freePercent                              # Percentage of free users claimed (e.g. free/total * 100
        }
    )   

  return $retValue
}


# Produce pretty display to console, with pretty colours and/or create .csv file! :)
function OutputUsagePerSku {
  Param (
    [Parameter(Mandatory=$true)]
    [string] $featureID
  )

  $skuUsage = GetUsagePerSku $featureID

  if ( $skuUsage.edition -eq "Premium" ) {
    $skuUsage.edition = "Citrix Virtual Apps and Desktops, Premium"
  } elseif ( $skuUsage.edition -eq "Base" ) {
    $skuUsage.edition = "Citrix Virtual Apps, Standard"
  } elseif ( $skuUsage.edition -eq "VDI Edition" ) {
    $skuUsage.edition = "Citrix Virtual Desktops, Standard"
  } 

  if ( $quiet -eq $false ) {
    if ( $firstcall -eq $true ) {
      write-host "`nCSP LUI Usage for" $objCreds.customerId "for" (Get-Culture).DateTimeFormat.GetMonthName($month) $year
      $script:firstcall = $false
    }

    write-host $skuUsage.edition -ForegroundColor Yellow -NoNewLine
    Write-Host "".PadRight((50-$skuUsage.edition.length)," ") -NoNewLine
    write-host "Total: " -NoNewLine
    write-host $skuUsage.totalUsers -ForegroundColor Yellow  -NoNewLine
    Write-Host "".PadRight((6-$skuUsage.totalUsers.ToString().length)," ") -NoNewLine
    write-host "Paid: " -NoNewLine
    write-host $skuUsage.paidUsers -ForegroundColor Red -NoNewLine
    Write-Host "".PadRight((6-$skuUsage.paidUsers.ToString().length)," ") -NoNewLine
    write-host "Free: " -NoNewLine
    write-host $skuUsage.freeUsers -ForegroundColor Green -NoNewLine
    write-host " ($($skuUsage.freeUserPercent)%)" -ForegroundColor Gray

    # Display SKU usage per Server, if -detail flag set, showing servers marked as free in green.
    if ( $detail -eq $true ) {
      $serverSkuUsage = $usage.skus.features | Where-Object {$_.'featureID' -eq $featureID}
      foreach ( $server in $serverSkuUsage.licenseServerUsages ) {
        $foreColor = "DarkGray"
        if ( $server.isLicenseServerFree -eq $true ) {
          $foreColor = "Green"
        }
        Write-Host "".PadLeft(8," ") $server.fqdn "".PadRight(39-$server.fqdn.length, " ") `
                   "total:" $server.count "".PadRight((4-$server.count.tostring().length), " ") `
                   "paid:" ([int]$server.count - [int]$server.freeUsersCount) "".PadRight(4-([int]$server.count - [int]$server.freeUsersCount).ToString().length ," ") `
                   "free:" $server.freeUsersCount -ForegroundColor $foreColor
      }
    }
  }

  # Write CSV output file required at path specified by variable $csvfilepath
  if ( $csv -eq $true) {
    # $csvfilepath = $csvfilepath + "LUI_Report_" + $customerId + "_" + $year + "-" + $month + ".csv"
    $csvusage = @(
        [pscustomobject]@{
          Edition = $skuUsage.edition
          Total = $skuUsage.totalUsers
          Paid = $skuUsage.paidUsers
          Free = $skuUsage.freeUsers
          PercentFree = $skuUsage.freeUserPercent
        }
      )
    $csvusage | Export-Csv -Path $csvfilepath -Append -NoTypeInformation
  }
}

## MAIN
$bearerToken = GetBearerToken $objCreds.clientId $objCreds.clientSecret

$usage = GetCSPLicenseUsageData $objCreds.customerId $reportdate

OutputUsagePerSku "XDT_PLT_UD"
OutputUsagePerSku "XDT_ADV_UD" 
OutputUsagePerSku "XDT_STD_UD" 

if (( test-path $csvfilepath ) -and ($send -eq $true )) {
  Write-Output $csvfilepath
}