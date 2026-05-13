# Generate-InstallationScripts.ps1
# Generates installation, uninstallation, and detection scripts for Winget packages

param(
    [Parameter(Mandatory = $true)]
    [string]$PackageId,

    [Parameter(Mandatory = $false)]
    [bool]$UsePSADT = $true,

    [Parameter(Mandatory = $false)]
    [string]$InstallContext = "system",

    [Parameter(Mandatory = $false)]
    [string]$AppName,

    [Parameter(Mandatory = $false)]
    [string]$Publisher,

    [Parameter(Mandatory = $false)]
    [string]$Version,

    [Parameter(Mandatory = $false)]
    [string]$CustomDetectionScript
)

if (-not $AppName) {
    $AppName = $PackageId.Split('.')[-1]
}

if ($UsePSADT) {
    # Generate PSADT installation script
    $installScript = @"
## PowerShell App Deployment Toolkit Script
## App Name - $AppName
## Publisher - $Publisher
## Version - $Version

[CmdletBinding()]
Param (
    [Parameter(Mandatory = `$false)]
    [ValidateSet('Install','Uninstall','Repair')]
    [String]`$DeploymentType = 'Install',
    [Parameter(Mandatory = `$false)]
    [ValidateSet('Interactive','Silent','NonInteractive')]
    [String]`$DeployMode = 'Silent'
)

Try {
    Set-ExecutionPolicy -ExecutionPolicy 'ByPass' -Scope 'Process' -Force -ErrorAction 'Stop'

    ## Variables: Application
    [String]`$appVendor = '$Publisher'
    [String]`$appName = '$AppName'
    [String]`$appVersion = '$Version'
    [String]`$appArch = 'x64'
    [String]`$appLang = 'EN'
    [String]`$appRevision = '01'
    [String]`$appScriptVersion = '1.0.0'
    [String]`$appScriptDate = '`$(Get-Date -Format 'yyyy-MM-dd')'
    [String]`$appScriptAuthor = 'GitHub Actions'

    ## Dot source the required App Deploy Toolkit Functions
    Try {
        [String]`$moduleAppDeployToolkitMain = "`$scriptDirectory\AppDeployToolkit\AppDeployToolkitMain.ps1"
        If (-not (Test-Path -LiteralPath `$moduleAppDeployToolkitMain -PathType 'Leaf')) {
            Throw "Module does not exist at the specified location [`$moduleAppDeployToolkitMain]."
        }
        . `$moduleAppDeployToolkitMain
    }
    Catch {
        If (`$mainExitCode -eq 0) { [Int32]`$mainExitCode = 60008 }
        Write-Error "Module [`$moduleAppDeployToolkitMain] failed to load: ``n`$(`$_.Exception.Message)"
        Exit `$mainExitCode
    }

    If (`$deploymentType -ine 'Uninstall' -and `$deploymentType -ine 'Repair') {
        [String]`$installPhase = 'Pre-Installation'
        Show-InstallationWelcome -CloseApps 'iexplore' -CheckDiskSpace -PersistPrompt

        [String]`$installPhase = 'Installation'
        Execute-Process -Path 'winget' -Parameters "install --id $PackageId --silent --accept-package-agreements --accept-source-agreements" -WindowStyle 'Hidden'

        [String]`$installPhase = 'Post-Installation'
    }
    ElseIf (`$deploymentType -ieq 'Uninstall') {
        [String]`$installPhase = 'Pre-Uninstallation'
        Show-InstallationWelcome -CloseApps 'iexplore' -CloseAppsCountdown 300

        [String]`$installPhase = 'Uninstallation'
        Execute-Process -Path 'winget' -Parameters "uninstall --id $PackageId --silent" -WindowStyle 'Hidden'

        [String]`$installPhase = 'Post-Uninstallation'
    }

    Exit-Script -ExitCode `$mainExitCode
}
Catch {
    [Int32]`$mainExitCode = 60001
    [String]`$mainErrorMessage = "``$(Resolve-Error)"
    Write-Log -Message `$mainErrorMessage -Severity 3 -Source `$deployAppScriptFriendlyName
    Show-DialogBox -Text `$mainErrorMessage -Icon 'Stop'
    Exit-Script -ExitCode `$mainExitCode
}
"@

    $uninstallScript = 'Deploy-Application.exe -DeploymentType "Uninstall" -DeployMode "Silent"'
} else {
    # Standard Winget scripts
    $installScript = "winget install --id $PackageId --silent --accept-package-agreements --accept-source-agreements"
    $uninstallScript = "winget uninstall --id $PackageId --silent"
}

# Detection script
$detectionScript = $CustomDetectionScript
if (-not $detectionScript) {
    $detectionScript = @"
# Detection script for $AppName
try {
    `$wingetList = winget list --id $PackageId --exact --accept-source-agreements 2>`$null

    if (`$wingetList -match `"$PackageId`") {
        Write-Output `"$AppName is installed`"
        exit 0
    }

    # Alternative registry detection
    `$uninstallKeys = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"
    )

    foreach (`$key in `$uninstallKeys) {
        `$apps = Get-ChildItem -Path `$key -ErrorAction SilentlyContinue
        foreach (`$app in `$apps) {
            `$properties = Get-ItemProperty -Path `$app.PSPath -ErrorAction SilentlyContinue
            if (`$properties.DisplayName -like "*$AppName*" -and `$properties.Publisher -like "*$Publisher*") {
                Write-Output "$AppName is installed (Registry)"
                exit 0
            }
        }
    }

    Write-Output "$AppName is not installed"
    exit 1
}
catch {
    Write-Error "Detection script failed: `$_"
    exit 1
}
"@
}

# Save scripts to output
$installScript | Out-File -FilePath "install_script.ps1" -Encoding UTF8
$uninstallScript | Out-File -FilePath "uninstall_script.ps1" -Encoding UTF8
$detectionScript | Out-File -FilePath "detection_script.ps1" -Encoding UTF8

# Set output
if ($env:GITHUB_OUTPUT) {
    Add-Content -Path $env:GITHUB_OUTPUT -Value "scripts_generated=true"
}

Write-Host "Scripts generated successfully"
Write-Host "- install_script.ps1"
Write-Host "- uninstall_script.ps1"
Write-Host "- detection_script.ps1"
