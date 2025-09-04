<#
    Additional UI assignments for new i18n keys.
    Import this script at the end of Set-Language to apply translations
    to the newly introduced pages (Spotify/Spicetify, Password Manager,
    Chris Titus Tools and Sims DLC Tools) and updated controls on the
    Install/Apps page.
    Use: after calling `$t = $i18n[$code]`, dot‑source this file or
    paste the contents into your `Set-Language` function.
#>

# Sidebar buttons for new pages
if ($spotifyBtn)         { $spotifyBtn.Content         = $t.spotify }
if ($passwordManagerBtn) { $passwordManagerBtn.Content = $t.passwordManager }
if ($chrisTitusBtn)      { $chrisTitusBtn.Content      = $t.chrisTitus }
if ($simsBtn)            { $simsBtn.Content            = $t.sims }

# Spotify/Spicetify page
$spTitle  = $window.FindName('SpotifyTitle')
if ($spTitle) { $spTitle.Text = $t.spotifyTitle }
if ($SpicetifyInstallBtn)       { $SpicetifyInstallBtn.Content       = $t.spicetifyInstallBtn }
if ($SpicetifyUninstallBtn)     { $SpicetifyUninstallBtn.Content     = $t.spicetifyUninstallBtn }
if ($SpicetifyFullUninstallBtn) { $SpicetifyFullUninstallBtn.Content = $t.spicetifyFullUninstallBtn }
if ($SpicetifyStatusLabel)      { $SpicetifyStatusLabel.Text        = $t.ready }

# Password Manager page
$pmTitle = $window.FindName('PasswordManagerTitle')
if ($pmTitle) { $pmTitle.Text = $t.passwordManagerTitle }
$pmDesc  = $window.FindName('PasswordManagerDesc')
if ($pmDesc)  { $pmDesc.Text  = $t.passwordManagerDesc }
if ($OpenPasswordManagerBtn) { $OpenPasswordManagerBtn.Content = $t.openPasswordManager }

# Chris Titus Tools page
$ctTitle = $window.FindName('ChrisTitusTitle')
if ($ctTitle) { $ctTitle.Text = $t.chrisTitusTitle }
$ctDesc  = $window.FindName('ChrisTitusDesc')
if ($ctDesc)  { $ctDesc.Text  = $t.chrisTitusDesc }
if ($RunChrisTitusBtn) { $RunChrisTitusBtn.Content = $t.runChrisTitus }

# Sims DLC Tools page
$simsTitle = $window.FindName('SimsTitle')
if ($simsTitle) { $simsTitle.Text = $t.simsTitle }
$simsDesc  = $window.FindName('SimsDesc')
if ($simsDesc)  { $simsDesc.Text  = $t.simsDesc }
if ($RunSimsDlcBtn) { $RunSimsDlcBtn.Content = $t.runSimsTools }

# Install/Apps page controls
if ($BtnAdd)      { $BtnAdd.Content      = $t.addBtn }
if ($BtnRemove)   { $BtnRemove.Content   = $t.removeBtn }
if ($BtnDownload) { $BtnDownload.Content = $t.downloadInstallBtn }

# Apps downloads page labels and status
$availLbl   = $window.FindName('AvailableLabel')
if ($availLbl) { $availLbl.Text = $t.availableLabel }
$selLbl     = $window.FindName('SelectedLabel')
if ($selLbl) { $selLbl.Text = $t.selectedLabel }
$progressTitle = $window.FindName('AppsProgressTitle')
if ($progressTitle) { $progressTitle.Text = $t.appsProgressTitle }

# Maintenance & download page buttons
if ($DeleteTempBtn)   { $DeleteTempBtn.Content   = $t.cleanTempBtn }
if ($SystemScanBtn)   { $SystemScanBtn.Content   = $t.systemScanBtn }
if ($DownloadPatchBtn){ $DownloadPatchBtn.Content = $t.patchMyPcBtn }

# Maintenance page titles and descriptions
$mTempTitle = $window.FindName('MaintenanceTempTitle')
if ($mTempTitle) { $mTempTitle.Text = $t.cleanTempTitle }
$mTempDesc  = $window.FindName('MaintenanceTempDesc')
if ($mTempDesc)  { $mTempDesc.Text  = $t.cleanTempDesc }
$mScanTitle = $window.FindName('MaintenanceScanTitle')
if ($mScanTitle) { $mScanTitle.Text = $t.systemScanTitle }
$mScanDesc  = $window.FindName('MaintenanceScanDesc')
if ($mScanDesc)  { $mScanDesc.Text  = $t.systemScanDesc }
$pmTitle    = $window.FindName('PatchMyPcTitle')
if ($pmTitle)    { $pmTitle.Text    = $t.patchMyPcTitle }
$pmDesc     = $window.FindName('PatchMyPcDesc')
if ($pmDesc)     { $pmDesc.Text     = $t.patchMyPcDesc }

# Quick launch titles and descriptions (Password Manager & Chris Titus)
$pmQLTitle = $window.FindName('PmQuickLaunchTitle')
if ($pmQLTitle) { $pmQLTitle.Text = $t.quickStart }
$pmQLDesc  = $window.FindName('PmQuickLaunchDesc')
if ($pmQLDesc)  { $pmQLDesc.Text  = $t.passwordManagerNote }
$ctQLTitle = $window.FindName('ChrisTitusQuickLaunchTitle')
if ($ctQLTitle) { $ctQLTitle.Text = $t.quickStart }
$ctQLDesc  = $window.FindName('ChrisTitusQuickLaunchDesc')
if ($ctQLDesc)  { $ctQLDesc.Text  = $t.chrisTitusNote }

# Info panel cards titles and descriptions
$infoPwTitle = $window.FindName('InfoPwMgrTitle')
if ($infoPwTitle) { $infoPwTitle.Text = $t.infoPwMgrTitle }
$infoPwDesc  = $window.FindName('InfoPwMgrDesc')
if ($infoPwDesc)  { $infoPwDesc.Text  = $t.infoPwMgrDesc }

$infoSimsTitle = $window.FindName('InfoSimsTitle')
if ($infoSimsTitle) { $infoSimsTitle.Text = $t.infoSimsTitle }
$infoSimsDesc  = $window.FindName('InfoSimsDesc')
if ($infoSimsDesc)  { $infoSimsDesc.Text  = $t.infoSimsDesc }

$infoWinUtilTitle = $window.FindName('InfoWindowsUtilitiesTitle')
if ($infoWinUtilTitle) { $infoWinUtilTitle.Text = $t.infoWindowsUtilitiesTitle }
$infoWinUtilDesc  = $window.FindName('InfoWindowsUtilitiesDesc')
if ($infoWinUtilDesc)  { $infoWinUtilDesc.Text  = $t.infoWindowsUtilitiesDesc }

$infoPubInstTitle = $window.FindName('InfoPublicInstallersTitle')
if ($infoPubInstTitle) { $infoPubInstTitle.Text = $t.infoPublicInstallersTitle }
$infoPubInstDesc  = $window.FindName('InfoPublicInstallersDesc')
if ($infoPubInstDesc)  { $infoPubInstDesc.Text  = $t.infoPublicInstallersDesc }

$infoClearTempTitle = $window.FindName('InfoClearTempTitle')
if ($infoClearTempTitle) { $infoClearTempTitle.Text = $t.infoClearTempTitle }
$infoClearTempDesc  = $window.FindName('InfoClearTempDesc')
if ($infoClearTempDesc)  { $infoClearTempDesc.Text  = $t.infoClearTempDesc }

$infoCrackSitesTitle = $window.FindName('InfoCrackSitesTitle')
if ($infoCrackSitesTitle) { $infoCrackSitesTitle.Text = $t.infoCrackSitesTitle }
$infoCrackSitesDesc  = $window.FindName('InfoCrackSitesDesc')
if ($infoCrackSitesDesc)  { $infoCrackSitesDesc.Text  = $t.infoCrackSitesDesc }

$infoMultitoolTitle = $window.FindName('InfoMultitoolTitle')
if ($infoMultitoolTitle) { $infoMultitoolTitle.Text = $t.infoMultitoolTitle }
$infoMultitoolDesc  = $window.FindName('InfoMultitoolDesc')
if ($infoMultitoolDesc)  { $infoMultitoolDesc.Text  = $t.infoMultitoolDesc }

$infoCustomMsgBoxTitle = $window.FindName('InfoCustomMsgBoxTitle')
if ($infoCustomMsgBoxTitle) { $infoCustomMsgBoxTitle.Text = $t.infoCustomMsgBoxTitle }
$infoCustomMsgBoxDesc  = $window.FindName('InfoCustomMsgBoxDesc')
if ($infoCustomMsgBoxDesc)  { $infoCustomMsgBoxDesc.Text  = $t.infoCustomMsgBoxDesc }

# Sims DLC page translations
$siBtn    = $window.FindName('SimsInstallBtn')
if ($siBtn) { $siBtn.Content = $t.simsInstallBtn }
$suBtn    = $window.FindName('SimsUnlockerBtn')
if ($suBtn) { $suBtn.Content = $t.simsUnlockerBtn }
$snTitle  = $window.FindName('SimsNoteTitle')
if ($snTitle) { $snTitle.Text = $t.simsNoteTitle }
$snDesc   = $window.FindName('SimsNoteDesc')
if ($snDesc) { $snDesc.Text = $t.simsNoteDesc }
$stLabel  = $window.FindName('SimsTutorialLabel')
if ($stLabel) { $stLabel.Text = $t.simsTutorialLabel }