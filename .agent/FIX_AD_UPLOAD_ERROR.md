# Fix Ad Upload Storage Error

## Problem
Getting error when uploading ads:
```
Error: StorageException(message: new row violates row-level security policy, statusCode: 403, error: Unauthorized)
```

## Root Cause
The storage bucket `ads` doesn't have proper Row-Level Security (RLS) policies configured to allow authenticated users (admins) to upload images.

## Solution

### Step 1: Apply the SQL Fix
1. Open your **Supabase Dashboard**
2. Navigate to **SQL Editor**
3. Open the file `.agent/fix_ads_storage_rls.sql` from this project
4. Copy the entire SQL script
5. Paste it into the Supabase SQL Editor
6. Click **Run** to execute the script
7. Verify you see the success message and the policy verification results

### Step 2: Verify the Fix
After running the script, you should see output showing:
- The `ads` bucket exists and is public
- Four policies created for the ads bucket:
  - `ads_bucket_public_read` - Anyone can view ads
  - `ads_bucket_authenticated_insert` - Authenticated users can upload
  - `ads_bucket_authenticated_update` - Authenticated users can update
  - `ads_bucket_authenticated_delete` - Authenticated users can delete

### Step 3: Test the Upload
1. **Hot restart** your Flutter app (don't just hot reload)
   - Stop the app completely
   - Run `flutter run` again
2. Navigate to the **Admin Ads page**
3. Try uploading an ad with an image
4. The upload should now work without errors

## What the Fix Does
- Creates/ensures the `ads` storage bucket exists and is public
- Removes any conflicting old policies
- Creates fresh RLS policies that allow:
  - **Public users**: Read/view ad images
  - **Authenticated users**: Upload, update, and delete ad images
- Since admins are authenticated, they can now upload ads successfully

## Troubleshooting
If the error persists after applying the fix:
1. Check if you're logged in as an authenticated user (not anonymous)
2. Run the SQL script again to ensure it executed successfully
3. Check the Flutter terminal for any specific error messages
4. Verify the bucket policies in Supabase Dashboard → Storage → ads bucket → Policies tab
