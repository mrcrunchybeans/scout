<#
SCOUT Build Script
- Builds Flutter web app for manual deployment
- Files will be ready in build/web for upload via FileZilla

Updated: 2025-10-01
#>

[CmdletBinding()]
param(
    [switch]$SkipBuild
)

# -----------------------------
# Build step
# -----------------------------
$ProjectRoot = $PSScriptRoot
$BuildDir    = Join-Path $ProjectRoot "build\web"

Write-Host "🚀 SCOUT Build Script" -ForegroundColor Cyan
Write-Host "Project Root: $ProjectRoot" -ForegroundColor Gray
Write-Host "Build Directory: $BuildDir" -ForegroundColor Gray
Write-Host ""

if (-not $SkipBuild) {
    try {
        Write-Host "📦 Building Flutter web app..." -ForegroundColor Yellow
        Push-Location $ProjectRoot
        & flutter build web --release
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

if (-not (Test-Path $BuildDir)) {
    Write-Error "Build directory not found: $BuildDir"
    exit 1
}

Write-Host "`n📁 Build files are ready in: $BuildDir" -ForegroundColor Green
Write-Host "📤 Upload these files manually using FileZilla to your web server" -ForegroundColor Cyan
Write-Host "`n🎉 Build completed! Ready for manual deployment." -ForegroundColor Cyan
