# Functions: Algolia sync and utilities

This folder contains Firebase Cloud Functions for the Scout project.

Purpose
- Keep Algolia write keys server-side and perform indexing operations securely.
- Provide callable endpoints for admin UI: triggerFullReindex, configureAlgoliaIndex, syncItemToAlgoliaCallable.
- Maintain a `status/algolia` Firestore document with last sync time and last error for monitoring.

Required environment variables (set in your Cloud Functions runtime)
- ALGOLIA_APP_ID - Algolia Application ID
- ALGOLIA_ADMIN_API_KEY - Algolia Admin (write) key - MUST be kept secret
- ALGOLIA_INDEX_NAME - Target Algolia index name

Local development / deploy steps
1. Install dependencies:

```pwsh
cd functions
npm install
```

2. Set environment variables for local testing (use .env or emulator options). For the emulator you can set env in your terminal session.

3. Build the TypeScript code:

```pwsh
cd functions
npm run build
```

4. Deploy functions to Firebase:

```pwsh
# make sure firebase CLI is authenticated and project selected
cd functions
npm run build
firebase deploy --only functions
```

Security notes
- Do not place the Algolia write key in Firestore or client code. Use Cloud Functions environment variables or Secret Manager.
- Callables check for `req.auth.token.admin` — ensure admin users have the appropriate custom claim.

Status doc
- Functions write to `status/algolia` in Firestore with fields `lastSyncAt`, `lastIndexedCount`, `lastSuccessItem`, and `lastError`.
- The admin UI reads this doc to show the last successful sync or errors.

If you want I can also:
- Add CI steps to run `npm run build` and lint before deploy.
- Tighten the admin claim checks or integrate with IAM-based service account checks.
