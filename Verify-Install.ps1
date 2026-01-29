<#
.SYNOPSIS
    Verifies WAU Postpone Mod installation and integrity
.DESCRIPTION
    Checks that all required files exist and that the function Show-WAUPostponeDialog is present in _Mods-Functions.ps1
#>

# --- Paths ---
$wauBasePath = "C:\Program Files\Winget-AutoUpdate"
$wauModsPath = Join-Path $wauBasePath "mods"
$wauIconsPath = Join-Path $wauBasePath "icons"

$filesToCheck = @(
    "_Mods-Functions.ps1",
    "_WAU-mods.ps1"
)
$iconToCheck = "update.ico"

$allOk = $true

# --- Check mod files ---
foreach ($file in $filesToCheck) {
    $filePath = Join-Path $wauModsPath $file
    if (-not (Test-Path $filePath)) {
        Write-Host "[ERROR] Missing file: $filePath"
        $allOk = $false
    } else {
        Write-Host "[OK] Found: $filePath"
    }
}

# --- Check icon ---
$iconPath = Join-Path $wauIconsPath $iconToCheck
if (-not (Test-Path $iconPath)) {
    Write-Host "[ERROR] Missing icon: $iconPath"
    $allOk = $false
} else {
    Write-Host "[OK] Found: $iconPath"
}

# --- Check function in _Mods-Functions.ps1 ---
$modsFunctionsPath = Join-Path $wauModsPath "_Mods-Functions.ps1"
if (Test-Path $modsFunctionsPath) {
    $content = Get-Content $modsFunctionsPath -Raw
    if ($content -match 'function\s+Show-WAUPostponeDialog') {
        Write-Host "[OK] Function Show-WAUPostponeDialog found in _Mods-Functions.ps1"
    } else {
        Write-Host "[ERROR] Function Show-WAUPostponeDialog NOT found in _Mods-Functions.ps1"
        $allOk = $false
    }
}

if ($allOk) {
    Write-Host "All required files and functions are present."
    exit 0
} else {
    Write-Host "Some files or functions are missing."
    exit 1
}
