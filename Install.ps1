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

# --- Files to copy ---

$filesToCopy = @(
    "_Mods-Functions.ps1",
    "_WAU-mods.ps1"
)
$iconScriptPath = Join-Path $scriptPath "update.ico"
$iconIconsPath = Join-Path $wauIconsPath "update.ico"

# --- Helper functions ---
function Throw-And-Exit($msg) {
    Write-Host $msg
    exit 1
}

function Copy-If-Exists($src, $dst, $desc) {
    if (Test-Path $src) {
        Copy-Item -Path $src -Destination $dst -Force
        Write-Host "[INFO] $desc copied: $src -> $dst"
        return $true
    }
    return $false
}

# --- Ensure folders exist ---
function Ensure-Folder($path) {
    if (-not (Test-Path $path)) {
        try {
            New-Item -Path $path -ItemType Directory -Force | Out-Null
            Write-Host "[INFO] Created folder: $path"
        } catch {
            Throw-And-Exit "[ERROR] Failed to create folder: $path. $($_.Exception.Message)"
        }
    }
}

try {
    # --- Log all key paths ---
    Write-Host "[DEBUG] wauBasePath: $wauBasePath"
    Write-Host "[DEBUG] wauModsPath: $wauModsPath"
    Write-Host "[DEBUG] wauIconsPath: $wauIconsPath"
    Write-Host "[DEBUG] scriptPath: $scriptPath"
    Write-Host "[DEBUG] iconScriptPath: $iconScriptPath"
    Write-Host "[DEBUG] iconIconsPath: $iconIconsPath"
    Write-Host "[DEBUG] iconDestPath: $iconDestPath"

    # --- Ensure required folders exist ---
    Ensure-Folder $wauBasePath
    Ensure-Folder $wauModsPath
    Ensure-Folder $wauIconsPath

    # --- Copy update.ico to icons (only) if missing ---
    if (-not (Test-Path $iconIconsPath) -and (Test-Path $iconScriptPath)) {
        try {
            Copy-Item -Path $iconScriptPath -Destination $iconIconsPath -Force
            Write-Host "[INFO] update.ico copied to $iconIconsPath"
        } catch {
            Write-Host "[ERROR] Dont copy update.ico to icons: $($_.Exception.Message)"
        }
    }

    # --- Remove old mod files ---
    foreach ($file in $filesToCopy) {
        $destPath = Join-Path $wauModsPath $file
        if (Test-Path $destPath) { Remove-Item $destPath -Force }
    }

    # --- Copy mod files (only to mods) ---
    foreach ($file in $filesToCopy) {
        $sourcePath = Join-Path $scriptPath $file
        $destPath = Join-Path $wauModsPath $file
        if (-not (Copy-If-Exists $sourcePath $destPath $file)) {
            Throw-And-Exit "Source file not found: $file"
        }
    }

    # --- Verify files ---
    foreach ($file in $filesToCopy) {
        $destPath = Join-Path $wauModsPath $file
        if (-not (Test-Path $destPath)) {
            Throw-And-Exit "File verification failed: $file"
        }
    }
    if (-not (Test-Path $iconIconsPath)) {
        Throw-And-Exit "File verification failed: update.ico"
    }

    Write-Host "WAU Postpone Mod deployed successfully"
    exit 0
}
catch {
    Write-Host "Error: $($_.Exception.Message)"
    exit 1
}