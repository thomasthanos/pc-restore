# Make Your Life Easier – Modern WPF (2025, clean titlebar + modern switches + toast + scrollbars + rounded)
# - PowerShell 5 compatible
# - Saves/loads settings at %APPDATA%\Kolokithes A.E\settings.json
# - Greek/English only
# - Solid Light/Dark theming
# - Minimal modern ScrollBars (auto dark/light)
# - Stable rounded outline via RectangleGeometry clip
# - Titlebar: custom Close/Minimize (hover/position fixed), icon added next to title, app icon for taskbar
# - Profile: modern switches for Notifications/Sound/Theme + "Test notification"
# - Toast banner (bottom-right) with optional sound (animated progress, theme-aware)
# - Downloads hacker.ico from Dropbox if not present
# - InstallBtn opens **Install page in-app** (no dialog)

Add-Type -AssemblyName PresentationCore,PresentationFramework,WindowsBase,System.Windows.Forms

# Ensure System.Net.Http is loaded for HttpClient usage (PowerShell 5 compatibility)
try {
    Add-Type -AssemblyName System.Net.Http -ErrorAction Stop
} catch {
    # If the assembly cannot be loaded, the download functions will use fallback
    Write-Verbose "System.Net.Http assembly could not be loaded: $($_.Exception.Message)"
}

# -------------------- P/Invoke for audio playback with volume control --------------------
Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;

public class Audio {
    [DllImport("winmm.dll")]
    public static extern uint mciSendString(string lpstrCommand, StringBuilder lpstrReturnString, int uReturnLength, IntPtr hwndCallback);

    public static void PlaySound(string filePath) {
        if (string.IsNullOrEmpty(filePath) || !System.IO.File.Exists(filePath)) return;
        mciSendString(string.Format("open \"{0}\" type waveaudio alias MakeYourLifeEasierSound", filePath), null, 0, IntPtr.Zero);
        mciSendString("play MakeYourLifeEasierSound", null, 0, IntPtr.Zero);
    }

    public static void StopSound() {
        mciSendString("stop MakeYourLifeEasierSound", null, 0, IntPtr.Zero);
        mciSendString("close MakeYourLifeEasierSound", null, 0, IntPtr.Zero);
    }
}
"@

# -------------------- Paths & Settings helpers --------------------
$AppDir        = Join-Path $env:APPDATA 'Kolokithes A.E'
$SettingsPath  = Join-Path $AppDir 'settings.json'
$SoundFilePath = Join-Path $AppDir 'click.wav'
$IconFilePath  = Join-Path $AppDir 'hacker.ico'
if (-not (Test-Path $AppDir)) { New-Item -ItemType Directory -Force -Path $AppDir | Out-Null }

<#
Utility functions for downloading files and working with the Kolokithes A.E data directory.
These helpers ensure that all downloads (executables, images, etc.) are stored under
%APPDATA%\Kolokithes A.E and that this directory is created if it does not exist.
-- Get-KolokithesDataRoot: returns the path to the application data root, creating
   the folder if necessary.
-- Get-DownloadPath: given a filename, returns its full path inside the data root.
-- Invoke-FileDownload: downloads a file from a URL to a destination path, using
   Invoke-WebRequest and falling back to WebClient when necessary.
-- Initialize-ActivationImages: downloads the Activate/AutoLogin images from the
   remote repository if they are missing, then applies them to the corresponding
   image borders in the UI.  This should be called after the XAML is loaded.
#>
function Get-KolokithesDataRoot {
    $root = Join-Path $env:APPDATA 'Kolokithes A.E'
    if (-not (Test-Path $root)) {
        try { New-Item -ItemType Directory -Force -Path $root | Out-Null } catch {}
    }
    return $root
}

function Get-AppPaths {
    <#
    Returns a dictionary of important asset paths under the application data root.  The
    application stores its assets in structured subdirectories of
    `%APPDATA%\Kolokithes A.E` so that users can easily locate and inspect them.
    The structure is as follows:

        %APPDATA%\Kolokithes A.E\assets\config\i18n.psd1
                                             \Set-Language_additions.ps1
                                      \images\activate.png
                                             \autologin.png
                                      \ui    \App.xaml

    The helper ensures that each of these directories exists before returning the
    computed paths.  Call this whenever you need to retrieve or create the
    asset tree.
    #>
    $root       = Get-KolokithesDataRoot
    $assetsDir  = Join-Path $root 'assets'
    $imagesDir  = Join-Path $assetsDir 'images'
    $configDir  = Join-Path $assetsDir 'config'
    $uiDir      = Join-Path $assetsDir 'ui'
    foreach ($d in @($assetsDir, $imagesDir, $configDir, $uiDir)) {
        if (-not (Test-Path $d)) {
            try { New-Item -ItemType Directory -Force -Path $d | Out-Null } catch {}
        }
    }
    return [ordered]@{
        Root             = $root
        ImagesDir        = $imagesDir
        ConfigDir        = $configDir
        UiDir            = $uiDir
        I18nPsd1         = Join-Path $configDir 'i18n.psd1'
        SetLangAdditions = Join-Path $configDir 'Set-Language_additions.ps1'
        AppXaml          = Join-Path $uiDir   'App.xaml'
        ActivatePng      = Join-Path $imagesDir 'activate.png'
        AutoLoginPng     = Join-Path $imagesDir 'autologin.png'
    }
}

function Initialize-AppAssets {
    <#
    Ensures that all core application assets exist in the application data
    directory.  If any of the required files are missing or empty (length
    zero), they are downloaded from the upstream repository.  The function
    returns the same dictionary as Get-AppPaths so callers can retrieve the
    absolute paths immediately after initialization.  Use the -Force switch to
    force re-download of the assets even if they already exist.
    #>
    param([switch]$Force)
    $p = Get-AppPaths
    $sources = @(
        @{ url = 'https://raw.githubusercontent.com/thomasthanos/pc-restore/refs/heads/main/i18n.psd1';                 dest = $p.I18nPsd1 },
        @{ url = 'https://raw.githubusercontent.com/thomasthanos/pc-restore/refs/heads/main/Set-Language_additions.ps1'; dest = $p.SetLangAdditions },
        @{ url = 'https://raw.githubusercontent.com/thomasthanos/pc-restore/refs/heads/main/App.xaml';                   dest = $p.AppXaml },
        @{ url = 'https://raw.githubusercontent.com/thomasthanos/pc-restore/main/images/activate.png';                   dest = $p.ActivatePng },
        @{ url = 'https://raw.githubusercontent.com/thomasthanos/pc-restore/main/images/autologin.png';                  dest = $p.AutoLoginPng }
    )
    foreach ($s in $sources) {
        $needsDownload = $Force -or -not (Test-Path $s.dest)
        if (-not $needsDownload -and (Test-Path $s.dest)) {
            try {
                $fileInfo = Get-Item $s.dest
                if ($fileInfo.Length -eq 0) { $needsDownload = $true }
            } catch {
                $needsDownload = $true
            }
        }
        if ($needsDownload) {
            try {
                Invoke-FileDownload -Uri $s.url -Destination $s.dest | Out-Null
            } catch {
                # Ignore download errors; the user might be offline
            }
        }
    }
    return $p
}
function Get-DownloadPath {
    param([Parameter(Mandatory)][string]$FileName)
    $root = Get-KolokithesDataRoot
    return Join-Path $root $FileName
}

function Invoke-FileDownload {
    param(
        [Parameter(Mandatory)][string]$Uri,
        [Parameter(Mandatory)][string]$Destination
    )
    # Ensure destination directory exists
    $destDir = Split-Path -Parent $Destination
    if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Force -Path $destDir | Out-Null }
    try {
        Invoke-WebRequest -Uri $Uri -OutFile $Destination -UseBasicParsing -ErrorAction Stop
    } catch {
        # Fallback to WebClient if Invoke-WebRequest fails (PowerShell 5 compatibility)
        try {
            $client = New-Object System.Net.WebClient
            $client.Headers['User-Agent'] = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'
            $client.DownloadFile($Uri, $Destination)
            $client.Dispose()
        } catch {
            throw $_
        }
    }
    return $Destination
}

function Initialize-ActivationImages {
    # Download and set the images for the AutoLogin and Activate cards if missing.
    # This runs after the XAML is loaded so we can find controls by name.
    if (-not $window) { return }
    $autoLoginBorder = $window.FindName('AutoLoginImageBorder')
    $activateBorder  = $window.FindName('ActivateImageBorder')
    # Determine image paths using the application asset tree
    $paths = Get-AppPaths
    $autoPath    = $paths.AutoLoginPng
    $activatePath = $paths.ActivatePng
    # Download missing images from GitHub into the assets directory
    if (-not (Test-Path $autoPath)) {
        try { Invoke-FileDownload -Uri 'https://raw.githubusercontent.com/thomasthanos/pc-restore/main/images/autologin.png' -Destination $autoPath | Out-Null } catch {}
    }
    if (-not (Test-Path $activatePath)) {
        try { Invoke-FileDownload -Uri 'https://raw.githubusercontent.com/thomasthanos/pc-restore/main/images/activate.png' -Destination $activatePath | Out-Null } catch {}
    }
    # Create brushes and set backgrounds if controls exist and images exist
    try {
        if ($autoLoginBorder -and (Test-Path $autoPath)) {
            $img1 = New-Object System.Windows.Media.Imaging.BitmapImage
            $img1.BeginInit(); $img1.UriSource = New-Object System.Uri($autoPath); $img1.DecodePixelWidth = 320; $img1.EndInit()
            $brush1 = New-Object System.Windows.Media.ImageBrush
            $brush1.ImageSource = $img1
            $brush1.Stretch = [System.Windows.Media.Stretch]::UniformToFill
            $autoLoginBorder.Background = $brush1
        }
        if ($activateBorder -and (Test-Path $activatePath)) {
            $img2 = New-Object System.Windows.Media.Imaging.BitmapImage
            $img2.BeginInit(); $img2.UriSource = New-Object System.Uri($activatePath); $img2.DecodePixelWidth = 320; $img2.EndInit()
            $brush2 = New-Object System.Windows.Media.ImageBrush
            $brush2.ImageSource = $img2
            $brush2.Stretch = [System.Windows.Media.Stretch]::UniformToFill
            $activateBorder.Background = $brush2
        }
    } catch {
        # ignore any image loading errors
    }
}

# -------------------- WebView2 cache paths --------------------
# To avoid downloading the WebView2 NuGet package on every run, cache
# the package and its extracted DLLs under the application data folder.
$WebView2LibDir   = Join-Path $AppDir 'WebView2Lib'
$WebView2PkgPath  = Join-Path $WebView2LibDir 'Microsoft.Web.WebView2.nupkg'
$WebView2PkgUnzip = Join-Path $WebView2LibDir 'pkg'

# -------------------- Download Icon if Missing --------------------
function Get-Icon {
    if (-not (Test-Path $IconFilePath)) {
        try {
            Invoke-WebRequest -Uri "https://www.dropbox.com/scl/fi/zt7tggv62s2np9h3l0ezh/hacker.ico?rlkey=07boesbyk3z54k941885pxbwf&st=vtd2yp50&dl=1" -OutFile $IconFilePath -UseBasicParsing
        } catch {
            Write-Host "Failed to download icon: $($_.Exception.Message)"
        }
    }
}
Get-Icon

# -------------------- WebView2 helper functions --------------------
#
# Test-WebView2Runtime: checks if the Microsoft Edge WebView2 runtime is
# installed by looking for its registry key. Returns $true if found,
# otherwise $false.
function Test-WebView2Runtime {
    # The runtime registers itself under this CLSID; check both 64- and 32-bit hives
    $key64 = 'HKLM:\SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}'
    $key32 = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}'
    # Evaluate each Test-Path separately to avoid accidental parameter name parsing (PSScriptAnalyzer rule)
    $exists64 = Test-Path -Path $key64
    $exists32 = Test-Path -Path $key32
    return ($exists64 -or $exists32)
}

# Import-WebView2Assemblies: downloads and unpacks the WebView2 NuGet package
# into the cached directory under $AppDir and loads the required DLLs into
# the current session. This runs only when needed.
function Import-WebView2Assemblies {
    # Ensure base directory exists
    if (-not (Test-Path $WebView2LibDir)) { New-Item -ItemType Directory -Force -Path $WebView2LibDir | Out-Null }
    # Download the package if missing
    if (-not (Test-Path $WebView2PkgPath)) {
        Invoke-WebRequest -Uri 'https://www.nuget.org/api/v2/package/Microsoft.Web.WebView2' -OutFile $WebView2PkgPath -UseBasicParsing
    }
    # Extract once
    if (-not (Test-Path $WebView2PkgUnzip)) {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::ExtractToDirectory($WebView2PkgPath, $WebView2PkgUnzip)
    }
    # Locate the Core and WinForms assemblies
    $coreDll = Get-ChildItem -Recurse -Path $WebView2PkgUnzip -Filter 'Microsoft.Web.WebView2.Core.dll' | Select-Object -First 1
    $winDll  = Get-ChildItem -Recurse -Path $WebView2PkgUnzip -Filter 'Microsoft.Web.WebView2.WinForms.dll' |
               Where-Object { $_.FullName -match 'lib\\net' } | Select-Object -First 1
    if (-not $coreDll -or -not $winDll) { throw 'Δεν βρέθηκαν οι WebView2 DLLs στο NuGet πακέτο.' }
    # Load the assemblies; Core must load before WinForms
    Add-Type -Path $coreDll.FullName
    Add-Type -Path $winDll.FullName
}

# Open-PasswordManagerWebView: opens a 1280x720 WinForms window with
# a WebView2 control navigated to the password manager website. The
# window is centered on screen and disables the default context menu
# and developer tools.
function Open-PasswordManagerWebView {
    if (-not (Test-WebView2Runtime)) {
        [System.Windows.MessageBox]::Show(
            'Λείπει το Microsoft Edge WebView2 Runtime. Εγκατάστησέ το και ξαναπροσπάθησε.',
            'WebView2',
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Warning
        ) | Out-Null
        return
    }

    Import-WebView2Assemblies
    Add-Type -AssemblyName System.Windows.Forms, System.Drawing

    # --- Minimize κύριο WPF window & θυμήσου προηγούμενη κατάσταση
    $prevState = $null
    if ($null -ne $script:window) {
        $prevState = $script:window.WindowState
        $script:window.WindowState = 'Minimized'
    }

    # --- WebView2 παράθυρο 1400x800, κέντρο
    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'Password Manager'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.MinimizeBox = $true
    $form.StartPosition = 'CenterScreen'
    $form.Size = New-Object System.Drawing.Size(1400, 800)

    # --- Κάν’ το TopMost για 2s
    $form.TopMost = $true
    $topTimer = New-Object System.Windows.Forms.Timer
    $topTimer.Interval = 2000
    $null = $form.Add_Shown({ param($s,$e) $topTimer.Start() })
    $null = $topTimer.Add_Tick({
        param($t,$e)
        try {
            $form.TopMost = $false
        } finally {
            $t.Stop(); $t.Dispose()
        }
    })

    # --- WebView2 control
    $wv = New-Object Microsoft.Web.WebView2.WinForms.WebView2
    $wv.Dock = [System.Windows.Forms.DockStyle]::Fill
    $null = $form.Controls.Add($wv)

    $userData = Join-Path $AppDir 'WebView2UserData'
    if (-not (Test-Path $userData)) { New-Item -ItemType Directory -Force -Path $userData | Out-Null }
    $props = New-Object Microsoft.Web.WebView2.WinForms.CoreWebView2CreationProperties
    $props.UserDataFolder = $userData
    $wv.CreationProperties = $props

    $null = $wv.add_CoreWebView2InitializationCompleted({
        param($src, $evt)
        if ($evt.IsSuccess) {
            $src.CoreWebView2.Settings.AreDefaultContextMenusEnabled = $false
            $src.CoreWebView2.Settings.AreDevToolsEnabled = $false
            $src.CoreWebView2.Navigate('https://password-manager-78x.pages.dev/')
        }
    })

    # --- Στο κλείσιμο: επανάφερέ μου το κύριο παράθυρο και φέρ’το μπροστά
    $null = $form.Add_FormClosed({
        param($s,$e)
        if ($null -ne $script:window) {
            $stateToSet = if ($prevState) { $prevState } else { 'Normal' }
            $script:window.Dispatcher.Invoke([action]{
                $script:window.WindowState = $stateToSet
                $script:window.Activate()
                $script:window.Topmost = $true
                $script:window.Topmost = $false
            })
        }
    })

    $null = $wv.EnsureCoreWebView2Async()
    [void]$form.ShowDialog()
}

# ----------------------------------------------
# Helpers to center a PowerShell console window
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class Win32 {
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);
  public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
  public static readonly IntPtr HWND_TOP = new IntPtr(0);
  public const uint SWP_NOSIZE = 0x0001;
  public const uint SWP_NOZORDER = 0x0004;
}
"@

function Start-CenteredPowerShellCommand {
  param([Parameter(Mandatory=$true)][string]$Command)
  Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
  $proc = $null
  try {
    $proc = Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-Command',$Command) -WindowStyle Normal -PassThru -ErrorAction Stop
  } catch {
    return $null
  }
  try {
    for($i=0; $i -lt 80 -and $proc.MainWindowHandle -eq 0; $i++){ Start-Sleep -Milliseconds 100; $proc.Refresh() }
    if($proc -and $proc.MainWindowHandle -ne 0){
      $wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
      [Win32.RECT]$r = New-Object Win32+RECT
      [void][Win32]::GetWindowRect($proc.MainWindowHandle, [ref]$r)
      $w = $r.Right - $r.Left
      $h = $r.Bottom - $r.Top
      $x = $wa.X + [int](($wa.Width  - $w)/2)
      $y = $wa.Y + [int](($wa.Height - $h)/2)
      [void][Win32]::SetWindowPos($proc.MainWindowHandle, [Win32]::HWND_TOP, $x, $y, 0, 0, [Win32]::SWP_NOSIZE -bor [Win32]::SWP_NOZORDER)
    }
  } catch { }
  return $proc
}


function Set-AppSettings {
    [CmdletBinding()]
    param(
        [string]$Resolution, [string]$Theme, [string]$UserName,
        [string]$Language, [bool]$Notifications, [bool]$Sound
    )
    $obj = [ordered]@{
        resolution    = $Resolution
        theme         = $Theme
        userName      = $UserName
        language      = $Language
        notifications = $Notifications
        sound         = $Sound
    }
    try {
        ($obj | ConvertTo-Json -Depth 4) | Set-Content -LiteralPath $SettingsPath -Encoding UTF8 -ErrorAction Stop
    } catch {
        [System.Windows.MessageBox]::Show("Σφάλμα αποθήκευσης: $($_.Exception.Message)", "Σφάλμα", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
    }
}

function Get-AppSettings {
    if (Test-Path $SettingsPath) {
        try { Get-Content -LiteralPath $SettingsPath -Encoding UTF8 | ConvertFrom-Json } catch { $null }
    }
}

# -------------------- Small UI helpers --------------------
function New-LinearGradientBrush {
    param(
        [string]$StartHex, [string]$EndHex,
        [ValidateSet('Horizontal','Vertical')] [string]$Direction = 'Horizontal'
    )
    $conv  = New-Object System.Windows.Media.BrushConverter
    $c1    = ($conv.ConvertFromString($StartHex)).Color
    $c2    = ($conv.ConvertFromString($EndHex)).Color
    $brush = New-Object System.Windows.Media.LinearGradientBrush
    if ($Direction -eq 'Horizontal') {
        $brush.StartPoint = New-Object System.Windows.Point 0,0
        $brush.EndPoint   = New-Object System.Windows.Point 1,0
    } else {
        $brush.StartPoint = New-Object System.Windows.Point 0,0
        $brush.EndPoint   = New-Object System.Windows.Point 0,1
    }
    $brush.GradientStops.Add( (New-Object System.Windows.Media.GradientStop -ArgumentList @($c1, 0.0)) )
    $brush.GradientStops.Add( (New-Object System.Windows.Media.GradientStop -ArgumentList @($c2, 1.0)) )
    return $brush
}

function Set-Brush([string]$key,[string]$hex){
    if ($null -eq $script:window) { return }
    $br = [System.Windows.Media.SolidColorBrush]$window.Resources[$key]
    if ($null -eq $br) { return }
    $converter = New-Object System.Windows.Media.BrushConverter
    $clr = $converter.ConvertFromString($hex)
    if($br.IsFrozen){ $window.Resources[$key] = $converter.ConvertFromString($hex) }
    else { $br.Color = $clr.Color }
}

# -------------------- Load XAML --------------------
# Before loading the UI, ensure all required assets are present and downloaded.
$Paths = Initialize-AppAssets  # Creates folders and downloads App.xaml/i18n/images as needed
# Read the XAML from the assets directory under %APPDATA%\Kolokithes A.E
$xamlPath = $Paths.AppXaml
if (!(Test-Path $xamlPath)) { throw "App.xaml not found at $xamlPath" }
[xml]$xaml = Get-Content -Path $xamlPath -Raw
$reader = New-Object System.Xml.XmlNodeReader $xaml
try {
    $window = [System.Windows.Markup.XamlReader]::Load($reader)
} catch {
    $msg = if ($_.Exception.InnerException) { $_.Exception.InnerException.Message } else { $_.Exception.Message }
    [System.Windows.MessageBox]::Show("XAML error: $msg") | Out-Null
    return
}

# Capture the dispatcher for the window early. This will be used in asynchronous callbacks where
# [System.Windows.Application]::Current may be null (e.g. in job events or timers).
$script:UI_Dispatcher = $window.Dispatcher

# -------------------- Set Application Icon for Taskbar and Window --------------------
if (Test-Path $IconFilePath) {
    try {
        $bitmap = New-Object System.Windows.Media.Imaging.BitmapImage
        $bitmap.BeginInit(); $bitmap.UriSource = New-Object System.Uri($IconFilePath); $bitmap.DecodePixelWidth = 32; $bitmap.EndInit()
        if ($bitmap.Width -gt 0 -and $bitmap.Height -gt 0) { $window.Icon = $bitmap }
    } catch { Write-Host "Failed to set application icon: $($_.Exception.Message)" }
}

# Grab controls
$minBtn        = $window.FindName('MinBtn')
$closeBtn      = $window.FindName('CloseBtn')
$titleBar      = $window.FindName('TitleBar')
$titleIcon     = $window.FindName('TitleIcon')
$toastHost     = $window.FindName('ToastHost')
$toastText     = $window.FindName('ToastText')
$toastProgress = $window.FindName('ToastProgress')

$profileBtn       = $window.FindName('ProfileBtn')
$installBtn       = $window.FindName('InstallBtn')
$activateBtn      = $window.FindName('ActivateBtn')
$maintenanceBtn   = $window.FindName('MaintenanceBtn')
$sitesBtn         = $window.FindName('SitesBtn')
$appsBtn          = $window.FindName('AppsBtn')
$infoBtn          = $window.FindName('InfoBtn')

# New sidebar buttons for additional pages
$spotifyBtn         = $window.FindName('SpotifyBtn')
$passwordManagerBtn = $window.FindName('PasswordManagerBtn')
$chrisTitusBtn      = $window.FindName('ChrisTitusBtn')
$simsBtn            = $window.FindName('SimsBtn')
# Apps page controls
$script:AppsDownloadsPanel  = $window.FindName('AppsButtonsPanel')
$script:AppsOverallProgress = $window.FindName('AppsOverallProgressBar')
$script:AppsStatusText      = $window.FindName('AppsStatusText')

# Additional controls for dynamic spacing on the Apps page
$script:AppsStack        = $window.FindName('AppsStack')
$script:AppsProgressCard = $window.FindName('AppsProgressCard')

# Define a helper to adjust spacing based on the window height
function Update-AppsSpacing {
    try {
        $height = [int]$window.ActualHeight
        if ($height -le 520) {
            # On very small heights (~480p), keep a 10px gap for the progress bar and align the top of the buttons with the menu
            if ($script:AppsProgressCard) { $script:AppsProgressCard.Margin = '0,10,0,16' }
            if ($script:AppsStack)        { $script:AppsStack.Margin        = '24,24,24,0' }
        } else {
            # On 720p/1080p, provide a 100px gap and larger top margin
            if ($script:AppsProgressCard) { $script:AppsProgressCard.Margin = '0,100,0,16' }
            if ($script:AppsStack)        { $script:AppsStack.Margin        = '24,32,24,0' }
        }
    } catch {
        # Ignore any errors from sizing logic
    }
}

# Initialize spacing immediately once the window is created
$null = $window.Add_SourceInitialized({ Update-AppsSpacing })
# Update spacing when the window size changes
$null = $window.Add_SizeChanged({ Update-AppsSpacing })
$null = $appsBtn.Add_Click({ Show-Content 'Apps'; Initialize-AppsPageUI })
$null = $appsBtn.Add_Click({ Show-Content 'Apps' })

# Attach click events for the additional sidebar buttons
if ($spotifyBtn)         { $null = $spotifyBtn.Add_Click({ Show-Content 'Spotify' }) }
if ($passwordManagerBtn) { $null = $passwordManagerBtn.Add_Click({ Show-Content 'PasswordManager' }) }
if ($chrisTitusBtn)      { $null = $chrisTitusBtn.Add_Click({ Show-Content 'ChrisTitus' }) }
if ($simsBtn)            { $null = $simsBtn.Add_Click({ Show-Content 'Sims' }) }

# Text/UI elements for i18n
$TitleText   = $window.FindName('TitleText')
$MenuLabel   = $window.FindName('MenuLabel')
$ProfileTitle= $window.FindName('ProfileTitle')
$DisplayTitle= $window.FindName('DisplayTitle')
$ResolutionLabel = $window.FindName('ResolutionLabel')
$ThemeLabel  = $window.FindName('ThemeLabel')
$ThemeToggle = $window.FindName('ThemeToggle')
$ThemeToggleLabel = $window.FindName('ThemeToggleLabel')
$PersonalizationTitle = $window.FindName('PersonalizationTitle')
$UsernameLabel= $window.FindName('UsernameLabel')
$LanguageLabel= $window.FindName('LanguageLabel')
$NotificationsTitle = $window.FindName('NotificationsTitle')
$NotifEnabledLabel  = $window.FindName('NotifEnabledLabel')
$SoundLabel         = $window.FindName('SoundLabel')
$SaveProfileBtn     = $window.FindName('SaveProfileBtn')
$ResetBtn           = $window.FindName('ResetBtn')
$TestNotifBtn       = $window.FindName('TestNotifBtn')

$resolutionCombo     = $window.FindName('ResolutionCombo')
$userName            = $window.FindName('UserName')
$languageCombo       = $window.FindName('LanguageCombo')
$notificationsToggle = $window.FindName('NotificationsToggle')
$soundToggle         = $window.FindName('SoundToggle')

$rootShell   = $window.FindName('RootShell')

# Grab site and game buttons for the Sites page (added for improved navigation)
$ThePirateCityBtn   = $window.FindName('ThePirateCityBtn')
$DownloadPirateBtn  = $window.FindName('DownloadPirateBtn')
$FileCRBtn          = $window.FindName('FileCRBtn')
$RepackGamesBtn     = $window.FindName('RepackGamesBtn')
$SteamUnlockedBtn   = $window.FindName('SteamUnlockedBtn')
$SteamRipBtn        = $window.FindName('SteamRipBtn')
$FitGirlRepacksBtn  = $window.FindName('FitGirlRepacksBtn')
$OnlineFixBtn       = $window.FindName('OnlineFixBtn')

# Action buttons for new pages (launch external resources)
$OpenSpotifyBtn         = $window.FindName('OpenSpotifyBtn')
$OpenPasswordManagerBtn = $window.FindName('OpenPasswordManagerBtn')
$RunChrisTitusBtn       = $window.FindName('RunChrisTitusBtn')
$RunSimsDlcBtn          = $window.FindName('RunSimsDlcBtn')

    # --------------------------------------------------------------------
    # Spotify/Spicetify page controls
    #
    # The Spotify page has been updated to remove the old "Listen to music" button
    # and instead provide three buttons for installing/uninstalling Spicetify and
    # completely removing Spotify.  These controls must have unique names to
    # avoid clashing with existing $installBtn variables used elsewhere in the
    # application.  Here we grab references to those controls.
    $SpicetifyInstallBtn       = $window.FindName('SpicetifyInstallBtn')
    $SpicetifyUninstallBtn     = $window.FindName('SpicetifyUninstallBtn')
    $SpicetifyFullUninstallBtn = $window.FindName('SpicetifyFullUninstallBtn')
    $SpicetifyStatusLabel      = $window.FindName('SpicetifyStatusLabel')

    # Helper functions for Spotify/Spicetify actions
    function Stop-SpotifyProcess {
        try {
            # Attempt to close running Spotify processes.  Suppress any errors.
            Get-Process -Name Spotify -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 1
            return $true
        } catch {
            return $false
        }
    }

    function Update-SpicetifyStatus {
        param([string]$message)
        # Update the status label on the UI thread.  Skip if the label is null (e.g., page not loaded yet).
        if ($null -ne $SpicetifyStatusLabel) {
            $SpicetifyStatusLabel.Dispatcher.Invoke([action]{ $SpicetifyStatusLabel.Text = $message }, "Normal")
        }
    }

    function Restart-Spotify {
        try {
            Update-SpicetifyStatus "Restarting Spotify..."
            # Build the Spotify executable path using System.IO.Path.Combine to avoid positional argument errors
            $spotifyPath = [System.IO.Path]::Combine($env:APPDATA,'Spotify','Spotify.exe')
            if (Test-Path $spotifyPath) {
                Start-Process -FilePath $spotifyPath -WindowStyle Minimized
            } else {
                # Fallback to system path
                Start-Process -FilePath 'spotify' -ErrorAction SilentlyContinue
            }
        } catch {
            Update-SpicetifyStatus "Could not restart Spotify automatically."
        }
    }

    # Attach click handlers for the Spotify/Spicetify buttons.  We guard with
    # null checks so these handlers are only added if the controls exist in
    # the loaded XAML (e.g., after UI modifications).
    if ($SpicetifyInstallBtn) {
        $null = $SpicetifyInstallBtn.Add_Click({
            # Use custom parameter names to avoid clobbering PowerShell's automatic $sender/$args variables.
            param($src, $evtArgs)
            # Use translated message for starting Spicetify installation if available.
            try {
                $code = ([System.Windows.Controls.ComboBoxItem]$languageCombo.SelectedItem).Tag
                if ($i18n.ContainsKey($code) -and $i18n[$code].ContainsKey('spicetifyInstallStart')) {
                    Update-SpicetifyStatus ($i18n[$code].spicetifyInstallStart)
                } else {
                    Update-SpicetifyStatus "Starting Spicetify installation..."
                }
            } catch {
                Update-SpicetifyStatus "Starting Spicetify installation..."
            }

            # Check if Spotify is installed before attempting to install Spicetify.
            # Use Join-Path to build the path without expanding environment variables inside a double-quoted string.
            if (-not (Test-Path (Join-Path $env:APPDATA 'Spotify'))) {
                try {
                    $code = ([System.Windows.Controls.ComboBoxItem]$languageCombo.SelectedItem).Tag
                    if ($i18n.ContainsKey($code) -and $i18n[$code].ContainsKey('spotifyNotFoundForSpicetifyInstall')) {
                        Update-SpicetifyStatus ($i18n[$code].spotifyNotFoundForSpicetifyInstall)
                    } else {
                        Update-SpicetifyStatus "Spotify not found. Please install Spotify first."
                    }
                } catch {
                    Update-SpicetifyStatus "Spotify not found. Please install Spotify first."
                }
                return
            }

            $job = Start-Job -ScriptBlock {
                try {
                    $scriptURL  = 'https://raw.githubusercontent.com/spicetify/cli/main/install.ps1'
                    $scriptPath = Join-Path $env:TEMP 'spicetify-install.ps1'
                    Invoke-WebRequest -Uri $scriptURL -UseBasicParsing -OutFile $scriptPath

                    # Modify the downloaded install script to skip interactive prompts
                    $scriptContent = Get-Content -Path $scriptPath -Raw
                    $scriptContent = $scriptContent -replace '(?s)\$choice\s*=\s*\$Host\.UI\.PromptForChoice\([^)]*abort[^)]*\)', '$choice = 1'
                    $scriptContent = $scriptContent -replace '(?s)\$choice\s*=\s*\$Host\.UI\.PromptForChoice\([^)]*install Spicetify Marketplace[^)]*\)', '$choice = 0'
                    Set-Content -Path $scriptPath -Value $scriptContent -Encoding UTF8

                    $process = Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`"" -PassThru -Wait
                    if ($process.ExitCode -eq 0) {
                        return 'Spicetify installed successfully.'
                    } else {
                        return 'Spicetify installation failed.'
                    }
                } catch {
                    return "Failed to install Spicetify: $_"
                }
            }

            # Keep the UI responsive while waiting for the job to complete.
            while ($job.State -eq 'Running') {
                Start-Sleep -Milliseconds 100
                [System.Windows.Threading.Dispatcher]::CurrentDispatcher.Invoke([action]{}, 'Background')
            }

            $result = Receive-Job -Job $job
            Update-SpicetifyStatus $result

            # On success, restart Spotify to apply the changes.
            if ($result -like '*successfully*') {
                $restartJob = Start-Job -ScriptBlock {
                    try {
                        Get-Process -Name Spotify -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
                        Start-Sleep -Seconds 2
                        # Use System.IO.Path.Combine to build the full Spotify path (APPDATA\Spotify\Spotify.exe)
                        $spotifyPath = [System.IO.Path]::Combine($env:APPDATA,'Spotify','Spotify.exe')
                        if (Test-Path $spotifyPath) {
                            Start-Process -FilePath $spotifyPath -WindowStyle Minimized
                        } else {
                            Start-Process -FilePath 'spotify' -ErrorAction SilentlyContinue
                        }
                        Start-Sleep -Seconds 3
                        $spotifyProcess = Get-Process -Name Spotify -ErrorAction SilentlyContinue
                        if ($spotifyProcess) {
                            return 'Spotify restarted successfully.'
                        } else {
                            return 'Failed to restart Spotify: Process not found.'
                        }
                    } catch {
                        return "Failed to restart Spotify: $_"
                    }
                }

                while ($restartJob.State -eq 'Running') {
                    Start-Sleep -Milliseconds 100
                    [System.Windows.Threading.Dispatcher]::CurrentDispatcher.Invoke([action]{}, 'Background')
                }
                $restartResult = Receive-Job -Job $restartJob
                Update-SpicetifyStatus $restartResult
                Remove-Job -Job $restartJob
            }
            Remove-Job -Job $job
        })
    }

    if ($SpicetifyUninstallBtn) {
        $null = $SpicetifyUninstallBtn.Add_Click({
            param($src, $evtArgs)
            # Use translated message for starting Spicetify uninstallation if available.
            try {
                $code = ([System.Windows.Controls.ComboBoxItem]$languageCombo.SelectedItem).Tag
                if ($i18n.ContainsKey($code) -and $i18n[$code].ContainsKey('spicetifyUninstallStart')) {
                    Update-SpicetifyStatus ($i18n[$code].spicetifyUninstallStart)
                } else {
                    Update-SpicetifyStatus 'Starting Spicetify uninstallation...'
                }
            } catch {
                Update-SpicetifyStatus 'Starting Spicetify uninstallation...'
            }

            # Ensure Spicetify is present before attempting removal.
            if (-not (Test-Path (Join-Path $env:APPDATA 'spicetify')) -and -not (Test-Path (Join-Path $env:LOCALAPPDATA 'spicetify'))) {
                try {
                    $code = ([System.Windows.Controls.ComboBoxItem]$languageCombo.SelectedItem).Tag
                    if ($i18n.ContainsKey($code) -and $i18n[$code].ContainsKey('spicetifyNotFound')) {
                        Update-SpicetifyStatus ($i18n[$code].spicetifyNotFound)
                    } else {
                        Update-SpicetifyStatus 'Spicetify not found. Nothing to uninstall.'
                    }
                } catch {
                    Update-SpicetifyStatus 'Spicetify not found. Nothing to uninstall.'
                }
                return
            }

            $job = Start-Job -ScriptBlock {
                try {
                    & spicetify restore 2>&1 | Out-Null
                    Remove-Item -Path (Join-Path $env:APPDATA     'spicetify') -Recurse -Force -ErrorAction SilentlyContinue
                    Remove-Item -Path (Join-Path $env:LOCALAPPDATA 'spicetify') -Recurse -Force -ErrorAction SilentlyContinue
                    return 'Spicetify uninstalled successfully.'
                } catch {
                    return "Failed to uninstall Spicetify: $_"
                }
            }

            while ($job.State -eq 'Running') {
                Start-Sleep -Milliseconds 100
                [System.Windows.Threading.Dispatcher]::CurrentDispatcher.Invoke([action]{}, 'Background')
            }
            $result = Receive-Job -Job $job
            Update-SpicetifyStatus $result

            if ($result -like '*successfully*') {
                $restartJob = Start-Job -ScriptBlock {
                    try {
                        Get-Process -Name Spotify -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
                        Start-Sleep -Seconds 2
                        # Use System.IO.Path.Combine to build the full Spotify path (APPDATA\Spotify\Spotify.exe)
                        $spotifyPath = [System.IO.Path]::Combine($env:APPDATA,'Spotify','Spotify.exe')
                        if (Test-Path $spotifyPath) {
                            Start-Process -FilePath $spotifyPath -WindowStyle Minimized
                        } else {
                            Start-Process -FilePath 'spotify' -ErrorAction SilentlyContinue
                        }
                        Start-Sleep -Seconds 3
                        $spotifyProcess = Get-Process -Name Spotify -ErrorAction SilentlyContinue
                        if ($spotifyProcess) {
                            return 'Spotify reloaded successfully.'
                        } else {
                            return 'Failed to reload Spotify: Process not found.'
                        }
                    } catch {
                        return "Failed to reload Spotify: $_"
                    }
                }

                while ($restartJob.State -eq 'Running') {
                    Start-Sleep -Milliseconds 100
                    [System.Windows.Threading.Dispatcher]::CurrentDispatcher.Invoke([action]{}, 'Background')
                }
                $restartResult = Receive-Job -Job $restartJob
                Update-SpicetifyStatus $restartResult
                Remove-Job -Job $restartJob
            }
            Remove-Job -Job $job
        })
    }

    if ($SpicetifyFullUninstallBtn) {
        $null = $SpicetifyFullUninstallBtn.Add_Click({
            param($src, $evtArgs)
            # Use translated message for starting complete Spotify uninstallation if available.
            try {
                $code = ([System.Windows.Controls.ComboBoxItem]$languageCombo.SelectedItem).Tag
                if ($i18n.ContainsKey($code) -and $i18n[$code].ContainsKey('spicetifyFullUninstallStart')) {
                    Update-SpicetifyStatus ($i18n[$code].spicetifyFullUninstallStart)
                } else {
                    Update-SpicetifyStatus 'Starting Spotify complete uninstallation...'
                }
            } catch {
                Update-SpicetifyStatus 'Starting Spotify complete uninstallation...'
            }

            # Verify Spotify is installed before attempting full removal.
            if (-not (Test-Path (Join-Path $env:APPDATA 'Spotify')) -and -not (Test-Path (Join-Path $env:LOCALAPPDATA 'Spotify'))) {
                try {
                    $code = ([System.Windows.Controls.ComboBoxItem]$languageCombo.SelectedItem).Tag
                    if ($i18n.ContainsKey($code) -and $i18n[$code].ContainsKey('spotifyNotFound')) {
                        Update-SpicetifyStatus ($i18n[$code].spotifyNotFound)
                    } else {
                        Update-SpicetifyStatus 'Spotify not found. Nothing to uninstall.'
                    }
                } catch {
                    Update-SpicetifyStatus 'Spotify not found. Nothing to uninstall.'
                }
                return
            }

            $job = Start-Job -ScriptBlock {
                try {
                    # Stop running Spotify processes
                    Get-Process -Name Spotify -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
                    Start-Sleep -Seconds 1
                    # Attempt to adjust permissions on the Update folder so it can be deleted cleanly
                    # Build the Update folder path with System.IO.Path.Combine to avoid positional argument errors
                    $updateFolder = [System.IO.Path]::Combine($env:LOCALAPPDATA,'Spotify','Update')
                    $username     = $env:UserName
                    if (Test-Path $updateFolder) {
                        & icacls $updateFolder /remove:d "$username" 2>&1 | Out-Null
                        # Wrap the username in braces before the colon so PowerShell does not misinterpret the colon.
                        & icacls $updateFolder /grant    "${username}:(OI)(CI)F" /T 2>&1 | Out-Null
                        & icacls $updateFolder /reset /T 2>&1 | Out-Null
                    }
                    # Remove Spotify program data
                    $spotifyFolders = @(
                        Join-Path $env:APPDATA     'Spotify',
                        Join-Path $env:LOCALAPPDATA 'Spotify'
                    )
                    foreach ($folder in $spotifyFolders) {
                        if (Test-Path $folder) {
                            Remove-Item -Path $folder -Recurse -Force -ErrorAction SilentlyContinue
                        }
                    }
                    # Clean registry entries related to Spotify
                    $regPaths = @(
                        'HKCU:\Software\Spotify',
                        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run',
                        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Spotify'
                    )
                    foreach ($path in $regPaths) {
                        if (Test-Path $path) {
                            if ($path -like '*Spotify*') {
                                Remove-Item -Path $path -Recurse -Force -ErrorAction SilentlyContinue
                            } else {
                                $properties = Get-ItemProperty -Path $path -ErrorAction SilentlyContinue
                                if ($properties -and $properties.PSObject.Properties.Name -contains 'Spotify') {
                                    Remove-ItemProperty -Path $path -Name 'Spotify' -ErrorAction SilentlyContinue
                                }
                            }
                        }
                    }
                    return 'Spotify completely uninstalled and permissions restored.'
                } catch {
                    return "Failed to uninstall Spotify completely: $_"
                }
            }

            while ($job.State -eq 'Running') {
                Start-Sleep -Milliseconds 100
                [System.Windows.Threading.Dispatcher]::CurrentDispatcher.Invoke([action]{}, 'Background')
            }
            $result = Receive-Job -Job $job
            Update-SpicetifyStatus $result
            Remove-Job -Job $job
        })
    }

# Attach click handlers for launching websites
if ($OpenSpotifyBtn) {
    $null = $OpenSpotifyBtn.Add_Click({
        try {
            Start-Process 'https://open.spotify.com/'
        } catch {
            [System.Windows.MessageBox]::Show("Δεν ήταν δυνατή η εκκίνηση του Spotify.", "Σφάλμα", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
        }
    })
}
if ($OpenPasswordManagerBtn) {
    # Launch the in-app Password Manager via WebView2.  Use custom parameter
    # names to avoid clobbering PowerShell automatic variables ($sender/$args).
    $null = $OpenPasswordManagerBtn.Add_Click({
        param($src, $evt)
        try {
            Open-PasswordManagerWebView
        } catch {
            [System.Windows.MessageBox]::Show("Σφάλμα: $($_.Exception.Message)", "Password Manager", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error) | Out-Null
        }
    })
}
if ($RunChrisTitusBtn) {
    $null = $RunChrisTitusBtn.Add_Click({
        try {
            # Minimize main window while launching the external console
            $prevState = $null
            if ($null -ne $script:window) {
                $prevState = $script:window.WindowState
                $script:window.WindowState = [System.Windows.WindowState]::Minimized
            }

            $proc = Start-CenteredPowerShellCommand 'iwr -useb https://christitus.com/win | iex'

            if (-not $proc) {
                # Restore window immediately on failure
                if ($null -ne $script:window) {
                    $stateToSet = if ($prevState) { $prevState } else { [System.Windows.WindowState]::Normal }
                    $script:window.WindowState = $stateToSet
                }
                [System.Windows.MessageBox]::Show("Δεν ήταν δυνατή η εκτέλεση του εργαλείου Chris Titus.", "Σφάλμα", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
                return
            }

            # Restore main window when the process exits
            $proc.EnableRaisingEvents = $true
            $null = $proc.add_Exited({
                $script:window.Dispatcher.Invoke([action]{
                    $restore = if ($prevState) { $prevState } else { [System.Windows.WindowState]::Normal }
                    if ($restore -eq [System.Windows.WindowState]::Maximized) {
                        # Force re-maximize by toggling through Normal
                        $script:window.WindowState = [System.Windows.WindowState]::Normal
                        $script:window.WindowState = [System.Windows.WindowState]::Maximized
                    } else {
                        $script:window.WindowState = $restore
                    }
                    $script:window.Activate()
                    $script:window.Topmost = $true
                    # Keep window topmost for 2 seconds then reset
                    $timer = New-Object System.Windows.Threading.DispatcherTimer
                    $timer.Interval = [TimeSpan]::FromSeconds(2)
                    $null = $timer.Add_Tick({ param($s,$e) $script:window.Topmost = $false; $s.Stop() })
                    $timer.Start()
                })
            })
        } catch {
            # suppress non-fatal errors
        }
    })
}
if ($RunSimsDlcBtn) {
    $null = $RunSimsDlcBtn.Add_Click({
        try {
            Start-Process 'https://www.ea.com/games/the-sims'
        } catch {
            [System.Windows.MessageBox]::Show("Δεν ήταν δυνατή η εκκίνηση της σελίδας The Sims.", "Σφάλμα", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
        }
    })
}

# =====================================================================
#                     UI Scaling Helpers
#
# The application supports multiple window resolutions.  To ensure the
# user interface remains usable across these resolutions, font sizes,
# element heights and paddings are dynamically scaled when the window
# resolution changes.  We capture the original (base) metrics the first
# time scaling is applied and then reuse them for subsequent changes.
#
# Scaling factors are piecewise: resolutions up to 854 px wide (≈480p)
# use a factor of 1 and display text with bold weight; widths up to
# 1280 px (≈720p) use a factor of 1.3; widths up to 1920 px (≈1080p)
# use 1.6; widths up to 2560 px (≈1440p) use 1.8; anything larger
# defaults to 2.0.  These values were tuned to provide visibly larger
# text on higher resolutions while maintaining layout integrity.

# Flag indicating whether base metrics have been captured.
$script:BaseMetricsCollected = $false
# Dictionaries to store base properties by element name.
$script:BaseFontSizes   = @{}
$script:BaseHeights     = @{}
$script:BasePaddings    = @{}
$script:BaseFontWeights = @{}

# Track the current scale and whether bold styling should be used.  These
# values are updated whenever the resolution changes and are used to
# reapply scaling when switching pages.
$script:CurrentScale = 1.0
$script:CurrentBold  = $false

function Save-BaseMetrics {
    <#
        Capture the initial FontSize, FontWeight, Height and Padding
        for a predefined list of controls.  This must run before
        applying any scaling so that subsequent scales multiply the
        original values rather than accumulating error.
    #>
    if ($script:BaseMetricsCollected) { return }
    # List of elements to consider for scaling.  Modify this list to
    # include any additional controls whose typography should scale.
    $controlsToScale = @(
        # Core labels and titles
        $TitleText, $MenuLabel, $ProfileTitle, $DisplayTitle, $ResolutionLabel,
        $ThemeLabel, $PersonalizationTitle, $UsernameLabel, $LanguageLabel,
        $NotificationsTitle, $NotifEnabledLabel, $SoundLabel,
        $ThemeToggleLabel,
        # Buttons on the content pages (not the sidebar)
        $SaveProfileBtn, $ResetBtn, $TestNotifBtn,
        $BtnAdd, $BtnRemove, $BtnDownload,
        $AutoLoginBtn, $WinActivateBtn,
        $DeleteTempBtn, $SystemScanBtn, $DownloadPatchBtn,
        # List boxes and other controls on pages
        $AvailableApps, $SelectedApps,
        # Titles and descriptions for each page
        ($window.FindName('InstallTitle')), ($window.FindName('InstallDesc')),
        ($window.FindName('ActivateTitle')), ($window.FindName('ActivateDesc')),
        ($window.FindName('MaintenanceTitle')), ($window.FindName('MaintenanceDesc')),
        ($window.FindName('InfoTitle')), ($window.FindName('InfoDesc')),
        ($window.FindName('VersionLabel')), ($window.FindName('CopyrightLabel')),
        ($window.FindName('StatusText')), $MaintenanceStatusText, $ActivateStatusText
        # Note: sidebar buttons (profileBtn, installBtn, etc.) are intentionally omitted
        # from this list to preserve their original proportions and modern look.
    ) | Where-Object { $null -ne $_ }
    foreach ($ctrl in $controlsToScale) {
        $name = $ctrl.Name
        # Capture font size and weight once
        if (-not $script:BaseFontSizes.ContainsKey($name)) {
            $script:BaseFontSizes[$name]   = $ctrl.FontSize
            $script:BaseFontWeights[$name] = $ctrl.FontWeight
        }
        # Height is only captured when explicitly set (NaN implies auto)
        if (-not $script:BaseHeights.ContainsKey($name) -and -not [double]::IsNaN([double]$ctrl.Height)) {
            $script:BaseHeights[$name] = $ctrl.Height
        }
        # Padding exists on many controls but may be undefined on others
        if (-not $script:BasePaddings.ContainsKey($name) -and $ctrl.PSObject.Properties.Match('Padding')) {
            $pad = $ctrl.Padding
            # Only capture if padding is defined; some controls default to Thickness(0,0,0,0)
            if ($null -ne $pad) { $script:BasePaddings[$name] = $pad }
        }
    }
    $script:BaseMetricsCollected = $true
}

function Get-ScaleFactor {
    <#
        Given a window width, return an appropriate scale factor.  The
        piecewise mapping below results in progressively larger
        typography for higher resolutions.  Feel free to tweak the
        thresholds or factors if the UI still appears too small.
    #>
    param([double]$width)
    if ($width -le 854) { return 1.0 }
    elseif ($width -le 1280) { return 1.3 }
    elseif ($width -le 1920) { return 1.6 }
    elseif ($width -le 2560) { return 1.8 }
    else { return 2.0 }
}

function Set-BoldWeight {
    <#
        Apply the given scale factor to all stored controls.  For very
        small resolutions (≤480p), set FontWeight to Bold; otherwise
        restore the original weight.  Heights and paddings are scaled
        proportionally when available.
    #>
    param(
        [Parameter(Mandatory)][double]$scale,
        [Parameter(Mandatory)][bool]$bold
    )
    foreach ($name in $script:BaseFontWeights.Keys) {
        $ctrl = $window.FindName($name)
        if ($null -eq $ctrl) { continue }
        # Only toggle font weight.  The overall size of the UI is now handled
        # by a ScaleTransform on the root container.  Bold is applied for
        # the smallest resolution, otherwise we restore the captured weight.
        if ($bold) { $ctrl.FontWeight = [System.Windows.FontWeights]::Bold }
        else { $ctrl.FontWeight = $script:BaseFontWeights[$name] }
    }
}

# Controls for Activate/Autologin section
$AutoLoginBtn        = $window.FindName('AutoLoginBtn')
$WinActivateBtn      = $window.FindName('WinActivateBtn')
$ActivateProgressBar = $window.FindName('ActivateProgressBar')
$ActivateStatusText  = $window.FindName('ActivateStatusText')
# Use Border elements for the AutoLogin and Activate images so we can apply rounded corners via ImageBrush
# Remove unused border variables; call Initialize-ActivationImages to download and apply images
Initialize-ActivationImages

# Controls for the Maintenance page
$DeleteTempBtn        = $window.FindName('DeleteTempBtn')
$SystemScanBtn        = $window.FindName('SystemScanBtn')
$DownloadPatchBtn     = $window.FindName('DownloadPatchBtn')
$MaintenanceProgressBar = $window.FindName('MaintenanceProgressBar')
$MaintenanceStatusText  = $window.FindName('MaintenanceStatusText')


# Remove the old image loading logic; images are now handled by Initialize-ActivationImages

# -------------------- Set Icon in Titlebar --------------------
if (Test-Path $IconFilePath) {
    try {
        $bitmap = New-Object System.Windows.Media.Imaging.BitmapImage
        $bitmap.BeginInit(); $bitmap.UriSource = New-Object System.Uri($IconFilePath); $bitmap.DecodePixelWidth = 24; $bitmap.EndInit()
        if ($bitmap.Width -gt 0 -and $bitmap.Height -gt 0) { $titleIcon.Source = $bitmap }
    } catch { Write-Host "Failed to load titlebar icon: $($_.Exception.Message)" }
}

# -------------------- i18n dictionaries --------------------
# Define an empty dictionary; it will be populated from the external i18n.psd1 file.
$i18n = @{}


# Attempt to import translations from the external PowerShell data file (i18n.psd1)
# located in the application assets directory.  If the file is missing or
# fails to load, the $i18n variable will remain empty.
$translationsPath = $Paths.I18nPsd1
if (Test-Path $translationsPath) {
    try {
        $fileTranslations = Import-PowerShellDataFile -Path $translationsPath
        if ($fileTranslations) {
            $i18n = $fileTranslations
        }
    } catch {
        Write-Host "Failed to import translations file: $($_.Exception.Message)"
        # leave $i18n as empty; downstream code may fallback to hard-coded keys if needed.
    }
} else {
    Write-Host "Warning: i18n.psd1 not found at $translationsPath. Using built-in English strings only."
}

# -------------------- Page switching --------------------
function Show-Content([string]$name){
    # Include all content pages, including newly added ones (Spotify, Password Manager, ChrisTitus, Sims).
    $all = @(
        $window.FindName('ProfileContent'),
        $window.FindName('InstallContent'),
        $window.FindName('ActivateContent'),
        $window.FindName('MaintenanceContent'),
        $window.FindName('SitesContent'),
        $window.FindName('AppsContent'),
        $window.FindName('InfoContent'),
        $window.FindName('SpotifyContent'),
        $window.FindName('PasswordManagerContent'),
        $window.FindName('ChrisTitusContent'),
        $window.FindName('SimsContent')
    )
    foreach($g in $all){ if($g){ $g.Visibility = [System.Windows.Visibility]::Collapsed } }

    foreach($b in @($profileBtn,$installBtn,$activateBtn,$maintenanceBtn,$sitesBtn,$appsBtn,$infoBtn,$spotifyBtn,$passwordManagerBtn,$chrisTitusBtn,$simsBtn)){
        if($b){ $b.Style = $window.FindResource("PillButton") }
    }

    switch($name){
        'Profile'     { ($window.FindName('ProfileContent')).Visibility='Visible';     $profileBtn.Style=$window.FindResource("ActivePillButton") }
        'Install'     { ($window.FindName('InstallContent')).Visibility='Visible';     $installBtn.Style=$window.FindResource("ActivePillButton") }
        'Activate'    { ($window.FindName('ActivateContent')).Visibility='Visible';    $activateBtn.Style=$window.FindResource("ActivePillButton") }
        'Maintenance' { ($window.FindName('MaintenanceContent')).Visibility='Visible'; $maintenanceBtn.Style=$window.FindResource("ActivePillButton") }
        'Sites'       { ($window.FindName('SitesContent')).Visibility='Visible';       $sitesBtn.Style=$window.FindResource("ActivePillButton") }
        'Apps'        { ($window.FindName('AppsContent')).Visibility='Visible';        $appsBtn.Style=$window.FindResource("ActivePillButton") }
        'Info'        { ($window.FindName('InfoContent')).Visibility='Visible';        $infoBtn.Style=$window.FindResource("ActivePillButton") }
        'Spotify'     { ($window.FindName('SpotifyContent')).Visibility='Visible';     if($spotifyBtn){ $spotifyBtn.Style=$window.FindResource("ActivePillButton") } }
        'PasswordManager' { ($window.FindName('PasswordManagerContent')).Visibility='Visible'; if($passwordManagerBtn){ $passwordManagerBtn.Style=$window.FindResource("ActivePillButton") } }
        'ChrisTitus'  { ($window.FindName('ChrisTitusContent')).Visibility='Visible';  if($chrisTitusBtn){ $chrisTitusBtn.Style=$window.FindResource("ActivePillButton") } }
        'Sims'        { ($window.FindName('SimsContent')).Visibility='Visible';        if($simsBtn){ $simsBtn.Style=$window.FindResource("ActivePillButton") } }
    }

    # Reapply current bold settings to newly visible content.  When switching
    # pages the controls on the new page might not have been visible
    # during the last scaling pass; invoke Set-BoldWeight to ensure they
    # adopt the current font weight (bold or normal).  The scale and bold
    # flags are stored globally when the resolution changes.
    try {
        if ($script:BaseMetricsCollected -and $script:CurrentScale) {
            Set-BoldWeight -scale $script:CurrentScale -bold:$script:CurrentBold
        }
    } catch { }
}


function Set-BaseFontResources([int]$w){
    # Map width buckets to base font sizes/padding for crisp, non-zoom scaling
    $base = switch ($w) {
        {$_ -le 640}   { 12; break }
        {$_ -le 854}   { 13; break }   # ~480p-540p
        {$_ -le 1280}  { 14; break }   # 720p
        {$_ -le 1600}  { 15; break }   # between 720p and 1080p
        {$_ -le 1920}  { 16; break }   # 1080p
        default         { 17 }
    }
    try {
        # Ensure the keys exist; if not, add them.
        if ($window.Resources.Contains("BaseFontSize")) {
            $window.Resources["BaseFontSize"] = [double]$base
        } else {
            $window.Resources.Add("BaseFontSize", [double]$base) | Out-Null
        }
        if ($window.Resources.Contains("BasePadding")) {
            $window.Resources["BasePadding"] = (New-Object System.Windows.Thickness( [double][math]::Round($base*0.6), [double][math]::Round($base*0.6), [double][math]::Round($base*0.6), [double][math]::Round($base*0.6) ))
        } else {
            $pad = New-Object System.Windows.Thickness( [double][math]::Round($base*0.6) )
            $window.Resources.Add("BasePadding", $pad) | Out-Null
        }
    } catch {
        Write-Verbose "Could not update BaseFont resources: $($_.Exception.Message)"
    }
}

function Set-WindowResolution([string]$sel){
    if($sel -match '(\d{3,4})x(\d{3,4})'){
        $w = [int]$matches[1]; $h = [int]$matches[2]
        Set-BaseFontResources $w
        # Apply dynamic UI scaling based on the selected resolution.  The first time this is called
        # it will capture and store the base font sizes, heights and paddings of all relevant UI
        # elements before modifying them.  Subsequent calls will reuse those stored values.
        if (-not $script:BaseMetricsCollected) { Save-BaseMetrics }
        # Compute the scale factor without assigning it to an unused variable.
        $null = Get-ScaleFactor $w
        $useBold = $w -le 854
        # Remember current scale and bold flag so we can reapply them when
        # switching pages without recomputing.
        # scaling automatically, so we leave the scale factor at 1 and only
        # adjust font weight if the resolution is very small.
        $script:CurrentScale = 1.0
        $script:CurrentBold  = $useBold
        # contained in the XAML ensures the content scales uniformly to fit.
        $window.Width  = [double]$w
        $window.Height = [double]$h
        # Center to primary screen after size change
        $screenW = [System.Windows.SystemParameters]::PrimaryScreenWidth
        $screenH = [System.Windows.SystemParameters]::PrimaryScreenHeight
        $window.Left = [math]::Round(($screenW - $window.Width)/2)
        $window.Top  = [math]::Round(($screenH - $window.Height)/2)
        # Reset any previous transform to identity
        # Apply or remove bold weight on text elements as needed
        Set-BoldWeight -scale 1 -bold:$useBold
    }
}

function Set-ThemeLight {
    Set-Brush "AppBg"     "#F4F6FA"
    Set-Brush "ContentBg" "#FFFFFF"
    Set-Brush "TextBrush" "#111217"
    Set-Brush "MutedText" "#4B5563"
    Set-Brush "CardBg"    "#FFFFFF"
    Set-Brush "BorderBr"  "#D1D5DB"
    Set-Brush "ScrollThumb" "#C9CFDA"
    Set-Brush "ScrollTrack" "#00000000"
    Set-Brush "SwitchTrack" "#D1D5DB"
    Set-Brush "ToastBg"     "#FFFFFFFF"
    Set-Brush "ToastBorder" "#E5E7EB"
    Set-Brush "ToastAccent" "#4A8BFF"
    Set-Brush "ToastTrack"  "#E5E7EB"
    $titleBar.Background = New-LinearGradientBrush "#F0F2F7" "#E9ECF3" -Direction Horizontal
    ($window.FindName('Sidebar')).Background  = New-LinearGradientBrush "#F7F9FD" "#EEF2F9" -Direction Vertical
}

function Set-ThemeDark {
    Set-Brush "AppBg"     "#0F1115"
    Set-Brush "ContentBg" "#141821"
    Set-Brush "TextBrush" "#EDEFF5"
    Set-Brush "MutedText" "#AAB2C0"
    Set-Brush "CardBg"    "#1E2128"
    Set-Brush "BorderBr"  "#3A3D42"
    Set-Brush "ScrollThumb" "#4A4F57"
    Set-Brush "ScrollTrack" "#00000000"
    Set-Brush "SwitchTrack" "#3A3D42"
    Set-Brush "ToastBg"     "#E61E2128"
    Set-Brush "ToastBorder" "#403A3D42"
    Set-Brush "ToastAccent" "#4A8BFF"
    Set-Brush "ToastTrack"  "#282C33"
    $titleBar.Background = New-LinearGradientBrush "#1C1F26" "#1A1D24" -Direction Horizontal
    ($window.FindName('Sidebar')).Background  = New-LinearGradientBrush "#12151B" "#0F1218" -Direction Vertical
}

function Set-Language([string]$code){
    if(-not $i18n.ContainsKey($code)){ $code = "en" }
    $t = $i18n[$code]

    $TitleText.Text = $t.title
    $MenuLabel.Text = $t.menu
    $profileBtn.Content = $t.profile
    $installBtn.Content = $t.install
    $activateBtn.Content = $t.activate
    $maintenanceBtn.Content = $t.maintenance
    $sitesBtn.Content = $t.sites
    $appsBtn.Content = $t.apps
    $infoBtn.Content = $t.info

    $ProfileTitle.Text = $t.profileTitle
    $DisplayTitle.Text = $t.displayTitle
    $ResolutionLabel.Text = $t.resolution
    $ThemeLabel.Text = $t.theme

    $PersonalizationTitle.Text = $t.personalization
    $UsernameLabel.Text = $t.username
    $LanguageLabel.Text = $t.language

    $NotificationsTitle.Text = $t.notifications
    $NotifEnabledLabel.Text  = $t.notifEnabled
    $SoundLabel.Text         = $t.sound

    $SaveProfileBtn.Content  = $t.save
    $ResetBtn.Content        = $t.reset
    $TestNotifBtn.Content    = $t.toastTest

    ($window.FindName('InstallTitle')).Text     = $t.installTitle
    ($window.FindName('InstallDesc')).Text      = $t.installDesc
    ($window.FindName('ActivateTitle')).Text    = $t.activateTitle
    ($window.FindName('ActivateDesc')).Text     = $t.activateDesc
    ($window.FindName('MaintenanceTitle')).Text = $t.maintenanceTitle
    ($window.FindName('MaintenanceDesc')).Text  = $t.maintenanceDesc

    ($window.FindName('InfoTitle')).Text        = $t.infoTitle
    ($window.FindName('InfoDesc')).Text         = $t.infoDesc
    ($window.FindName('VersionLabel')).Text     = $t.version
    ($window.FindName('CopyrightLabel')).Text   = $t.copyright

    $themeToggleLabel.Text = if ($themeToggle.IsChecked) { $t.darkText } else { $t.lightText }

    # Apply additional translations for new pages and buttons (Spotify, Password Manager,
    # ChrisTitus Tools, Sims DLC tools, extended install/maintenance controls, etc.).
    # If a Set-Language_additions.ps1 file exists next to this script, dot-source it.
    try {
        # Load the Set-Language_additions script from the assets folder in the
        # application data directory.  This allows the script to self-heal
        # if the file is missing and ensures a single copy is used regardless
        # of the current working directory.
        $addonPath = $Paths.SetLangAdditions
        if (Test-Path $addonPath) {
            . $addonPath
        }
    } catch {
        Write-Host "Failed to apply Set-Language additions: $($_.Exception.Message)"
    }
}

# -------------------- TRUE rounded clip (stable) --------------------
function Set-RoundedClip {
    param([System.Windows.FrameworkElement]$el, [double]$radius = 16)
    if ($null -eq $el) { return }
    $w = [double]$el.ActualWidth
    $h = [double]$el.ActualHeight
    if ($w -le 0 -or $h -le 0) { return }
    $geom = New-Object System.Windows.Media.RectangleGeometry
    $geom.Rect    = New-Object System.Windows.Rect(0, 0, $w, $h)
    $geom.RadiusX = $radius
    $geom.RadiusY = $radius
    $el.Clip = $geom
}

# -------------------- Toast helper (theme-aware + animated progress) --------------------
$script:ToastTimer = $null
function Show-Toast([string]$text, [int]$ms=2200, [bool]$playSound=$false) {
    $toastText.Text = $text
    $toastHost.Visibility = 'Visible'

    $toastProgress.BeginAnimation([System.Windows.Controls.Primitives.RangeBase]::ValueProperty, $null)
    $toastProgress.Value = 0
    if ($ms -gt 0) {
        $ease = New-Object System.Windows.Media.Animation.CubicEase
        $ease.EasingMode = [System.Windows.Media.Animation.EasingMode]::EaseOut
        $da = New-Object System.Windows.Media.Animation.DoubleAnimation(0,100,[TimeSpan]::FromMilliseconds($ms))
        $da.EasingFunction = $ease
        $toastProgress.BeginAnimation([System.Windows.Controls.Primitives.RangeBase]::ValueProperty, $da)
    }

    if ($playSound -and $soundToggle.IsChecked) {
        if (-not (Test-Path $SoundFilePath)) {
            $code = ([System.Windows.Controls.ComboBoxItem]$languageCombo.SelectedItem).Tag
            Show-Toast ($i18n[$code].downloadingSound) 3000 $false
            try {
                Invoke-WebRequest -Uri "https://www.dropbox.com/scl/fi/s871pdk7zk1ps6po6ebkt/click.wav?rlkey=1sseob8us489hypvnxlua33ya&st=xt5q8nuk&dl=1" -OutFile $SoundFilePath -UseBasicParsing
                if (Test-Path $SoundFilePath) {
                    [Audio]::PlaySound($SoundFilePath); Start-Sleep -Milliseconds 500; [Audio]::StopSound()
                } else { [System.Console]::Beep(1000, 300) }
            } catch { [System.Console]::Beep(1000, 300) }
        } else {
            [Audio]::PlaySound($SoundFilePath); Start-Sleep -Milliseconds 500; [Audio]::StopSound()
        }
    }

    if ($null -eq $script:ToastTimer) {
        $script:ToastTimer = New-Object System.Windows.Threading.DispatcherTimer
        $script:ToastTimer.Add_Tick({
            param($s, $e)
            $toastProgress.BeginAnimation([System.Windows.Controls.Primitives.RangeBase]::ValueProperty, $null)
            $toastProgress.Value = 0
            $toastHost.Visibility = 'Collapsed'
            if ($s -is [System.Windows.Threading.DispatcherTimer]) { $s.Stop() }
        })
    }
    if ($ms -gt 0) {
        if ($script:ToastTimer.IsEnabled) { $script:ToastTimer.Stop() }
        $script:ToastTimer.Interval = [TimeSpan]::FromMilliseconds($ms)
        $script:ToastTimer.Start()
    }
}

# -------------------- Helper: find ancestor Button to avoid drag stealing clicks --------------------
function Get-AncestorOfType {
    param([System.Windows.DependencyObject]$obj,[Type]$type)
    while($obj){
        if ($type.IsInstanceOfType($obj)) { return $obj }
        $obj = [System.Windows.Media.VisualTreeHelper]::GetParent($obj)
    }
    return $null
}

# -------------------- Apply on load + on size changes --------------------
$null = $window.Add_Loaded({
    Set-RoundedClip -el $rootShell -radius 16
    if (-not (Test-Path $IconFilePath)) {
        $code = ([System.Windows.Controls.ComboBoxItem]$languageCombo.SelectedItem).Tag
        Show-Toast ($i18n[$code].downloadingIcon) 3000 $false
    }
})
$null = $rootShell.Add_SizeChanged({ Set-RoundedClip -el $rootShell -radius 16 })

# -------------------- Events --------------------
$null = $titleBar.Add_MouseLeftButtonDown({
    $src = [System.Windows.DependencyObject]$_.OriginalSource
    $isBtn = (Get-AncestorOfType -obj $src -type ([System.Windows.Controls.Primitives.ButtonBase]))
    if (-not $isBtn) { $window.DragMove() }
})
$null = $closeBtn.Add_Click({ $window.Close() })
$null = $minBtn.Add_Click({ $window.WindowState = [System.Windows.WindowState]::Minimized })

# -------------------- INSTALL PAGE GRAB CONTROLS --------------------
$AvailableApps       = $window.FindName('AvailableApps')
$SelectedApps        = $window.FindName('SelectedApps')
$BtnAdd              = $window.FindName('BtnAdd')
$BtnRemove           = $window.FindName('BtnRemove')
$BtnDownload         = $window.FindName('BtnDownload')
$DownloadProgressBar = $window.FindName('DownloadProgressBar')
$StatusText          = $window.FindName('StatusText')

# Sidebar buttons (InstallBtn opens IN-APP page)
$null = $profileBtn.Add_Click({ Show-Content 'Profile' })
$null = $installBtn.Add_Click({ Show-Content 'Install'; Initialize-InstallPage })
$null = $activateBtn.Add_Click({ Show-Content 'Activate' })
$null = $maintenanceBtn.Add_Click({ Show-Content 'Maintenance' })
$null = $sitesBtn.Add_Click({ Show-Content 'Sites' })
$null = $appsBtn.Add_Click({ Show-Content 'Apps' })
$null = $infoBtn.Add_Click({ Show-Content 'Info' })

# Profile controls
$null = $resolutionCombo.Add_SelectionChanged({
    $sel = $resolutionCombo.SelectedItem.Content.ToString()
    Set-WindowResolution $sel
})
$null = $themeToggle.Add_Checked({
    Set-ThemeDark
    $code = ([System.Windows.Controls.ComboBoxItem]$languageCombo.SelectedItem).Tag
    $themeToggleLabel.Text = $i18n[$code].darkText
})
$null = $themeToggle.Add_Unchecked({
    Set-ThemeLight
    $code = ([System.Windows.Controls.ComboBoxItem]$languageCombo.SelectedItem).Tag
    $themeToggleLabel.Text = $i18n[$code].lightText
})
$null = $languageCombo.Add_SelectionChanged({
    $selItem = [System.Windows.Controls.ComboBoxItem]$languageCombo.SelectedItem
    $code = $selItem.Tag
    Set-Language $code
})

# Interlock: Sound depends on Notifications
$script:PrevSoundEnabled = $true
function Update-SoundInterlock {
    if ($notificationsToggle.IsChecked) {
        $soundToggle.IsEnabled = $true
        if ($null -ne $script:PrevSoundEnabled) { $soundToggle.IsChecked = $script:PrevSoundEnabled }
    } else {
        $script:PrevSoundEnabled = [bool]$soundToggle.IsChecked
        $soundToggle.IsChecked = $false
        $soundToggle.IsEnabled = $false
    }
}
$null = $notificationsToggle.Add_Checked({ Update-SoundInterlock })
$null = $notificationsToggle.Add_Unchecked({ Update-SoundInterlock })

# Test notification
$null = $TestNotifBtn.Add_Click({
    $code = ([System.Windows.Controls.ComboBoxItem]$languageCombo.SelectedItem).Tag
    if ($notificationsToggle.IsChecked) {
        Show-Toast ($i18n[$code].toastTest) 2200 $true
    } else {
        Show-Toast ($i18n[$code].disabledNote) 1800 $false
    }
})

# Save / Reset
$null = $SaveProfileBtn.Add_Click({
    $selRes = $resolutionCombo.SelectedItem.Content.ToString()
    $theme = if ($themeToggle.IsChecked) { "dark" } else { "light" }
    $selItem = [System.Windows.Controls.ComboBoxItem]$languageCombo.SelectedItem
    $lang = "$($selItem.Tag)"

    Set-AppSettings -Resolution $selRes -Theme $theme -UserName $userName.Text `
                    -Language $lang -Notifications $notificationsToggle.IsChecked `
                    -Sound $soundToggle.IsChecked

    Show-Toast ($i18n[$lang].savedMsg) -playSound $true
})

$null = $ResetBtn.Add_Click({
    # Reset to 1080p (index 2 because a 480p entry was added at the top of the list)
    $resolutionCombo.SelectedIndex = 2
    Set-WindowResolution ($resolutionCombo.SelectedItem.Content.ToString())
    $themeToggle.IsChecked = $true
    Set-ThemeDark
    $languageCombo.SelectedIndex = 0
    Set-Language "el"
    $userName.Text = $env:USERNAME
    $notificationsToggle.IsChecked = $true
    $soundToggle.IsChecked = $true
    $soundToggle.IsEnabled = $true
    Set-AppSettings -Resolution ($resolutionCombo.SelectedItem.Content.ToString()) -Theme "dark" `
                    -UserName $userName.Text -Language "el" `
                    -Notifications $true -Sound $true
    Show-Toast ($i18n['el'].savedMsg) -playSound $true
})

# -------------------- Load defaults / saved settings --------------------
$userName.Text = $env:USERNAME
Set-WindowResolution ($resolutionCombo.SelectedItem.Content.ToString())
Set-ThemeDark
Set-Language "el"

$loaded = Get-AppSettings
if ($null -ne $loaded) {
    $idx = 0
    for($i=0;$i -lt $resolutionCombo.Items.Count;$i++){
        if ($resolutionCombo.Items[$i].Content.ToString() -eq $loaded.resolution) { $idx=$i; break }
    }
    $resolutionCombo.SelectedIndex = $idx
    Set-WindowResolution $loaded.resolution

    if ($loaded.theme -eq 'light') { $themeToggle.IsChecked=$false; Set-ThemeLight } else { $themeToggle.IsChecked=$true; Set-ThemeDark }
    if ($loaded.language -eq 'en') { $languageCombo.SelectedIndex = 1; Set-Language 'en' } else { $languageCombo.SelectedIndex = 0; Set-Language 'el' }

    if ($loaded.userName) { $userName.Text = $loaded.userName }
    if ($null -ne $loaded.notifications) { $notificationsToggle.IsChecked = [bool]$loaded.notifications }
    if ($null -ne $loaded.sound)         { $soundToggle.IsChecked         = [bool]$loaded.sound }
}
Update-SoundInterlock

# ======================================================================
#                     INSTALLER (IN-APP)
# ======================================================================

# 1) Links για λήψη (πρόσθεσε/άλλαξε ό,τι θες)
$script:DownloadLinks = [ordered]@{
    'discord'           = 'https://www.dropbox.com/scl/fi/skxd8a63snzmciqdhdclt/discord.exe?rlkey=pcfengbhf2wcstvunhh127l39&st=2pojcgit&dl=1'
    'discord_ptb'       = 'https://www.dropbox.com/scl/fi/s3mjizraz0xthulzjstb8/discord_ptb.exe?rlkey=asslvcp52zq995bb0xao12s5b&st=euikzqqd&dl=1'
    'brave'             = 'https://www.dropbox.com/scl/fi/hrzzxh78i2su3ydoq5xaq/brave.exe?rlkey=b9mbyg4lqylhl8ajm122rbjy7&st=sbz96p8d&dl=1'
    'better_discord'    = 'https://www.dropbox.com/scl/fi/1zkmjej8c8qwt0hrpr7x3/better_discord.exe?rlkey=bv0y0nmz4o8fuycyzsoz0emu5&st=w02kl1zh&dl=1'
    'steam'             = 'https://www.dropbox.com/scl/fi/gop5c9hu4e2gxe0t4mlwi/steam.exe?rlkey=4k5wmsqs8r7srs4syf9qsixj5&st=tyfftt01&dl=1'
    'epic_games'        = 'https://www.dropbox.com/scl/fi/zqvmbsdc9id0exjjoexck/epic_games.msi?rlkey=h6cgvu6u3tnfivd9wy8umpb8y&st=i0jasrxz&dl=1'
    'ubisoft'           = 'https://www.dropbox.com/scl/fi/78yfx1jinihuoj0itmcmr/ubisoft.exe?rlkey=dlcxncvl54tf510xpasicncux&st=kefgrf8l&dl=1'
    # ειδική περίπτωση .zip → extract → .msi
    'advancedinstaller' = 'https://example.com/advancedinstaller.zip'  # Βάλε σωστό zip link
}

# 2) Paths για 7-Zip
function Get-AppInstallationPath { 'C:\Program Files (x86)\Kolokithes A.E\Make your life easier' }
function Get-7ZipPath {
    $exe = Join-Path (Join-Path (Get-AppInstallationPath) '7-Zip') '7z.exe'
    if (-not (Test-Path $exe)) { throw "Δεν βρέθηκε το 7z.exe: $exe" }
    $exe
}

# ---- Helper: human-readable sizes ----
function Format-Size {
    param([long]$bytes)
    if ($bytes -lt 1KB) { return "$bytes B" }
    elseif ($bytes -lt 1MB) { return ("{0:N1} KB" -f ($bytes/1KB)) }
    elseif ($bytes -lt 1GB) { return ("{0:N1} MB" -f ($bytes/1MB)) }
    else { return ("{0:N2} GB" -f ($bytes/1GB)) }
}

# 3) Downloader με real progress & safe finish

# Normalize cloud links (Dropbox, etc.) to a stable direct-download form.
function ConvertTo-DirectDownloadUrl {
    param([Parameter(Mandatory)][string] $Url)
    try {
        # Dropbox: use dl.dropboxusercontent.com and drop transient 'st=' query param.
        if ($Url -match 'dropbox\.com') {
            $u = [System.Uri]$Url
            $builder = New-Object System.UriBuilder $u
            $builder.Host = 'dl.dropboxusercontent.com'
            # remove 'st' parameter (short-lived token), and ensure dl=1
            $qs = [System.Web.HttpUtility]::ParseQueryString($builder.Query)
            $qs.Remove('st') | Out-Null
            if (-not $qs['dl']) { $qs['dl'] = '1' } else { $qs['dl'] = '1' }
            $builder.Query = $qs.ToString()
            return $builder.Uri.AbsoluteUri
        }
    } catch {}
    return $Url
}

# Quick signature check for file type (by magic header)
function Get-FileMagic {
    param([Parameter(Mandatory)][string] $Path, [int]$Bytes=4)
    if (-not (Test-Path $Path)) { return $null }
    try {
        $fs = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        try {
            $buf = New-Object byte[] ($Bytes)
            [void]$fs.Read($buf, 0, $Bytes)
            return ($buf | ForEach-Object { $_.ToString('X2') }) -join ' '
        } finally { $fs.Dispose() }
    } catch { return $null }
}

# Helper: check if the downloaded file looks like a real ZIP
function Test-IsZipFile {
    param([Parameter(Mandatory)][string] $Path)
    $magic = Get-FileMagic -Path $Path -Bytes 4
    return ($magic -eq '50 4B 03 04' -or $magic -eq '50 4B 05 06' -or $magic -eq '50 4B 07 08')
}
function Start-AppFileDownload {
    param(
        [Parameter(Mandatory)] [string] $Url,
        [Parameter(Mandatory)] [string] $DestinationPath,
        [Parameter(Mandatory)] $ProgressBar,     # WPF ProgressBar
        [Parameter(Mandatory)] $StatusTextBlock  # WPF TextBlock
    )

    # UI helpers
    $setStatus = {
        param($text)
        try { $StatusTextBlock.Dispatcher.Invoke([action]{ $StatusTextBlock.Text = $text }) } catch {}
    }
    $setBarIndeterminate = {
        param($isIndeterminate)
        try { $ProgressBar.Dispatcher.Invoke([action]{ $ProgressBar.IsIndeterminate = $isIndeterminate }) } catch {}
    }
    # Removed unused $setBar helper (updates happen directly via dispatcher calls)
    $finishBar = {
        try {
            $ProgressBar.Dispatcher.Invoke([action]{
                $ProgressBar.IsIndeterminate = $false
                $ProgressBar.Maximum = 1
                $ProgressBar.Value   = 1
            })
        } catch {}
        [System.Windows.Forms.Application]::DoEvents()
    }

    # Ensure target folder exists
    $destDir = Split-Path -Parent $DestinationPath
    if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Force -Path $destDir | Out-Null }

    $fileOnly = [System.IO.Path]::GetFileName($DestinationPath)
    & $setBarIndeterminate $true
    & $setStatus "Σύνδεση: $fileOnly..."

    # Modern asynchronous download using WebClient to avoid freezing the UI
    & $setStatus "Λήψη: $fileOnly..."
    try {
        $doneEvent = New-Object System.Threading.ManualResetEvent($false)
        $webClient = New-Object System.Net.WebClient
        $webClient.Headers.Add('User-Agent','Mozilla/5.0 (Windows NT 10.0; Win64; x64) PowerShell')
        $webClient.Headers.Add('Accept','*/*')
        $webClient.UseDefaultCredentials = $true
        # Prefer TLS 1.2 for secure downloads
        try { [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12 } catch {}

        $null = $webClient.add_DownloadProgressChanged([System.Net.DownloadProgressChangedEventHandler]{
            # Use custom param names to avoid clobbering automatic $sender variable
            param($progressSource, $progressArgs)
            $pct = $progressArgs.ProgressPercentage
            try {
                $ProgressBar.Dispatcher.Invoke([action]{
                    $ProgressBar.IsIndeterminate = $false
                    $ProgressBar.Maximum = 100
                    $ProgressBar.Value = $pct
                })
                $StatusTextBlock.Dispatcher.Invoke([action]{
                    $StatusTextBlock.Text = "Λήψη: $fileOnly ($pct`%)"
                })
            } catch {}
        })
        $null = $webClient.add_DownloadFileCompleted([System.ComponentModel.AsyncCompletedEventHandler]{
            # Use custom param names to avoid clobbering automatic $sender variable
            param($completeSource, $completeArgs)
            $doneEvent.Set()
        })
        $realUrl = ConvertTo-DirectDownloadUrl -Url $Url
        $webClient.DownloadFileAsync($realUrl, $DestinationPath)
        while (-not $doneEvent.WaitOne(50)) {
            [System.Windows.Forms.Application]::DoEvents()
        }
        $webClient.Dispose()
        & $finishBar
        $size = ([System.IO.FileInfo]$DestinationPath).Length
        & $setStatus "Ολοκληρώθηκε η λήψη: $fileOnly ($(Format-Size $size))"
    } catch {
        & $setBarIndeterminate $false
        throw $_
    }
}

# -------------------- PUMP: keep WPF responsive during waits --------------------
function Invoke-DispatcherPump {
    param([int]$milliseconds = 50)
    $frame = New-Object System.Windows.Threading.DispatcherFrame
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds($milliseconds)
    $null = $timer.Add_Tick({
        param($s,$e)
        try { $s.Stop() } catch {}
        try { $script:__pf.Continue = $false } catch {}
    })
    $script:__pf = $frame
    $timer.Start()
    [System.Windows.Threading.Dispatcher]::PushFrame($frame)
    Remove-Variable -Name __pf -Scope Script -ErrorAction SilentlyContinue
}

# 4) Εγκατάσταση αρχείου ή extract .zip για advancedinstaller
function Install-AppPackage {
    param(
        [Parameter(Mandatory)] [string] $AppName,
        [Parameter(Mandatory)] [string] $FilePath,
        [Parameter(Mandatory)] $OwnerWindow
    )

    if ($AppName -ieq 'advancedinstaller') {
        $sevenZip   = Get-7ZipPath
        $extractDir = Join-Path (Split-Path -Parent $FilePath) 'AdvancedInstaller'
        if (-not (Test-Path $extractDir)) { New-Item -ItemType Directory -Force -Path $extractDir | Out-Null }

        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName  = $sevenZip
        $psi.Arguments = "x `"$FilePath`" -o`"$extractDir`" -y"
        $psi.UseShellExecute        = $false
        $psi.CreateNoWindow         = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError  = $true
        $p = [System.Diagnostics.Process]::Start($psi)
        while (-not $p.HasExited) { Invoke-DispatcherPump 50 }

        if (Test-Path $FilePath) { Remove-Item $FilePath -Force }
        $msi = Join-Path $extractDir 'advancedinstaller.msi'
        if (-not (Test-Path $msi)) {
            # Use enumeration values for the button and icon to avoid parameter parsing errors
            [System.Windows.MessageBox]::Show(
                $OwnerWindow,
                'Δεν βρέθηκε advancedinstaller.msi μετά το extract.',
                'Σφάλμα',
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Error
            ) | Out-Null
            return
        }
        $proc = Start-Process -FilePath $msi -PassThru
        while (-not $proc.HasExited) { Invoke-DispatcherPump 50 }


    # Installation completion toast removed here to avoid duplicate notifications; handled in Start-AppBatch
        return
    }

    $proc = Start-Process -FilePath $FilePath -PassThru
        while (-not $proc.HasExited) { Invoke-DispatcherPump 50 }
    # Installation completion toast removed here to avoid duplicate notifications; handled in Start-AppBatch
}

# 5) Batch workflow (πολλαπλά apps) με άμεσα toast/status
function Start-AppBatch {
    param(
        [Parameter(Mandatory)] [string[]] $AppNames,
        [Parameter(Mandatory)] $ProgressBar,
        [Parameter(Mandatory)] $StatusTextBlock,
        [Parameter(Mandatory)] $OwnerWindow
    )

    if ($AppNames.Count -eq 0) {
        [System.Windows.MessageBox]::Show(
            $OwnerWindow,
            'Δεν έχεις επιλέξει εφαρμογές.',
            'Προσοχή',
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Warning
        ) | Out-Null
        return
    }

    $downloadsRoot = Join-Path $env:USERPROFILE 'Downloads\auto_install_apps'
    if (-not (Test-Path $downloadsRoot)) { New-Item -ItemType Directory -Force -Path $downloadsRoot | Out-Null }

    foreach ($app in $AppNames) {

        if (-not $script:DownloadLinks.Contains($app)) {
            [System.Windows.MessageBox]::Show(
                $OwnerWindow,
                "Άγνωστη εφαρμογή: $app",
                'Σφάλμα',
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Error
            ) | Out-Null
            continue
        }

        $url = $script:DownloadLinks[$app]
        $nameFromUrl = [System.IO.Path]::GetFileName(([Uri]$url).AbsolutePath)
        if ([string]::IsNullOrWhiteSpace($nameFromUrl)) {
            $nameFromUrl = if ($app -ieq 'advancedinstaller') { "$app.zip" } else { "$app.exe" }
        }
        if ($app -ieq 'advancedinstaller') { $nameFromUrl = "$app.zip" }
        $target = Join-Path $downloadsRoot $nameFromUrl

        # === Download ===
        Show-Toast "Ξεκινά η λήψη: $app" 1200 $false
        try {
            $StatusTextBlock.Dispatcher.Invoke([action]{ $StatusTextBlock.Text = "Έναρξη λήψης: $nameFromUrl" })
            $ProgressBar.Dispatcher.Invoke([action]{ $ProgressBar.IsIndeterminate = $true; $ProgressBar.Value = 0 })

            Start-AppFileDownload -Url $url -DestinationPath $target -ProgressBar $ProgressBar -StatusTextBlock $StatusTextBlock

            Show-Toast "Ολοκληρώθηκε η λήψη: $app" 1200 $false
        }
        catch {
            # Use enumeration values for the buttons and icon to avoid parameter parsing errors
            [System.Windows.MessageBox]::Show(
                $OwnerWindow,
                "Σφάλμα λήψης ${app}:`n$($_.Exception.Message)",
                'Σφάλμα',
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Error
            ) | Out-Null
            $ProgressBar.Dispatcher.Invoke([action]{ $ProgressBar.IsIndeterminate = $false; $ProgressBar.Value = 0 })
            $StatusTextBlock.Dispatcher.Invoke([action]{ $StatusTextBlock.Text = '' })
            continue
        }

        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 120

        # === Install ===
        Show-Toast "Εγκατάσταση: $app" 1000 $false
        try {
            $StatusTextBlock.Dispatcher.Invoke([action]{ $StatusTextBlock.Text = "Εγκατάσταση: $nameFromUrl" })
            $ProgressBar.Dispatcher.Invoke([action]{ $ProgressBar.IsIndeterminate = $true; $ProgressBar.Value = 0 })

            Install-AppPackage -AppName $app -FilePath $target -OwnerWindow $OwnerWindow

            Show-Toast "Ολοκληρώθηκε η εγκατάσταση: $app" 1200 $false
        }
        catch {
            # Use enumeration values for the buttons and icon to avoid parameter parsing errors
            [System.Windows.MessageBox]::Show(
                $OwnerWindow,
                "Σφάλμα εγκατάστασης ${app}:`n$($_.Exception.Message)",
                'Σφάλμα',
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Error
            ) | Out-Null
        }
        finally {
            $ProgressBar.Dispatcher.Invoke([action]{ $ProgressBar.IsIndeterminate = $false; $ProgressBar.Value = 0 })
            $StatusTextBlock.Dispatcher.Invoke([action]{ $StatusTextBlock.Text = '' })
            # Remove app from SelectedApps list after installation completes
            try {
                if ($null -ne $script:SelectedApps) {
                    $SelectedApps.Dispatcher.Invoke([action]{ $SelectedApps.Items.Remove($app) })
                }
            } catch {}
        }
    }

    Show-Toast "Οι εργασίες ολοκληρώθηκαν." 1600 $false
}

# -------------------- AutoLogin and Activate functions --------------------
function Invoke-AutoLogin {
    param(
        [Parameter(Mandatory)] $ProgressBar,
        [Parameter(Mandatory)] $StatusTextBlock,
        [Parameter(Mandatory)] $OwnerWindow
    )
    # Downloads the AutoLogin executable and runs it with admin privileges while updating the UI.
    $url = 'https://github.com/thomasthanos/Make_your_life_easier/raw/refs/heads/main/.exe%20files/auto%20login.exe'
    $fileName = [System.IO.Path]::GetFileName(([Uri]$url).AbsolutePath)
    # Place the downloaded AutoLogin executable into the Kolokithes A.E data folder
    $destPath = Get-DownloadPath $fileName
    try {
        # Ensure progress bar visible and start download
        $StatusTextBlock.Dispatcher.Invoke([action]{ $StatusTextBlock.Text = "Σύνδεση στη λήψη: $fileName" })
        $ProgressBar.Dispatcher.Invoke([action]{ $ProgressBar.Visibility = 'Visible'; $ProgressBar.IsIndeterminate = $true; $ProgressBar.Value = 0 })
        # Download the AutoLogin executable into our application data folder
        Start-AppFileDownload -Url $url -DestinationPath $destPath -ProgressBar $ProgressBar -StatusTextBlock $StatusTextBlock
        # Run the downloaded executable as administrator
        $StatusTextBlock.Dispatcher.Invoke([action]{ $StatusTextBlock.Text = 'Εκτέλεση αρχείου...' })
        $ProgressBar.Dispatcher.Invoke([action]{ $ProgressBar.IsIndeterminate = $true; $ProgressBar.Value = 0 })
        try {
            # Run the downloaded executable (from the application data folder) with administrative privileges
            $proc = Start-Process -FilePath $destPath -Verb RunAs -PassThru
        } catch {
            throw "Αποτυχία εκτέλεσης ως διαχειριστής: $($_.Exception.Message)"
        }
        # Wait for the process to finish and keep UI responsive
        while (-not $proc.HasExited) {
            [System.Windows.Forms.Application]::DoEvents()
            Start-Sleep -Milliseconds 100
        }
        Show-Toast 'Ολοκληρώθηκε το Auto Login.' 1500 $false
    } catch {
        Show-Toast ("Σφάλμα Auto Login: " + $_.Exception.Message) 3000 $false
    } finally {
        $ProgressBar.Dispatcher.Invoke([action]{ $ProgressBar.IsIndeterminate = $false; $ProgressBar.Value = 0; $ProgressBar.Visibility = 'Collapsed' })
        $StatusTextBlock.Dispatcher.Invoke([action]{ $StatusTextBlock.Text = '' })
        # Do not remove the downloaded file; keep it in the application data folder for future use
    }
}

function Invoke-ActivateWindows {
    param(
        [Parameter(Mandatory)] $ProgressBar,
        [Parameter(Mandatory)] $StatusTextBlock,
        [Parameter(Mandatory)] $OwnerWindow
    )
    # Runs Windows activation commands quietly and updates the UI while working
    try {
        $ProgressBar.Dispatcher.Invoke([action]{ $ProgressBar.Visibility = 'Visible'; $ProgressBar.IsIndeterminate = $true; $ProgressBar.Value = 0 })
        $StatusTextBlock.Dispatcher.Invoke([action]{ $StatusTextBlock.Text = 'Ενεργοποίηση...' })
        # Install generic volume license key
        $StatusTextBlock.Dispatcher.Invoke([action]{ $StatusTextBlock.Text = 'Εγκατάσταση κλειδιού...' })
        # Use braces around the environment variable to avoid colon parsing issues when concatenating paths
        cscript.exe //B //NoLogo "${env:windir}\system32\slmgr.vbs" /ipk W269N-WFGWX-YVC9B-4J6C9-T83GX | Out-Null
        [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 300
        # Set KMS server
        $StatusTextBlock.Dispatcher.Invoke([action]{ $StatusTextBlock.Text = 'Ορισμός KMS server...' })
        cscript.exe //B //NoLogo "${env:windir}\system32\slmgr.vbs" /skms kms9.MSGuides.com | Out-Null
        [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 300
        # Activate
        $StatusTextBlock.Dispatcher.Invoke([action]{ $StatusTextBlock.Text = 'Ολοκλήρωση ενεργοποίησης...' })
        cscript.exe //B //NoLogo "${env:windir}\system32\slmgr.vbs" /ato | Out-Null
        [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 300
        Show-Toast 'Η ενεργοποίηση ολοκληρώθηκε.' 1800 $false
    } catch {
        Show-Toast ("Σφάλμα ενεργοποίησης: " + $_.Exception.Message) 3000 $false
    } finally {
        $ProgressBar.Dispatcher.Invoke([action]{ $ProgressBar.IsIndeterminate = $false; $ProgressBar.Value = 0; $ProgressBar.Visibility = 'Collapsed' })
        $StatusTextBlock.Dispatcher.Invoke([action]{ $StatusTextBlock.Text = '' })
    }
}

# -------------------- Initialize Install page --------------------
function Initialize-InstallPage {
    if ($null -eq $AvailableApps -or $null -eq $SelectedApps) { return }
    $AvailableApps.Items.Clear()
    $script:DownloadLinks.Keys | Sort-Object | ForEach-Object { [void]$AvailableApps.Items.Add($_) }
    $SelectedApps.Items.Clear()
}

# -------------------- Install page events --------------------
if ($BtnAdd) {
    $null = $BtnAdd.Add_Click({
        $toAdd = @($AvailableApps.SelectedItems)
        foreach($i in $toAdd){
            if(-not $SelectedApps.Items.Contains($i)){
                [void]$SelectedApps.Items.Add($i)
            }
        }
    })
}
if ($BtnRemove) {
    $null = $BtnRemove.Add_Click({
        $toRemove = @($SelectedApps.SelectedItems)
        foreach($i in $toRemove){ $SelectedApps.Items.Remove($i) }
    })
}
if ($AvailableApps) {
    $null = $AvailableApps.Add_MouseDoubleClick({
        if($AvailableApps.SelectedItem){
            if(-not $SelectedApps.Items.Contains($AvailableApps.SelectedItem)){
                [void]$SelectedApps.Items.Add($AvailableApps.SelectedItem)
            }
        }
    })
}
if ($SelectedApps) {
    $null = $SelectedApps.Add_MouseDoubleClick({
        if($SelectedApps.SelectedItem){ $SelectedApps.Items.Remove($SelectedApps.SelectedItem) }
    })
}
if ($BtnDownload) {
    $null = $BtnDownload.Add_Click({
        $chosen = @()
        foreach($it in $SelectedApps.Items){ $chosen += [string]$it }
        if ($chosen.Count -eq 0) {
            $code = ([System.Windows.Controls.ComboBoxItem]$languageCombo.SelectedItem).Tag
            Show-Toast ($i18n[$code].noAppsSelected) 2000 $false
            return
        }
        try {
            Start-AppBatch -AppNames $chosen -ProgressBar $DownloadProgressBar -StatusTextBlock $StatusText -OwnerWindow $window
        } catch {
            $code = ([System.Windows.Controls.ComboBoxItem]$languageCombo.SelectedItem).Tag
            Show-Toast ($i18n[$code].installError + ": " + $_.Exception.Message) 3000 $false
        }
    })
}

 # Activate page events
 if ($AutoLoginBtn) {
     $null = $AutoLoginBtn.Add_Click({
         try {
             Invoke-AutoLogin -ProgressBar $ActivateProgressBar -StatusTextBlock $ActivateStatusText -OwnerWindow $window
         } catch {}
     })
 }
 if ($WinActivateBtn) {
     $null = $WinActivateBtn.Add_Click({
         try {
             Invoke-ActivateWindows -ProgressBar $ActivateProgressBar -StatusTextBlock $ActivateStatusText -OwnerWindow $window
         } catch {}
     })
 }

# -------------------- Maintenance page events --------------------
if ($DeleteTempBtn) {
    $null = $DeleteTempBtn.Add_Click({
        try {
            # Update UI to indicate deletion is starting
            if ($MaintenanceStatusText) { $MaintenanceStatusText.Text = 'Γίνεται καθαρισμός προσωρινών αρχείων...' }
            if ($MaintenanceProgressBar) {
                $MaintenanceProgressBar.Value = 0
                $MaintenanceProgressBar.IsIndeterminate = $true
                $MaintenanceProgressBar.Visibility = 'Visible'
            }
            # Remove files from %TEMP%, Windows\Temp and Prefetch directories
            Remove-Item -Path (Join-Path $env:TEMP '*') -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -Path (Join-Path $env:WinDir 'Temp\*') -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -Path (Join-Path $env:SystemRoot 'Prefetch\*') -Recurse -Force -ErrorAction SilentlyContinue
            # Update UI to indicate completion
            if ($MaintenanceProgressBar) {
                $MaintenanceProgressBar.IsIndeterminate = $false
                $MaintenanceProgressBar.Visibility = 'Collapsed'
                $MaintenanceProgressBar.Value = 100
            }
            if ($MaintenanceStatusText) { $MaintenanceStatusText.Text = 'Ο καθαρισμός προσωρινών αρχείων ολοκληρώθηκε.' }
        } catch {
            if ($MaintenanceProgressBar) {
                $MaintenanceProgressBar.IsIndeterminate = $false
                $MaintenanceProgressBar.Visibility = 'Collapsed'
            }
            if ($MaintenanceStatusText) { $MaintenanceStatusText.Text = "Σφάλμα καθαρισμού: $($_.Exception.Message)" }
        }
    })
}
# === System Scan (SFC + DISM) – interactive CMD, no redirects ===
# === System Scan (SFC + DISM) – CMD auto-close, app stays open, reliable UI update via Dispatcher ===
if ($null -ne $SystemScanBtn) {
    $null = $SystemScanBtn.Add_Click({
        try {
            # --- Admin check ---
            $id        = [Security.Principal.WindowsIdentity]::GetCurrent()
            $principal = New-Object Security.Principal.WindowsPrincipal($id)
            $isAdmin   = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
            if (-not $isAdmin) {
                [System.Windows.MessageBox]::Show(
                    "Παρακαλώ εκτελέστε την εφαρμογή ως Διαχειριστής.",
                    "Προσοχή",
                    [System.Windows.MessageBoxButton]::OK,
                    [System.Windows.MessageBoxImage]::Warning
                ) | Out-Null
                return
            }

            # --- UI: start state ---
            $uiDisp = [System.Windows.Application]::Current.Dispatcher
            if ($null -ne $uiDisp) {
                $uiDisp.Invoke([System.Action]{
                    if ($null -ne $MaintenanceProgressBar) {
                        $MaintenanceProgressBar.IsIndeterminate = $true
                        $MaintenanceProgressBar.Visibility = 'Visible'
                    }
                    if ($null -ne $MaintenanceStatusText) {
                        $MaintenanceStatusText.Text = "Εκτελείται SFC και DISM..."
                    }
                })
            }

            # --- Sentinel file ---
            $tempDir  = "C:\Temp"
            if (-not (Test-Path $tempDir)) { New-Item -ItemType Directory -Path $tempDir -Force | Out-Null }
            $sentinel = Join-Path $tempDir "systemscan.done"
            if (Test-Path $sentinel) { Remove-Item $sentinel -Force -ErrorAction SilentlyContinue }

            # --- Run CMD (visible), auto-close when done, then write sentinel ---
            $cmdLine = 'sfc /scannow & dism /online /cleanup-image /restorehealth & echo done> "C:\Temp\systemscan.done"'
            Start-Process -FilePath "cmd.exe" -ArgumentList "/c", $cmdLine -Verb RunAs -WindowStyle Normal | Out-Null

            # --- Reliable UI update: Timer polls sentinel, Dispatcher updates UI on the UI thread ---
            $timer = New-Object System.Timers.Timer
            $timer.Interval = 1000
            $timer.AutoReset = $true

            # .NET event (όχι Register-ObjectEvent) για να κρατήσουμε το ίδιο runspace
            $null = $timer.add_Elapsed({
                try {
                    if (Test-Path "C:\Temp\systemscan.done") {
                        $timer.Stop()

                        # ενημέρωση UI ΠΑΝΤΑ με Dispatcher του Application.Current (ίδιο UI thread)
                        $disp = [System.Windows.Application]::Current.Dispatcher
                        if ($null -ne $disp) {
                            $disp.Invoke([System.Action]{
                                if ($null -ne $MaintenanceProgressBar) {
                                    $MaintenanceProgressBar.IsIndeterminate = $false
                                    $MaintenanceProgressBar.Visibility = 'Collapsed'
                                }
                                if ($null -ne $MaintenanceStatusText) {
                                    $MaintenanceStatusText.Text = "Ολοκληρώθηκε!"
                                }
                            })
                        }

                        # καθάρισμα marker
                        Remove-Item "C:\Temp\systemscan.done" -Force -ErrorAction SilentlyContinue
                        $timer.Dispose()
                    }
                } catch {
                    # ignore
                }
            })
            $timer.Start()
        }
        catch {
            [System.Windows.MessageBox]::Show(
                "Σφάλμα: $($_.Exception.Message)",
                "Σφάλμα",
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Error
            ) | Out-Null

            $uiDisp = [System.Windows.Application]::Current.Dispatcher
            if ($null -ne $uiDisp) {
                $uiDisp.Invoke([System.Action]{
                    if ($null -ne $MaintenanceProgressBar) { $MaintenanceProgressBar.Visibility = 'Collapsed' }
                    if ($null -ne $MaintenanceStatusText)  { $MaintenanceStatusText.Text = "Σφάλμα εκτέλεσης." }
                })
            }
        }
    })
}


if ($DownloadPatchBtn) {
    $null = $DownloadPatchBtn.Add_Click({
        # Κατεβάζει το Patch My PC με πραγματικό progress και το τρέχει αμέσως μετά
        $url  = 'https://github.com/thomasthanos/Easy_your_Life_byAi/raw/refs/heads/main/apps/exe/patch_my_pc.exe'
        # Store Patch My PC under the Kolokithes A.E data folder rather than the temp folder
        $dest = Get-DownloadPath 'patch_my_pc.exe'

        try {
            # --- UI: Έναρξη ---
            if ($MaintenanceStatusText) {
                $MaintenanceStatusText.Dispatcher.Invoke([action]{ $MaintenanceStatusText.Text = 'Λήψη Patch My PC...' })
            }
            if ($MaintenanceProgressBar) {
                $MaintenanceProgressBar.Dispatcher.Invoke([action]{
                    $MaintenanceProgressBar.Value = 0
                    $MaintenanceProgressBar.IsIndeterminate = $true
                    $MaintenanceProgressBar.Visibility = 'Visible'
                })
            }

            # --- Λήψη με το υπάρχον helper για progress ---
            Start-AppFileDownload -Url $url -DestinationPath $dest -ProgressBar $MaintenanceProgressBar -StatusTextBlock $MaintenanceStatusText

            # --- Εκτέλεση (ως διαχειριστής) ---
            if ($MaintenanceStatusText) {
                $MaintenanceStatusText.Dispatcher.Invoke([action]{ $MaintenanceStatusText.Text = 'Εκτέλεση Patch My PC...' })
            }
            if ($MaintenanceProgressBar) {
                $MaintenanceProgressBar.Dispatcher.Invoke([action]{
                    $MaintenanceProgressBar.IsIndeterminate = $true
                    $MaintenanceProgressBar.Value = 0
                })
            }

            try {
                # Αν θες auto-mode χωρίς GUI, βάλε arguments π.χ. '/auto' (αν υποστηρίζεται)
                # $proc = Start-Process -FilePath $dest -ArgumentList '/auto' -Verb RunAs -PassThru
                $proc = Start-Process -FilePath $dest -Verb RunAs -PassThru
            } catch {
                throw "Αποτυχία εκτέλεσης ως διαχειριστής: $($_.Exception.Message)"
            }

            # Περιμένει να τελειώσει, κρατώντας το WPF responsive
            while (-not $proc.HasExited) {
                [System.Windows.Forms.Application]::DoEvents()
                Start-Sleep -Milliseconds 100
            }

            if ($MaintenanceStatusText) {
                $MaintenanceStatusText.Dispatcher.Invoke([action]{ $MaintenanceStatusText.Text = 'Patch My PC: ολοκληρώθηκε.' })
            }
            Show-Toast 'Patch My PC: ολοκληρώθηκε.' 1600 $false
        }
        catch {
            if ($MaintenanceStatusText) {
                $MaintenanceStatusText.Dispatcher.Invoke([action]{ $MaintenanceStatusText.Text = "Σφάλμα: $($_.Exception.Message)" })
            }
        }
        finally {
            if ($MaintenanceProgressBar) {
                $MaintenanceProgressBar.Dispatcher.Invoke([action]{
                    $MaintenanceProgressBar.IsIndeterminate = $false
                    $MaintenanceProgressBar.Visibility = 'Collapsed'
                    $MaintenanceProgressBar.Value = 0
                })
            }
            # Μην αφαιρείς το εκτελέσιμο· διατήρησέ το στο application data folder για μελλοντική χρήση
        }
    })
}

# -------------------- Sites/Games page button events --------------------
foreach ($btn in @($ThePirateCityBtn,$DownloadPirateBtn,$FileCRBtn,$RepackGamesBtn,$SteamUnlockedBtn,$SteamRipBtn,$FitGirlRepacksBtn,$OnlineFixBtn)) {
    if ($null -ne $btn) {
        $null = $btn.Add_Click({
            # Use custom parameter names to avoid clobbering the automatic `$sender`
            # variable.  `$src` represents the clicked button and `$evtArgs` holds
            # the event arguments.
            param($src, $evtArgs)
            try {
                # Use default browser to open the URL stored in the Tag property
                Start-Process -FilePath $src.Tag
            } catch {
                # Silently ignore any errors launching the URL
            }
        })
    }
}
# ===== Apps page: Download Manager state =====
# Λίστα εφαρμογών -> links (όπως στο WinForms)
$script:AppsDownloads = [ordered]@{
    'Clip Studio'      = 'https://www.dropbox.com/scl/fi/kx8gqow9zfian7g8ocqg3/Clip-Studio-Paint.zip?rlkey=wz4b7kfkchzgnsq9tpnp40rcw&dl=1'
    'Encoder'          = 'https://www.dropbox.com/scl/fi/mw4sk0dvdk2r8ux9g1lfc/encoder.zip?rlkey=qwnelw8d920jlum14n1x44zku&dl=1'
    'Illustrator'      = 'https://www.dropbox.com/scl/fi/aw95btp46onbyhk50gn7b/Illustrator.zip?rlkey=mvklovmenagfasuhr6clorbfj&dl=1'
    'Lightroom Classic'= 'https://www.dropbox.com/scl/fi/0p9rln704lc3qgqtjad9n/Lightroom-Classic.zip?rlkey=gp29smsg6t8oxhox80661k4gu&dl=1'
    'Office'           = 'https://www.dropbox.com/scl/fi/pcfv8ft3egcq4x6jzigny/Office2024.zip?rlkey=qbic04ie56dvoxzk1smri0hoo&dl=1'
    'Photoshop'        = 'https://www.dropbox.com/scl/fi/8vf3d46sq1wj1rb55r4jz/Photoshop.zip?rlkey=6u0dpbfnqopfndwcwq1082f7a&dl=1'
    'Premiere'         = 'https://www.dropbox.com/scl/fi/1yqqufgow2v4rc93l6wu4/premiere.zip?rlkey=49ymly6zgzufwtijnf2se35tc&dl=1'
}

# Downloads folder (όπως στο WinForms με shell:Downloads)
try {
    $sh  = New-Object -ComObject 'Shell.Application'
    $dlF = $sh.Namespace('shell:Downloads')
    $script:AppsDownloadPath = ($dlF.Self.Path.TrimEnd('\') + '\')
} catch {
    $script:AppsDownloadPath = [Environment]::GetFolderPath('MyDocuments') + '\Downloads\'
}
if (-not (Test-Path $script:AppsDownloadPath)) {
    New-Item -ItemType Directory -Force -Path $script:AppsDownloadPath | Out-Null
}

# Κατάσταση/clients ανά app για ακύρωση/cleanup
$script:AppsWebClients      = @{}
$script:AppsDownloadStatus  = @{}   # Pending/Downloading/Completed/Error
$script:AppsStarted         = New-Object System.Collections.ArrayList
$script:AppsDownloadsPanel  = $window.FindName('AppsButtonsPanel')
$script:AppsOverallProgress = $window.FindName('AppsOverallProgressBar')
$script:AppsStatusText      = $window.FindName('AppsStatusText')

# Init status
$script:AppsDownloads.Keys | ForEach-Object { $script:AppsDownloadStatus[$_] = 'Pending' }

function Update-AppsOverallProgress {
    $started = [int]$script:AppsStarted.Count
    if ($started -le 0) {
        if ($script:AppsOverallProgress) { 
            $script:AppsOverallProgress.Width = 0 
        }
        # When no downloads are in progress, display the localized "readyToDownload" status
        if ($script:AppsStatusText) { 
            $code = 'en'
            try {
                if ($languageCombo -and $languageCombo.SelectedItem) {
                    $code = ([System.Windows.Controls.ComboBoxItem]$languageCombo.SelectedItem).Tag
                }
            } catch {}
            if ($i18n.ContainsKey($code) -and $i18n[$code].ContainsKey('readyToDownload')) {
                $script:AppsStatusText.Text = $i18n[$code].readyToDownload
            } else {
                $script:AppsStatusText.Text = 'Ready to download'
            }
        }
        return
    }
    
    $completed = 0
    foreach ($k in $script:AppsStarted) {
        if ($script:AppsDownloadStatus[$k] -eq 'Completed') { $completed++ }
    }
    
    $pct = [math]::Round(($completed / [double]$started) * 100)
    
    try {
        # Update progress bar width
        if ($script:AppsOverallProgress -and $script:AppsOverallProgress.Parent.ActualWidth -gt 0) {
            $parentWidth = $script:AppsOverallProgress.Parent.ActualWidth
            $newWidth = ($pct / 100) * $parentWidth
            $script:AppsOverallProgress.Width = $newWidth
        }
        
        # Update status text (number of files downloaded). Use localized format string if available.
        if ($script:AppsStatusText) {
            $code = 'en'
            try {
                if ($languageCombo -and $languageCombo.SelectedItem) {
                    $code = ([System.Windows.Controls.ComboBoxItem]$languageCombo.SelectedItem).Tag
                }
            } catch {}
            if ($i18n.ContainsKey($code) -and $i18n[$code].ContainsKey('downloadedOf')) {
                $script:AppsStatusText.Text = [string]::Format($i18n[$code].downloadedOf, $completed, $started)
            } else {
                $script:AppsStatusText.Text = "Downloaded $completed of $started files"
            }
        }
    } catch {
        Write-Host "Error updating progress: $($_.Exception.Message)"
    }
}

function Initialize-AppsPageUI {
    if (-not $script:AppsDownloadsPanel) { return }
    $script:AppsDownloadsPanel.Children.Clear()
    foreach ($k in $script:AppsDownloads.Keys) {
        $btn = New-Object System.Windows.Controls.Button
        # Determine current language code for per-app download button label. Falls back to 'en' if language combo not found.
        $code = 'en'
        try {
            if ($languageCombo -and $languageCombo.SelectedItem) {
                $code = ([System.Windows.Controls.ComboBoxItem]$languageCombo.SelectedItem).Tag
            }
        } catch {}
        # Format the button content using the downloadAppBtn template from i18n. If the key is missing, default to "Download <AppName>".
        $template = if ($i18n.ContainsKey($code) -and $i18n[$code].ContainsKey('downloadAppBtn')) { $i18n[$code].downloadAppBtn } else { 'Download {0}' }
        $btn.Content = [string]::Format($template, $k)
        $btn.Tag     = $k
        $btn.Margin  = [System.Windows.Thickness]::new(6)
        try { $btn.Style = $window.FindResource('PillButton') } catch {}
        $null = $btn.Add_Click({
            param($src,$e)
            try { Start-AppDirectDownload -ItemName $src.Tag } catch {}
        })
        [void]$script:AppsDownloadsPanel.Children.Add($btn)
    }
    # Set initial status text to the localized "readyToDownload" string
    if ($script:AppsStatusText) {
        $code = 'en'
        try {
            if ($languageCombo -and $languageCombo.SelectedItem) {
                $code = ([System.Windows.Controls.ComboBoxItem]$languageCombo.SelectedItem).Tag
            }
        } catch {}
        if ($i18n.ContainsKey($code) -and $i18n[$code].ContainsKey('readyToDownload')) {
            $script:AppsStatusText.Text = $i18n[$code].readyToDownload
        } else {
            $script:AppsStatusText.Text = 'Ready to download'
        }
    }
    if ($script:AppsOverallProgress) {
        $script:AppsOverallProgress.Width = 0
    }
}

function Start-AppDirectDownload {
    param(
        [Parameter(Mandatory)][string]$ItemName
    )
    if ($script:AppsDownloadStatus[$ItemName] -ne 'Pending') { return }

    $url  = $script:AppsDownloads[$ItemName]
    $name = ($ItemName + '.zip')
    $dest = Join-Path $script:AppsDownloadPath $name

    # Create per-item WebClient
    $wc = New-Object System.Net.WebClient
    $script:AppsWebClients[$ItemName] = $wc

    # Add ItemName and dest as properties to the WebClient object
    $wc | Add-Member -MemberType NoteProperty -Name 'ItemName' -Value $ItemName
    $wc | Add-Member -MemberType NoteProperty -Name 'Destination' -Value $dest

    # Progress changed event handler
    $wc.Add_DownloadProgressChanged({
        param($psSender, $psEventArgs)
        try {
            if ($script:AppsStatusText) {
                $got = [math]::Round($psEventArgs.BytesReceived/1MB,2)
                $tot = if ($psEventArgs.TotalBytesToReceive -gt 0) { [math]::Round($psEventArgs.TotalBytesToReceive/1MB,2) } else { 0 }
                $pct = $psEventArgs.ProgressPercentage
                $script:AppsStatusText.Dispatcher.Invoke([action]{
                    $script:AppsStatusText.Text = "Downloading $($psSender.ItemName)... $pct`% ($got/$tot MB)"
                })
            }
        } catch {}
    })

    # Download completed event handler
    $wc.Add_DownloadFileCompleted({
        param($psSender, $psEventArgs)
        try {
            $itemName = $psSender.ItemName
            $destPath = $psSender.Destination
            
            if ($psEventArgs.Error) {
                $script:AppsDownloadStatus[$itemName] = 'Error'
                $script:AppsStatusText.Text = "Error downloading $($itemName): $($psEventArgs.Error.Message)"
            } else {
                $script:AppsDownloadStatus[$itemName] = 'Completed'
                $sizeMB = [math]::Round((Get-Item -LiteralPath $destPath).Length/1MB,2)
                $script:AppsStatusText.Dispatcher.Invoke([action]{ 
                    $script:AppsStatusText.Text = "$itemName downloaded successfully! ($sizeMB MB)`nLocation: $destPath" 
                })
            }
        } finally {
            try { $psSender.Dispose() } catch {}
            try { $script:AppsWebClients.Remove($itemName) } catch {}
            Update-AppsOverallProgress
        }
    })

    # Mark start
    if (-not $script:AppsStarted.Contains($ItemName)) { [void]$script:AppsStarted.Add($ItemName) }
    $script:AppsDownloadStatus[$ItemName] = 'Downloading'
    Update-AppsOverallProgress

    # Kick off async download
    try {
        $real = ConvertTo-DirectDownloadUrl -Url $url
        if ($script:AppsStatusText) {
            $script:AppsStatusText.Text = "Connecting: $ItemName..."
        }
        $wc.Headers.Add('User-Agent','Mozilla/5.0 (Windows NT 10.0; Win64; x64)')
        $wc.DownloadFileAsync($real, $dest)
    } catch {
        $script:AppsDownloadStatus[$ItemName] = 'Error'
        if ($script:AppsStatusText) { $script:AppsStatusText.Text = "Error: $($_.Exception.Message)" }
        try { $wc.Dispose() } catch {}
        try { $script:AppsWebClients.Remove($ItemName) } catch {}
        Update-AppsOverallProgress
    }
}




# Ακύρωση/cleanup όλων στο κλείσιμο του παραθύρου
$null = $window.Add_Closing({
    try {
        foreach ($wc in $script:AppsWebClients.Values) {
            try { $wc.CancelAsync(); $wc.Dispose() } catch {}
        }
        $script:AppsWebClients.Clear()
    } catch {}
})
















# -------------------- Initialize on load --------------------
$null = $window.Add_Loaded({ Initialize-InstallPage })

# -------------------- Run --------------------
$window.ShowDialog() | Out-Null

# SIG # Begin signature block
# MIIb7QYJKoZIhvcNAQcCoIIb3jCCG9oCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUBNx2c9lZ5arFxUkIac/k2Bdh
# b86gghZeMIIDIDCCAgigAwIBAgIQLdCLb+Qm6r9Ht8dEfMa9SjANBgkqhkiG9w0B
# AQsFADAaMRgwFgYDVQQDDA9Lb2xva2l0aGVzIEEuRS4wHhcNMjUwOTAzMDIwOTUw
# WhcNMjYwOTAzMDIxOTUwWjAaMRgwFgYDVQQDDA9Lb2xva2l0aGVzIEEuRS4wggEi
# MA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQDHDWhDQv2IJi78NWbyMKWeiYhq
# 1NP3AEh5tKihtAOCdoY0v+LQK4djxiQmyz98yFor5Eck1R4BuXxrE+d2H3n6K/jh
# V7lbdO6mZ2wDm/7NERXHcGfl7L/x7i9hv1SvGTTJ6rQCOajEWszJDKTz/FCoGTK7
# 58u9/4RWDahYu4Ts0szxpTYV/LmKkwoF+b+ZMg362huk9JKMX96PIDiRwdy/fvy4
# IES/WXVAQGrJDgZMnJCRImblaGwXSXW/Dsk+8OtLfwmTXJr+6sS/NzbrtTek3+76
# 9j5QqC0ylHOgwlRwoc5Er1+5leQ+lOa+G8F4zbXcKMqh0vBOcRed98OEhh/xAgMB
# AAGjYjBgMA4GA1UdDwEB/wQEAwIHgDATBgNVHSUEDDAKBggrBgEFBQcDAzAaBgNV
# HREEEzARgg9Lb2xva2l0aGVzIEEuRS4wHQYDVR0OBBYEFExwu9osP7sFKGFKHcbA
# pYWDO9tZMA0GCSqGSIb3DQEBCwUAA4IBAQAERp/tYHA67r/hKMhuEj9qaIRGSpQI
# vgFVIKargxJXrjhpkS72lbBJkjNEIz1n3IIOk+CoNoOnjXvVLmP51+DPRalMfkID
# x5lvY0Bemdtt/X4rUbV0Y1v2sJ1z+BO4k6KQKnk4BBu8lq37v/16dUZB8sZ0jt52
# M2gsom1cWzcfxbTD04af5I4e/HHUAt9Y7sEAsHquO1amYlmpFy07gjPnAGrHAoRv
# 5bxqHlA76KADkJLplaFE9j2wPcfW+uNQ1VJQkwPKXuwHD+/eJWeGS+G+JJdqU9nE
# wSmzummN4cMadx4tRqp8F+gb5LQ12rJxEvx5ZsvFCviPjPb9x8Ywx24RMIIFjTCC
# BHWgAwIBAgIQDpsYjvnQLefv21DiCEAYWjANBgkqhkiG9w0BAQwFADBlMQswCQYD
# VQQGEwJVUzEVMBMGA1UEChMMRGlnaUNlcnQgSW5jMRkwFwYDVQQLExB3d3cuZGln
# aWNlcnQuY29tMSQwIgYDVQQDExtEaWdpQ2VydCBBc3N1cmVkIElEIFJvb3QgQ0Ew
# HhcNMjIwODAxMDAwMDAwWhcNMzExMTA5MjM1OTU5WjBiMQswCQYDVQQGEwJVUzEV
# MBMGA1UEChMMRGlnaUNlcnQgSW5jMRkwFwYDVQQLExB3d3cuZGlnaWNlcnQuY29t
# MSEwHwYDVQQDExhEaWdpQ2VydCBUcnVzdGVkIFJvb3QgRzQwggIiMA0GCSqGSIb3
# DQEBAQUAA4ICDwAwggIKAoICAQC/5pBzaN675F1KPDAiMGkz7MKnJS7JIT3yithZ
# wuEppz1Yq3aaza57G4QNxDAf8xukOBbrVsaXbR2rsnnyyhHS5F/WBTxSD1Ifxp4V
# pX6+n6lXFllVcq9ok3DCsrp1mWpzMpTREEQQLt+C8weE5nQ7bXHiLQwb7iDVySAd
# YyktzuxeTsiT+CFhmzTrBcZe7FsavOvJz82sNEBfsXpm7nfISKhmV1efVFiODCu3
# T6cw2Vbuyntd463JT17lNecxy9qTXtyOj4DatpGYQJB5w3jHtrHEtWoYOAMQjdjU
# N6QuBX2I9YI+EJFwq1WCQTLX2wRzKm6RAXwhTNS8rhsDdV14Ztk6MUSaM0C/CNda
# SaTC5qmgZ92kJ7yhTzm1EVgX9yRcRo9k98FpiHaYdj1ZXUJ2h4mXaXpI8OCiEhtm
# mnTK3kse5w5jrubU75KSOp493ADkRSWJtppEGSt+wJS00mFt6zPZxd9LBADMfRyV
# w4/3IbKyEbe7f/LVjHAsQWCqsWMYRJUadmJ+9oCw++hkpjPRiQfhvbfmQ6QYuKZ3
# AeEPlAwhHbJUKSWJbOUOUlFHdL4mrLZBdd56rF+NP8m800ERElvlEFDrMcXKchYi
# Cd98THU/Y+whX8QgUWtvsauGi0/C1kVfnSD8oR7FwI+isX4KJpn15GkvmB0t9dmp
# sh3lGwIDAQABo4IBOjCCATYwDwYDVR0TAQH/BAUwAwEB/zAdBgNVHQ4EFgQU7Nfj
# gtJxXWRM3y5nP+e6mK4cD08wHwYDVR0jBBgwFoAUReuir/SSy4IxLVGLp6chnfNt
# yA8wDgYDVR0PAQH/BAQDAgGGMHkGCCsGAQUFBwEBBG0wazAkBggrBgEFBQcwAYYY
# aHR0cDovL29jc3AuZGlnaWNlcnQuY29tMEMGCCsGAQUFBzAChjdodHRwOi8vY2Fj
# ZXJ0cy5kaWdpY2VydC5jb20vRGlnaUNlcnRBc3N1cmVkSURSb290Q0EuY3J0MEUG
# A1UdHwQ+MDwwOqA4oDaGNGh0dHA6Ly9jcmwzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2Vy
# dEFzc3VyZWRJRFJvb3RDQS5jcmwwEQYDVR0gBAowCDAGBgRVHSAAMA0GCSqGSIb3
# DQEBDAUAA4IBAQBwoL9DXFXnOF+go3QbPbYW1/e/Vwe9mqyhhyzshV6pGrsi+Ica
# aVQi7aSId229GhT0E0p6Ly23OO/0/4C5+KH38nLeJLxSA8hO0Cre+i1Wz/n096ww
# epqLsl7Uz9FDRJtDIeuWcqFItJnLnU+nBgMTdydE1Od/6Fmo8L8vC6bp8jQ87PcD
# x4eo0kxAGTVGamlUsLihVo7spNU96LHc/RzY9HdaXFSMb++hUD38dglohJ9vytsg
# jTVgHAIDyyCwrFigDkBjxZgiwbJZ9VVrzyerbHbObyMt9H5xaiNrIv8SuFQtJ37Y
# OtnwtoeW/VvRXKwYw02fc7cBqZ9Xql4o4rmUMIIGtDCCBJygAwIBAgIQDcesVwX/
# IZkuQEMiDDpJhjANBgkqhkiG9w0BAQsFADBiMQswCQYDVQQGEwJVUzEVMBMGA1UE
# ChMMRGlnaUNlcnQgSW5jMRkwFwYDVQQLExB3d3cuZGlnaWNlcnQuY29tMSEwHwYD
# VQQDExhEaWdpQ2VydCBUcnVzdGVkIFJvb3QgRzQwHhcNMjUwNTA3MDAwMDAwWhcN
# MzgwMTE0MjM1OTU5WjBpMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNlcnQs
# IEluYy4xQTA/BgNVBAMTOERpZ2lDZXJ0IFRydXN0ZWQgRzQgVGltZVN0YW1waW5n
# IFJTQTQwOTYgU0hBMjU2IDIwMjUgQ0ExMIICIjANBgkqhkiG9w0BAQEFAAOCAg8A
# MIICCgKCAgEAtHgx0wqYQXK+PEbAHKx126NGaHS0URedTa2NDZS1mZaDLFTtQ2oR
# jzUXMmxCqvkbsDpz4aH+qbxeLho8I6jY3xL1IusLopuW2qftJYJaDNs1+JH7Z+Qd
# SKWM06qchUP+AbdJgMQB3h2DZ0Mal5kYp77jYMVQXSZH++0trj6Ao+xh/AS7sQRu
# QL37QXbDhAktVJMQbzIBHYJBYgzWIjk8eDrYhXDEpKk7RdoX0M980EpLtlrNyHw0
# Xm+nt5pnYJU3Gmq6bNMI1I7Gb5IBZK4ivbVCiZv7PNBYqHEpNVWC2ZQ8BbfnFRQV
# ESYOszFI2Wv82wnJRfN20VRS3hpLgIR4hjzL0hpoYGk81coWJ+KdPvMvaB0WkE/2
# qHxJ0ucS638ZxqU14lDnki7CcoKCz6eum5A19WZQHkqUJfdkDjHkccpL6uoG8pbF
# 0LJAQQZxst7VvwDDjAmSFTUms+wV/FbWBqi7fTJnjq3hj0XbQcd8hjj/q8d6ylgx
# CZSKi17yVp2NL+cnT6Toy+rN+nM8M7LnLqCrO2JP3oW//1sfuZDKiDEb1AQ8es9X
# r/u6bDTnYCTKIsDq1BtmXUqEG1NqzJKS4kOmxkYp2WyODi7vQTCBZtVFJfVZ3j7O
# gWmnhFr4yUozZtqgPrHRVHhGNKlYzyjlroPxul+bgIspzOwbtmsgY1MCAwEAAaOC
# AV0wggFZMBIGA1UdEwEB/wQIMAYBAf8CAQAwHQYDVR0OBBYEFO9vU0rp5AZ8esri
# kFb2L9RJ7MtOMB8GA1UdIwQYMBaAFOzX44LScV1kTN8uZz/nupiuHA9PMA4GA1Ud
# DwEB/wQEAwIBhjATBgNVHSUEDDAKBggrBgEFBQcDCDB3BggrBgEFBQcBAQRrMGkw
# JAYIKwYBBQUHMAGGGGh0dHA6Ly9vY3NwLmRpZ2ljZXJ0LmNvbTBBBggrBgEFBQcw
# AoY1aHR0cDovL2NhY2VydHMuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0VHJ1c3RlZFJv
# b3RHNC5jcnQwQwYDVR0fBDwwOjA4oDagNIYyaHR0cDovL2NybDMuZGlnaWNlcnQu
# Y29tL0RpZ2lDZXJ0VHJ1c3RlZFJvb3RHNC5jcmwwIAYDVR0gBBkwFzAIBgZngQwB
# BAIwCwYJYIZIAYb9bAcBMA0GCSqGSIb3DQEBCwUAA4ICAQAXzvsWgBz+Bz0RdnEw
# vb4LyLU0pn/N0IfFiBowf0/Dm1wGc/Do7oVMY2mhXZXjDNJQa8j00DNqhCT3t+s8
# G0iP5kvN2n7Jd2E4/iEIUBO41P5F448rSYJ59Ib61eoalhnd6ywFLerycvZTAz40
# y8S4F3/a+Z1jEMK/DMm/axFSgoR8n6c3nuZB9BfBwAQYK9FHaoq2e26MHvVY9gCD
# A/JYsq7pGdogP8HRtrYfctSLANEBfHU16r3J05qX3kId+ZOczgj5kjatVB+NdADV
# ZKON/gnZruMvNYY2o1f4MXRJDMdTSlOLh0HCn2cQLwQCqjFbqrXuvTPSegOOzr4E
# Wj7PtspIHBldNE2K9i697cvaiIo2p61Ed2p8xMJb82Yosn0z4y25xUbI7GIN/TpV
# fHIqQ6Ku/qjTY6hc3hsXMrS+U0yy+GWqAXam4ToWd2UQ1KYT70kZjE4YtL8Pbzg0
# c1ugMZyZZd/BdHLiRu7hAWE6bTEm4XYRkA6Tl4KSFLFk43esaUeqGkH/wyW4N7Oi
# gizwJWeukcyIPbAvjSabnf7+Pu0VrFgoiovRDiyx3zEdmcif/sYQsfch28bZeUz2
# rtY/9TCA6TD8dC3JE3rYkrhLULy7Dc90G6e8BlqmyIjlgp2+VqsS9/wQD7yFylIz
# 0scmbKvFoW2jNrbM1pD2T7m3XDCCBu0wggTVoAMCAQICEAqA7xhLjfEFgtHEdqeV
# dGgwDQYJKoZIhvcNAQELBQAwaTELMAkGA1UEBhMCVVMxFzAVBgNVBAoTDkRpZ2lD
# ZXJ0LCBJbmMuMUEwPwYDVQQDEzhEaWdpQ2VydCBUcnVzdGVkIEc0IFRpbWVTdGFt
# cGluZyBSU0E0MDk2IFNIQTI1NiAyMDI1IENBMTAeFw0yNTA2MDQwMDAwMDBaFw0z
# NjA5MDMyMzU5NTlaMGMxCzAJBgNVBAYTAlVTMRcwFQYDVQQKEw5EaWdpQ2VydCwg
# SW5jLjE7MDkGA1UEAxMyRGlnaUNlcnQgU0hBMjU2IFJTQTQwOTYgVGltZXN0YW1w
# IFJlc3BvbmRlciAyMDI1IDEwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoIC
# AQDQRqwtEsae0OquYFazK1e6b1H/hnAKAd/KN8wZQjBjMqiZ3xTWcfsLwOvRxUwX
# cGx8AUjni6bz52fGTfr6PHRNv6T7zsf1Y/E3IU8kgNkeECqVQ+3bzWYesFtkepEr
# vUSbf+EIYLkrLKd6qJnuzK8Vcn0DvbDMemQFoxQ2Dsw4vEjoT1FpS54dNApZfKY6
# 1HAldytxNM89PZXUP/5wWWURK+IfxiOg8W9lKMqzdIo7VA1R0V3Zp3DjjANwqAf4
# lEkTlCDQ0/fKJLKLkzGBTpx6EYevvOi7XOc4zyh1uSqgr6UnbksIcFJqLbkIXIPb
# cNmA98Oskkkrvt6lPAw/p4oDSRZreiwB7x9ykrjS6GS3NR39iTTFS+ENTqW8m6TH
# uOmHHjQNC3zbJ6nJ6SXiLSvw4Smz8U07hqF+8CTXaETkVWz0dVVZw7knh1WZXOLH
# gDvundrAtuvz0D3T+dYaNcwafsVCGZKUhQPL1naFKBy1p6llN3QgshRta6Eq4B40
# h5avMcpi54wm0i2ePZD5pPIssoszQyF4//3DoK2O65Uck5Wggn8O2klETsJ7u8xE
# ehGifgJYi+6I03UuT1j7FnrqVrOzaQoVJOeeStPeldYRNMmSF3voIgMFtNGh86w3
# ISHNm0IaadCKCkUe2LnwJKa8TIlwCUNVwppwn4D3/Pt5pwIDAQABo4IBlTCCAZEw
# DAYDVR0TAQH/BAIwADAdBgNVHQ4EFgQU5Dv88jHt/f3X85FxYxlQQ89hjOgwHwYD
# VR0jBBgwFoAU729TSunkBnx6yuKQVvYv1Ensy04wDgYDVR0PAQH/BAQDAgeAMBYG
# A1UdJQEB/wQMMAoGCCsGAQUFBwMIMIGVBggrBgEFBQcBAQSBiDCBhTAkBggrBgEF
# BQcwAYYYaHR0cDovL29jc3AuZGlnaWNlcnQuY29tMF0GCCsGAQUFBzAChlFodHRw
# Oi8vY2FjZXJ0cy5kaWdpY2VydC5jb20vRGlnaUNlcnRUcnVzdGVkRzRUaW1lU3Rh
# bXBpbmdSU0E0MDk2U0hBMjU2MjAyNUNBMS5jcnQwXwYDVR0fBFgwVjBUoFKgUIZO
# aHR0cDovL2NybDMuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0VHJ1c3RlZEc0VGltZVN0
# YW1waW5nUlNBNDA5NlNIQTI1NjIwMjVDQTEuY3JsMCAGA1UdIAQZMBcwCAYGZ4EM
# AQQCMAsGCWCGSAGG/WwHATANBgkqhkiG9w0BAQsFAAOCAgEAZSqt8RwnBLmuYEHs
# 0QhEnmNAciH45PYiT9s1i6UKtW+FERp8FgXRGQ/YAavXzWjZhY+hIfP2JkQ38U+w
# tJPBVBajYfrbIYG+Dui4I4PCvHpQuPqFgqp1PzC/ZRX4pvP/ciZmUnthfAEP1HSh
# TrY+2DE5qjzvZs7JIIgt0GCFD9ktx0LxxtRQ7vllKluHWiKk6FxRPyUPxAAYH2Vy
# 1lNM4kzekd8oEARzFAWgeW3az2xejEWLNN4eKGxDJ8WDl/FQUSntbjZ80FU3i54t
# px5F/0Kr15zW/mJAxZMVBrTE2oi0fcI8VMbtoRAmaaslNXdCG1+lqvP4FbrQ6IwS
# BXkZagHLhFU9HCrG/syTRLLhAezu/3Lr00GrJzPQFnCEH1Y58678IgmfORBPC1JK
# kYaEt2OdDh4GmO0/5cHelAK2/gTlQJINqDr6JfwyYHXSd+V08X1JUPvB4ILfJdmL
# +66Gp3CSBXG6IwXMZUXBhtCyIaehr0XkBoDIGMUG1dUtwq1qmcwbdUfcSYCn+Own
# cVUXf53VJUNOaMWMts0VlRYxe5nK+At+DI96HAlXHAL5SlfYxJ7La54i71McVWRP
# 66bW+yERNpbJCjyCYG2j+bdpxo/1Cy4uPcU3AWVPGrbn5PhDBf3Froguzzhk++am
# i+r3Qrx5bIbY3TVzgiFI7Gq3zWcxggT5MIIE9QIBATAuMBoxGDAWBgNVBAMMD0tv
# bG9raXRoZXMgQS5FLgIQLdCLb+Qm6r9Ht8dEfMa9SjAJBgUrDgMCGgUAoHgwGAYK
# KwYBBAGCNwIBDDEKMAigAoAAoQKAADAZBgkqhkiG9w0BCQMxDAYKKwYBBAGCNwIB
# BDAcBgorBgEEAYI3AgELMQ4wDAYKKwYBBAGCNwIBFTAjBgkqhkiG9w0BCQQxFgQU
# cGhPseGY5tZwGckjAc6c01Bk6MowDQYJKoZIhvcNAQEBBQAEggEALuUdW+pyIQkK
# hEFLzpALKy1Nm3V6enIgg0Hkk3ozEQ5S1vQGw8USkTeUc8J5Zkq+djhwrudlLBO0
# PZTNT33g4+YwsEajMeVqH1RfjHH1KdTtBjbRJHuPxFUB9StWKCEpUI4MFI3BKsXa
# MsSjvH58sqmZucIxbdXH57gM5UkP3e3vvCBYyjGoN833dTvCOsiYZrZ1CmyuM8EM
# YOpYnlMkp/FEVGW6B04AV5J4HrPkKBGtFgP7mi41unjkmeG+UyZK5ANA0PsUTtvG
# x1SnraSRm6y7rXFXzWr9/1VVAGj29MtjNKnSWE3umlRLHciE9irh9zksgxaYUZE0
# oIWVADsYU6GCAyYwggMiBgkqhkiG9w0BCQYxggMTMIIDDwIBATB9MGkxCzAJBgNV
# BAYTAlVTMRcwFQYDVQQKEw5EaWdpQ2VydCwgSW5jLjFBMD8GA1UEAxM4RGlnaUNl
# cnQgVHJ1c3RlZCBHNCBUaW1lU3RhbXBpbmcgUlNBNDA5NiBTSEEyNTYgMjAyNSBD
# QTECEAqA7xhLjfEFgtHEdqeVdGgwDQYJYIZIAWUDBAIBBQCgaTAYBgkqhkiG9w0B
# CQMxCwYJKoZIhvcNAQcBMBwGCSqGSIb3DQEJBTEPFw0yNTA5MDMwMjIwMjNaMC8G
# CSqGSIb3DQEJBDEiBCC+eSrbay+MWJF7sdzA7doy8E3pn+ZVWlwNVE30DCggnDAN
# BgkqhkiG9w0BAQEFAASCAgB1nMjzF6r4zqimtNfwyouJcoHATt+BFYNix+revQXn
# VlOn3gx8XDJWnHa/Gdnct9fvSE/bPwXzbJV3Kbw9rGhBcTBt269iXBrHUs+ED8GI
# b8uMWazFOGLXZ2NeJ22o5MzpUEx/eLuKMf6/3nNYKm6N7f9j457n0Z098JZJGgFp
# GwT4rbjf3xfFvwXuXbhEhucsx9uQxRweRnSl4V1VFhl36h9Ub5vaAtX4j7giLrEH
# /5nC3Ne1asGEHMj1V48Rbq55NXxcF4TddokkNdSAev0L2JwEKJWEBKGPz2J9NmC4
# t49Xxh5DWxApBEqJH182PgOfMz1P2zB69pZqmEXozJm7zc4hB6qnLR0QdQW+eB3M
# XJuDE4YRI43xNIacRpHu6Gt7cNJNYCTPTSduKytwJ6uR9sYrssxqHPLyp8+rnwNM
# QxKnDt+6qP0Ht1U+OT/0bGdOxTDQuLj16mVbr8z6fHSg1h99eQwSxAIJa67lI0Ml
# 51YpGCZkcOpspXWjPohcazTkjMAqf3bmmhoip4kJsbhFki+dzV7k7GM/+eYxGfTE
# RZGRIKI96wGx9crENT/feYGP6Zv8EWRLlVkhyv2qOPU0J7j28LMx/qole6i8vMk3
# lxACLFzqm+DvClLjyK6emUz0o8oFveDHKfZGmPnU6ahqqhMLbg+kyN3k1qfP8Ynm
# gg==
# SIG # End signature block
