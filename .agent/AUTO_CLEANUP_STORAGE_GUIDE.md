# ✅ AUTOMATIC STORAGE CLEANUP - IMPLEMENTATION GUIDE

## 🎯 OVERVIEW

This implementation adds **automatic cleanup** of images from Supabase storage when:

1. ✅ **Ad is deleted** → Ad image deleted from `ads` bucket
2. ✅ **Ad expires** → Can trigger cleanup of expired ads
3. ✅ **User/Provider deleted** → Avatar deleted from `avatars` bucket

**No manual cleanup needed!** 🎉

---

## 📝 WHAT WAS CREATED

### **File:** `lib/security/AUTO_CLEANUP_STORAGE.sql`

This SQL script contains:

1. **Ad Image Cleanup Trigger**
   - Function: `cleanup_ad_image()`
   - Trigger: `trigger_cleanup_ad_image`
   - Runs: BEFORE DELETE on `ads` table

2. **Expired Ads Cleanup Function**
   - Function: `cleanup_expired_ads()`
   - Purpose: Delete expired ads (can be scheduled)

3. **User Avatar Cleanup Trigger**
   - Function: `cleanup_user_avatar()`
   - Trigger: `trigger_cleanup_user_avatar`
   - Runs: BEFORE DELETE on `users` table

4. **Orphaned Image Finder**
   - Function: `cleanup_orphaned_images()`
   - Purpose: Find images without database references

---

## 🚀 INSTALLATION STEPS

### **Step 1: Run the SQL Script**

1. Open **Supabase Dashboard**
2. Go to **SQL Editor**
3. Copy the entire content of `lib/security/AUTO_CLEANUP_STORAGE.sql`
4. Paste and **Run**

### **Step 2: Verify Installation**

Run this query to check triggers:

```sql
SELECT 
  trigger_name,
  event_object_table,
  action_timing
FROM information_schema.triggers
WHERE trigger_name IN (
  'trigger_cleanup_ad_image',
  'trigger_cleanup_user_avatar'
);
```

**Expected Result:**
```
trigger_name                  | event_object_table | action_timing
------------------------------|-------------------|---------------
trigger_cleanup_ad_image      | ads               | BEFORE
trigger_cleanup_user_avatar   | users             | BEFORE
```

---

## 🔍 HOW IT WORKS

### **1. Ad Image Cleanup**

```
Admin deletes ad
       ↓
DELETE FROM ads WHERE id = '...'
       ↓
Trigger: trigger_cleanup_ad_image
       ↓
Function: cleanup_ad_image()
       ↓
1. Extract filename from image_url
2. DELETE FROM storage.objects
       ↓
✅ Ad AND image both deleted!
```

**Example:**
```sql
-- This ad has an image
DELETE FROM ads WHERE id = 'some-ad-id';

-- Automatically:
-- 1. Ad record deleted from database
-- 2. Image file deleted from 'ads' bucket
```

### **2. Expired Ad Cleanup**

```
Run cleanup function (manual or scheduled)
       ↓
SELECT cleanup_expired_ads();
       ↓
Finds all ads WHERE:
  - end_date < NOW()
  - is_active = false
       ↓
DELETE FROM ads (for each expired ad)
       ↓
Trigger cleanup_ad_image() fires for each
       ↓
✅ All expired ads and images cleaned up!
```

### **3. User/Provider Avatar Cleanup**

```
Admin deletes user account
       ↓
DELETE FROM users WHERE id = '...'
       ↓
Trigger: trigger_cleanup_user_avatar
       ↓
Function: cleanup_user_avatar()
       ↓
1. Extract filename from avatar_url
2. DELETE FROM storage.objects
       ↓
✅ User AND avatar both deleted!
```

---

## 🧪 TESTING

### **Test 1: Ad Image Cleanup**

```sql
-- 1. Create a test ad with image
INSERT INTO ads (id, title, image_url, end_date, is_active)
VALUES (
  gen_random_uuid(),
  'Test Ad',
  'https://rvrpsqdrbwfvllelyqhf.supabase.co/storage/v1/object/public/ads/test-image.jpg',
  NOW() + INTERVAL '1 day',
  true
);

-- 2. Delete the ad
DELETE FROM ads WHERE title = 'Test Ad';

-- 3. Check storage - image should be gone
SELECT * FROM storage.objects 
WHERE bucket_id = 'ads' 
AND name = 'test-image.jpg';
-- Should return 0 rows
```

### **Test 2: Expired Ads Cleanup**

```sql
-- 1. Create expired test ad
INSERT INTO ads (id, title, image_url, end_date, is_active)
VALUES (
  gen_random_uuid(),
  'Expired Test Ad',
  'https://rvrpsqdrbwfvllelyqhf.supabase.co/storage/v1/object/public/ads/expired.jpg',
  NOW() - INTERVAL '1 day',  -- Already expired
  false
);

-- 2. Run cleanup
SELECT cleanup_expired_ads();

-- 3. Verify ad is gone
SELECT * FROM ads WHERE title = 'Expired Test Ad';
-- Should return 0 rows
```

### **Test 3: User Avatar Cleanup**

```sql
-- 1. Check a user's avatar
SELECT id, full_name, avatar_url 
FROM users 
WHERE id = 'test-user-id';

-- 2. Delete the user (CAUTION: Only use test accounts!)
DELETE FROM users WHERE id = 'test-user-id';

-- 3. Check storage - avatar should be gone
SELECT * FROM storage.objects 
WHERE bucket_id = 'avatars';
-- The user's avatar file should not be in the list
```

---

## 📊 MONITORING

### **Check Recent Deletions (Logs)**

In your Supabase **Logs** section, look for:

```
Deleted ad image from storage: test-image.jpg
Deleted user avatar from storage: avatar-123.jpg (User: John Doe)
Cleaned up 5 expired ads
```

### **Find Orphaned Images**

Images that exist in storage but have no database reference:

```sql
SELECT * FROM cleanup_orphaned_images();
```

**Result shows:**
```
bucket   | filename        | action
---------|----------------|-------------
ads      | orphan-1.jpg   | Would delete
avatars  | orphan-2.png   | Would delete
```

*(Manual deletion required for these)*

---

## 🔄 AUTOMATIC EXPIRY CLEANUP (Optional)

### **Option 1: Manual Cleanup**

Run this whenever you want:

```sql
SELECT cleanup_expired_ads();
```

### **Option 2: Scheduled Cleanup (Advanced)**

If you have **pg_cron** extension enabled:

```sql
-- Run cleanup every day at 2 AM
SELECT cron.schedule(
  'cleanup-expired-ads',     -- Job name
  '0 2 * * *',               -- Cron schedule (2 AM daily)
  'SELECT cleanup_expired_ads()'
);
```

### **Option 3: Edge Function (Alternative)**

Create a Supabase Edge Function that runs periodically:

```typescript
// edge-functions/cleanup-expired-ads/index.ts
import { createClient } from '@supabase/supabase-js'

Deno.serve(async (req) => {
  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
  )
  
  const { data, error } = await supabase.rpc('cleanup_expired_ads')
  
  return new Response(
    JSON.stringify({ success: !error, data }),
    { headers: { 'Content-Type': 'application/json' } }
  )
})
```

---

## 🎨 FLUTTER INTEGRATION

### **Admin Ads Page - Already Integrated!**

When admin deletes an ad from the Flutter app:

```dart
// In admin_ads.dart
await SupabaseConfig.supabase
    .from('ads')
    .delete()
    .eq('id', adId);

// The trigger automatically deletes the image from storage!
// No extra code needed in Flutter
```

### **Admin User Management - Already Works!**

When admin deletes a user:

```dart
// In admin dashboard
await SupabaseConfig.supabase
    .from('users')
    .delete()
    .eq('id', userId);

// The trigger automatically deletes the avatar from storage!
// No extra code needed in Flutter
```

---

## ⚠️ IMPORTANT NOTES

### **Storage Buckets Required**

Make sure these buckets exist in Supabase Storage:

1. **`ads`** - For ad images
2. **`avatars`** - For user/provider profile pictures

### **Security**

- Functions use `SECURITY DEFINER` to access `storage.objects`
- Only database operations can trigger these functions
- Cannot be called directly from Flutter (security)

### **Cascading Deletes**

When you delete a user, consider:

1. **Orders** created by user
2. **Feedback** given by user
3. **Notifications** for user
4. **Service requests** by user

You may want to:
- Add `ON DELETE CASCADE` to foreign keys
- Or soft-delete users instead of hard-delete

### **Backup Considerations**

Before implementing:

1. **Backup your database** and storage
2. **Test thoroughly** with test accounts
3. **Consider soft deletes** for users (set is_active = false)

---

## 🔧 CUSTOMIZATION

### **Change Bucket Names**

If your buckets have different names:

```sql
-- In cleanup_ad_image()
bucket_name TEXT := 'my-ads-bucket';  -- Change this

-- In cleanup_user_avatar()
bucket_name TEXT := 'my-avatars-bucket';  -- Change this
```

### **Add More File Types**

To cleanup other file types:

```sql
-- Example: Cleanup service images
CREATE OR REPLACE FUNCTION cleanup_service_image()
RETURNS TRIGGER AS $$
DECLARE
  image_path TEXT;
BEGIN
  IF OLD.image_url IS NOT NULL THEN
    image_path := substring(OLD.image_url from '[^/]+$');
    DELETE FROM storage.objects 
    WHERE bucket_id = 'services' 
    AND name = image_path;
  END IF;
  RETURN OLD;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER trigger_cleanup_service_image
  BEFORE DELETE ON services
  FOR EACH ROW
  EXECUTE FUNCTION cleanup_service_image();
```

---

## ✅ VERIFICATION CHECKLIST

After installation:

- [ ] SQL script ran without errors
- [ ] Triggers appear in information_schema.triggers
- [ ] Test ad deletion → Image deleted from storage
- [ ] Test user deletion → Avatar deleted from storage
- [ ] `cleanup_expired_ads()` function works
- [ ] `cleanup_orphaned_images()` function works
- [ ] No errors in Supabase logs

---

## 🎯 BENEFITS

| Before | After |
|--------|-------|
| Manual cleanup needed | ✅ Automatic |
| Storage fills with orphaned files | ✅ Always clean |
| Costs increase over time | ✅ Optimized |
| Admin must remember to clean | ✅ Triggers do it |

---

## 📊 EXPECTED RESULTS

### **When Ad is Deleted:**
```
Before: 
- Database: Ad record exists
- Storage: Image file exists

DELETE FROM ads WHERE id = '123';

After:
- Database: Ad record gone ✅
- Storage: Image file gone ✅
```

### **When User is Deleted:**
```
Before:
- Database: User record exists
- Storage: Avatar file exists

DELETE FROM users WHERE id = '456';

After:
- Database: User record gone ✅
- Storage: Avatar file gone ✅
```

---

## 🚀 NEXT STEPS

1. **Install the SQL script** in Supabase
2. **Test with dummy data** first
3. **Verify triggers** work correctly
4. **Optional:** Set up scheduled cleanup for expired ads
5. **Monitor** storage usage decreasing

---

**STATUS: READY TO INSTALL** 🎉

**Just run the SQL script in Supabase Dashboard and you're done!**

The triggers will automatically handle all storage cleanup from now on!
