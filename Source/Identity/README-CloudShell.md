# Azure Cloud Shell Usage for Identity Policy Scripts

## NewIdentity-CloudShell.ps1

This script is designed to run in Azure Cloud Shell **without** requiring Power Platform PowerShell modules.

### Important: How to Run

**DO NOT** run this script from a directory where you have the repository cloned with other PowerShell scripts that auto-import modules.

#### Option 1: Download and Run Directly (Recommended for Cloud Shell)

```bash
# Download the script directly from GitHub
curl -O https://raw.githubusercontent.com/sarmadjari/PowerPlatform-EnterprisePolicies/main/Source/Identity/NewIdentity-CloudShell.ps1

# Run it
pwsh ./NewIdentity-CloudShell.ps1 -environmentId "YOUR-ENV-ID" -policyArmId "/subscriptions/.../enterprisePolicies/myPolicy"
```

#### Option 2: Run from a Clean Directory

If you have the repository cloned:

```powershell
# Copy the script to a clean directory
mkdir ~/temp-identity
cp ~/PowerPlatform-EnterprisePolicies/Source/Identity/NewIdentity-CloudShell.ps1 ~/temp-identity/
cd ~/temp-identity

# Run it
./NewIdentity-CloudShell.ps1 -environmentId "YOUR-ENV-ID" -policyArmId "/subscriptions/.../enterprisePolicies/myPolicy"
```

### Why This Matters

If you run the script from within the repository directory structure, PowerShell may auto-import other scripts from the `Common` folder that have dependencies on Power Platform modules, causing the error:

```
Import-Module: /home/farhana/PowerPlatform-EnterprisePolicies/Source/Common/EnvironmentEnterprisePolicyOperations.ps1:32
The module to process 'Microsoft.PowerApps.PowerShell.psd1', listed in field 'ModuleToProcess/RootModule' of module manifest...
```

The `NewIdentity-CloudShell.ps1` script is **completely self-contained** and has all the functions it needs built-in.

### Prerequisites

- Azure Cloud Shell (or local PowerShell with Az module installed)
- Already authenticated to Azure (`Connect-AzAccount` if running locally)
- Appropriate permissions to the Power Platform environment and Enterprise Policy

### Parameters

- `environmentId` (required) - The GUID of your Power Platform environment
- `policyArmId` (required) - Full ARM resource ID of the Enterprise Identity Policy
  - Format: `/subscriptions/{sub-id}/resourceGroups/{rg-name}/providers/Microsoft.PowerPlatform/enterprisePolicies/{policy-name}`
- `endpoint` (optional) - BAP endpoint, defaults to "prod"
  - Options: tip1, tip2, prod, usgovhigh, dod, china

### Example

```powershell
./NewIdentity-CloudShell.ps1 `
    -environmentId "12345678-1234-1234-1234-123456789abc" `
    -policyArmId "/subscriptions/abc-123/resourceGroups/my-rg/providers/Microsoft.PowerPlatform/enterprisePolicies/my-identity-policy" `
    -endpoint "prod"
```
