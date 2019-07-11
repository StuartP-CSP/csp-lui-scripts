###############################################
#       Save-CredentialsFile.ps1
#
# This script is used to create a JSON formatted
# credentials file for the CSP LUI Scripts, which inturn
# utilise the Citrix Cloud licensing API to interact with
# the current LUI Server Status.
#
# https://developer.cloud.com/index.html
# https://licensing.citrixworkspacesapi.net/Help
#
# USE AT OWN RISK - NO WARANTY PROVIDED
#
# Author. Stuart Parkington, Lead SE, CSP EMEA


$customerId = Read-Host -Prompt "CustomerID"
$clientId = Read-Host -Prompt "ClientID"
$clientSecret = Read-Host -Prompt "Client Secret"

$objCreds = New-Object -TypeName psobject
$objCreds | Add-Member -MemberType NoteProperty -Name customerID -Value $customerId
$objCreds | Add-Member -MemberType NoteProperty -Name clientId -Value $clientId
$objCreds | Add-Member -MemberType NoteProperty -Name clientSecret -Value $clientSecret

$objCreds | ConvertTo-Json | Out-File ./cccreds.json