# Fix Storage Upload Error - Services Bucket

## Problem
Upload failed: StorageException(message: new row violates row-level security policy, statusCode: 403, error: Unauthorized)

## Solution
You need to add RLS policies through the Supabase Dashboard UI (not SQL Editor).

### Step-by-Step Instructions:

1. **Go to Supabase Dashboard**
   - Navigate to: https://supabase.com/dashboard
   - Select your project

2. **Open Storage Section**
   - Click on **Storage** in the left sidebar
   - Find the **services** bucket
   - If it doesn't exist, create it first:
     - Click "New bucket"
     - Name: `services`
     - Public bucket: **YES** (check this box)
     - Click "Create bucket"

3. **Configure Policies for 'services' Bucket**
   - Click on the **services** bucket
   - Click on **Policies** tab at the top
   - You should see a "New Policy" button

4. **Add INSERT Policy (for uploads)**
   - Click **"New Policy"**
   - Choose **"For full customization"** (or "Custom")
   - Policy name: `Authenticated Insert Services`
   - Allowed operation: **INSERT** (check this box)
   - Target roles: **authenticated**
   - USING expression: Leave empty or use `true`
   - WITH CHECK expression: `bucket_id = 'services'`
   - Click **"Save"** or **"Create policy"**

5. **Add SELECT Policy (for reading/viewing)**
   - Click **"New Policy"** again
   - Policy name: `Public Read Services`
   - Allowed operation: **SELECT** (check this box)
   - Target roles: **public** (or **anon**)
   - USING expression: `bucket_id = 'services'`
   - Click **"Save"**

6. **Add UPDATE Policy (optional, for editing)**
   - Click **"New Policy"**
   - Policy name: `Authenticated Update Services`
   - Allowed operation: **UPDATE**
   - Target roles: **authenticated**
   - USING expression: `bucket_id = 'services'`
   - Click **"Save"**

7. **Add DELETE Policy (optional, for deleting)**
   - Click **"New Policy"**
   - Policy name: `Authenticated Delete Services`
   - Allowed operation: **DELETE**
   - Target roles: **authenticated**
   - USING expression: `bucket_id = 'services'`
   - Click **"Save"**

### Alternative: Use Policy Templates

If Supabase offers policy templates:
1. Look for "Use a template" or "Policy templates"
2. Select **"Allow authenticated uploads"** template
3. Apply it to the `services` bucket

### Test After Setup
1. Go back to your Flutter app
2. Try uploading a service image again
3. It should work immediately

### If Still Not Working
Check that:
- The bucket name is exactly `services` (lowercase)
- The bucket is marked as **public**
- You are logged in as an authenticated user when uploading
- Your authentication session is valid

### Debug Info
The upload code is in: `lib/admin/admin_services.dart` (line 98-132)
It uploads to bucket: `services`
Current user check: Line 100-104
