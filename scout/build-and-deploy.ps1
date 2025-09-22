# Build and Deploy Script
# Run this instead of 'flutter build web --release' to build and deploy

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

# Run Flutter build
& flutter build web --release
if ($LASTEXITCODE -ne 0) {
    Write-Error "Build failed"
    exit $LASTEXITCODE
}

# Run deployment
& ".\deploy.ps1" -SkipBuild

Write-Host "✅ Build and deployment completed!" -ForegroundColor Green