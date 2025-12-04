# Scout Deployment Script - Cloudflare Pages
# Builds Flutter web app, pushes to GitHub, creates release, and deploys to Cloudflare Pages

param(
    [string]$Message = "",
    [switch]$SkipGit = $false,
    [switch]$Major = $false,
    [switch]$Minor = $false,
    [switch]$NoIncrement = $false
)

# Get current version from pubspec.yaml
$pubspecPath = "pubspec.yaml"
$pubspec = Get-Content $pubspecPath -Raw
if ($pubspec -match 'version:\s*(\d+)\.(\d+)\.(\d+)') {
    $major = [int]$matches[1]
    $minor = [int]$matches[2]
    $patch = [int]$matches[3]
    $oldVersion = "$major.$minor.$patch"
} else {
    $major = 0
    $minor = 0
    $patch = 0
    $oldVersion = "0.0.0"
}

# Increment version (unless NoIncrement is set)
if (-not $NoIncrement) {
    if ($Major) {
        $major++
        $minor = 0
        $patch = 0
    } elseif ($Minor) {
        $minor++
        $patch = 0
    } else {
        # Default: increment patch
        $patch++
    }
}

$version = "$major.$minor.$patch"

# Update pubspec.yaml with new version (unless NoIncrement)
if (-not $NoIncrement -and $version -ne $oldVersion) {
    $newPubspec = $pubspec -replace 'version:\s*\d+\.\d+\.\d+', "version: $version"
    Set-Content $pubspecPath -Value $newPubspec -NoNewline
    Write-Host "Version bumped: $oldVersion -> $version" -ForegroundColor Magenta
}

$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm"
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
            
            # Create GitHub release using gh CLI (if available)
            $ghAvailable = Get-Command gh -ErrorAction SilentlyContinue
            if ($ghAvailable) {
                gh release create "v$version" --title "v$version" --notes "$commitMessage" --latest
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
