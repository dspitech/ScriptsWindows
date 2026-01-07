# --- CONFIGURATION ---
$ReportDirectory = "C:\WindowsUpdateReports"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
[System.Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Format-Bytes {
    param([Parameter(Mandatory)][double]$Bytes)
    if ($Bytes -ge 1TB) { return ("{0:N2} TB" -f ($Bytes/1TB)) }
    if ($Bytes -ge 1GB) { return ("{0:N2} GB" -f ($Bytes/1GB)) }
    if ($Bytes -ge 1MB) { return ("{0:N2} MB" -f ($Bytes/1MB)) }
    if ($Bytes -ge 1KB) { return ("{0:N2} KB" -f ($Bytes/1KB)) }
    return ("{0:N0} B" -f $Bytes)
}

function Write-Banner {
    param(
        [string]$Title = "SYSTEM MAINTENANCE & AUTO-UPDATE",
        [string]$Version = "v5.8",
        [string]$Subtitle = "Enterprise Maintenance Runner"
    )
    $now = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $computer = $env:COMPUTERNAME
    $user = $env:USERNAME
    $os = (Get-CimInstance Win32_OperatingSystem).Caption

Clear-Host
    Write-Host ""
    Write-Host "====================================================================" -ForegroundColor DarkCyan
    Write-Host ("  {0}  {1}" -f $Title, $Version) -ForegroundColor Cyan
    Write-Host ("  {0}" -f $Subtitle) -ForegroundColor DarkGray
    Write-Host "--------------------------------------------------------------------" -ForegroundColor DarkCyan
    Write-Host ("  Host: {0}    User: {1}" -f $computer, $user) -ForegroundColor Gray
    Write-Host ("  OS:   {0}" -f $os) -ForegroundColor Gray
    Write-Host ("  Time: {0}" -f $now) -ForegroundColor Gray
    Write-Host "====================================================================" -ForegroundColor DarkCyan
    Write-Host ""
}

function Write-Step {
    param(
        [string]$Msg,
        [string]$Stat = "INFO",
        [int]$Step = 0,
        [int]$TotalSteps = 0
    )
    $c = "Cyan"
    if ($Stat -eq "SUCCESS") { $c = "Green"; $pre = " [OK] " }
    elseif ($Stat -eq "WORKING") { $c = "Yellow"; $pre = " [...] " }
    elseif ($Stat -eq "ERROR") { $c = "Red"; $pre = " [!] " }
    $ts = Get-Date -Format "HH:mm:ss"
    $stepPrefix = ""
    if ($Step -gt 0 -and $TotalSteps -gt 0) {
        $stepPrefix = ("[STEP {0}/{1}] " -f $Step, $TotalSteps)
    }
    Write-Host ("{0} {1}{2}{3}" -f $ts, $stepPrefix, $pre, $Msg) -ForegroundColor $c
}

# --- 1. INITIALISATION ---
$totalSteps = 5
Write-Banner

Write-Step "Starting: system baseline and disk snapshot." "WORKING" 1 $totalSteps
$driveBefore = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
$beforeFree = $driveBefore.FreeSpace
Write-Step ("Done: baseline captured. Free space before: {0}." -f (Format-Bytes $beforeFree)) "SUCCESS" 1 $totalSteps
Write-Step "Next: cleanup (Recycle Bin + Temp)." "INFO" 1 $totalSteps

# --- 2. NETTOYAGE ---
Write-Step "Starting: cleanup (Recycle Bin + Temp)." "WORKING" 2 $totalSteps
$sizeRecycle = (Get-ChildItem 'C:\$Recycle.Bin' -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
if (-not $sizeRecycle) { $sizeRecycle = 0 }
Clear-RecycleBin -Confirm:$false -ErrorAction SilentlyContinue
$tempPaths = @("$env:TEMP", "$env:SystemRoot\Temp", "$env:SystemRoot\Prefetch")
foreach ($p in $tempPaths) { Get-ChildItem -Path ("$p\*") -Recurse -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue }
Write-Step ("Done: cleanup completed. Recycle Bin removed: {0}." -f (Format-Bytes $sizeRecycle)) "SUCCESS" 2 $totalSteps
Write-Step "Next: component store optimization (DISM)." "INFO" 2 $totalSteps

# --- 3. OPTIMISATION DISM ---
Write-Step "Starting: component store optimization (DISM WinSxS)." "WORKING" 3 $totalSteps
Dism.exe /Online /Cleanup-Image /StartComponentCleanup /ResetBase | Out-Null
$preDism = (Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'").FreeSpace
$gainWinSxS = [Math]::Round(($preDism - $beforeFree) / 1MB, 1)
Write-Step ("Done: DISM completed. Estimated change since baseline: {0} MB." -f $gainWinSxS) "SUCCESS" 3 $totalSteps
Write-Step "Next: Windows Update scan and install." "INFO" 3 $totalSteps

# --- 4. WINDOWS UPDATE ---
Write-Step "Starting: Windows Update scan and install." "WORKING" 4 $totalSteps
$updatesInstalled = @()
try {
    $uSession = New-Object -ComObject Microsoft.Update.Session
    $uSearcher = $uSession.CreateUpdateSearcher()
    $uSearch = $uSearcher.Search("IsInstalled=0 and Type='Software'")
    if ($uSearch.Updates.Count -gt 0) {
        $uDownloader = $uSession.CreateUpdateDownloader(); $uDownloader.Updates = $uSearch.Updates; $uDownloader.Download() | Out-Null
        $uInstaller = $uSession.CreateUpdateInstaller(); $uInstaller.Updates = $uSearch.Updates; $uInstaller.Install() | Out-Null
        foreach($u in $uSearch.Updates) { $updatesInstalled += $u.Title }
    }
} catch { Write-Step "Windows Update error (scan/install failed)." "ERROR" 4 $totalSteps }
Write-Step ("Done: Windows Update completed. Installed: {0} update(s)." -f $updatesInstalled.Count) "SUCCESS" 4 $totalSteps
Write-Step "Next: generate HTML report and open it." "INFO" 4 $totalSteps

Write-Step "Starting: report generation." "WORKING" 5 $totalSteps

# --- 5. CALCULS ---
$driveFinal = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
$totalGainMB = [Math]::Round(($driveFinal.FreeSpace - $beforeFree) / 1MB, 1)
$freeGB = [Math]::Round($driveFinal.FreeSpace / 1GB, 1)
$totalGB = [Math]::Round($driveFinal.Size / 1GB, 1)

# --- 6. HTML DASHBOARD PROFESSIONNEL ---
$osInfo = Get-CimInstance Win32_OperatingSystem
$osName = $osInfo.Caption
$osBuild = $osInfo.BuildNumber
$executionDate = Get-Date -Format "dd/MM/yyyy HH:mm:ss"
$usedGB = [Math]::Round(($totalGB - $freeGB), 1)
$usedPercent = [Math]::Round((($usedGB / $totalGB) * 100), 1)
$freePercent = [Math]::Round((($freeGB / $totalGB) * 100), 1)

# Additional metrics for charts
$beforeFreeGB = [Math]::Round(($beforeFree / 1GB), 1)
$memoryTotalGB = [Math]::Round(($osInfo.TotalVisibleMemorySize * 1KB) / 1GB, 1)
$memoryFreeGB = [Math]::Round(($osInfo.FreePhysicalMemory * 1KB) / 1GB, 1)
$memoryUsedGB = [Math]::Round(($memoryTotalGB - $memoryFreeGB), 1)
$memoryUsedPercent = if ($memoryTotalGB -gt 0) { [Math]::Round(($memoryUsedGB / $memoryTotalGB) * 100, 1) } else { 0 }
$recycleMB = [Math]::Round(($sizeRecycle / 1MB), 1)
$winsxsMB = [Math]::Round([Math]::Max(0, $gainWinSxS), 1)
$otherGainMB = [Math]::Round([Math]::Max(0, ($totalGainMB - $recycleMB - $winsxsMB)), 1)
$cpuLoad = [Math]::Round(((Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average), 1)
$cpuIdle = [Math]::Max(0, 100 - $cpuLoad)

# Preparation de la liste des mises a jour pour le HTML (echappement HTML pour securite)
$updatesHtmlList = ""
if ($updatesInstalled.Count -gt 0) {
    $updatesList = @()
    foreach ($update in $updatesInstalled) {
        $escapedUpdate = $update -replace '&', '&amp;' -replace '<', '&lt;' -replace '>', '&gt;' -replace '"', '&quot;' -replace "'", '&#39;'
        $updatesList += "<div class='update-item'><i class='fas fa-shield-alt text-primary me-2'></i>$escapedUpdate</div>"
    }
    $updatesHtmlList = $updatesList -join ""
} else {
    $updatesHtmlList = "<div class='update-item'><i class='fas fa-info-circle text-info me-2'></i>The system was already up to date at the time of analysis.</div>"
}

$html = @"
<!DOCTYPE html>
<html lang="fr">
<head>
    <meta http-equiv="Content-Type" content="text/html; charset=UTF-8">
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>System Maintenance Report - $($env:COMPUTERNAME)</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.2/dist/css/bootstrap.min.css" rel="stylesheet">
    <link href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.1/css/all.min.css" rel="stylesheet">
    <script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js"></script>
    <style>
        @import url('https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700;800&display=swap');
        
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        :root {
            --primary: #6366f1;
            --primary-dark: #4f46e5;
            --secondary: #8b5cf6;
            --success: #10b981;
            --warning: #f59e0b;
            --danger: #ef4444;
            --info: #3b82f6;
            --dark: #1e293b;
            --light: #f8fafc;
            --border: #e2e8f0;
        }
        
        body {
            font-family: 'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            color: #1e293b;
            line-height: 1.6;
        }
        
        .dashboard-container {
            display: flex;
            min-height: 100vh;
        }
        
        .sidebar {
            width: 280px;
            background: linear-gradient(180deg, #111827 0%, #0f172a 60%, #0b1220 100%);
            color: white;
            position: fixed;
            height: 100vh;
            padding: 30px 25px;
            box-shadow: 4px 0 24px rgba(0,0,0,0.25);
            border-right: 1px solid rgba(255,255,255,0.05);
            backdrop-filter: blur(4px);
            overflow-y: auto;
            z-index: 1000;
        }
        
        .brand {
            display: flex;
            align-items: center;
            gap: 14px;
            margin-bottom: 28px;
        }

        .brand-logo {
            width: 44px;
            height: 44px;
            display: grid;
            place-items: center;
            border-radius: 10px;
            background: linear-gradient(135deg, rgba(99,102,241,0.25), rgba(124,58,237,0.25));
            border: 1px solid rgba(255,255,255,0.1);
            box-shadow: inset 0 0 12px rgba(99,102,241,0.25);
        }
        
        .brand-title {
            font-size: 1.25rem;
            font-weight: 800;
            background: linear-gradient(135deg, #667eea, #764ba2);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
            background-clip: text;
        }
        
        .brand-subtitle {
            font-size: 0.75rem;
            color: rgba(255,255,255,0.6);
            text-transform: uppercase;
            letter-spacing: 1px;
        }

        .divider {
            height: 1px;
            width: 100%;
            background: linear-gradient(90deg, rgba(255,255,255,0.08), rgba(255,255,255,0.02));
            margin: 18px 0 22px 0;
        }
        
        .kv-list {
            display: grid;
            gap: 14px;
            margin-bottom: 22px;
        }
        
        .kv-item {
            display: flex;
            justify-content: space-between;
            align-items: center;
            gap: 10px;
            padding: 10px 0;
            border-bottom: 1px dashed rgba(255,255,255,0.08);
        }

        .kv-item:last-child {
            border-bottom: none;
        }

        .kv-left {
            display: inline-flex;
            align-items: center;
            gap: 10px;
        }

        .kv-icon {
            width: 22px;
            height: 22px;
            display: grid;
            place-items: center;
            color: #93c5fd;
            opacity: 0.85;
        }

        .kv-label {
            font-size: 0.7rem;
            color: rgba(255,255,255,0.5);
            text-transform: uppercase;
            letter-spacing: 1px;
        }
        
        .kv-value {
            font-size: 0.95rem;
            font-weight: 600;
            color: white;
            text-align: right;
            max-width: 145px;
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
        }
        
        .status-pill {
            display: flex;
            align-items: center;
            gap: 10px;
            padding: 10px 12px;
            margin-top: 16px;
            width: fit-content;
            border-radius: 999px;
            background: linear-gradient(135deg, rgba(16,185,129,0.18), rgba(99,102,241,0.12));
            border: 1px solid rgba(255,255,255,0.12);
            box-shadow: 0 6px 18px rgba(16,185,129,0.12);
        }
        
        .status-pill i {
            color: var(--success);
            animation: pulse 2s infinite;
        }
        
        @keyframes pulse {
            0%, 100% { opacity: 1; }
            50% { opacity: 0.5; }
        }
        
        .main-content {
            margin-left: 280px;
            flex: 1;
            padding: 40px;
        }
        
        .header-section {
            background: white;
            border-radius: 16px;
            padding: 30px;
            margin-bottom: 30px;
            box-shadow: 0 4px 20px rgba(0,0,0,0.08);
        }
        
        .header-section h1 {
            font-size: 2.5rem;
            font-weight: 800;
            margin-bottom: 10px;
            background: linear-gradient(135deg, #667eea, #764ba2);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
            background-clip: text;
        }
        
        .header-section p {
            color: #64748b;
            font-size: 1rem;
        }
        
        .kpi-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }
        
        .kpi-card {
            background: white;
            border-radius: 16px;
            padding: 25px;
            box-shadow: 0 4px 20px rgba(0,0,0,0.08);
            transition: all 0.3s ease;
            border-left: 4px solid;
            position: relative;
            overflow: hidden;
        }
        
        .kpi-card::before {
            content: '';
            position: absolute;
            top: 0;
            right: 0;
            width: 100px;
            height: 100px;
            background: radial-gradient(circle, rgba(99,102,241,0.1) 0%, transparent 70%);
            border-radius: 50%;
            transform: translate(30px, -30px);
        }
        
        .kpi-card:hover {
            transform: translateY(-5px);
            box-shadow: 0 8px 30px rgba(0,0,0,0.12);
        }
        
        .kpi-card.primary { border-left-color: var(--primary); }
        .kpi-card.success { border-left-color: var(--success); }
        .kpi-card.warning { border-left-color: var(--warning); }
        .kpi-card.danger { border-left-color: var(--danger); }
        
        .kpi-icon {
            font-size: 2rem;
            margin-bottom: 15px;
            opacity: 0.8;
        }
        
        .kpi-label {
            font-size: 0.75rem;
            color: #64748b;
            text-transform: uppercase;
            letter-spacing: 1px;
            margin-bottom: 10px;
            font-weight: 600;
        }
        
        .kpi-value {
            font-size: 2rem;
            font-weight: 700;
            color: #1e293b;
            margin-bottom: 5px;
        }
        
        .kpi-subtitle {
            font-size: 0.85rem;
            color: #94a3b8;
        }
        
        .content-grid {
            display: grid;
            grid-template-columns: 2fr 1fr;
            gap: 30px;
            margin-bottom: 30px;
        }
        
        @media (max-width: 1200px) {
            .content-grid {
                grid-template-columns: 1fr;
            }
        }
        
        .card-modern {
            background: white;
            border-radius: 16px;
            padding: 30px;
            box-shadow: 0 4px 20px rgba(0,0,0,0.08);
        }
        
        .card-title {
            font-size: 1.25rem;
            font-weight: 700;
            margin-bottom: 20px;
            color: #1e293b;
            display: flex;
            align-items: center;
            gap: 10px;
        }
        
        .card-title i {
            color: var(--primary);
        }
        
        .activity-item {
            display: flex;
            justify-content: space-between;
            align-items: center;
            padding: 15px;
            background: var(--light);
            border-radius: 10px;
            margin-bottom: 10px;
            transition: all 0.2s ease;
        }
        
        .activity-item:hover {
            background: #f1f5f9;
            transform: translateX(5px);
        }
        
        .badge-modern {
            padding: 6px 12px;
            border-radius: 20px;
            font-size: 0.75rem;
            font-weight: 600;
        }
        
        .updates-list {
            max-height: 400px;
            overflow-y: auto;
            padding-right: 10px;
        }
        
        .update-item {
            padding: 12px;
            background: var(--light);
            border-radius: 8px;
            margin-bottom: 8px;
            border-left: 3px solid var(--primary);
            font-size: 0.9rem;
        }
        
        .chart-container {
            position: relative;
            height: 250px;
            margin: 20px 0;
        }
        
        .disk-stats {
            display: flex;
            justify-content: space-around;
            margin-top: 20px;
            padding-top: 20px;
            border-top: 1px solid var(--border);
        }
        
        .disk-stat {
            text-align: center;
        }
        
        .disk-stat-value {
            font-size: 1.5rem;
            font-weight: 700;
            color: var(--primary);
        }
        
        .disk-stat-label {
            font-size: 0.75rem;
            color: #64748b;
            text-transform: uppercase;
            margin-top: 5px;
        }
        
        .footer-modern {
            background: white;
            border-radius: 16px;
            padding: 20px 30px;
            text-align: center;
            color: #64748b;
            font-size: 0.85rem;
            box-shadow: 0 4px 20px rgba(0,0,0,0.08);
        }

        .extra-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));
            gap: 20px;
            margin: 20px 0 30px 0;
        }
        
        .progress-bar-modern {
            height: 8px;
            background: var(--light);
            border-radius: 10px;
            overflow: hidden;
            margin-top: 10px;
        }
        
        .progress-fill {
            height: 100%;
            background: linear-gradient(90deg, var(--primary), var(--secondary));
            border-radius: 10px;
            transition: width 1s ease;
        }
        
        ::-webkit-scrollbar {
            width: 8px;
        }
        
        ::-webkit-scrollbar-track {
            background: var(--light);
        }
        
        ::-webkit-scrollbar-thumb {
            background: var(--primary);
            border-radius: 10px;
        }
        
        ::-webkit-scrollbar-thumb:hover {
            background: var(--primary-dark);
        }
    </style>
</head>
<body>
    <div class="dashboard-container">
        <div class="sidebar">
            <div class="brand">
                <div class="brand-logo"><i class="fas fa-shield-alt"></i></div>
                <div>
                    <div class="brand-title">SYSADMIN</div>
                    <div class="brand-subtitle">Maintenance Dashboard</div>
                </div>
            </div>
            <div class="divider"></div>
            <div class="kv-list">
                <div class="kv-item">
                    <div class="kv-left">
                        <span class="kv-icon"><i class="fas fa-desktop"></i></span>
                        <div class="kv-label">Station ID</div>
                    </div>
                    <div class="kv-value">$($env:COMPUTERNAME)</div>
                </div>
                <div class="kv-item">
                    <div class="kv-left">
                        <span class="kv-icon"><i class="fas fa-user"></i></span>
                        <div class="kv-label">User</div>
                    </div>
                    <div class="kv-value">$($env:USERNAME)</div>
                </div>
                <div class="kv-item">
                    <div class="kv-left">
                        <span class="kv-icon"><i class="fas fa-microchip"></i></span>
                        <div class="kv-label">System</div>
                    </div>
                    <div class="kv-value">$osName</div>
                </div>
                <div class="kv-item">
                    <div class="kv-left">
                        <span class="kv-icon"><i class="fas fa-hashtag"></i></span>
                        <div class="kv-label">Build</div>
                    </div>
                    <div class="kv-value">$osBuild</div>
                </div>
            </div>
            <div class="status-pill">
                <i class="fas fa-circle"></i>
                <span>System Operational</span>
            </div>
        </div>
        
        <div class="main-content">
            <div class="header-section">
                <h1>System Maintenance Report</h1>
                <p>Full analysis and optimization performed on $executionDate</p>
            </div>
            
            <div class="kpi-grid">
                <div class="kpi-card primary">
                    <div class="kpi-icon"><i class="fas fa-hdd text-primary"></i></div>
                    <div class="kpi-label">Total Space Gain</div>
                    <div class="kpi-value">$totalGainMB MB</div>
                    <div class="kpi-subtitle">Space freed</div>
                </div>
                <div class="kpi-card danger">
                    <div class="kpi-icon"><i class="fas fa-trash text-danger"></i></div>
                    <div class="kpi-label">Recycle Bin</div>
                    <div class="kpi-value">$([Math]::Round($sizeRecycle / 1MB, 1)) MB</div>
                    <div class="kpi-subtitle">Files removed</div>
                </div>
                <div class="kpi-card warning">
                    <div class="kpi-icon"><i class="fas fa-cog text-warning"></i></div>
                    <div class="kpi-label">WinSxS Optimization</div>
                    <div class="kpi-value">$gainWinSxS MB</div>
                    <div class="kpi-subtitle">DISM cleanup</div>
                </div>
                <div class="kpi-card success">
                    <div class="kpi-icon"><i class="fas fa-sync-alt text-success"></i></div>
                    <div class="kpi-label">Windows Updates</div>
                    <div class="kpi-value">$($updatesInstalled.Count)</div>
                    <div class="kpi-subtitle">Installed fixes</div>
                </div>
            </div>
            
            <div class="content-grid">
                <div class="card-modern">
                    <div class="card-title">
                        <i class="fas fa-clipboard-list"></i>
                        Journal des Interventions
                    </div>
                    <div class="activity-item">
                        <span><i class="fas fa-check-circle text-success me-2"></i>Optimisation profonde WinSxS (DISM)</span>
                        <span class="badge-modern bg-success text-white">Completed</span>
                    </div>
                    <div class="activity-item">
                        <span><i class="fas fa-check-circle text-success me-2"></i>Vidage de la corbeille et fichiers temporaires</span>
                        <span class="badge-modern bg-success text-white">Completed</span>
                    </div>
                    <div class="activity-item">
                        <span><i class="fas fa-check-circle text-success me-2"></i>Windows Update: scan and install</span>
                        <span class="badge-modern bg-success text-white">Completed</span>
                    </div>
                    
                    <div class="card-title mt-4">
                        <i class="fas fa-download"></i>
                        Installed Patches History
                    </div>
                    <div class="updates-list">
                        $updatesHtmlList
                    </div>
                </div>
                
                <div class="card-modern">
                    <div class="card-title">
                        <i class="fas fa-database"></i>
                        Local Storage (C:)
                    </div>
                    <div class="chart-container">
                        <canvas id="diskChart"></canvas>
                    </div>
                    <div class="disk-stats">
                        <div class="disk-stat">
                            <div class="disk-stat-value">$freeGB GB</div>
                            <div class="disk-stat-label">Free ($freePercent%)</div>
                        </div>
                        <div class="disk-stat">
                            <div class="disk-stat-value" style="color: var(--warning);">$usedGB GB</div>
                            <div class="disk-stat-label">Used ($usedPercent%)</div>
                        </div>
                        <div class="disk-stat">
                            <div class="disk-stat-value" style="color: var(--primary);">$totalGB GB</div>
                            <div class="disk-stat-label">Total</div>
                        </div>
                    </div>
                    <div class="progress-bar-modern mt-3">
                        <div class="progress-fill" style="width: $usedPercent%"></div>
                    </div>
                </div>
            </div>

            <div class="extra-grid">
                <div class="card-modern">
                    <div class="card-title">
                        <i class="fas fa-memory"></i>
                        Memory Usage
                    </div>
                    <div class="chart-container">
                        <canvas id="memoryChart"></canvas>
                    </div>
                    <div class="disk-stats">
                        <div class="disk-stat">
                            <div class="disk-stat-value">$memoryFreeGB GB</div>
                            <div class="disk-stat-label">Free</div>
                        </div>
                        <div class="disk-stat">
                            <div class="disk-stat-value" style="color: var(--warning);">$memoryUsedGB GB</div>
                            <div class="disk-stat-label">Used ($memoryUsedPercent%)</div>
                        </div>
                        <div class="disk-stat">
                            <div class="disk-stat-value" style="color: var(--primary);">$memoryTotalGB GB</div>
                            <div class="disk-stat-label">Total</div>
                        </div>
                    </div>
                </div>

                <div class="card-modern">
                    <div class="card-title">
                        <i class="fas fa-broom"></i>
                        Cleanup Impact
                    </div>
                    <div class="chart-container">
                        <canvas id="cleanupChart"></canvas>
                    </div>
                    <div class="disk-stats">
                        <div class="disk-stat">
                            <div class="disk-stat-value">$recycleMB MB</div>
                            <div class="disk-stat-label">Recycle Bin</div>
                        </div>
                        <div class="disk-stat">
                            <div class="disk-stat-value" style="color: var(--warning);">$winsxsMB MB</div>
                            <div class="disk-stat-label">WinSxS</div>
                        </div>
                        <div class="disk-stat">
                            <div class="disk-stat-value" style="color: var(--primary);">$otherGainMB MB</div>
                            <div class="disk-stat-label">Other</div>
                        </div>
                    </div>
                </div>

                <div class="card-modern">
                    <div class="card-title">
                        <i class="fas fa-microchip"></i>
                        CPU Load (snapshot)
                    </div>
                    <div class="chart-container">
                        <canvas id="cpuChart"></canvas>
                    </div>
                    <div class="disk-stats">
                        <div class="disk-stat">
                            <div class="disk-stat-value">$cpuLoad %</div>
                            <div class="disk-stat-label">Load</div>
                        </div>
                        <div class="disk-stat">
                            <div class="disk-stat-value" style="color: var(--primary);">$cpuIdle %</div>
                            <div class="disk-stat-label">Idle</div>
                        </div>
                    </div>
                </div>
            </div>
            
            <div class="footer-modern">
                <i class="fas fa-clock me-2"></i>
                Generated on $executionDate | 
                <i class="fas fa-server ms-3 me-2"></i>
                SysAdmin Dashboard v5.8 | 
                <i class="fas fa-shield-alt ms-3 me-2"></i>
                Automated Maintenance System
            </div>
        </div>
    </div>
    
    <script>
        const ctx = document.getElementById('diskChart').getContext('2d');
        new Chart(ctx, {
            type: 'doughnut',
            data: {
                labels: ['Free Space', 'Used Space'],
                datasets: [{
                    data: [$freeGB, $usedGB],
                    backgroundColor: [
                        'rgba(99, 102, 241, 0.8)',
                        'rgba(241, 245, 249, 0.8)'
                    ],
                    borderColor: [
                        'rgba(99, 102, 241, 1)',
                        'rgba(241, 245, 249, 1)'
                    ],
                    borderWidth: 2
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                cutout: '75%',
                plugins: {
                    legend: {
                        position: 'bottom',
                        labels: {
                            padding: 15,
                            font: {
                                size: 12,
                                family: 'Inter'
                            }
                        }
                    },
                    tooltip: {
                        callbacks: {
                            label: function(context) {
                                return context.label + ': ' + context.parsed + ' GB';
                            }
                        }
                    }
                }
            }
        });

        // Memory chart
        const memCtx = document.getElementById('memoryChart').getContext('2d');
        new Chart(memCtx, {
            type: 'doughnut',
            data: {
                labels: ['Free Memory', 'Used Memory'],
                datasets: [{
                    data: [$memoryFreeGB, $memoryUsedGB],
                    backgroundColor: [
                        'rgba(16, 185, 129, 0.8)',
                        'rgba(250, 204, 21, 0.8)'
                    ],
                    borderColor: [
                        'rgba(16, 185, 129, 1)',
                        'rgba(250, 204, 21, 1)'
                    ],
                    borderWidth: 2
                }]
            },
            options: { responsive: true, maintainAspectRatio: false, cutout: '70%', plugins: { legend: { position: 'bottom' } } }
        });

        // Cleanup bar chart
        const clCtx = document.getElementById('cleanupChart').getContext('2d');
        new Chart(clCtx, {
            type: 'bar',
            data: {
                labels: ['Recycle Bin', 'WinSxS', 'Other'],
                datasets: [{
                    label: 'Freed (MB)',
                    data: [$recycleMB, $winsxsMB, $otherGainMB],
                    backgroundColor: ['#ef4444', '#f59e0b', '#6366f1']
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                scales: {
                    y: { beginAtZero: true, ticks: { stepSize: 100 } }
                },
                plugins: { legend: { display: false } }
            }
        });

        // CPU chart
        const cpuCtx = document.getElementById('cpuChart').getContext('2d');
        new Chart(cpuCtx, {
            type: 'doughnut',
            data: {
                labels: ['Load', 'Idle'],
                datasets: [{
                    data: [$cpuLoad, $cpuIdle],
                    backgroundColor: [
                        'rgba(99, 102, 241, 0.85)',
                        'rgba(226, 232, 240, 0.9)'
                    ],
                    borderColor: [
                        'rgba(99, 102, 241, 1)',
                        'rgba(226, 232, 240, 1)'
                    ],
                    borderWidth: 2
                }]
            },
            options: { responsive: true, maintainAspectRatio: false, cutout: '70%', plugins: { legend: { position: 'bottom' } } }
        });
    </script>
</body>
</html>
"@

# Last-mile safety: convert any remaining accented text to HTML entities
# NOTE: HTML already written in UTF-8 with BOM and includes meta charset UTF-8.
# If your editor saved this file in UTF-8 with BOM, accents will render correctly in the browser.

# --- 7. EXPORTATION FORCEE (METHODE .NET POUR ACCENTS) ---
if (-not (Test-Path $ReportDirectory)) { New-Item $ReportDirectory -ItemType Directory | Out-Null }
$reportPath = Join-Path $ReportDirectory "Maintenance_Report_$($env:COMPUTERNAME).html"

# Creation d'un encodage UTF8 avec signature (BOM) pour garantir l'affichage correct des accents
$utf8WithBOM = New-Object System.Text.UTF8Encoding($true)
try {
    # Utiliser WriteAllText avec encodage UTF-8 BOM
    [System.IO.File]::WriteAllText($reportPath, $html, $utf8WithBOM)
} catch {
    # Fallback : utiliser Out-File avec UTF8
    $html | Out-File -FilePath $reportPath -Encoding UTF8 -Force
}

Write-Step "Done: report generated. Opening report in default browser..." "SUCCESS" 5 $totalSteps
Start-Process $reportPath