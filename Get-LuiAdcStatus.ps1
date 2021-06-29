###############################################
#       Get-LuiAdcStatus.ps1
#
# This script is intended to utilise the Citrix Cloud licensing
# API to return the current ADC Status.
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
  [string]$output  = ""                             # "notreport      ADCs not reporting currently
                                                    # "flag"          ADCs with any warning or error flag set
                                                    # "notfound"      ADCs not found in back office
                                                    # "expired"       ADCs hosting expired licenses
                                                    # "expiring"      ADCs with expiring licenses
                                                    # "standalone"    Standalone (not HA or Clustered) ADCs
                                                    # "ha"            ADCs in HA Pair
                                                    # "clustered"     Clustered ADCs
                                                    # "active"        Active node ADCs
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
function GetCspLuiAdcStatus {
  param (
    [Parameter(Mandatory=$true)]
    [string] $customerId
  )

  $postHeaders = @{
    "Content-Type"="application/json";
    "Authorization"="CwsAuth bearer=$($bearerToken)"
  }
  $Url = "https://licensing.citrixworkspacesapi.net/$($customerId)/netscalercallinghomedata"

  try {
    $adcStatus = Invoke-RestMethod -Uri $Url -Method GET -Headers $postHeaders
  } catch {
    # Dig into the exception to get the Response details.
    # Note that value__ is not a typo.
    write-host "Error making REST request to:`n" $restUrl -ForegroundColor Red
    Write-Host "`nStatus Code:" $_.Exception.Response.StatusCode.value__ -ForegroundColor Red
    Write-Host "Status Description:" $_.Exception.Response.StatusDescription -ForegroundColor Red
    exit
  }

  if ( $null -eq $adcStatus.netScalerCallingHomeDetails ) {
    write-host "No ADC status information available for customer" $customerId "."  -ForegroundColor White -BackgroundColor Red
    exit
  }

  return $adcStatus
}


## MAIN
$bearerToken = GetBearerToken $objCreds.clientId $objCreds.clientSecret

$adcStatus = GetCspLuiAdcStatus $objCreds.customerId

$adcs = $adcStatus.netScalerCallingHomeDetails

$adcArray = @()
ForEach ($adc in $adcs) {
  
  $adcDetails = [PSCustomObject]@{
    fqdn = $adc.fqdn
    hostId = $adc.hostId
    daysToExpire = $adc.netScalerLicenseModels.daysToExpire
    licenseExpirationDate = $adc.netScalerLicenseModels.licenseExpirationDate
    hostType = $adc.netScalerLicenseModels.hostType
    localReportingDate= $adc.netScalerLicenseModels.localReportingDate
    productName = $adc.netScalerLicenseModels.productName
    entitlementId = $adc.netScalerLicenseModels.entitlementId
    fulfillmentId = $adc.netScalerLicenseModels.fulfillmentId
    deploymentType = $adc.netScalerLicenseModels.deploymentType
    vpxMode = $adc.netScalerLicenseModels.vpxMode
    isExpired = $adc.netScalerLicenseModels.isExpired
    isReporting = $adc.netScalerLicenseModels.isReporting
    latestReportingDate = $adc.netScalerLicenseModels.latestReportingDate
    isFoundInBackOffice = $adc.netScalerLicenseModels.isFoundInBackOffice
  }
  if ( $adc.netScalerLicenseModels.licenseExpirationDate -is [DateTime] ) {
    $adcArray += $adcDetails
  } else {
    for ($lic = 0; $lic -le $adc.netScalerLicenseModels.licenseExpirationDate.length; $lic++) {
      $adcDetails = [PSCustomObject]@{
        fqdn = $adc.fqdn
        hostId = $adc.hostId
        daysToExpire = $adc.netScalerLicenseModels.daysToExpire[$lic]
        licenseExpirationDate = $adc.netScalerLicenseModels.licenseExpirationDate[$lic]
        hostType = $adc.netScalerLicenseModels.hostType[$lic]
        localReportingDate= $adc.netScalerLicenseModels.localReportingDate[$lic]
        productName = $adc.netScalerLicenseModels.productName[$lic]
        entitlementId = $adc.netScalerLicenseModels.entitlementId[$lic]
        fulfillmentId = $adc.netScalerLicenseModels.fulfillmentId[$lic]
        deploymentType = $adc.netScalerLicenseModels.deploymentType[$lic]
        vpxMode = $adc.netScalerLicenseModels.vpxMode[$lic]
        isExpired = $adc.netScalerLicenseModels.isExpired[$lic]
        isReporting = $adc.netScalerLicenseModels.isReporting[$lic]
        latestReportingDate = $adc.netScalerLicenseModels.latestReportingDate
        isFoundInBackOffice = $adc.netScalerLicenseModels.isFoundInBackOffice[$lic]
      }
      $adcArray += $adcDetails
    }
  }

}

Switch ( $output ) {
  "flag" { $outObj = $adcArray |
            where-object { 
              $_.isReporting -eq $False -or
              $_.isFoundInBackOffice -eq $True -or 
              $_.isExpired -eq $True -or
              $_.daysToExpire -le 90
            } | Format-Table -Property hostID, fqdn, isReporting, isFoundInBackOffice, isExpired, daysToExpire, licenseExpirationDate
          }
  "notreporting" { $outObj = $adcArray | where-object { $_.isReporting -eq $False } | Format-Table -Property hostID, fqdn, isReporting, lastPhoningHomeTime, productName }
  "notfound" { $outObj = $adcArray | where-object { $_.isFoundInBackOffice -eq $False } | Format-Table -Property hostID, fqdn, isFoundInBackOffice, productName }
  "expired" { $outObj = $adcArray | where-object { $_.isExpired -eq $True } | Format-Table -Property hostID, fqdn, isExpired, productName } 
  "expiring" { $outObj = $adcArray | where-object { $_.daysToExpire -le 90 } | Format-Table -Property hostID, fqdn, licenseExpirationDate, daysToExpire, productName }
  "standalone" { $outObj = $adcArray | where-object { $_.deploymentType -eq "Standalone Primary" } | Format-Table -Property hostID, fqdn, deploymentType, productName }
  "ha" { $outObj = $adcArray | where-object { $_.deploymentType -eq "HA Primary" -or $_.deploymentType -eq "HA Secondary"} | Format-Table -Property hostID, fqdn, deploymentType, productName }
  "clustered" { $outObj = $adcArray | where-object { $_.deploymentType -eq "Cluster Node" } | Format-Table -Property hostID, fqdn, deploymentType, productName }
  "active" { $outObj = $adcArray | where-object { $_.vpxMode -eq "Active" } | Format-Table -Property hostID, fqdn, vpxMode, deploymentType, productName }
  default { $outObj = $adcArray | Format-Table} 
}

$outObj 