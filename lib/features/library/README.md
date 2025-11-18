# Library Management System

A comprehensive check-in/check-out system for tracking reusable items and equipment.

## Features

### Item Management
- Add, edit, and delete library items
- Track item details: name, description, category, barcode, serial number, location
- Support for multiple item statuses: Available, Checked Out, Maintenance, Retired

### Check-Out System
- Check out items to specific borrowers (operators)
- Set optional due dates for returns
- Track who checked out each item and when
- Add notes during check-out

### Check-In System
- Check in items when returned
- Track return timestamps
- Flag overdue items automatically
- Add notes about item condition on return

### Search & Filtering
- Search by item name, barcode, serial number, or borrower
- Filter by status (All, Available, Checked Out, Maintenance, Retired)
- Filter to show only overdue items
- Real-time updates via Firestore streams

### Audit Trail
All library transactions are automatically logged to the audit system:
- `library.item.create` - New item added
- `library.item.update` - Item details modified
- `library.item.delete` - Item removed
- `library.checkout` - Item checked out
- `library.checkin` - Item checked in

## Data Model

### Firestore Collection: `library_items`

```dart
{
  "name": string,              // Required: Item name
  "description": string?,      // Optional: Additional details
  "category": string?,         // Optional: Category/type
  "barcode": string?,          // Optional: Barcode identifier
  "serialNumber": string?,     // Optional: Serial/asset number
  "location": string?,         // Optional: Storage location
  "status": string,            // Required: available|checked_out|maintenance|retired
  "checkedOutBy": string?,     // Operator name when checked out
  "checkedOutAt": Timestamp?,  // Check-out timestamp
  "dueDate": Timestamp?,       // Optional due date
  "notes": string?,            // Current notes
  "createdAt": Timestamp,      // Creation timestamp
  "updatedAt": Timestamp,      // Last update timestamp
  "createdBy": string?,        // Firebase Auth UID
  "operatorName": string?      // Operator name who last modified
}
```

## Usage

### Accessing Library Management

1. Navigate to **Admin / Config** page
2. Under **Data Management** section, click **Library Management**

### Adding Items

1. Click the **+** button (FAB or app bar)
2. Fill in item details (only name is required)
3. Click **Add**

### Checking Out Items

1. Find an available item in the list
2. Click the **Check Out** button
3. Enter borrower name (defaults to current operator if set)
4. Optionally set a due date
5. Add any notes if needed
6. Click **Check Out**

### Checking In Items

1. Find a checked-out item in the list
2. Click the **Check In** button
3. Review check-out details and overdue status
4. Add any notes about condition
5. Click **Check In**

### Editing Items

1. Click on any item card or click the edit icon
2. Modify item details or change status
3. Click **Save**

### Deleting Items

1. Click the delete icon (trash can) on an item
2. Confirm deletion
3. Item is permanently removed

## Status Colors

- **Available** (Green): Item is ready to be checked out
- **Checked Out** (Blue): Item is currently with a borrower
- **Maintenance** (Orange): Item is being serviced or repaired
- **Retired** (Grey): Item is no longer in active use

## Overdue Detection

Items are automatically flagged as overdue when:
- Status is "Checked Out"
- Due date is set
- Current date is past the due date

Overdue items are highlighted in red in the interface.

## Integration with Existing Systems

- Uses the existing **Audit** utility for transaction logging
- Integrates with **OperatorStore** for default borrower names
- Follows the same Firestore patterns as other collections
- Consistent UI/UX with the rest of the SCOUT application

## Future Enhancements

Potential improvements for future versions:
- Email/notification reminders for due dates
- Item reservation system
- Check-out history per item
- Borrower statistics and history
- Barcode scanner integration for faster check-in/out
- Export library reports to CSV
- Item photos/images
- Maintenance scheduling
- Fine/fee tracking for late returns
