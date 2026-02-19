Add-Type -AssemblyName PresentationCore,PresentationFramework,WindowsBase

$xamlTemplate = @'
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
        <SolidColorBrush x:Key="Danger" Color="#FF5D5D"/>
        <SolidColorBrush x:Key="Warning" Color="#F6C343"/>

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

                    <TextBlock Text="WAU" FontSize="13" FontWeight="SemiBold" VerticalAlignment="Center" Margin="0,0,10,0" Foreground="{StaticResource SubText}"/>
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
                            <TextBlock Text="Automatic updates are configured to keep your applications secure and up to date." Foreground="{StaticResource Text}" FontWeight="SemiBold" TextWrapping="Wrap"/>
                        </DockPanel>

                        <TextBlock Margin="0,10,0,0" Text="If you are currently busy, you can postpone the update. Otherwise, it will be performed as scheduled." Foreground="{StaticResource SubText}" TextWrapping="Wrap"/>

                        <TextBlock Margin="0,10,0,0" Text="The computer may restart automatically without warning to complete the update process. Please save your work to avoid data loss." Foreground="{StaticResource Danger}" TextWrapping="Wrap"/>
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
'@

$alertIconPath = Join-Path $PSScriptRoot "..\..\icons\alert.png"
if (-not (Test-Path $alertIconPath)) {
    $alertIconPath = Join-Path $PSScriptRoot "alert.png"
}
$warnIconPath = Join-Path $PSScriptRoot "..\..\icons\crisis.png"
if (-not (Test-Path $warnIconPath)) {
    $warnIconPath = Join-Path $PSScriptRoot "..\..\icons\alert.png"
}
if (-not (Test-Path $warnIconPath)) {
    $warnIconPath = Join-Path $PSScriptRoot "crisis.png"
}
$xamlTemplate = $xamlTemplate.Replace("__ALERT_ICON_PATH__", $alertIconPath)
$xamlTemplate = $xamlTemplate.Replace("__WARN_ICON_PATH__", $warnIconPath)
[xml]$xaml = $xamlTemplate

$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)

$btnClose = $window.FindName('BtnClose')
$btnSnooze30 = $window.FindName('BtnSnooze30')
$btnSnooze60 = $window.FindName('BtnSnooze60')
$btnUpdateNow = $window.FindName('BtnUpdateNow')
$titleBar = $window.FindName('TitleBar')

$script:Result = 'Closed'

$btnClose.Add_Click({
    $script:Result = 'Closed'
    $window.Close()
})

$btnSnooze30.Add_Click({
    $script:Result = 'Postpone30'
    $window.Close()
})

$btnSnooze60.Add_Click({
    $script:Result = 'Postpone60'
    $window.Close()
})

$btnUpdateNow.Add_Click({
    $script:Result = 'UpdateNow'
    $window.Close()
})

$titleBar.Add_MouseLeftButtonDown({
    $window.DragMove()
})

$null = $window.ShowDialog()
Write-Host "Dialog result: $script:Result"
