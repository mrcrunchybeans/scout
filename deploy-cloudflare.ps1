# Scout Deployment Script - Cloudflare Pages
# Builds Flutter web app, pushes to GitHub, creates release, and deploys to Cloudflare Pages

param(
    [string]$Message = "",
    [switch]$SkipGit = $false,
    [switch]$BumpMajor = $false,
    [switch]$BumpMinor = $false,
    [switch]$NoIncrement = $false,
    [switch]$NoAI = $false
)

# Get current version from pubspec.yaml
$pubspecPath = "pubspec.yaml"
$pubspec = Get-Content $pubspecPath -Raw

# Extract version using regex
$versionMatch = [regex]::Match($pubspec, 'version:\s*(\d+)\.(\d+)\.(\d+)')
if ($versionMatch.Success) {
    $vMajor = [int]$versionMatch.Groups[1].Value
    $vMinor = [int]$versionMatch.Groups[2].Value
    $vPatch = [int]$versionMatch.Groups[3].Value
    $oldVersion = "$vMajor.$vMinor.$vPatch"
} else {
    $vMajor = 1
    $vMinor = 0
    $vPatch = 0
    $oldVersion = "1.0.0"
}

# Increment version (unless NoIncrement is set)
if (-not $NoIncrement) {
    if ($BumpMajor) {
        $vMajor++
        $vMinor = 0
        $vPatch = 0
    } elseif ($BumpMinor) {
        $vMinor++
        $vPatch = 0
    } else {
        # Default: increment patch
        $vPatch++
    }
}

$version = "$vMajor.$vMinor.$vPatch"

# Update pubspec.yaml with new version (unless NoIncrement)
if (-not $NoIncrement -and $version -ne $oldVersion) {
    $newPubspec = $pubspec -replace 'version:\s*\d+\.\d+\.\d+(\+\d+)?', "version: $version"
    Set-Content $pubspecPath -Value $newPubspec -NoNewline
    Write-Host "Version bumped: $oldVersion -> $version" -ForegroundColor Magenta
}

$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm"

# Find gh CLI path
$ghPath = Get-Command gh -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source
if (-not $ghPath -and (Test-Path "C:\Program Files\GitHub CLI\gh.exe")) {
    $ghPath = "C:\Program Files\GitHub CLI\gh.exe"
}

# Generate release notes using AI (based on changes since last tag)
$releaseNotes = ""
if (-not $NoAI -and $ghPath) {
    Write-Host "Generating release notes with AI..." -ForegroundColor Cyan
    
    # Get the last tag
    $lastTag = git describe --tags --abbrev=0 2>$null
    
    if ($lastTag) {
        # Get commit messages since last tag
        $commitLog = git log "$lastTag..HEAD" --pretty=format:"%s" 2>$null
        
        # Get file changes summary
        $fileChanges = git diff --stat "$lastTag..HEAD" 2>$null
        
        if ($commitLog -or $fileChanges) {
            $prompt = @"
Generate concise release notes for version $version of a Flutter web app called Scout (inventory management for a non-profit).

Recent commits:
$commitLog

Files changed:
$fileChanges

Format as markdown bullet points. Focus on user-facing changes. Be brief (3-6 bullet points max). Don't include technical details like file paths.
"@
            
            try {
                # Use gh copilot to generate release notes
                $releaseNotes = $prompt | & $ghPath copilot explain --no-pager 2>$null
                
                if ($LASTEXITCODE -ne 0 -or -not $releaseNotes) {
                    # Fallback: generate simple notes from commit messages
                    $releaseNotes = "## What's Changed`n`n"
                    $commitLog -split "`n" | Where-Object { $_ -and $_ -notmatch "^(Merge|Deploy v)" } | Select-Object -First 10 | ForEach-Object {
                        $releaseNotes += "- $_`n"
                    }
                }
            } catch {
                Write-Host "  AI generation failed, using commit log" -ForegroundColor Yellow
                $releaseNotes = ""
            }
        }
    }
}

# Fallback commit message and release notes
if (-not $releaseNotes) {
    $releaseNotes = "Release v$version - $timestamp"
}
$commitMessage = if ($Message) { $Message } else { "Deploy v$version - $timestamp" }

Write-Host ""
Write-Host "Scout Deployment Script" -ForegroundColor Cyan
Write-Host "=======================" -ForegroundColor Cyan
Write-Host "Version: $version" -ForegroundColor Yellow
Write-Host ""

# Step 1: Git operations (unless skipped)
if (-not $SkipGit) {
    Write-Host "Step 1: Pushing to GitHub..." -ForegroundColor Cyan
    
    # Check for changes
    $gitStatus = git status --porcelain
    if ($gitStatus) {
        Write-Host "  Adding all changes..." -ForegroundColor Gray
        git add -A
        
        Write-Host "  Committing: $commitMessage" -ForegroundColor Gray
        git commit -m $commitMessage
        
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  Git commit failed (maybe no changes?)" -ForegroundColor Yellow
        }
    } else {
        Write-Host "  No uncommitted changes" -ForegroundColor Gray
    }
    
    Write-Host "  Pushing to origin..." -ForegroundColor Gray
    git push origin main
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Git push failed!" -ForegroundColor Red
        exit 1
    }
    
    # Create GitHub release
    Write-Host "`nStep 2: Creating GitHub release v$version..." -ForegroundColor Cyan
    
    # Check if tag already exists
    $existingTag = git tag -l "v$version"
    if ($existingTag) {
        Write-Host "  Tag v$version already exists, skipping release creation" -ForegroundColor Yellow
    } else {
        # Create and push tag
        git tag -a "v$version" -m "Release v$version - $timestamp"
        git push origin "v$version"
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  Created tag v$version" -ForegroundColor Green
            
            if ($ghPath) {
                # Create release with AI-generated or fallback notes
                & $ghPath release create "v$version" --title "v$version" --notes "$releaseNotes" --latest
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "  Created GitHub release v$version" -ForegroundColor Green
                } else {
                    Write-Host "  GitHub release creation failed (tag was created)" -ForegroundColor Yellow
                }
            } else {
                Write-Host "  GitHub CLI (gh) not found - tag created but release skipped" -ForegroundColor Yellow
                Write-Host "  Install with: winget install GitHub.cli" -ForegroundColor Gray
            }
        } else {
            Write-Host "  Failed to push tag" -ForegroundColor Yellow
        }
    }
} else {
    Write-Host "Step 1-2: Skipping Git operations (--SkipGit)" -ForegroundColor Yellow
}

# Step 3: Build Flutter
Write-Host "`nStep 3: Building Flutter web app..." -ForegroundColor Cyan
flutter build web --release --pwa-strategy=none

if ($LASTEXITCODE -ne 0) {
    Write-Host "Flutter build failed!" -ForegroundColor Red
    exit 1
}

# Step 4: Deploy to Cloudflare
Write-Host "`nStep 4: Deploying to Cloudflare Pages..." -ForegroundColor Cyan
Push-Location build\web
wrangler pages deploy . --project-name=scout --commit-dirty=true
Pop-Location

if ($LASTEXITCODE -eq 0) {
    Write-Host "`n=======================" -ForegroundColor Green
    Write-Host "Deployment successful!" -ForegroundColor Green
    Write-Host "=======================" -ForegroundColor Green
    Write-Host "Version: v$version" -ForegroundColor Green
    Write-Host "Scout is live at: https://scout.littleempathy.com" -ForegroundColor Green
} else {
    Write-Host "`nDeployment failed!" -ForegroundColor Red
    exit 1
}
