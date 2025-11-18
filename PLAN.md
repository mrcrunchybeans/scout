# SCOUT Web Modernization Plan

Last updated: 2025-10-09
Owner: Brian (with Copilot assist)
Status: Draft → Iterating

## Goals and Success Metrics

- Performance
  - Dashboard initial paint < 1.5s (p50), < 3s (p95) on mid-tier laptop
  - Items list interaction: search results update < 300ms after debounce
  - Cart close end-to-end < 800ms (p50), < 1.5s (p95)
- Reliability
  - Zero partial inventory updates (atomic writes only) — monitored via error logs
  - Web error rate < 0.5% sessions; no “Dart exception thrown from converted Future” in core flows
- UX
  - Smooth navigation with skeletons, no major jank
  - Clear empty/error states; consistent theming and accessibility
- Maintainability
  - Repository + DTO layer covers 80% of Firestore usage
  - Unit/integration tests for critical flows (cart close, items paging)
  - CI gates: analyze, test, build

## Phases Overview

- Phase 0: Quick Wins (low-risk, immediate value)
  1) Dashboard: cap bucket lists, add “See all” links
  2) Items: debounce search + page results (cursor-based)
  3) Logging: ensure diagnostics disabled in release

- Phase 1: Data Access Foundation
  - Repositories + DataSources (Firestore, Algolia)
  - DTOs with withConverter, consistent Timestamp handling
  - Shared query helpers (filters, paging)

- Phase 2: State Management & Screens
  - Riverpod providers for items, sessions, dashboard
  - Migrate Items page to repo/providers, add virtualized list for large sets
  - Migrate Session flows to repositories (keep atomic batch pattern)

- Phase 3: Aggregation & Counts
  - Cloud Function maintains meta/dashboard_stats
  - Dashboard tiles use aggregated counts (constant-time)
  - Backfill script + validation

- Phase 4: Performance & Offline
  - Tune renderer (HTML/CanvasKit) per device
  - Resource bundling, deferred/lazy loading for heavy screens
  - Optional Firestore persistence (per-browser A/B guard)

- Phase 5: Tooling & CI/CD
  - Strict analysis, format
  - Tests for repos and critical UI flows
  - GitHub Actions: analyze→test→build→deploy
  - Feature flags/Remote Config

## Detailed Step-by-Step Plan

### Phase 0: Quick Wins
1. Dashboard bucket cap
   - Limit per-bucket display to first 10 items
   - Add “See all” chip/link → navigates to Items with filter preset (follow-up)
   - Acceptance: UI renders quickly, avoids long DOM lists

2. Items search/pagination
   - Add 300ms debounce for text input
   - Cursor-based paging (25–50 per page)
   - Cancel stale queries when input changes
   - Acceptance: typing is fluid, memory stable, small Firestore bills

3. Logging guard
   - Ensure router diagnostics and verbose logs disabled in release
   - Optional: wrap debug prints behind `if (kDebugMode)` or a `logD()` helper
   - Acceptance: release console is clean, no perf hit from logs

### Phase 1: Data Access Foundation
- Create `/lib/data` modules: `models/`, `dto/`, `repos/`, `sources/`
- Implement ItemsRepo, SessionsRepo, DashboardRepo
- withConverter on collections for type safety
- Acceptance: Items list reads via repo; unit tests covering mapping and paging

### Phase 2: State + Screens
- Introduce Riverpod; providers per repo/query
- Migrate Items page to providers + repo
- Migrate cart session flows (keep single-batch writes)
- Acceptance: Screens compile and run; fewer direct Firestore calls in widgets

### Phase 3: Aggregation & Counts
- Cloud Function: maintain `meta/dashboard_stats` (low/expiring/stale/expired counts)
- Read counts from a single doc in dashboard
- Acceptance: Tile counts accurate (±1 transient), minimal listeners, lower cost

### Phase 4: Performance & Offline
- Evaluate HTML vs CanvasKit renderer for target devices
- Introduce deferred imports for admin/heavy screens
- Measure and (optionally) enable Firestore persistence based on browser support
- Acceptance: Lower memory, faster initial paint, reliable behavior across browsers

### Phase 5: Tooling & CI/CD
- Add analysis options and format hooks
- Unit + widget tests for repos and key flows
- GitHub Actions to run analyze/test/build and deploy hosting/functions
- Acceptance: Green CI is required; easy releases

## Risks and Mitigations
- Firestore schema drift / timestamps: enforce DTO/withConverter; add guards
- Web interop quirks: avoid complex FieldValue on web; prefer explicit values
- Search relevance: elevate Algolia for text search; hybrid filters on Firestore
- Aggregation accuracy: Cloud Function retries + backfill scripts

## Rollback Plan
- Keep changes behind small flags where risky
- Revert to previous page implementations if repo/provider migration breaks flows

## Ownership & Timeline (T-shirt sizes)
- Phase 0: S (hours–1 day)
- Phase 1: M (1–3 days)
- Phase 2: M/L (2–5 days)
- Phase 3: S/M (1–2 days)
- Phase 4: S/M (1–2 days)
- Phase 5: S/M (1–2 days)

## Acceptance Checklists

- Phase 0
  - [ ] Dashboard caps per-bucket to 10 with See all
  - [ ] Items search debounced; paging works; no jank
  - [ ] Release logs minimal (no router diagnostics)

- Phase 1
  - [ ] Repos and DTOs in place for Items; tests pass

- Phase 2
  - [ ] Items & Sessions use providers+repos

- Phase 3
  - [ ] Dashboard uses aggregated counts doc

- Phase 4
  - [ ] Renderer and deferred loading tuned

- Phase 5
  - [ ] CI runs analyze/test/build/deploy

## Decision Log (append as we go)
- 2025-10-09: Adopt single-batch Firestore writes for cart close to ensure atomicity on web.
- 2025-10-09: Replace FieldValue.serverTimestamp with explicit Timestamp values to avoid interop errors on web.

