# Deploying Cloud Functions (scout/functions)

This document describes how to prepare, test, and deploy the Cloud Functions included in this repository.

Prerequisites
- Firebase CLI (>= 11) installed and authenticated: `npm install -g firebase-tools`
- A Firebase project configured for this repo (see `firebase.json` at repo root)
- Node 20 runtime support (functions/package.json specifies node 20)
- GitHub repository access if you plan to use the provided Actions workflow

Required environment variables (server-side only)
- ALGOLIA_APP_ID - Algolia Application ID
- ALGOLIA_ADMIN_API_KEY - Algolia Admin API Key (write privileges). MUST remain secret; do not store in Firestore or client code.
- ALGOLIA_INDEX_NAME - Target Algolia index name

Environment configuration strategy (migrated away from functions.config())
- Local/dev: use a `.env` file in `functions/` (see `.env.example`). The code uses `dotenv` and prefers `process.env`.
- Production: set runtime environment variables in the Firebase Console for the Functions service, or use Secret Manager. The code prefers `process.env` and only falls back to deprecated `functions.config()` if present.

Helper scripts
- If you still prefer Secret Manager, helper scripts exist at `functions/scripts/provision_secrets.sh` and `functions/scripts/provision_secrets.ps1` — but they are optional. The instructions below show the firebase CLI approach which works without using GCP Secret Manager.

Local build & test
1. Install dependencies
   cd functions
   npm ci

2. TypeScript build
   npm run build

3. Lint
   npm run lint

Run emulator locally (optional)
  npm run serve

Deploying to Firebase (manual)
1. Ensure you're using the correct Firebase project
   firebase projects:list
   firebase use <PROJECT_ID>

2. Set production env vars (preferred going forward)

Option A: Firebase Console
- Go to Firebase Console → Build → Functions → Environment variables, add:
   - ALGOLIA_APP_ID
   - ALGOLIA_ADMIN_API_KEY
   - ALGOLIA_INDEX_NAME

Option B: Secret Manager (optional)
- Use `functions/scripts/provision_secrets.ps1` or `.sh` to provision ALGOLIA_ADMIN_API_KEY to Secret Manager, then reference it in your deployment configuration.

Legacy note: `firebase functions:config:set` is deprecated and will stop working after March 2026. This project will still fall back to `functions.config()` if present for backward compatibility, but you should migrate to runtime envs.

3. (Optional) Use runtime env vars

If you prefer environment variables instead of `functions.config`, you can set them in the runtime when deploying via the Firebase Console or set process.env before starting the function runtime locally. The code first checks `process.env` and falls back to `functions.config()`.

4. Deploy functions
   cd functions
   npm run build
   firebase deploy --only functions

CI / GitHub Actions
- A sample GitHub Actions workflow is provided to build the functions on push and optionally deploy when a `FIREBASE_TOKEN` is provided as a repository secret. See `.github/workflows/deploy-functions.yml`.

Security notes
- Keep Algolia admin key out of Firestore and client code. Use Cloud Functions or Secret Manager to store it securely.
- Callable functions (`configureAlgoliaIndex`, `triggerFullReindex`, `syncItemToAlgoliaCallable`) perform a minimal auth check requiring `req.auth.token.admin` — ensure callers set the custom claim appropriately and restrict access in production.

Verification
- After deploy, check `status/algolia` document in Firestore for reindex status.
- Use `firebase functions:log` or the Cloud Console logs to inspect function runtime errors.

Troubleshooting
- If TypeScript lints fail, run `npm run lint` and fix or `npm run lint -- --fix` where applicable.

Contact
- If you need help adding automated secret provisioning or finer-grained IAM, I can add a deployment script or more detailed instructions.
