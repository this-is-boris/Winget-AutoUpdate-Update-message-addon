#Common shared functions to handle the mods

function Invoke-ModsApp ($Run, $RunSwitch, $RunWait, $User) {
    if (Test-Path "$Run") {
        if (!$RunSwitch) { $RunSwitch = " " }
        if (!$User) {
            if (!$RunWait) {
                Start-Process $Run -ArgumentList $RunSwitch
            }
            else {
                Start-Process $Run -ArgumentList $RunSwitch -Wait
            }
        }
        else {
            Start-Process explorer $Run
        }
    }
    Return
}

function Skip-ModsProc ($SkipApp) {
    foreach ($process in $SkipApp) {
        $running = Get-Process -Name $process -ErrorAction SilentlyContinue
        if ($running) {
            Return $true
        }
    }
    Return
}

function Stop-ModsProc ($Proc) {
    foreach ($process in $Proc) {
        Stop-Process -Name $process -Force -ErrorAction SilentlyContinue | Out-Null
    }
    Return
}

function Stop-ModsSvc ($Svc) {
    foreach ($service in $Svc) {
        Stop-Service -Name $service -Force -ErrorAction SilentlyContinue | Out-Null
    }
    Return
}

function Wait-ModsProc ($Wait) {
    foreach ($process in $Wait) {
        Get-Process $process -ErrorAction SilentlyContinue | Foreach-Object { $_.WaitForExit() }
    }
    Return
}

function Install-WingetID ($WingetIDInst) {
    foreach ($app in $WingetIDInst) {
        & $Winget install --id $app -e --accept-package-agreements --accept-source-agreements -s winget -h
    }
    Return
}

function Uninstall-WingetID ($WingetIDUninst) {
    foreach ($app in $WingetIDUninst) {
        & $Winget uninstall --id $app -e --accept-source-agreements -s winget -h
    }
    Return
}

function Uninstall-ModsApp ($AppUninst, $AllVersions) {
    foreach ($app in $AppUninst) {
        # we start from scanning the x64 node in registry, if something was found, then we set x64=TRUE
        [bool]$app_was_x64 = Get-InstalledSoftware -app $app -x64 $true;

        # if nothing was found in x64 node, then we repeat that action in x86 node
        if (!$app_was_x64) {
            Get-InstalledSoftware -app $app | Out-Null;
        }
    }
    Return
}

Function Get-InstalledSoftware() {
    [OutputType([Bool])]
    Param(
        [parameter(Mandatory = $true)] [string]$app,
        [parameter(Mandatory = $false)][bool]  $x64 = $false
    )
    if ($true -eq $x64) {
        [string]$path = "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall";
    }
    else {
        [string]$path = "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall";
    }

    [bool]$app_was_found = $false;
    [Microsoft.Win32.RegistryKey[]]$InstalledSoftware = Get-ChildItem $path;
    foreach ($obj in $InstalledSoftware) {
        if ($obj.GetValue('DisplayName') -like $App) {
            $UninstallString = $obj.GetValue('UninstallString')
            $CleanedUninstallString = $UninstallString.Replace('"', '')
            $ExeString = $CleanedUninstallString.Substring(0, $CleanedUninstallString.IndexOf('.exe') + 4)
            if ($UninstallString -like "MsiExec.exe*") {
                $ProductCode = Select-String "{.*}" -inputobject $UninstallString
                $ProductCode = $ProductCode.matches.groups[0].value
                # MSI Installer
                $Exec = Start-Process "$env:SystemRoot\System32\msiexec.exe" -ArgumentList "/x$ProductCode REBOOT=R /qn" -PassThru -Wait
                # Stop Hard Reboot (if bad MSI!)
                if ($Exec.ExitCode -eq 1641) {
                    Start-Process "$env:SystemRoot\System32\shutdown.exe" -ArgumentList "/a"
                }
            }
            else {
                $QuietUninstallString = $obj.GetValue('QuietUninstallString')
                if ($QuietUninstallString) {
                    $QuietUninstallString = Select-String '("[^"]*") +(.*)' -inputobject $QuietUninstallString
                    $Command = $QuietUninstallString.matches.groups[1].value
                    $Parameter = $QuietUninstallString.matches.groups[2].value
                    # All EXE Installers (already defined silent uninstall)
                    Start-Process $Command -ArgumentList $Parameter -Wait
                }
                else {
                    # Improved detection logic
                    if ((Test-Path $ExeString -ErrorAction SilentlyContinue)) {
                        try {
                            # Read the whole file to find installer signatures
                            $fileContent = Get-Content -Path $ExeString -Raw -ErrorAction Stop
                            # Executes silent uninstallation based on installer type
                            if ($fileContent -match "\bNullsoft\b" -or $fileContent -match "\bNSIS\b") {
                                # Nullsoft (NSIS) Uninstaller
                                Start-Process $ExeString -ArgumentList "/NCRC /S" -Wait
                            }
                            elseif ($fileContent -match "\bInno Setup\b") {
                                # Inno Uninstaller
                                Start-Process $ExeString -ArgumentList "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP-" -Wait
                            }
                            elseif ($fileContent -match "\bWise Solutions\b") {
                                # Wise Uninstaller (Unwise32.exe)
                                # Find the Install.log path parameter in the UninstallString
                                $ArgString = $CleanedUninstallString.Substring($CleanedUninstallString.IndexOf('.exe') + 4).Trim()
                                # Copy files to temp folder so that Unwise32.exe can find Install.log (very, very old system)
                                Copy-Item -Path $ExeString -Destination $env:TEMP -Force
                                $ExeString = Join-Path $env:TEMP (Split-Path $ExeString -Leaf)
                                Copy-Item -Path $ArgString -Destination $env:TEMP -Force
                                $ArgString = Join-Path $env:TEMP (Split-Path $ArgString -Leaf)
                                # Execute the uninstaller with the copied Unwise32.exe
                                Start-Process $ExeString -ArgumentList "/s $ArgString" -Wait
                                # Remove the copied Unwise32.exe from temp folder (Install.log gets deleted by Unwise32.exe)
                                Remove-Item -Path $ExeString -Force -ErrorAction SilentlyContinue
                            }
                            else {
                                Write-Host "$(if($true -eq $x64) {'x64'} else {'x86'}) Uninstaller unknown, trying the UninstallString from registry..."
                                $NativeUninstallString = Select-String "(\x22.*\x22) +(.*)" -inputobject $UninstallString
                                $Command = $NativeUninstallString.matches.groups[1].value
                                $Parameter = $NativeUninstallString.matches.groups[2].value
                                Start-Process $Command -ArgumentList $Parameter -Wait
                            }
                        }
                        catch {
                            Write-Warning "Could not read installer file: $_"
                            # Fallback to standard method
                            Write-Host "Failed to inspect installer, trying UninstallString directly..."
                            $NativeUninstallString = Select-String "(\x22.*\x22) +(.*)" -inputobject $UninstallString
                            $Command = $NativeUninstallString.matches.groups[1].value
                            $Parameter = $NativeUninstallString.matches.groups[2].value
                            Start-Process $Command -ArgumentList $Parameter -Wait
                        }
                    }
                }
            }
            $app_was_found = $true
            if (!$AllVersions) {
                break
            }
        }
    }
    return $app_was_found;
}

function Remove-ModsLnk ($Lnk) {
    $removedCount = 0
    foreach ($link in $Lnk) {
        $linkPath = "${env:Public}\Desktop\$link.lnk"
        if (Test-Path $linkPath) {
            Remove-Item -Path $linkPath -Force -ErrorAction SilentlyContinue | Out-Null
            $removedCount++
        }
    }
    Return $removedCount
}

function Add-ModsReg ($AddKey, $AddValue, $AddTypeData, $AddType) {
    if ($AddKey -like "HKEY_LOCAL_MACHINE*") {
        $AddKey = $AddKey.replace("HKEY_LOCAL_MACHINE", "HKLM:")
    }
    if (!(Test-Path "$AddKey")) {
        New-Item $AddKey -Force -ErrorAction SilentlyContinue | Out-Null
    }
    New-ItemProperty $AddKey -Name $AddValue -Value $AddTypeData -PropertyType $AddType -Force | Out-Null
    Return
}

function Remove-ModsReg ($DelKey, $DelValue) {
    if ($DelKey -like "HKEY_LOCAL_MACHINE*") {
        $DelKey = $DelKey.replace("HKEY_LOCAL_MACHINE", "HKLM:")
    }
    if (Test-Path "$DelKey") {
        if (!$DelValue) {
            Remove-Item $DelKey -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
        }
        else {
            Remove-ItemProperty $DelKey -Name $DelValue -Force -ErrorAction SilentlyContinue | Out-Null
        }
    }
    Return
}

function Remove-ModsFile ($DelFile) {
    foreach ($file in $DelFile) {
        if (Test-Path "$file") {
            Remove-Item -Path $file -Force -Recurse -ErrorAction SilentlyContinue | Out-Null
        }
    }
    Return
}

function Rename-ModsFile ($RenFile, $NewName) {
    if (Test-Path "$RenFile") {
        Rename-Item -Path $RenFile -NewName $NewName -Force -ErrorAction SilentlyContinue | Out-Null
    }
    Return
}

function Copy-ModsFile ($CopyFile, $CopyTo) {
    if (Test-Path "$CopyFile") {
        Copy-Item -Path $CopyFile -Destination $CopyTo -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
    }
    Return
}

function Edit-ModsFile ($File, $FindText, $ReplaceText) {
    if (Test-Path "$File") {
        ((Get-Content -path $File -Raw) -replace "$FindText", "$ReplaceText") | Set-Content -Path $File -Force -ErrorAction SilentlyContinue | Out-Null
    }
    Return
}

function Grant-ModsPath ($GrantPath) {
    foreach ($path in $GrantPath) {
        if (Test-Path "$path") {
            $NewAcl = Get-Acl -Path $path
            $identity = New-Object System.Security.Principal.SecurityIdentifier S-1-5-11
            if ((Get-Item $path) -is [System.IO.DirectoryInfo]) {
                $fileSystemAccessRuleArgumentList = $identity, 'Modify', 'ContainerInherit, ObjectInherit', 'None', 'Allow'
            }
            else {
                $fileSystemAccessRuleArgumentList = $identity, 'Modify', 'Allow'
            }
            $fileSystemAccessRule = New-Object -TypeName System.Security.AccessControl.FileSystemAccessRule -ArgumentList $fileSystemAccessRuleArgumentList
            $NewAcl.SetAccessRule($fileSystemAccessRule)

            # Grant delete permissions to subfolders and files
            $inheritanceFlag = [System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [System.Security.AccessControl.InheritanceFlags]::ObjectInherit
            $propagationFlag = [System.Security.AccessControl.PropagationFlags]::InheritOnly
            $deleteAccessRule = New-Object -TypeName System.Security.AccessControl.FileSystemAccessRule -ArgumentList $identity, 'Delete', $inheritanceFlag, $propagationFlag, 'Allow'
            $NewAcl.AddAccessRule($deleteAccessRule)


            Set-Acl -Path $path -AclObject $NewAcl
        }
    }
    Return
}

function Show-WAUPostponeDialog {
    <#
    .SYNOPSIS
        Shows an interactive dialog allowing users to postpone WAU updates.
    
    .DESCRIPTION
        Universal function that works in both SYSTEM (Session 0) and USER contexts.
        Displays a modern WPF dialog with three options:
        - Postpone 30 minutes
        - Postpone 60 minutes  
        - Update Now
        
        When running as SYSTEM in Session 0, uses ServiceUI.exe to display the GUI
        in the active user session. Falls back to direct display in user context.
        
        Uses a dark theme (#1E1E1E background) with blue accent (#3A9DFF) matching
        the PreNotify style from Winget-AutoUpdate.
    
    .OUTPUTS
        System.Double or $null
        Returns 0.5 for 30 minutes, 1.0 for 60 minutes, or $null for immediate update.
    
    .EXAMPLE
        $postponeDuration = Show-WAUPostponeDialog
        if ($null -ne $postponeDuration) {
            Write-Host "User postponed for $postponeDuration hours"
        } else {
            Write-Host "User chose to update immediately"
        }
    
    .NOTES
        Requires: PresentationCore, PresentationFramework, WindowsBase assemblies
        Optional: ServiceUI.exe for SYSTEM context display
        Created: 2024 for Winget-AutoUpdate interactive postpone feature
    #>
    
    # Detect execution context
    $isSystem = [System.Security.Principal.WindowsIdentity]::GetCurrent().IsSystem
    $sessionID = [System.Diagnostics.Process]::GetCurrentProcess().SessionId
    
    # Define XAML UI (shared between ServiceUI and direct display)
    $xamlTemplate = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Application Update Scheduled"
        Height="320" Width="540"
        WindowStartupLocation="CenterScreen"
        ResizeMode="NoResize"
        WindowStyle="SingleBorderWindow"
        Background="#1E1E1E"
        Foreground="#FFFFFF"
        FontFamily="Segoe UI"
        Icon="$PSScriptRoot\..\icons\update.ico"
        Topmost="True">
    <Grid Margin="20">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <StackPanel Orientation="Horizontal" Grid.Row="0" Margin="0,0,0,10">
            <Border Width="56" Height="56" CornerRadius="28" Margin="0,0,10,0" ClipToBounds="True" VerticalAlignment="Center">
                <Image Source="$PSScriptRoot\..\icons\updatelogo.png"/>
            </Border>
            <StackPanel VerticalAlignment="Center">
                <TextBlock Text="Application Update Scheduled"
                           FontSize="18"
                           FontWeight="Bold"
                           Foreground="#FFFFFF"/>
                <TextBlock Text="Winget-AutoUpdate will install updates shortly."
                           FontSize="12"
                           Foreground="#B0B0B0"
                           Margin="0,2,0,0"/>
            </StackPanel>
        </StackPanel>

        <Border Grid.Row="1" CornerRadius="8" Background="#FF2A2A2A" Padding="15">
            <StackPanel>
                <TextBlock Text="To ensure the security and up-to-date status of your applications, automatic updates are configured on this computer."
                           TextWrapping="Wrap"
                           FontSize="13"
                           Margin="0,0,0,10"/>
                <TextBlock Text="If you are currently busy with an important task, you can postpone the update. Otherwise, the update will be performed as scheduled."
                           TextWrapping="Wrap"
                           FontSize="13"
                           Foreground="#CCCCCC"/>
            </StackPanel>
        </Border>

        <StackPanel Grid.Row="2" Orientation="Horizontal" HorizontalAlignment="Center" Margin="0,15,0,0">
            <Button x:Name="BtnSnooze30"
                    Content="Postpone 30 min"
                    Margin="0,0,10,0"
                    Padding="14,6"
                    Background="#3B68FC"
                    Foreground="White"
                    BorderBrush="#3B68FC"
                    BorderThickness="1"
                    Cursor="Hand"/>

            <Button x:Name="BtnSnooze60"
                    Content="Postpone 60 min"
                    Margin="0,0,10,0"
                    Padding="14,6"
                    Background="#3B68FC"
                    Foreground="White"
                    BorderBrush="#3B68FC"
                    BorderThickness="1"
                    Cursor="Hand"/>

            <Button x:Name="BtnUpdateNow"
                    Content="Update Now"
                    Padding="16,6"
                    Background="#3B68FC"
                    Foreground="White"
                    BorderBrush="#3B68FC"
                    BorderThickness="1"
                    FontWeight="SemiBold"
                    Cursor="Hand"/>
        </StackPanel>
    </Grid>
</Window>
"@
    
    # Branch 1: SYSTEM context in Session 0 - use ServiceUI if available
    if ($isSystem -and $sessionID -eq 0) {
        $ServiceUIexe = Join-Path $PSScriptRoot "..\ServiceUI.exe"
        
        if (Test-Path $ServiceUIexe) {
            # Create temporary PowerShell script for ServiceUI execution
            $tempScript = "$env:TEMP\WAU_PostponeDialog_$(Get-Random).ps1"
            
            # Script that will run in user session via ServiceUI
            $serviceUIScript = @"
Add-Type -AssemblyName PresentationCore,PresentationFramework,WindowsBase

`$xaml = @'
$xamlTemplate
'@

`$reader = New-Object System.Xml.XmlNodeReader ([xml]`$xaml)
`$window = [Windows.Markup.XamlReader]::Load(`$reader)

`$btnUpdateNow = `$window.FindName("BtnUpdateNow")
`$btnSnooze30  = `$window.FindName("BtnSnooze30")
`$btnSnooze60  = `$window.FindName("BtnSnooze60")

`$script:UserChoice = 0

`$btnUpdateNow.Add_Click({
    `$script:UserChoice = 0
    `$window.Close()
})

`$btnSnooze30.Add_Click({
    `$script:UserChoice = 5
    `$window.Close()
})

`$btnSnooze60.Add_Click({
    `$script:UserChoice = 10
    `$window.Close()
})

`$null = `$window.ShowDialog()
Exit `$script:UserChoice
"@
            
            $serviceUIScript | Out-File -FilePath $tempScript -Encoding UTF8 -Force
            
            try {
                # Launch GUI through ServiceUI in active user session
                $process = Start-Process -FilePath $ServiceUIexe `
                    -ArgumentList "-process:explorer.exe powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$tempScript`"" `
                    -Wait -PassThru -NoNewWindow
                
                $exitCode = $process.ExitCode
                
                # Map exit codes to postpone durations
                switch ($exitCode) {
                    5  { return 0.5 }  # 30 minutes
                    10 { return 1.0 }  # 60 minutes
                    default { return $null }  # Update now or error
                }
            }
            finally {
                Remove-Item $tempScript -Force -ErrorAction SilentlyContinue
            }
        }
        else {
            # No ServiceUI available - cannot display GUI from Session 0
            # Return null to proceed with update
            return $null
        }
    }
    
    # Branch 2: User context or non-Session-0 - show GUI directly
    else {
        Add-Type -AssemblyName PresentationCore,PresentationFramework,WindowsBase
        
        $reader = New-Object System.Xml.XmlNodeReader ([xml]$xamlTemplate)
        $window = [Windows.Markup.XamlReader]::Load($reader)
        
        $btnUpdateNow = $window.FindName("BtnUpdateNow")
        $btnSnooze30  = $window.FindName("BtnSnooze30")
        $btnSnooze60  = $window.FindName("BtnSnooze60")
        
        $script:UserChoice = $null
        
        $btnUpdateNow.Add_Click({
            $script:UserChoice = $null
            $window.Close()
        })
        
        $btnSnooze30.Add_Click({
            $script:UserChoice = 0.5
            $window.Close()
        })
        
        $btnSnooze60.Add_Click({
            $script:UserChoice = 1.0
            $window.Close()
        })
        
        $null = $window.ShowDialog()
        
        return $script:UserChoice
    }
}
