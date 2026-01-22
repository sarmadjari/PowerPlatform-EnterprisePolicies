<#
SAMPLE CODE NOTICE

THIS SAMPLE CODE IS MADE AVAILABLE AS IS. MICROSOFT MAKES NO WARRANTIES, WHETHER EXPRESS OR IMPLIED,
OF FITNESS FOR A PARTICULAR PURPOSE, OF ACCURACY OR COMPLETENESS OF RESPONSES, OF RESULTS, OR CONDITIONS OF MERCHANTABILITY.
THE ENTIRE RISK OF THE USE OR THE RESULTS FROM THE USE OF THIS SAMPLE CODE REMAINS WITH THE USER.
NO TECHNICAL SUPPORT IS PROVIDED. YOU MAY NOT DISTRIBUTE THIS CODE UNLESS YOU HAVE A LICENSE AGREEMENT WITH MICROSOFT THAT ALLOWS YOU TO DO SO.

.SYNOPSIS
Azure Cloud Shell compatible version of NewIdentity that uses Azure access tokens instead of Power Platform modules.

.DESCRIPTION
This script links an Enterprise Identity Policy to a Power Platform environment using only Azure authentication,
making it fully compatible with Azure Cloud Shell without requiring interactive Power Platform login.

IMPORTANT: This script is completely self-contained and does NOT require any Power Platform PowerShell modules.
It should be run directly without dot-sourcing any other scripts from the repository.

.PARAMETER environmentId
The GUID of the Power Platform environment

.PARAMETER policyArmId
The full ARM resource ID of the Enterprise Identity Policy

.PARAMETER endpoint
The BAP endpoint (tip1, tip2, prod, usgovhigh, dod, china). Defaults to "prod"

.EXAMPLE
./NewIdentity-CloudShell.ps1 -environmentId "abc123..." -policyArmId "/subscriptions/.../enterprisePolicies/myPolicy" -endpoint "prod"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [String]$environmentId,

    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [String]$policyArmId,

    [Parameter(Mandatory=$false)]
    [ValidateSet("tip1", "tip2", "prod", "usgovhigh", "dod", "china")]
    [String]$endpoint = "prod"
)

# CRITICAL: Stop immediately if any Power Platform modules try to load
$ErrorActionPreference = "Stop"
$ProgressPreference = 'SilentlyContinue'

# Verify we're not accidentally importing Power Platform modules
$loadedModules = Get-Module | Where-Object { $_.Name -like "*PowerApps*" -or $_.Name -like "*PowerPlatform*" }
if ($loadedModules) {
    Write-Warning "Detected Power Platform modules already loaded. This script is designed to work WITHOUT them."
    Write-Warning "Loaded modules: $($loadedModules.Name -join ', ')"
    Write-Warning "Continuing anyway, but this may cause conflicts..."
}

#region Helper Functions

function Get-BAPResourceUrl {
    param([string]$Endpoint)

    switch ($Endpoint) {
        "tip1" { return "https://tip1.api.bap.microsoft.com/" }
        "tip2" { return "https://tip2.api.bap.microsoft.com/" }
        "prod" { return "https://api.bap.microsoft.com/" }
        "usgovhigh" { return "https://high.api.bap.microsoft.us/" }
        "dod" { return "https://api.bap.appsplatform.us/" }
        "china" { return "https://api.bap.partner.microsoftonline.cn/" }
        default { throw "Invalid endpoint: $Endpoint" }
    }
}

function Get-AzureEnvironmentName {
    param([string]$Endpoint)

    switch ($Endpoint) {
        { $_ -in @("usgovhigh", "dod") } { return "AzureUSGovernment" }
        "china" { return "AzureChinaCloud" }
        default { return "AzureCloud" }
    }
}

function Get-AccessToken {
    param(
        [string]$Endpoint,
        [string]$AzureEnvironmentName
    )

    $resourceUrl = Get-BAPResourceUrl -Endpoint $Endpoint

    Write-Host "Acquiring access token for: $resourceUrl" -ForegroundColor Green

    # First attempt: Try to get token silently
    $token = Get-AzAccessToken -ResourceUrl $resourceUrl -ErrorAction SilentlyContinue

    if ($null -eq $token) {
        Write-Host "Silent token acquisition failed. Authenticating interactively with AuthScope..." -ForegroundColor Yellow
        Write-Host "You may be prompted for device code authentication (no browser window needed)." -ForegroundColor Yellow

        # Re-authenticate with AuthScope to get token for BAP API
        Connect-AzAccount -Environment $AzureEnvironmentName -AuthScope $resourceUrl -ErrorAction Stop | Out-Null

        # Try again after re-authentication
        $token = Get-AzAccessToken -ResourceUrl $resourceUrl -ErrorAction Stop
    }

    if ($null -eq $token -or [string]::IsNullOrEmpty($token.Token)) {
        throw "Failed to acquire access token for BAP API. Please check your Azure login."
    }

    return $token.Token
}

function Invoke-BAPApi {
    param(
        [string]$Uri,
        [string]$Method,
        [string]$AccessToken,
        [object]$Body = $null
    )

    $headers = @{
        "Authorization" = "Bearer $AccessToken"
        "Content-Type" = "application/json"
    }

    $params = @{
        Uri = $Uri
        Method = $Method
        Headers = $headers
    }

    if ($Body) {
        $params['Body'] = ($Body | ConvertTo-Json -Depth 10)
    }

    try {
        $response = Invoke-WebRequest @params -UseBasicParsing
        return @{
            StatusCode = $response.StatusCode
            Content = ($response.Content | ConvertFrom-Json -ErrorAction SilentlyContinue)
            Headers = $response.Headers
        }
    }
    catch {
        Write-Host "API call failed: $_" -ForegroundColor Red
        throw
    }
}

function Get-Environment {
    param(
        [string]$EnvironmentId,
        [string]$BAPBaseUrl,
        [string]$AccessToken
    )

    $uri = "${BAPBaseUrl}providers/Microsoft.BusinessAppPlatform/environments/${EnvironmentId}?api-version=2016-11-01"
    Write-Host "Retrieving environment: $EnvironmentId" -ForegroundColor Green

    $result = Invoke-BAPApi -Uri $uri -Method "GET" -AccessToken $AccessToken

    if ($null -eq $result.Content.Id) {
        throw "Environment not found or error retrieving environment: $EnvironmentId"
    }

    Write-Host "Environment retrieved: $($result.Content.properties.displayName)" -ForegroundColor Green
    return $result.Content
}

function Get-EnterprisePolicySystemId {
    param(
        [string]$PolicyArmId,
        [string]$AzureEnvironmentName
    )

    Write-Host "Retrieving Enterprise Policy: $PolicyArmId" -ForegroundColor Green

    # Ensure connected to Azure
    $context = Get-AzContext
    if ($null -eq $context) {
        Write-Host "Connecting to Azure: $AzureEnvironmentName" -ForegroundColor Green
        Connect-AzAccount -Environment $AzureEnvironmentName -ErrorAction Stop | Out-Null
    }

    $policy = Get-AzResource -ResourceId $PolicyArmId -ErrorAction Stop

    if ($null -eq $policy -or $null -eq $policy.Properties.systemId) {
        throw "Enterprise Policy not found or missing systemId: $PolicyArmId"
    }

    Write-Host "Enterprise Policy retrieved: $($policy.Name)" -ForegroundColor Green
    return $policy.Properties.systemId
}

function Link-IdentityPolicy {
    param(
        [object]$Environment,
        [string]$PolicySystemId,
        [string]$BAPBaseUrl,
        [string]$AccessToken
    )

    $environmentName = $Environment.Name
    $uri = "${BAPBaseUrl}providers/Microsoft.BusinessAppPlatform/environments/${environmentName}/enterprisePolicies/Identity/link?api-version=2019-10-01"

    $body = @{
        "SystemId" = $PolicySystemId
    }

    Write-Host "Linking Identity policy to environment..." -ForegroundColor Green

    $result = Invoke-BAPApi -Uri $uri -Method "POST" -AccessToken $AccessToken -Body $body

    if ($result.StatusCode -ne 202) {
        throw "Failed to link Identity policy. Status: $($result.StatusCode)"
    }

    Write-Host "Identity policy linked successfully!" -ForegroundColor Green
    Write-Host "Response: $($result.Content | ConvertTo-Json -Depth 5)" -ForegroundColor Cyan

    return $result
}

#endregion

#region Main Script

Write-Host "`n=== Link Enterprise Identity Policy to Environment ===" -ForegroundColor Cyan
Write-Host "Environment ID: $environmentId" -ForegroundColor Yellow
Write-Host "Policy ARM ID: $policyArmId" -ForegroundColor Yellow
Write-Host "Endpoint: $endpoint" -ForegroundColor Yellow
Write-Host ""

# Step 1: Get Azure environment and connect if needed
$azureEnvName = Get-AzureEnvironmentName -Endpoint $endpoint
Write-Host "[1/4] Ensuring Azure connection to $azureEnvName..." -ForegroundColor Cyan

$context = Get-AzContext
if ($null -eq $context -or $context.Environment.Name -ne $azureEnvName) {
    Write-Host "Connecting to Azure: $azureEnvName" -ForegroundColor Green
    Connect-AzAccount -Environment $azureEnvName -ErrorAction Stop | Out-Null
}
else {
    Write-Host "Already connected to Azure: $azureEnvName" -ForegroundColor Green
}

# Step 2: Get access token for BAP API
Write-Host "`n[2/4] Acquiring BAP API access token..." -ForegroundColor Cyan
$accessToken = Get-AccessToken -Endpoint $endpoint -AzureEnvironmentName $azureEnvName

# Step 3: Validate environment and policy
Write-Host "`n[3/4] Validating environment and policy..." -ForegroundColor Cyan
$bapBaseUrl = Get-BAPResourceUrl -Endpoint $endpoint
$environment = Get-Environment -EnvironmentId $environmentId -BAPBaseUrl $bapBaseUrl -AccessToken $accessToken
$policySystemId = Get-EnterprisePolicySystemId -PolicyArmId $policyArmId -AzureEnvironmentName $azureEnvName

# Step 4: Link the policy
Write-Host "`n[4/4] Linking Identity policy to environment..." -ForegroundColor Cyan
$linkResult = Link-IdentityPolicy -Environment $environment -PolicySystemId $policySystemId -BAPBaseUrl $bapBaseUrl -AccessToken $accessToken

Write-Host "`n=== Operation Completed Successfully ===" -ForegroundColor Green

#endregion
