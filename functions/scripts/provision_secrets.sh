#!/usr/bin/env bash
# Helper: push secrets to Google Secret Manager and grant Cloud Functions service account access.
# Usage (local):
#   export ALGOLIA_ADMIN_API_KEY="<secret>"
#   ./scripts/provision_secrets.sh

set -euo pipefail

PROJECT=$(gcloud config get-value project 2>/dev/null)
if [ -z "$PROJECT" ]; then
  echo "No gcloud project configured. Run: gcloud config set project <PROJECT_ID>" >&2
  exit 1
fi

echo "Using project: $PROJECT"

function upsert_secret() {
  local name=$1
  local value=$2
  if gcloud secrets describe "$name" --project="$PROJECT" >/dev/null 2>&1; then
    echo "Adding new version for secret $name"
    echo -n "$value" | gcloud secrets versions add "$name" --data-file=- --project="$PROJECT"
  else
    echo "Creating secret $name"
    echo -n "$value" | gcloud secrets create "$name" --data-file=- --project="$PROJECT"
  fi
}

echo "Provisioning Algolia admin key to Secret Manager as ALGOLIA_ADMIN_API_KEY"
upsert_secret ALGOLIA_ADMIN_API_KEY "$ALGOLIA_ADMIN_API_KEY"

SA_EMAIL=$(gcloud projects describe "$PROJECT" --format='get(projectNumber)')-compute@developer.gserviceaccount.com || true
if [ -n "$SA_EMAIL" ]; then
  echo "Granting access to Cloud Functions service account: $SA_EMAIL"
  gcloud secrets add-iam-policy-binding ALGOLIA_ADMIN_API_KEY \
    --member="serviceAccount:$SA_EMAIL" --role="roles/secretmanager.secretAccessor" --project="$PROJECT"
fi

echo "Done. You should reference the secret in your function runtime or set an env var mapping before deploy."
