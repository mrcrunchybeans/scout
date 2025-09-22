# SCOUT Backup & Restore System - End-to-End Testing Checklist

## Prerequisites
- [ ] Firebase project configured with Firestore
- [ ] Firebase Functions deployed
- [ ] Admin PIN configured (default: 2468)
- [ ] Test data exists in collections: items, lookups, config

## Manual Backup Testing
- [ ] Navigate to Admin → Database Management → Create Backup
- [ ] Click "Create Backup" button
- [ ] Verify success message appears
- [ ] Check Backup History page shows new backup
- [ ] Verify backup contains correct collections and document counts

## Backup History Testing
- [ ] Navigate to Admin → Database Management → Backup History
- [ ] Verify backups are listed with timestamps and creators
- [ ] Test refresh functionality
- [ ] Test manual cleanup (if backups exist)
- [ ] Verify backup types (manual vs automated) are displayed correctly

## Backup Settings Testing
- [ ] Navigate to Admin → Database Management → Backup Settings
- [ ] Verify default retention period (30 days) is displayed
- [ ] Change retention period using slider
- [ ] Change retention period using text field
- [ ] Save settings and verify success message
- [ ] Refresh page and verify settings persist

## Selective Restore Testing
- [ ] Navigate to Admin → Database Management → Database Restore
- [ ] Select a backup from the list
- [ ] Verify collection selection dialog appears
- [ ] Deselect some collections (e.g., keep only 'items')
- [ ] Click "Restore Selected"
- [ ] Confirm destructive action warning
- [ ] Verify restore completes successfully
- [ ] Check that only selected collections were restored
- [ ] Verify search index rebuilds (if items were restored)

## Full Restore Testing
- [ ] Navigate to Admin → Database Management → Database Restore
- [ ] Select a backup from the list
- [ ] Keep all collections selected (default)
- [ ] Click "Restore Selected"
- [ ] Confirm destructive action warning
- [ ] Verify restore completes successfully
- [ ] Check that all collections were restored
- [ ] Verify search index rebuilds

## Automated Backup Testing
- [ ] Wait for scheduled backup time (3:00 AM) or trigger manually
- [ ] Check Backup History for new automated backup
- [ ] Verify automated cleanup removes old backups based on retention settings

## Error Handling Testing
- [ ] Test restore with invalid backup ID
- [ ] Test backup creation with network issues (simulate offline)
- [ ] Test settings save with invalid values
- [ ] Verify proper error messages are displayed

## Performance Testing
- [ ] Test backup of large dataset (1000+ documents)
- [ ] Test restore of large dataset
- [ ] Verify UI remains responsive during operations
- [ ] Check memory usage during large operations

## Security Testing
- [ ] Verify admin PIN is required for all operations
- [ ] Test unauthorized access attempts
- [ ] Verify backup data is properly secured in Firestore

## Integration Testing
- [ ] Test backup/restore with Algolia search integration
- [ ] Verify audit logging captures backup/restore operations
- [ ] Test with different user roles (if applicable)

## All Tests Passed ✅
- [ ] Manual backup creation
- [ ] Backup history viewing
- [ ] Backup settings configuration
- [ ] Selective collection restore
- [ ] Full database restore
- [ ] Automated backup scheduling
- [ ] Error handling
- [ ] Performance with large datasets
- [ ] Security and authorization
- [ ] Integration with other features