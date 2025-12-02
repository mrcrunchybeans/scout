# Scout Deployment Script - Cloudflare Pages
# Builds Flutter web app and deploys to Cloudflare Pages

Write-Host "Building Flutter web app..." -ForegroundColor Cyan
flutter build web --release

if ($LASTEXITCODE -ne 0) {
    Write-Host "Flutter build failed!" -ForegroundColor Red
    exit 1
}

Write-Host "`nDeploying to Cloudflare Pages..." -ForegroundColor Cyan
Push-Location build\web
wrangler pages deploy . --project-name=scout --commit-dirty=true
Pop-Location

if ($LASTEXITCODE -eq 0) {
    Write-Host "`nDeployment successful!" -ForegroundColor Green
    Write-Host "Scout is live at: https://scout.littleempathy.com" -ForegroundColor Green
} else {
    Write-Host "`nDeployment failed!" -ForegroundColor Red
    exit 1
}
