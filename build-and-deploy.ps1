# Build and Deploy Script
# R# Update version in VersionService
Write-Host "🔄 Updating version in VersionService..." -ForegroundColor Yellow
$versionServicePath = "lib\services\version_service.dart"
$versionServiceContent = Get-Content $versionServicePath -Raw
$currentDate = Get-Date -Format "yyyy-MM-dd"
$versionServiceContent = $versionServiceContent -replace "static const String _appVersion = '[^']*';", "static const String _appVersion = '$newVersion';"
$versionServiceContent = $versionServiceContent -replace "static const String _buildDate = '[^']*';", "static const String _buildDate = '$currentDate';"
Set-Content $versionServicePath $versionServiceContent
Write-Host "📋 VersionService updated to: $newVersion ($currentDate)" -ForegroundColor Green  instead of 'flutter build web --release' to build and deploy

Write-Host "🔨 Building and deploying SCOUT..." -ForegroundColor Cyan

# Increment version number
Write-Host "📈 Incrementing version number..." -ForegroundColor Yellow
$pubspecPath = "pubspec.yaml"
$content = Get-Content $pubspecPath -Raw

# Extract current version
$versionMatch = [regex]::Match($content, 'version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)')
if ($versionMatch.Success) {
    $major = [int]$versionMatch.Groups[1].Value
    $minor = [int]$versionMatch.Groups[2].Value
    $patch = [int]$versionMatch.Groups[3].Value
    $build = [int]$versionMatch.Groups[4].Value + 1

    $newVersion = "$major.$minor.$patch+$build"
    $oldVersionLine = "version: $major.$minor.$patch+$($versionMatch.Groups[4].Value)"
    $newVersionLine = "version: $newVersion"

    $content = $content.Replace($oldVersionLine, $newVersionLine)
    Set-Content $pubspecPath $content

    Write-Host "📋 Version incremented to: $newVersion" -ForegroundColor Green
} else {
    Write-Host "⚠️ Could not parse version from pubspec.yaml" -ForegroundColor Yellow
}

# Update version in VersionService
Write-Host "� Updating version in VersionService..." -ForegroundColor Yellow
$versionServiceContent = $versionServiceContent -replace "static const String _appVersion = '[^']*';", "static const String _appVersion = '$newVersion';"
Set-Content $versionServicePath $versionServiceContent
Write-Host "📋 VersionService updated to: $newVersion" -ForegroundColor Green

# Run Flutter build (without service worker to prevent caching issues on mobile)
& flutter build web --release --pwa-strategy=none
if ($LASTEXITCODE -ne 0) {
    Write-Error "Build failed"
    exit $LASTEXITCODE
}

# Run deployment
& ".\deploy.ps1" -SkipBuild

Write-Host "✅ Build and deployment completed!" -ForegroundColor Green