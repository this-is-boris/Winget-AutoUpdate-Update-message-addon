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

function Get-WAUFallbackDialogTemplate {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TemplateFile
    )

    switch ($TemplateFile) {
        "PostponeDialog.xaml" {
            return @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Winget-AutoUpdate"
        Width="720" Height="360"
        WindowStartupLocation="CenterScreen"
        WindowStyle="None"
        ResizeMode="NoResize"
        Background="Transparent"
        AllowsTransparency="True"
        Topmost="True">

    <Window.Resources>
        <SolidColorBrush x:Key="Bg" Color="#111317"/>
        <SolidColorBrush x:Key="Surface" Color="#1A1E26"/>
        <SolidColorBrush x:Key="Text" Color="#E7EAF0"/>
        <SolidColorBrush x:Key="SubText" Color="#B6BECE"/>
        <SolidColorBrush x:Key="Accent" Color="#2B6DF3"/>
        <SolidColorBrush x:Key="Danger" Color="#FF8A8A"/>

        <DropShadowEffect x:Key="Shadow" BlurRadius="28" ShadowDepth="0" Opacity="0.45"/>

        <Style x:Key="PrimaryButton" TargetType="Button">
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="Background" Value="{StaticResource Accent}"/>
            <Setter Property="BorderBrush" Value="#00000000"/>
            <Setter Property="Padding" Value="18,10"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}" CornerRadius="10">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style x:Key="SecondaryButton" TargetType="Button" BasedOn="{StaticResource PrimaryButton}">
            <Setter Property="Background" Value="#2A3142"/>
            <Setter Property="Foreground" Value="{StaticResource Text}"/>
        </Style>
    </Window.Resources>

    <Border CornerRadius="18" Background="{StaticResource Bg}" Effect="{StaticResource Shadow}">
        <Grid>
            <Grid.RowDefinitions>
                <RowDefinition Height="52"/>
                <RowDefinition Height="*"/>
                <RowDefinition Height="82"/>
            </Grid.RowDefinitions>

            <Border x:Name="TitleBar" Grid.Row="0" Background="#0D0F14" CornerRadius="18,18,0,0">
                <Grid Margin="14,0">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="Auto"/>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>

                    <TextBlock Grid.Column="1" Text="Winget-AutoUpdate" Foreground="{StaticResource SubText}" VerticalAlignment="Center"/>

                    <Button x:Name="BtnClose" Grid.Column="2" Width="34" Height="26"
                            Background="#00000000" BorderBrush="#00000000"
                            Foreground="{StaticResource SubText}" Content="X" FontSize="14" FontWeight="SemiBold" Cursor="Hand"/>
                </Grid>
            </Border>

            <StackPanel Grid.Row="1" Margin="22,18,22,10" VerticalAlignment="Top">
                <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                    <Image Width="42" Height="42" Margin="0,0,12,0" Stretch="Uniform" Source="__ALERT_ICON_PATH__"/>
                    <TextBlock Text="Application Update Scheduled" Foreground="{StaticResource Text}" FontSize="26" FontWeight="Bold" VerticalAlignment="Center"/>
                </StackPanel>

                <TextBlock Margin="0,6,0,0" Text="Winget-AutoUpdate will install updates shortly." Foreground="{StaticResource SubText}" FontSize="13"/>

                <Border Margin="0,18,0,0" Background="{StaticResource Surface}" CornerRadius="14" Padding="16">
                    <StackPanel>
                        <DockPanel LastChildFill="True">
                            <Image Width="24" Height="24" Margin="0,0,10,0" Stretch="Uniform" Source="__WARN_ICON_PATH__"/>
                            <TextBlock Text="Automatic updates are configured to keep your applications secure and up to date."
                                       Foreground="{StaticResource Text}" FontWeight="SemiBold" TextWrapping="Wrap"/>
                        </DockPanel>

                        <TextBlock Margin="0,10,0,0"
                                   Text="If you are currently busy, you can postpone the update. Otherwise, it will be performed as scheduled."
                                   Foreground="{StaticResource SubText}" TextWrapping="Wrap"/>

                        <TextBlock Margin="0,10,0,0"
                                   Text="The computer may restart automatically without warning to complete the update process. Please save your work to avoid data loss."
                                   Foreground="{StaticResource Danger}" TextWrapping="Wrap"/>
                    </StackPanel>
                </Border>
            </StackPanel>

            <StackPanel Grid.Row="2" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,0,22,20">
                <Button x:Name="BtnSnooze30" Style="{StaticResource SecondaryButton}" Width="146" Height="44" Margin="0,0,10,0" Content="Postpone 30 min"/>
                <Button x:Name="BtnSnooze60" Style="{StaticResource SecondaryButton}" Width="146" Height="44" Margin="0,0,10,0" Content="Postpone 60 min"/>
                <Button x:Name="BtnUpdateNow" Style="{StaticResource PrimaryButton}" Width="136" Height="44" Content="Update Now"/>
            </StackPanel>
        </Grid>
    </Border>
</Window>
"@
        }
        "UpdateStartingNotification.xaml" {
            return @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Winget-AutoUpdate"
        Width="720" Height="280"
        WindowStartupLocation="CenterScreen"
        WindowStyle="None"
        ResizeMode="NoResize"
        Background="Transparent"
        AllowsTransparency="True"
        Topmost="True">

    <Window.Resources>
        <SolidColorBrush x:Key="Bg" Color="#111317"/>
        <SolidColorBrush x:Key="Surface" Color="#1A1E26"/>
        <SolidColorBrush x:Key="Text" Color="#E7EAF0"/>
        <SolidColorBrush x:Key="SubText" Color="#B6BECE"/>
        <SolidColorBrush x:Key="Danger" Color="#FF8A8A"/>

        <DropShadowEffect x:Key="Shadow" BlurRadius="28" ShadowDepth="0" Opacity="0.45"/>
    </Window.Resources>

    <Border CornerRadius="18" Background="{StaticResource Bg}" Effect="{StaticResource Shadow}">
        <Grid>
            <Grid.RowDefinitions>
                <RowDefinition Height="52"/>
                <RowDefinition Height="*"/>
            </Grid.RowDefinitions>

            <Border x:Name="TitleBar" Grid.Row="0" Background="#0D0F14" CornerRadius="18,18,0,0">
                <Grid Margin="14,0">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="Auto"/>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>

                    <TextBlock Grid.Column="1" Text="Winget-AutoUpdate" Foreground="{StaticResource SubText}" VerticalAlignment="Center"/>

                    <Button x:Name="BtnClose" Grid.Column="2" Width="34" Height="26"
                            Background="#00000000" BorderBrush="#00000000"
                            Foreground="{StaticResource SubText}" Content="X" FontSize="14" FontWeight="SemiBold" Cursor="Hand"/>
                </Grid>
            </Border>

            <StackPanel Grid.Row="1" Margin="22,18,22,18" VerticalAlignment="Top">
                <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                    <Image Width="38" Height="38" Margin="0,0,12,0" Stretch="Uniform" Source="__ALERT_ICON_PATH__"/>
                    <TextBlock Text="Updates Starting" Foreground="{StaticResource Text}" FontSize="24" FontWeight="Bold" VerticalAlignment="Center"/>
                </StackPanel>

                <Border Margin="0,14,0,0" Background="{StaticResource Surface}" CornerRadius="14" Padding="16">
                    <StackPanel>
                        <DockPanel LastChildFill="True">
                            <Image Width="24" Height="24" Margin="0,0,10,0" Stretch="Uniform" Source="__WARN_ICON_PATH__"/>
                            <TextBlock Text="Postpone time has ended. Updates are now starting."
                                       Foreground="{StaticResource Text}" FontWeight="SemiBold" TextWrapping="Wrap"/>
                        </DockPanel>

                        <TextBlock Margin="0,10,0,0"
                                   Text="Please save all open documents now. The computer may restart automatically to complete updates."
                                   Foreground="{StaticResource Danger}" TextWrapping="Wrap"/>

                        <TextBlock Margin="0,10,0,0"
                                   Text="This window will close automatically in 1 minute."
                                   Foreground="{StaticResource SubText}" TextWrapping="Wrap"/>
                    </StackPanel>
                </Border>
            </StackPanel>
        </Grid>
    </Border>
</Window>
"@
        }
        default {
            return $null
        }
    }
}

function Get-WAUDialogTemplate {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TemplateFile,

        [Parameter(Mandatory = $false)]
        [hashtable]$Replacements
    )

    $templatePath = Join-Path $PSScriptRoot "dialogs\$TemplateFile"
    $xamlTemplate = $null

    if (Test-Path $templatePath) {
        $xamlTemplate = Get-Content -Path $templatePath -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
    }

    if (-not $xamlTemplate) {
        $xamlTemplate = Get-WAUFallbackDialogTemplate -TemplateFile $TemplateFile
        if (-not $xamlTemplate) {
            return $null
        }
    }

    if ($Replacements) {
        foreach ($key in $Replacements.Keys) {
            $xamlTemplate = $xamlTemplate.Replace([string]$key, [string]$Replacements[$key])
        }
    }

    return $xamlTemplate
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
    
    $legacyIconPath = Join-Path $PSScriptRoot "..\icons\update.ico"
    $alertIconPath = Join-Path $PSScriptRoot "..\icons\alert.png"
    $warnIconPath = Join-Path $PSScriptRoot "..\icons\crisis.png"
    if (-not (Test-Path $warnIconPath)) {
        $warnIconPath = $alertIconPath
    }

    $xamlTemplate = Get-WAUDialogTemplate -TemplateFile "PostponeDialog.xaml" -Replacements @{
        "__ALERT_ICON_PATH__" = $alertIconPath
        "__WARN_ICON_PATH__" = $warnIconPath
        "__ICON_PATH__" = $legacyIconPath
    }
    if (-not $xamlTemplate) {
        return $null
    }
    
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
`$btnClose     = `$window.FindName("BtnClose")
`$titleBar     = `$window.FindName("TitleBar")

`$script:UserChoice = 0

`$btnUpdateNow.Add_Click({
    `$script:UserChoice = 0
    `$window.Close()
})

if (`$btnClose) {
    `$btnClose.Add_Click({
        `$script:UserChoice = 0
        `$window.Close()
    })
}

if (`$titleBar) {
    `$titleBar.Add_MouseLeftButtonDown({
        try { `$window.DragMove() } catch {}
    })
}

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
        $btnClose     = $window.FindName("BtnClose")
        $titleBar     = $window.FindName("TitleBar")
        
        $script:UserChoice = $null
        
        $btnUpdateNow.Add_Click({
            $script:UserChoice = $null
            $window.Close()
        })

        if ($btnClose) {
            $btnClose.Add_Click({
                $script:UserChoice = $null
                $window.Close()
            })
        }

        if ($titleBar) {
            $titleBar.Add_MouseLeftButtonDown({
                try { $window.DragMove() } catch {}
            })
        }
        
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

function Show-WAUUpdateStartingNotification {
    <#
    .SYNOPSIS
        Shows an informational dialog that updates are starting.

    .PARAMETER TimeoutSeconds
        Number of seconds before the window closes automatically. Default: 60.
    #>
    param(
        [Parameter(Mandatory = $false)]
        [int]$TimeoutSeconds = 60
    )

    if ($TimeoutSeconds -lt 1) {
        $TimeoutSeconds = 60
    }

    $isSystem = [System.Security.Principal.WindowsIdentity]::GetCurrent().IsSystem
    $sessionID = [System.Diagnostics.Process]::GetCurrentProcess().SessionId


    $alertIconPath = Join-Path $PSScriptRoot "..\icons\alert.png"
    $warnIconPath = Join-Path $PSScriptRoot "..\icons\crisis.png"
    if (-not (Test-Path $warnIconPath)) {
        $warnIconPath = $alertIconPath
    }

    $xamlTemplate = Get-WAUDialogTemplate -TemplateFile "UpdateStartingNotification.xaml" -Replacements @{

        "__ALERT_ICON_PATH__" = $alertIconPath
        "__WARN_ICON_PATH__" = $warnIconPath
    }
    if (-not $xamlTemplate) {
        return
    }

    if ($isSystem -and $sessionID -eq 0) {
        $ServiceUIexe = Join-Path $PSScriptRoot "..\ServiceUI.exe"

        if (Test-Path $ServiceUIexe) {
            $tempScript = "$env:TEMP\WAU_UpdateStartingNotification_$(Get-Random).ps1"

            $serviceUIScript = @"
Add-Type -AssemblyName PresentationCore,PresentationFramework,WindowsBase

`$xaml = @'
$xamlTemplate
'@

`$reader = New-Object System.Xml.XmlNodeReader ([xml]`$xaml)
`$window = [Windows.Markup.XamlReader]::Load(`$reader)
`$btnClose = `$window.FindName("BtnClose")
`$titleBar = `$window.FindName("TitleBar")

if (`$btnClose) {
    `$btnClose.Add_Click({
        `$window.Close()
    })
}

if (`$titleBar) {
    `$titleBar.Add_MouseLeftButtonDown({
        try { `$window.DragMove() } catch {}
    })
}

`$timer = New-Object System.Windows.Threading.DispatcherTimer
`$timer.Interval = [TimeSpan]::FromSeconds($TimeoutSeconds)
`$timer.Add_Tick({
    `$timer.Stop()
    `$window.Close()
})
`$timer.Start()

`$null = `$window.ShowDialog()
"@

            $serviceUIScript | Out-File -FilePath $tempScript -Encoding UTF8 -Force

            try {
                Start-Process -FilePath $ServiceUIexe `
                    -ArgumentList "-process:explorer.exe powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$tempScript`"" `
                    -Wait -NoNewWindow | Out-Null
            }
            finally {
                Remove-Item $tempScript -Force -ErrorAction SilentlyContinue
            }
        }
    }
    else {
        Add-Type -AssemblyName PresentationCore,PresentationFramework,WindowsBase

        $reader = New-Object System.Xml.XmlNodeReader ([xml]$xamlTemplate)
        $window = [Windows.Markup.XamlReader]::Load($reader)
        $btnClose = $window.FindName("BtnClose")
        $titleBar = $window.FindName("TitleBar")

        if ($btnClose) {
            $btnClose.Add_Click({
                $window.Close()
            })
        }

        if ($titleBar) {
            $titleBar.Add_MouseLeftButtonDown({
                try { $window.DragMove() } catch {}
            })
        }

        $timer = New-Object System.Windows.Threading.DispatcherTimer
        $timer.Interval = [TimeSpan]::FromSeconds($TimeoutSeconds)
        $timer.Add_Tick({
            $timer.Stop()
            $window.Close()
        })
        $timer.Start()

        $null = $window.ShowDialog()
    }

    Return
}
