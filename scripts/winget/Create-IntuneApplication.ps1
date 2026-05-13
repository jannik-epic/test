# Create-IntuneApplication.ps1
# Creates a Win32 application in Microsoft Intune

param(
    [Parameter(Mandatory = $true)]
    [string]$AccessToken,

    [Parameter(Mandatory = $true)]
    [string]$PackageId,

    [Parameter(Mandatory = $false)]
    [string]$AppName,

    [Parameter(Mandatory = $false)]
    [string]$AppDescription,

    [Parameter(Mandatory = $false)]
    [string]$Publisher,

    [Parameter(Mandatory = $false)]
    [string]$Version,

    [Parameter(Mandatory = $false)]
    [string]$InstallContext = "system",

    [Parameter(Mandatory = $false)]
    [bool]$UsePSADT = $true,

    [Parameter(Mandatory = $false)]
    [string]$IntuneApiUrl = "https://graph.microsoft.com/v1.0"
)

if (-not $AppName) {
    $AppName = $PackageId.Split('.')[-1]
}

if (-not $AppDescription) {
    $AppDescription = "$AppName installed via Winget"
}

# Read generated scripts
$installScript = Get-Content -Path "install_script.ps1" -Raw
$uninstallScript = Get-Content -Path "uninstall_script.ps1" -Raw
$detectionScript = Get-Content -Path "detection_script.ps1" -Raw

# Create app data for Intune
$appData = @{
    '@odata.type' = '#microsoft.graph.win32LobApp'
    displayName = $AppName
    description = $AppDescription
    publisher = $Publisher
    installExperience = @{
        runAsAccount = $InstallContext
        deviceRestartBehavior = 'basedOnReturnCode'
    }
    installCommandLine = if ($UsePSADT) { 'Deploy-Application.exe -DeploymentType "Install" -DeployMode "Silent"' } else { $installScript }
    uninstallCommandLine = $uninstallScript
    detectionRules = @(
        @{
            '@odata.type' = '#microsoft.graph.win32LobAppPowerShellScriptDetection'
            enforceSignatureCheck = $false
            runAs32Bit = $false
            scriptContent = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($detectionScript))
        }
    )
    requirementRules = @(
        @{
            '@odata.type' = '#microsoft.graph.win32LobAppRegistryRequirement'
            operator = 'equal'
            keyPath = 'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion'
            valueName = 'ProgramFilesDir'
            check32BitOn64System = $false
            detectionType = 'exists'
        }
    )
    returnCodes = @(
        @{ returnCode = 0; type = 'success' }
        @{ returnCode = 1; type = 'failed' }
        @{ returnCode = 1641; type = 'hardReboot' }
        @{ returnCode = 3010; type = 'softReboot' }
        @{ returnCode = 1618; type = 'retry' }
    )
    notes = "Package ID: $PackageId`nInstalled via: Winget`nInstall Method: $InstallContext`nUsing PSADT: $UsePSADT`nDeployed via: GitHub Actions"
}

# Convert to JSON
$jsonData = $appData | ConvertTo-Json -Depth 10

# Create the application in Intune
$headers = @{
    'Authorization' = "Bearer $AccessToken"
    'Content-Type' = 'application/json'
}

try {
    $response = Invoke-RestMethod -Uri "$IntuneApiUrl/deviceAppManagement/mobileApps" -Method POST -Headers $headers -Body $jsonData

    $appId = $response.id
    $appDisplayName = $response.displayName

    Write-Host "Successfully created application: $appDisplayName (ID: $appId)"

    if ($env:GITHUB_OUTPUT) {
        Add-Content -Path $env:GITHUB_OUTPUT -Value "app_id=$appId"
        Add-Content -Path $env:GITHUB_OUTPUT -Value "app_name=$appDisplayName"
        Add-Content -Path $env:GITHUB_OUTPUT -Value "success=true"
    }
}
catch {
    Write-Error "Failed to create application: $_"
    if ($env:GITHUB_OUTPUT) {
        Add-Content -Path $env:GITHUB_OUTPUT -Value "success=false"
    }
    exit 1
}
