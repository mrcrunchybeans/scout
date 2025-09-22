<# 
SCOUT Deployment Script (WinSCP Sync Edition)
- Builds Flutter web app and synchronizes to remote via FTPS (default) or SFTP.
- Only changed files are uploaded. Parallel transfers, retries, resume supported.

Updated: 2025-09-22
#>

[CmdletBinding()]
param(
    [string]$FtpServer,
    [string]$FtpUsername,
    [PSCredential]$FtpCredential,
    [string]$RemotePath,
    [ValidateSet('ftp','sftp')][string]$Protocol = 'ftp',
    [int]$Port,                          # optional; defaults: 21(FTPS), 22(SFTP)
    [switch]$PlainFtp,                   # force plain FTP (no TLS). Not recommended.
    [string]$ExcludeMask = "|\assets\assets\;assets/assets/;assets/packages/cupertino_icons/assets/",
    [switch]$MirrorDelete,               # delete remote files that don't exist locally
    [int]$ParallelTransfers = 8,         # WinSCP queue limit for parallel uploads
    [switch]$SkipBuild,
    [switch]$SkipUpload
)

# PSScriptAnalyzer note: we intentionally accept plain text passwords during config load
[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingPlainTextForPassword", "")]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingConvertToSecureStringWithPlainText", "")]

# -----------------------------
# Load configuration (same behavior you had)
# -----------------------------
$ScriptRoot = $PSScriptRoot
$configPath = Join-Path $ScriptRoot "ftp-config.ps1"
$envPath    = Join-Path $ScriptRoot ".env"

$configLoaded = $false

function Convert-EnvFile {
    param([string]$Content)
    # Simple .env parser (KEY=VALUE per line, ignores blanks/#)
    $result = @{}
    foreach ($line in ($Content -split "`n")) {
        $t = $line.Trim()
        if (-not $t -or $t.StartsWith("#")) { continue }
        $idx = $t.IndexOf("=")
        if ($idx -lt 1) { continue }
        $key = $t.Substring(0,$idx).Trim()
        $val = $t.Substring($idx+1).Trim()
        $result[$key] = $val
    }
    return $result
}

if (Test-Path $configPath) {
    try {
        . $configPath
        if (-not $FtpCredential -and $FtpPassword) {
            $secure = ConvertTo-SecureString $FtpPassword -AsPlainText -Force
            $FtpCredential = [PSCredential]::new($FtpUsername, $secure)
        }
        $configLoaded = $true
    } catch {
        Write-Error "Could not load FTP configuration from $configPath : $_"
        exit 1
    }
}
elseif (Test-Path $envPath) {
    try {
        $envVars = Convert-EnvFile -Content (Get-Content $envPath -Raw)
        if (-not $FtpServer)   { $FtpServer   = $envVars['FTP_SERVER'] }
        if (-not $FtpUsername) { $FtpUsername = $envVars['FTP_USERNAME'] }
        if (-not $FtpCredential) {
            $secure = ConvertTo-SecureString $envVars['FTP_PASSWORD'] -AsPlainText -Force
            $FtpCredential = [PSCredential]::new($envVars['FTP_USERNAME'], $secure)
        }
        if (-not $RemotePath)  { $RemotePath  = $envVars['FTP_REMOTE_PATH'] }
        if ($envVars['FTP_PROTOCOL'])        { $Protocol = $envVars['FTP_PROTOCOL'] } # ftp | sftp
        if ($envVars['FTP_PORT'])            { $Port = [int]$envVars['FTP_PORT'] }
        if ($envVars['FTP_PLAIN'])           { $PlainFtp = [bool]::Parse($envVars['FTP_PLAIN']) }
        if ($envVars['FTP_EXCLUDE_MASK'])    { $ExcludeMask = $envVars['FTP_EXCLUDE_MASK'] }
        if ($envVars['FTP_MIRROR_DELETE'])   { $MirrorDelete = [bool]::Parse($envVars['FTP_MIRROR_DELETE']) }
        if ($envVars['FTP_PARALLEL'])        { $ParallelTransfers = [int]$envVars['FTP_PARALLEL'] }
        $configLoaded = $true
    } catch {
        Write-Error "Could not load FTP configuration from $envPath : $_"
        exit 1
    }
}

if (-not $configLoaded) {
    Write-Host "FTP configuration file not found!" -ForegroundColor Red
    Write-Host "Create one of the following:" -ForegroundColor Yellow
    Write-Host "  1) Copy ftp-config-template.ps1 -> ftp-config.ps1 and fill values"
    Write-Host "  2) Copy .env.example -> .env and fill values"
    exit 1
}

# Extract username from credential if not provided
if (-not $FtpUsername -and $FtpCredential) {
    $FtpUsername = $FtpCredential.UserName
}

# Validate configuration
if (($FtpServer -eq "your-ftp-server.com") -or
    ($FtpUsername -eq "your-username")     -or
    (-not $FtpCredential)                  -or
    (-not $RemotePath)) {
    Write-Error "Config has placeholder/empty values. Update your ftp-config.ps1 or .env."
    exit 1
}

# Defaults for ports
if (-not $Port) {
    $Port = if ($Protocol -eq 'sftp') { 22 } else { 21 }
}

# -----------------------------
# Build step
# -----------------------------
$ProjectRoot = $ScriptRoot
$BuildDir    = Join-Path $ProjectRoot "build\web"

Write-Host "🚀 SCOUT Deployment (WinSCP Sync)" -ForegroundColor Cyan
Write-Host "Project Root: $ProjectRoot" -ForegroundColor Gray
Write-Host "Build Directory: $BuildDir" -ForegroundColor Gray
Write-Host "Protocol: $Protocol  Port: $Port  Parallel: $ParallelTransfers  MirrorDelete: $MirrorDelete" -ForegroundColor Gray
Write-Host ""

if (-not $SkipBuild) {
    try {
        Write-Host "📦 Building Flutter web app..." -ForegroundColor Yellow
        Push-Location $ProjectRoot
        & flutter build web --release --wasm
        if ($LASTEXITCODE -ne 0) { throw "Flutter build failed with exit code $LASTEXITCODE" }
        Write-Host "✅ Build completed successfully" -ForegroundColor Green
    } catch {
        Write-Error "Build failed: $_"
        exit 1
    } finally {
        Pop-Location
    }
} else {
    Write-Host "⏭️  Skipping build step" -ForegroundColor Yellow
}

if ($SkipUpload) {
    Write-Host "⏭️  Skipping upload step" -ForegroundColor Yellow
    Write-Host "`n🎉 Done." -ForegroundColor Green
    exit 0
}

if (-not (Test-Path $BuildDir)) {
    Write-Error "Build directory not found: $BuildDir"
    exit 1
}

# -----------------------------
# WinSCP .NET assembly load
# -----------------------------
function Import-WinScpAssembly {
    # Check if WinSCP types are already loaded
    try {
        $null = [WinSCP.Session]
        return $true
    } catch { }
    
    # Try to load from DLL files
    $dllCandidates = @(
        (Join-Path $ScriptRoot "WinSCPnet.dll"),
        "${env:ProgramFiles}\WinSCP\WinSCPnet.dll",
        "${env:ProgramFiles(x86)}\WinSCP\WinSCPnet.dll"
    )
    foreach ($p in $dllCandidates) {
        if (Test-Path $p) {
            try { Add-Type -Path $p; return $true } catch { }
        }
    }
    return $false
}

if (-not (Import-WinScpAssembly)) {
    Write-Error "WinSCPnet.dll not found. WinSCP is required for FTP/SFTP deployment."
    Write-Host ""
    Write-Host "To install WinSCP:" -ForegroundColor Yellow
    Write-Host "1. Download WinSCP from: https://winscp.net/eng/downloads.php" -ForegroundColor Cyan
    Write-Host "2. Install WinSCP (the GUI application)" -ForegroundColor Cyan
    Write-Host "3. Copy WinSCPnet.dll from the WinSCP installation directory to this script's directory" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "WinSCPnet.dll is typically located at:" -ForegroundColor Gray
    Write-Host "  C:\Program Files (x86)\WinSCP\WinSCPnet.dll" -ForegroundColor Gray
    Write-Host "  or" -ForegroundColor Gray
    Write-Host "  C:\Program Files\WinSCP\WinSCPnet.dll" -ForegroundColor Gray
    exit 1
}

# -----------------------------
# Prepare WinSCP session
# -----------------------------
$remoteRoot = ($RemotePath.TrimEnd('/') + "/")

$sessionOptions = New-Object WinSCP.SessionOptions

if ($Protocol -eq 'sftp') {
    $sessionOptions.Protocol  = [WinSCP.Protocol]::Sftp
    $sessionOptions.HostName  = $FtpServer
    $sessionOptions.PortNumber= $Port
    $sessionOptions.UserName  = $FtpUsername
    $sessionOptions.Password  = $FtpCredential.GetNetworkCredential().Password
    # Optional: Host key fingerprint pinning (recommended)
    # $sessionOptions.SshHostKeyFingerprint = "ssh-ed25519 255 xx:xx:..."
} else {
    $sessionOptions.Protocol  = [WinSCP.Protocol]::Ftp
    $sessionOptions.HostName  = $FtpServer
    $sessionOptions.PortNumber= $Port
    $sessionOptions.UserName  = $FtpUsername
    $sessionOptions.Password  = $FtpCredential.GetNetworkCredential().Password
    $sessionOptions.FtpSecure = $( if ($PlainFtp) { [WinSCP.FtpSecure]::None } else { [WinSCP.FtpSecure]::Explicit } )
    # Optional: TLS certificate pinning
    # $sessionOptions.TlsHostCertificateFingerprint = "xx:xx:..."
}

$transferOpts = New-Object WinSCP.TransferOptions
$transferOpts.TransferMode = [WinSCP.TransferMode]::Binary
$transferOpts.ResumeSupport.State = $true
$transferOpts.PreserveTimestamp = $true
if ($ExcludeMask) {
    # WinSCP expects masks separated by semicolons; a leading | means exclude
    if (-not $ExcludeMask.Trim().StartsWith("|")) {
        $ExcludeMask = "|" + $ExcludeMask
    }
    $transferOpts.FileMask = $ExcludeMask
}

$syncOpts = New-Object WinSCP.SynchronizationOptions
$syncOpts.Recurse           = $true
$syncOpts.DuplicateHandling = [WinSCP.DuplicateHandling]::Overwrite
$syncOpts.FileMask          = $transferOpts.FileMask
$syncOpts.AddedFiles        = $true
$syncOpts.ModifiedFiles     = $true
$syncOpts.DeletedFiles      = [bool]$MirrorDelete

$session = New-Object WinSCP.Session

try {
    # Open
    $session.Open($sessionOptions)

    # Speed/robustness knobs
    $session.AddRawConfiguration("SessionReopenAuto", "1")
    $session.AddRawConfiguration("QueueTransfers", "On")
    $session.AddRawConfiguration("QueueTransfersLimit", [Math]::Max(1, [Math]::Min($ParallelTransfers, 16)) )
    $session.AddRawConfiguration("TcpNoDelay", "1")
    $session.AddRawConfiguration("Timeout", "30")
    # Slight backoff for server friendliness
    $session.AddRawConfiguration("PostCommand", "sleep 100")

    Write-Host "📤 Synchronizing $BuildDir → $remoteRoot" -ForegroundColor Yellow
    $result = $session.SynchronizeDirectories(
        [WinSCP.SynchronizationMode]::Remote,
        $BuildDir,
        $remoteRoot,
        $MirrorDelete.IsPresent,
        $syncOpts
    )

    $result.Check() # throws on any failed transfer

    # Summary
    $uploaded   = $result.Uploads.Count
    $removed    = $result.Deletions.Count
    $skipped    = $result.Skipped.Count
    Write-Host "✅ Sync complete. Uploaded: $uploaded; Deleted: $removed; Skipped (unchanged): $skipped" -ForegroundColor Green
}
catch {
    Write-Error "Upload failed: $_"
    if ($_.Exception -and $_.Exception.InnerException) {
        Write-Error "Inner: $($_.Exception.InnerException.Message)"
    }
    exit 1
}
finally {
    if ($session) { $session.Dispose() }
}

Write-Host "`n🎉 Deployment completed! Your SCOUT app is live." -ForegroundColor Cyan
