# Lot Code Recalculation Tool

## Purpose
This admin tool standardizes lot codes across your inventory to ensure consistency with the new `YYMM-XXX` format (e.g., `2510-001`, `2510-002`, `2510-003`).

## Why You Need This
The old bulk inventory system used a letter-based format (e.g., `2510A`, `2510B`), which was inconsistent with the rest of the application. This tool migrates those old codes to the new standard format while preserving important data.

## What It Does

### 1. Finds Old Format Codes
Scans all lots in your database looking for codes that don't match the standard format.

### 2. Preserves Creation Dates
Uses the original `createdAt` timestamp from each lot to determine its place in the sequence.

### 3. Groups by Item and Month
- Groups lots by their parent item
- Within each item, groups lots by creation month (YYMM)
- This ensures lot codes are scoped correctly

### 4. Regenerates Codes
- Sorts lots chronologically (oldest first)
- Assigns sequential numbers: 001, 002, 003, etc.
- Format: `YYMM-XXX` where:
  - `YY` = last 2 digits of year
  - `MM` = month (01-12)
  - `XXX` = sequence number (001-999)

### 5. Updates Database
Updates the `lotCode` field in Firestore for each lot that needs to change.

## How to Use

### Access the Tool
1. Go to Dashboard → Menu (⋮) → **Admin / Config**
2. Enter your admin PIN
3. Scroll to the **Data Management** section
4. Click **"Recalculate Lot Codes"**
5. Enter developer password when prompted (extra security for data changes)

### Run the Recalculation
1. Click the **"Start Recalculation"** button
2. Wait for the process to complete
3. Review the detailed log

### Review Results
The tool provides:
- **Progress tracking**: Shows X/Y lots processed
- **Statistics**: 
  - Total lots processed
  - Lots updated (changed codes)
  - Lots skipped (already correct)
- **Detailed log**: Shows every change made with timestamps

## Safety Features

### 1. Read-Only Preview
You can review what will change before committing. The log shows old → new codes.

### 2. Preserves Data
- Original `createdAt` timestamps unchanged
- Lot quantities unchanged
- Expiration dates unchanged
- All other lot data preserved

### 3. Smart Skipping
Already-correct lot codes are left unchanged, minimizing database writes.

### 4. Transaction Safety
Each lot is updated individually, so if the process is interrupted, already-updated lots remain correct.

### 5. Developer-Only Access
Requires both:
- Admin PIN (4 digits)
- Developer password (full password)

## Example

### Before
```
Item: "Paper Towels"
- Lot: 2510A (created Oct 1, 2025)
- Lot: 2510B (created Oct 5, 2025)
- Lot: 2510C (created Oct 10, 2025)
```

### After
```
Item: "Paper Towels"
- Lot: 2510-001 (created Oct 1, 2025)
- Lot: 2510-002 (created Oct 5, 2025)
- Lot: 2510-003 (created Oct 10, 2025)
```

## When to Use

### Required Scenarios
- After migrating from the old bulk inventory system
- If you notice inconsistent lot code formats
- After importing data from external systems

### Optional Scenarios
- As a maintenance task to verify data consistency
- Before generating batch reports or labels
- After manual data corrections

## Troubleshooting

### "No lots need updating"
✅ This is good! All your lot codes are already in the correct format.

### Process is slow
⏳ Normal for large inventories. The tool processes every lot to ensure accuracy.

### Some lots skipped
ℹ️ Check the log - lots without `createdAt` timestamps cannot be recalculated and are skipped.

### Unexpected results
📧 Contact support with the detailed log for investigation.

## Technical Details

### Database Queries
- Uses `collectionGroup('lots')` to fetch all lots
- Groups in memory (no complex Firestore queries needed)
- Updates one lot at a time

### Performance
- Typical speed: ~50-100 lots per second
- 1,000 lots ≈ 10-20 seconds
- 10,000 lots ≈ 2-3 minutes

### Firestore Writes
- One write per updated lot
- No writes for already-correct lots
- Uses `FieldValue.serverTimestamp()` for `updatedAt`

## Code Location
- Tool: `lib/features/admin/recalculate_lot_codes_page.dart`
- Utility: `lib/utils/lot_code.dart`
- Routes: `lib/main.dart` (route: `/admin/recalculate-lot-codes`)
