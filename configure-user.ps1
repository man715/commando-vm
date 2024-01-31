$ErrorActionPreference = 'Continue'
$global:VerbosePreference = "SilentlyContinue"
Import-Module vm.common -Force -DisableNameChecking

try {
    # Gather packages to install
    $installedPackages = (VM-Get-InstalledPackages).Name
    $configPath = Join-Path ${Env:VM_COMMON_DIR} "packages.xml" -Resolve
    $configXml = [xml](Get-Content $configPath)

    ## Configure taskbar with custom Start Layout if it exists.
    $customLayout = Join-Path ${Env:VM_COMMON_DIR} "CustomStartLayout.xml"
    if (Test-Path $customLayout) {
        # Create an Admin Command Prompt shortcut and it to pin to taskbar (analogous to how the Windows Dev VM does this).
        $toolName = 'Admin Command Prompt'

        $executablePath = Join-Path ${Env:SystemRoot} 'system32\cmd.exe'
        $shortcutDir = ${Env:RAW_TOOLS_DIR}
        $shortcut = Join-Path $shortcutDir "$toolName.lnk"
        $target = "$executablePath"

        Install-ChocolateyShortcut -shortcutFilePath $shortcut -targetPath $target -RunAsAdmin
        VM-Assert-Path $shortcut

        Import-StartLayout -LayoutPath $customLayout -MountPath "C:\"
        Stop-Process -Name explorer -Force  # This restarts the explorer process so that the new taskbar is displayed.
    } else {
        VM-Write-Log "WARN" "CustomStartLayout.xml missing. No items will be pinned to the taskbar."
    }

    # Set Profile/Version specific configurations
    VM-Write-Log "INFO" "Beginning Windows OS VM profile configuration changes"
    $configPath = Join-Path $Env:VM_COMMON_DIR "config.xml" -Resolve
    VM-Apply-Configurations $configPath

    # Configure PowerShell and cmd prompts
    VM-Configure-Prompts

    # Configure PowerShell Logging
    VM-Configure-PS-Logging

    # Copy Desktop\Tools folder
    $userToolsDirectory = gci C:\Users | ? {$_.Name -ne 'Public' -and $_.Name -ne 'Administrator'} | ForEach-Object {Test-Path $_\Desktop\Tools} | Select-Object -First
    Copy-Item -Force $userToolsDirectory $env:USERPROFILE\Desktop

    # Refresh the desktop
    VM-Refresh-Desktop

    # Let users know installation is complete by setting lock screen & wallpaper background, playing win sound, and display message box

    # Set lock screen image
    $lockScreenImage = "${Env:VM_COMMON_DIR}\lockscreen.png"
    if ((Test-Path $lockScreenImage)) {
        New-Item "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\PersonalizationCSP" -Force | Out-Null
        New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\PersonalizationCSP" -Name LockScreenImagePath -PropertyType String -Value $lockScreenImage -Force | Out-Null
        New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\PersonalizationCSP" -Name LockScreenImageStatus -PropertyType DWord -Value 1 -Force | Out-Null
    }

    # Set wallpaper
    Set-ItemProperty 'HKCU:\Control Panel\Colors' -Name Background -Value "0 0 0" -Force | Out-Null
    $backgroundImage = "${Env:VM_COMMON_DIR}\background.png"
    if ((Test-Path $backgroundImage)) {
        # WallpaperStyle - Center: 0, Stretch: 2, Fit:6, Fill: 10, Span: 22
        Add-Type -AssemblyName System.Drawing
        $img = [System.Drawing.Image]::FromFile($backgroundImage);
        $wallpaperStyle = if ($img.Width/$img.Height -ge 16/9) { 6 } else { 0 }
        New-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name WallpaperStyle -PropertyType String -Value $wallpaperStyle -Force | Out-Null
        New-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name TileWallpaper -PropertyType String -Value 0 -Force | Out-Null
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public class VMBackground
{
    [DllImport("User32.dll",CharSet=CharSet.Unicode)]
    public static extern int SystemParametersInfo (Int32 uAction, Int32 uParam, String lpvParam, Int32 fuWinIni);
    [DllImport("User32.dll",CharSet=CharSet.Unicode)]
    public static extern bool SetSysColors(int cElements, int[] lpaElements, int[] lpaRgbValues);
}
"@
        [VMBackground]::SystemParametersInfo(20, 0, $backgroundImage, 3)
        [VMBackground]::SetSysColors(1, @(1), @(0x000000))
    }

    # Play sound
    try {
        $playWav = New-Object System.Media.SoundPlayer
        $playWav.SoundLocation = 'https://www.winhistory.de/more/winstart/down/owin31.wav'
        $playWav.PlaySync()
    } catch {
        VM-Write-Log-Exception $_
    }

    # Show dialog that install has been complete
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    # Create form
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "$Env:VMname Installation Complete"
    $form.TopMost = $true
    $form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $iconPath = Join-Path $Env:VM_COMMON_DIR "vm.ico"
    if (Test-Path $iconPath) {
        $form.Icon = New-Object System.Drawing.Icon($iconPath)
    }
    # Create a FlowLayoutPanel
    $flowLayout = New-Object System.Windows.Forms.FlowLayoutPanel
    $flowLayout.FlowDirection = [System.Windows.Forms.FlowDirection]::TopDown
    $flowLayout.Dock = [System.Windows.Forms.DockStyle]::Fill
    $flowLayout.AutoSize = $true
    # Create label
    $label = New-Object System.Windows.Forms.Label
    $label.Text = @"
Configuration Complete!

Thank you!
"@
    $label.AutoSize = $true
    $label.Font = New-Object System.Drawing.Font("Microsoft Sans Serif", 10, [System.Drawing.FontStyle]::Regular)
    # Create button
    $button = New-Object System.Windows.Forms.Button
    $button.Text = "Finish"
    $button.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $button.AutoSize = $true
    $button.Font = New-Object System.Drawing.Font("Microsoft Sans Serif", 10, [System.Drawing.FontStyle]::Regular)
    $button.Anchor = [System.Windows.Forms.AnchorStyles]::None
    # Add controls to the FlowLayoutPanel
    $flowLayout.Controls.Add($label)
    $flowLayout.Controls.Add($button)
    # Add the FlowLayoutPanel to the form
    $form.Controls.Add($flowLayout)
    # Auto-size form to fit content
    $form.AutoSize = $true
    $form.AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink
    # Show dialog
    $form.ShowDialog()

} catch {
    VM-Write-Log-Exception $_
}

