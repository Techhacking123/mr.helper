# Admin Push Notification Feature - Complete Guide

## Overview
This feature allows admins to send push notifications to users and providers with the following capabilities:
- Send notifications immediately or schedule them for later
- Target all users, all providers, or manually select specific recipients
- View notification history with detailed status tracking

## Implementation Components

### 1. Database Setup
**File**: `.agent/admin_push_notifications_setup.sql`

This SQL migration creates:
- `scheduled_notifications` table to store notification data
- Functions for sending notifications and retrieving recipient lists
- Automatic triggers for immediate notification sending
- RLS policies for admin-only access

**To deploy**:
```sql
-- Run this SQL in your Supabase SQL Editor
-- Execute the entire content of: .agent/admin_push_notifications_setup.sql
```

### 2. Flutter UI
**File**: `lib/admin/admin_send_notification.dart`

Two main pages:
1. **AdminSendNotificationPage**: Compose and send notifications
2. **AdminNotificationHistoryPage**: View sent/scheduled notifications

**Features**:
- ✅ Title and message input with validation
- ✅ Recipient type selection (all users/providers or manual selection)
- ✅ User/Provider list with multi-select checkboxes
- ✅ Schedule for later with date/time picker
- ✅ Real-time status updates
- ✅ Beautiful UI with chips and status indicators

### 3. Admin Dashboard Integration
**File**: `lib/admin/admin_dashboard.dart`

Added new action card "Send Push Notification" with pink accent color.

## How to Use

### For Admins:

#### 1. **Immediate Notification**
1. Open Admin Dashboard
2. Tap "Send Push Notification"
3. Enter title and message
4. Select recipient type:
   - All Users
   - All Providers
   - Select Users (manual)
   - Select Providers (manual)
5. If manual selection: Tap "Load Users/Providers" and select from list
6. Tap "Send Now"

#### 2. **Scheduled Notification**
1. Follow steps 1-5 above
2. Toggle "Schedule for later"
3. Select date and time
4. Tap "Schedule Notification"

#### 3. **View History**
1. On the Send Notification page, tap "History" in app bar
2. View all sent/scheduled notifications with:
   - Status badges (Sent, Scheduled, Failed, Pending)
   - Recipient count (sent/failed)
   - Timestamps
   - Error messages (if any)

## Database Schema

### scheduled_notifications Table
```sql
- id: UUID (Primary Key)
- title: TEXT (Notification title)
- message: TEXT (Notification message)
- recipient_type: TEXT (all_users, all_providers, selected_users, selected_providers)
- recipient_ids: JSONB (Array of user IDs for manual selection)
- scheduled_at: TIMESTAMPTZ (NULL for immediate send)
- status: TEXT (pending, sent, failed, scheduled)
- sent_at: TIMESTAMPTZ
- sent_count: INTEGER
- failed_count: INTEGER
- created_by: UUID (Admin who created it)
- created_at: TIMESTAMPTZ
- error_message: TEXT
```

## Database Functions

### 1. `send_admin_push_notification`
Sends push notifications to specified users.
```sql
Parameters:
- p_title: Notification title
- p_message: Notification message
- p_user_ids: Array of user IDs

Returns:
- success_count: Number of successful sends
- failed_count: Number of failed sends
```

### 2. `get_recipient_user_ids`
Gets user IDs based on recipient type.
```sql
Parameters:
- p_recipient_type: Type of recipients
- p_selected_ids: JSONB array of selected IDs (for manual selection)

Returns: Array of user UUIDs
```

### 3. `process_scheduled_notifications`
Called by cron job to send scheduled notifications.

## How It Works

### Immediate Notifications:
1. Admin creates notification with `scheduled_at = NULL`
2. `trigger_send_immediate_notification` fires on INSERT
3. Function calls `get_recipient_user_ids` to get targets
4. Function calls `send_admin_push_notification` to send
5. Notifications are inserted into `notifications` table
6. Existing FCM trigger sends push notifications
7. Status updated to 'sent' with counts

### Scheduled Notifications:
1. Admin creates notification with future `scheduled_at`
2. Trigger sets status to 'scheduled'
3. Cron job runs `process_scheduled_notifications` (needs setup)
4. When time matches, same flow as immediate notifications
5. Status updated to 'sent' or 'failed'

## Setting Up Scheduled Notifications (Optional)

To enable scheduled notifications, create a cron job in Supabase:

1. Go to Supabase Dashboard → Database → Cron Jobs (Requires pg_cron extension)
2. Create new job:
```sql
SELECT cron.schedule(
    'process-scheduled-notifications',
    '* * * * *', -- Every minute (adjust as needed)
    $$SELECT process_scheduled_notifications()$$
);
```

**Note**: Scheduled notifications require the `pg_cron` extension. If not available, you can use Supabase Edge Functions + scheduler instead.

## Features by Recipient Type

### All Users
- Sends to all non-provider, non-admin users with FCM tokens
- Auto-fetches user list from database
- No manual selection needed

### All Providers
- Sends to all providers with FCM tokens
- Auto-fetches provider list from database
- No manual selection needed

### Selected Users
- Admin loads user list
- Select specific users via checkboxes
- Shows selected count and chips
- Only sends to users with FCM tokens

### Selected Providers
- Admin loads provider list
- Select specific providers via checkboxes
- Shows selected count and chips
- Only sends to providers with FCM tokens

## UI Components

### Send Notification Page
- **Title Card**: Title and message input
- **Recipients Card**: Type selector and user list
- **Schedule Card**: Toggle and date/time picker
- **Send Button**: Dynamic based on schedule status

### History Page
- **Expandable Cards**: Tap to see details
- **Status Badges**: Color-coded (Green/Blue/Red/Orange)
- **Info Chips**: Sent/Failed counts
- **Error Display**: Shows error messages for failed notifications

## Security

### RLS Policies
- Only admins can view scheduled notifications
- Only admins can insert scheduled notifications
- Only admins can update scheduled notifications
- FCM token check ensures only users with valid tokens receive notifications

### Validation
- Title max length: 100 characters
- Message max length: 500 characters
- At least one recipient required for manual selection
- Scheduled date must be in the future

## Testing

### Test Immediate Notification:
1. Login as admin
2. Navigate to Send Push Notification
3. Select "All Users" or "All Providers"
4. Enter test message
5. Send immediately
6. Check user/provider devices for notification
7. Verify in History page

### Test Scheduled Notification:
1. Follow steps above
2. Toggle "Schedule for later"
3. Select time 2-3 minutes in future
4. Schedule notification
5. Wait for scheduled time
6. Check if notification sent
7. Verify status updated in History

### Test Manual Selection:
1. Select "Select Users" or "Select Providers"
2. Load users/providers
3. Select 2-3 recipients
4. Send notification
5. Verify only selected users receive it

## Troubleshooting

### Notifications Not Sending
- Verify SQL migration ran successfully
- Check RLS policies are active
- Ensure users have valid FCM tokens
- Check Supabase logs for errors
- Verify FCM setup is correct

### Scheduled Notifications Not Working
- Ensure cron job is created and running
- Check `process_scheduled_notifications` function exists
- Verify scheduled_at timestamp is in past when cron runs
- Check scheduled_notifications table for error_message

### Users Not Receiving Notifications
- Verify user has FCM token in database
- Check FCM service account credentials
- Verify push notification edge function is deployed
- Check notification permissions on device

## Next Steps

1. ✅ Run SQL migration in Supabase
2. ✅ Test immediate notifications
3. ⚠️ Optional: Set up cron job for scheduled notifications
4. ✅ Train admins on how to use the feature

## Additional Notes

- Notifications are inserted into the `notifications` table
- The existing FCM edge function handles actual push delivery
- Admin can view system notifications in the "Notifications" page
- This feature complements the existing notification system
- All notification data is stored for audit purposes
