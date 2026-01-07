<#
.SYNOPSIS
    Framework de maintenance automatisée pour Windows 10/11.
.DESCRIPTION
    Nettoyage WinSxS, purge des fichiers temporaires et gestion des mises à jour Cloud.
#>

$Header = @"
*****************************************************************
* SYSTEM MAINTENANCE & UPDATE FRAMEWORK v2.0           *
* Status: Administrator Mode | Target: Enterprise      *
*****************************************************************
"@

Clear-Host
Write-Host $Header -ForegroundColor Cyan

# --- 1. INITIALISATION ET RÉPARATION RÉSEAU ---
Write-Host "`n[STEP 1] Initialisation de la connectivité..." -ForegroundColor White -BackgroundColor Blue
# Correction des erreurs GPO/WSUS identifiées
$GPOPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
if (Test-Path $GPOPath) { 
    Remove-Item -Path $GPOPath -Recurse -Force -ErrorAction SilentlyContinue 
    Write-Host " -> Restrictions d'organisation supprimées." -ForegroundColor Green
}
netsh winhttp reset proxy | Out-Null
Restart-Service -Name wuauserv -Force

# --- 2. GESTION DES MISES À JOUR (CLOUD) ---
Write-Host "`n[STEP 2] Analyse des mises à jour Windows..." -ForegroundColor White -BackgroundColor Blue
try {
    $UpdateSession = New-Object -ComObject Microsoft.Update.Session
    $Searcher = $UpdateSession.CreateUpdateSearcher()
    $Searcher.ServerSelection = 2 # Force le passage par Internet (Cloud)
    
    $Result = $Searcher.Search("IsInstalled=0 and IsHidden=0")
    $Count = $Result.Updates.Count

    if ($Count -gt 0) {
        Write-Host " -> $Count mise(s) à jour critique(s) détectée(s)." -ForegroundColor Yellow
        $Confirm = Read-Host "Souhaitez-vous procéder à l'installation ? (O/N)"
        if ($Confirm -match "O") {
            $Collection = New-Object -ComObject Microsoft.Update.UpdateColl
            $Result.Updates | ForEach-Object { $Collection.Add($_) | Out-Null }

            Write-Progress -Activity "Installation en cours..." -Status "Traitement des paquets..." -PercentComplete 50
            $Installer = $UpdateSession.CreateUpdateInstaller()
            $Installer.Updates = $Collection
            $Final = $Installer.Install()
            Write-Host " -> Installation terminée (Code: $($Final.ResultCode))." -ForegroundColor Green
        }
    } else { Write-Host " -> Le système est parfaitement à jour." -ForegroundColor Green }
} catch { Write-Host " -> Erreur lors de la recherche : $($_.Exception.Message)" -ForegroundColor Red }

# --- 3. NETTOYAGE PROFOND (WINSXS & DISM) ---
Write-Host "`n[STEP 3] Optimisation du Magasin des Composants (WinSxS)..." -ForegroundColor White -BackgroundColor Blue
Write-Host " -> Analyse de l'espace disque..." -ForegroundColor Gray
Dism.exe /Online /Cleanup-Image /AnalyzeComponentStore

Write-Host " -> Nettoyage approfondi (StartComponentCleanup /ResetBase)..." -ForegroundColor Gray
Dism.exe /Online /Cleanup-Image /StartComponentCleanup /ResetBase
Write-Host " -> Magasin WinSxS optimisé." -ForegroundColor Green

# --- 4. PURGE DES FICHIERS TEMPORAIRES ---
Write-Host "`n[STEP 4] Purge des fichiers résiduels et Corbeille..." -ForegroundColor White -BackgroundColor Blue
$Targets = @("$env:TEMP\*", "$env:WinDir\Temp\*", "$env:WinDir\Prefetch\*")
foreach ($T in $Targets) {
    Remove-Item -Path $T -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host " -> Purge effectuée : $T" -ForegroundColor Gray
}
Clear-RecycleBin -Force -ErrorAction SilentlyContinue
Write-Host " -> Corbeille vidée." -ForegroundColor Green

# --- 5. CLÔTURE ---
Write-Host "`n*****************************************************************" -ForegroundColor Cyan
Write-Host "   MAINTENANCE TERMINÉE - SYSTÈME OPTIMISÉ" -ForegroundColor Cyan
Write-Host "*****************************************************************" -ForegroundColor Cyan
Read-Host "Appuyez sur Entrée pour quitter"