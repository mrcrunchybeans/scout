<#
Helper: provision Algolia admin key to Google Secret Manager from PowerShell
Usage:
  $env:ALGOLIA_ADMIN_API_KEY = "<secret>"
  ./provision_secrets.ps1
#>
param()
set-StrictMode -Version Latest

$proj = (& gcloud config get-value project 2>$null).Trim()
if (-not $proj) {
  Write-Error "No gcloud project configured. Run: gcloud config set project <PROJECT_ID>"
  exit 1
}

if (-not $env:ALGOLIA_ADMIN_API_KEY) {
  Write-Error "Please set environment variable ALGOLIA_ADMIN_API_KEY before running this script."
  exit 1
}

Write-Host "Using project: $proj"

try {
  # Check if secret exists
  & gcloud secrets describe ALGOLIA_ADMIN_API_KEY --project $proj > $null 2>&1
  $exists = $LASTEXITCODE -eq 0
} catch {
  $exists = $false
}

if ($exists) {
  Write-Host "Adding new version for secret ALGOLIA_ADMIN_API_KEY"
  $env:ALGOLIA_ADMIN_API_KEY | & gcloud secrets versions add ALGOLIA_ADMIN_API_KEY --data-file=- --project $proj
} else {
  Write-Host "Creating secret ALGOLIA_ADMIN_API_KEY"
  $env:ALGOLIA_ADMIN_API_KEY | & gcloud secrets create ALGOLIA_ADMIN_API_KEY --data-file=- --project $proj
}

$projectNumber = (& gcloud projects describe $proj --format='get(projectNumber)').Trim()
if ($projectNumber) {
  $sa = "$projectNumber-compute@developer.gserviceaccount.com"
  Write-Host "Granting secretAccessor to service account: $sa"
  & gcloud secrets add-iam-policy-binding ALGOLIA_ADMIN_API_KEY --member="serviceAccount:$sa" --role="roles/secretmanager.secretAccessor" --project $proj
}

Write-Host "Done."
