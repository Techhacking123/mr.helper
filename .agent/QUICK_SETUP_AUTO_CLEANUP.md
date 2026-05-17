# 🚀 QUICK SETUP: Auto Storage Cleanup

## ⚡ 5-MINUTE INSTALLATION

### **Step 1: Open Supabase Dashboard**
1. Go to https://supabase.com
2. Select your project
3. Click **SQL Editor** in left menu

### **Step 2: Run the Script**
1. Click **New Query**
2. Open `lib/security/AUTO_CLEANUP_STORAGE.sql`
3. **Copy ALL content** from the file
4. **Paste** into SQL Editor
5. Click **Run** button

### **Step 3: Verify**
Run this query:
```sql
SELECT trigger_name, event_object_table
FROM information_schema.triggers
WHERE trigger_name LIKE '%cleanup%';
```

**Expected result: 2 triggers**
- `trigger_cleanup_ad_image` on `ads`
- `trigger_cleanup_user_avatar` on `users`

---

## ✅ WHAT IT DOES

### **Automatic Cleanup:**

1. **Delete Ad** → Image auto-deleted from `ads` bucket
2. **Delete User** → Avatar auto-deleted from `avatars` bucket  
3. **Manual:** Run `SELECT cleanup_expired_ads();` to clean expired ads

---

## 🧪 QUICK TEST

Test ad cleanup:
```sql
-- Create test ad
INSERT INTO ads (title, image_url, end_date, is_active)
VALUES ('TEST', 'https://yourproject.supabase.co/storage/v1/object/public/ads/test.jpg', NOW() + INTERVAL '1 day', true);

-- Delete it
DELETE FROM ads WHERE title = 'TEST';

-- Check logs - should see: "Deleted ad image from storage: test.jpg"
```

---

## 📋 CHECKLIST

- [ ] SQL script run successfully
- [ ] 2 triggers created (verified with query)
- [ ] Test ad deletion works
- [ ] No errors in logs

---

## 🎯 RESULT

**From now on:**
- ✅ Admin deletes ad → Image auto-deleted
- ✅ Admin deletes user → Avatar auto-deleted
- ✅ No manual cleanup needed!

---

**TIME TO INSTALL:** ~3 minutes  
**COMPLEXITY:** Easy  
**MAINTENANCE:** Zero

Just run the SQL script and you're done! 🎉
