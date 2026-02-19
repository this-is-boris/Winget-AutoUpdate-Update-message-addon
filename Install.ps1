<#
.SYNOPSIS
    Deploy WAU Postpone Mod via Intune
.DESCRIPTION
    Checks if WAU is installed and copies mod files
#>


# === WAU Postpone Mod Installer ===

# --- Paths ---
$wauBasePath = "C:\Program Files\Winget-AutoUpdate"
$wauModsPath = Join-Path $wauBasePath "mods"
$wauIconsPath = Join-Path $wauBasePath "icons"

# --- Script location ---
$scriptPath = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }

# --- Files/folders to copy ---
$modFilesToCopy = @(
    "_Mods-Functions.ps1",
    "_WAU-mods.ps1"
)

$iconFilesToCopy = @(
    "crisis.png",
    "update.png"
)

$templatesFolderName = "templates"
$templatesSourcePath = Join-Path $scriptPath $templatesFolderName
$templatesDestPath = Join-Path $wauModsPath $templatesFolderName

# --- Helper functions ---
function Get-Templates-SourcePath($basePath) {
    $candidateFolders = @("templates", "template")
    foreach ($folder in $candidateFolders) {
        $candidatePath = Join-Path $basePath $folder
        if (Test-Path $candidatePath) {
            return $candidatePath
        }
    }
    return $null
}
function Throw-And-Exit($msg) {
    Write-Host $msg
    exit 1
}

function Ensure-Folder($path) {
    if (-not (Test-Path $path)) {
        try {
            New-Item -Path $path -ItemType Directory -Force | Out-Null
            Write-Host "[INFO] Created folder: $path"
        }
        catch {
            Throw-And-Exit "[ERROR] Failed to create folder: $path. $($_.Exception.Message)"
        }
    }
}

function Copy-File-With-Check($sourcePath, $destPath, $label) {
    if (-not (Test-Path $sourcePath)) {
        Throw-And-Exit "[ERROR] Source not found: $sourcePath"
    }

    try {
        Copy-Item -Path $sourcePath -Destination $destPath -Force
        Write-Host "[INFO] Copied ${label}: $sourcePath -> $destPath"
    }
    catch {
        Throw-And-Exit "[ERROR] Failed to copy $label. $($_.Exception.Message)"
    }
}

try {
    # --- Ensure required folders exist ---
    Ensure-Folder $wauBasePath
    Ensure-Folder $wauModsPath
    Ensure-Folder $wauIconsPath

    # --- Copy templates folder to mods\templates ---
    $templatesSourcePath = Get-Templates-SourcePath -basePath $scriptPath
    if (-not $templatesSourcePath) {
        Throw-And-Exit "[ERROR] Source folder not found: templates/template in $scriptPath"
    }

    if (Test-Path $templatesDestPath) {
        Remove-Item -Path $templatesDestPath -Recurse -Force
    }

    Copy-Item -Path $templatesSourcePath -Destination $templatesDestPath -Recurse -Force
    Write-Host "[INFO] Copied folder: $templatesSourcePath -> $templatesDestPath"

    # --- Copy mod files to mods with replacement ---
    foreach ($file in $modFilesToCopy) {
        $sourcePath = Join-Path $scriptPath $file
        $destPath = Join-Path $wauModsPath $file
        Copy-File-With-Check -sourcePath $sourcePath -destPath $destPath -label $file
    }

    # --- Copy icon files to icons with replacement ---
    foreach ($file in $iconFilesToCopy) {
        $sourcePath = Join-Path $scriptPath $file
        $destPath = Join-Path $wauIconsPath $file
        Copy-File-With-Check -sourcePath $sourcePath -destPath $destPath -label $file
    }

    # --- Verify files ---
    if (-not (Test-Path $templatesDestPath)) {
        Throw-And-Exit "[ERROR] Folder verification failed: $templatesDestPath"
    }

    foreach ($file in $modFilesToCopy) {
        $destPath = Join-Path $wauModsPath $file
        if (-not (Test-Path $destPath)) {
            Throw-And-Exit "[ERROR] File verification failed: $destPath"
        }
    }

    foreach ($file in $iconFilesToCopy) {
        $destPath = Join-Path $wauIconsPath $file
        if (-not (Test-Path $destPath)) {
            Throw-And-Exit "[ERROR] File verification failed: $destPath"
        }
    }

    Write-Host "WAU Postpone Mod deployed successfully"
    exit 0
}
catch {
    Write-Host "Error: $($_.Exception.Message)"
    exit 1
}