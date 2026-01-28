<#
.SYNOPSIS
    Interactive postpone dialog for Winget-AutoUpdate (WAU)
    
.DESCRIPTION
    Pre-update mod script that displays an interactive dialog allowing users to:
    - Postpone updates for 30 or 60 minutes
    - Continue with updates immediately
    
    Features:
    - Works in both SYSTEM (Session 0) and USER contexts
    - Registry-based postpone tracking (HKLM:\SOFTWARE\Romanitho\Winget-AutoUpdate)
    - Protection against infinite postponement (max 1 postpone per 24 hours)
    - Centralized logging to logs\mods-debug.log
    - Returns JSON output to WAU main script
    
.NOTES
    Author: WAU Community
    Version: 2.0
    Registry Keys Used:
        - PostponeLastTime: ISO 8601 timestamp of last postpone
        - PostponeCount: Number of consecutive postpones
        - PostponeTotalCount: Total postpones (statistics)
    
    WAU JSON Response Format:
        - Action: "Continue", "Postpone", or "Abort"
        - PostponeDuration: Hours to postpone (optional)
        - Message: User-friendly message for logs
        - LogLevel: "Green", "Yellow", or "Red"
        - ExitCode: Windows Installer exit code (optional)
    
.LINK
    https://github.com/Romanitho/Winget-AutoUpdate
#>

#region Initialization

# Configure debug logging
$debugLog = "$PSScriptRoot\..\logs\mods-debug.log"

function Write-DebugLog {
    <#
    .SYNOPSIS
        Writes timestamped debug messages to log file
    .PARAMETER msg
        Message to log
    #>
    param([string]$msg)
    
    try {
        "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $msg" | Out-File $debugLog -Append -Encoding UTF8 -ErrorAction Stop
    }
    catch {
        # Silently continue if no write permissions
    }
}

Write-DebugLog "=== WAU Mods Script Started ==="
Write-DebugLog "Current User: $(whoami)"
Write-DebugLog "Session ID: $([System.Diagnostics.Process]::GetCurrentProcess().SessionId)"
Write-DebugLog "Is SYSTEM: $([System.Security.Principal.WindowsIdentity]::GetCurrent().IsSystem)"

#endregion

try {
    #region Load Functions
    
    Write-DebugLog "Loading _Mods-Functions.ps1..."
    . $PSScriptRoot\_Mods-Functions.ps1
    Write-DebugLog "Functions loaded successfully"
    
    # Verify function availability
    if (Get-Command Show-WAUPostponeDialog -ErrorAction SilentlyContinue) {
        Write-DebugLog "Show-WAUPostponeDialog function available"
    }
    else {
        Write-DebugLog "ERROR: Show-WAUPostponeDialog function not found!"
        throw "Required function Show-WAUPostponeDialog is missing"
    }
    
    #endregion
    
    #region Postpone Protection Configuration
    
    # Registry configuration
    $regPath = "HKLM:\SOFTWARE\Romanitho\Winget-AutoUpdate"
    $maxPostpones = 1        # Maximum consecutive postpones allowed before forcing update
    $resetAfterHours = 24    # Hours after which postpone counter resets
    
    #endregion
    
    #region Check Postpone History
    
    Write-DebugLog "Checking postpone history from registry..."
    
    $allowPostpone = $true
    $postponeCount = 0
    
    try {
        # Ensure registry key exists
        if (-not (Test-Path $regPath)) {
            Write-DebugLog "Registry key does not exist, creating: $regPath"
            New-Item -Path $regPath -Force -ErrorAction SilentlyContinue | Out-Null
        }
        
        # Read postpone history from registry
        $lastPostponeValue = Get-ItemProperty -Path $regPath -Name "PostponeLastTime" -ErrorAction SilentlyContinue
        $postponeCountValue = Get-ItemProperty -Path $regPath -Name "PostponeCount" -ErrorAction SilentlyContinue
        
        if ($lastPostponeValue -and $lastPostponeValue.PostponeLastTime) {
            Write-DebugLog "Found postpone history in registry"
            
            # Parse timestamp and calculate elapsed time
            $lastPostpone = [DateTime]::Parse($lastPostponeValue.PostponeLastTime)
            $hoursSinceLastPostpone = ((Get-Date) - $lastPostpone).TotalHours
            $currentCount = if ($postponeCountValue) { $postponeCountValue.PostponeCount } else { 0 }
            
            Write-DebugLog "Last postpone: $lastPostpone ($([math]::Round($hoursSinceLastPostpone, 2)) hours ago)"
            Write-DebugLog "Current postpone count: $currentCount"
            
            # Check if within reset period
            if ($hoursSinceLastPostpone -lt $resetAfterHours) {
                $postponeCount = $currentCount
                
                if ($postponeCount -ge $maxPostpones) {
                    Write-DebugLog "Maximum postpones reached ($postponeCount/$maxPostpones) - forcing update"
                    $allowPostpone = $false
                }
                else {
                    Write-DebugLog "Within reset period - postpone allowed ($postponeCount/$maxPostpones used)"
                }
            }
            else {
                Write-DebugLog "Reset period expired ($([math]::Round($hoursSinceLastPostpone, 2))h > $($resetAfterHours)h) - resetting counter"
                $postponeCount = 0
            }
        }
        else {
            Write-DebugLog "No postpone history found - first time run"
        }
    }
    catch {
        Write-DebugLog "ERROR reading registry: $($_.Exception.Message)"
        # On error, allow postpone (fail-safe)
    }
    
    #endregion
    
    #region Handle Maximum Postpones Reached
    
    if (-not $allowPostpone) {
        Write-DebugLog "Postpone not allowed - forcing update to proceed"
        
        # Clear postpone history to allow future postpones after update
        try {
            Remove-ItemProperty -Path $regPath -Name "PostponeLastTime" -ErrorAction SilentlyContinue
            Remove-ItemProperty -Path $regPath -Name "PostponeCount" -ErrorAction SilentlyContinue
            Write-DebugLog "Cleared postpone history from registry"
        }
        catch {
            Write-DebugLog "ERROR clearing registry: $($_.Exception.Message)"
        }
        
        # Return JSON response to WAU
        $result = @{
            Action   = "Continue"
            Message  = "Maximum postpone limit reached ($maxPostpones times). Updates will proceed now."
            LogLevel = "Yellow"
        } | ConvertTo-Json -Compress
        
        Write-DebugLog "Returning: $result"
        Write-Output $result
        Exit 0
    }
    
    #endregion
    
    #region Display Postpone Dialog
    
    Write-DebugLog "Showing postpone dialog to user..."
    $postponeHours = Show-WAUPostponeDialog
    Write-DebugLog "User response: $(if ($null -eq $postponeHours) { 'Update Now' } else { "$postponeHours hours" })"
    
    #endregion
    
    #region Handle User Choice: Postpone
    
    if ($null -ne $postponeHours) {
        Write-DebugLog "Processing postpone request for $postponeHours hours"
        
        # Update postpone history in registry
        try {
            $timestamp = (Get-Date).ToString("o")  # ISO 8601 format
            Set-ItemProperty -Path $regPath -Name "PostponeLastTime" -Value $timestamp -Type String
            Set-ItemProperty -Path $regPath -Name "PostponeCount" -Value ($postponeCount + 1) -Type DWord
            
            # Track total postpones for statistics (optional)
            $totalPostpones = Get-ItemProperty -Path $regPath -Name "PostponeTotalCount" -ErrorAction SilentlyContinue
            if ($totalPostpones) {
                Set-ItemProperty -Path $regPath -Name "PostponeTotalCount" -Value ($totalPostpones.PostponeTotalCount + 1) -Type DWord
            }
            else {
                Set-ItemProperty -Path $regPath -Name "PostponeTotalCount" -Value 1 -Type DWord
            }
            
            Write-DebugLog "Updated registry: PostponeCount=$($postponeCount + 1), Time=$timestamp"
        }
        catch {
            Write-DebugLog "ERROR updating registry: $($_.Exception.Message)"
        }
        
        # Calculate remaining postpones
        $remainingPostpones = $maxPostpones - ($postponeCount + 1)
        $message = if ($remainingPostpones -gt 0) {
            "Updates postponed for $postponeHours hours ($remainingPostpones postpones remaining)"
        }
        else {
            "Updates postponed for $postponeHours hours (last postpone allowed)"
        }
        
        # Return JSON response with postpone action
        $result = @{
            Action           = "Postpone"
            PostponeDuration = $postponeHours
            Message          = $message
            LogLevel         = "Yellow"
            ExitCode         = 1602  # Windows Installer: User cancelled
        } | ConvertTo-Json -Compress
        
        Write-DebugLog "Returning: $result"
        Write-Output $result
        Exit 0
    }
    
    #endregion
    
    #region Handle User Choice: Update Now
    
    else {
        Write-DebugLog "User chose to update immediately"
        
        # Clear postpone history from registry
        try {
            Remove-ItemProperty -Path $regPath -Name "PostponeLastTime" -ErrorAction SilentlyContinue
            Remove-ItemProperty -Path $regPath -Name "PostponeCount" -ErrorAction SilentlyContinue
            Write-DebugLog "Cleared postpone history from registry"
        }
        catch {
            Write-DebugLog "ERROR clearing registry: $($_.Exception.Message)"
        }
        
        # Return JSON response to proceed with updates
        $result = @{
            Action   = "Continue"
            Message  = "User chose to continue with updates immediately"
            LogLevel = "Green"
        } | ConvertTo-Json -Compress
        
        Write-DebugLog "Returning: $result"
        Write-Output $result
        Exit 0
    }
    
    #endregion
}
catch {
    #region Error Handling
    
    Write-DebugLog "CRITICAL ERROR: $($_.Exception.Message)"
    Write-DebugLog "Stack Trace: $($_.ScriptStackTrace)"
    
    # On error, continue with updates (fail-safe behavior)
    $result = @{
        Action   = "Continue"
        Message  = "Mods script error: $($_.Exception.Message). Proceeding with updates."
        LogLevel = "Red"
    } | ConvertTo-Json -Compress
    
    Write-DebugLog "Returning error response: $result"
    Write-Output $result
    Exit 0
    
    #endregion
}
