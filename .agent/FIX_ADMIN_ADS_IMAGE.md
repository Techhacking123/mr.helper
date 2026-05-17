# 🔧 FIX: Admin Ads Image Upload & Preview Issue

## 🎯 PROBLEM
1. Images are not uploading in admin ads page
2. Uploaded image preview is not showing during upload

## ✅ SOLUTION

The current code SHOULD work, but there might be issues with:
1. Image file permissions
2. Storage bucket not configured
3. Image preview not refreshing

---

## 🚀 QUICK FIXES

### **Fix 1: Check Supabase Storage Bucket**

Run this in Supabase SQL Editor:

```sql
-- Check if ads bucket exists
SELECT * FROM storage.buckets WHERE name = 'ads';

-- If not found, create it with this SQL:
INSERT INTO storage.buckets (id, name, public)
VALUES ('ads', 'ads', true);

-- Set public access policy
CREATE POLICY "Public Access"
ON storage.objects FOR SELECT
USING ( bucket_id = 'ads' );

CREATE POLICY "Authenticated users can upload"
ON storage.objects FOR INSERT
WITH CHECK ( bucket_id = 'ads' AND auth.role() = 'authenticated' );

CREATE POLICY "Authenticated users can update"
ON storage.objects FOR UPDATE
USING ( bucket_id = 'ads' AND auth.role() = 'authenticated' );

CREATE POLICY "Authenticated users can delete"
ON storage.objects FOR DELETE
USING ( bucket_id = 'ads' AND auth.role() = 'authenticated' );
```

---

### **Fix 2: Check Image Permissions (Android)**

If on Android, check `AndroidManifest.xml`:

File: `android/app/src/main/AndroidManifest.xml`

Make sure these permissions exist:
```xml
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"/>
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE"/>
<uses-permission android:name="android.permission.CAMERA"/>
```

---

### **Fix 3: Hot Restart After Image Pick**

The current code has delays and unfocus logic. If preview still not showing:

**Try these steps:**
1. Pick an image
2. Wait 2-3 seconds
3. The preview should appear

**If still not working:**
- Check the terminal for errors
- Look for: `Image preview error:` or `Error picking image:`

---

## 🔍 DEBUG STEPS

### **Step 1: Check Console Logs**

After picking an image, check your terminal for:
```
flutter: Image picked directly: /path/to/image.jpg
```

**If you see this:** Image was picked correctly

**If you DON'T see this:** Image picker is failing

---

### **Step 2: Test Image Upload**

1. Open Admin Ads page
2. Click "+"  button
3. Fill in title
4. Click "Pick Image"
5. Select an image from gallery
6. **Wait 2-3 seconds**
7. Check if preview appears

**Expected:**
- ✅ Image preview shows in gray box
- ✅ Green checkmark with filename below
- ✅ Close button (X) in top right of image

**If not showing:**
- Check terminal for errors
-  Check storage bucket exists

---

### **Step 3: Test Upload**

1. After image preview appears
2. Set expiry date
3. Click "Publish"
4. Watch loading spinner on button

**Expected:**
- ✅ Button shows loading spinner
- ✅ Dialog closes
- ✅ New ad appears in list with image

**If fails:**
- Check terminal for upload errors
- Verify storage bucket policies

---

## 🎨 EXPECTED UI FLOW

### **Before Image Pick:**
```
[Title field]
[Pick Image button]
OR
[Image URL field]
```

### **After Image Pick:**
```
[Title field]

┌─────────────────┐
│                 │
│  [Image Preview]│  <-- Should show here
│                 │
│    [X] (close)  │
└─────────────────┘
✅ Image selected: photo.jpg  <-- Green text

[Pick Image button] <-- Can pick again
OR
[Image URL field]
```

### **During Upload:**
```
[Cancel button]  [⏳ Publish]  <-- Loading spinner
```

---

## 🔧 MANUAL TEST QUERIES

### **Check if ads bucket exists:**
```sql
SELECT * FROM storage.buckets WHERE name = 'ads';
```

**Should return 1 row**

---

### **Check recent ads:**
```sql
SELECT 
  id,
  title,
  image_url,
  is_active,
  created_at
FROM ads
ORDER BY created_at DESC
LIMIT 5;
```

**Check if `image_url` contains proper Supabase storage URL**

---

### **Check storage objects:**
```sql
SELECT 
  name,
  created_at,
  metadata
FROM storage.objects
WHERE bucket_id = 'ads'
ORDER BY created_at DESC
LIMIT 10;
```

**Should show uploaded images**

---

## 🎯 COMMON ISSUES & FIXES

### **Issue 1: Image picker opens but image doesn't show**

**Cause:** State not updating or image file path issue

**Fix:**
- Hot restart app (`R` in terminal)
- Try again
- Check terminal for `Image picked directly:` message

---

### **Issue 2: Image shows but upload fails**

**Cause:** Storage bucket not configured or no permissions

**Fix:**
1. Run storage bucket SQL (Fix 1 above)
2. Check Supabase dashboard → Storage → Policies
3. Make sure 'ads' bucket is public

---

### **Issue 3: Preview shows broken image icon**

**Cause:** Image file not accessible or corrupt

**Fix:**
- Try a different image
- Check image file size (should be < 5MB)
- Check image format (JPG, PNG)

---

### **Issue 4: Upload button stuck loading**

**Cause:** Network error or storage error

**Fix:**
- Check terminal for error message
- Check internet connection
- Verify Supabase project is active

---

## 📱 SIMPLIFIED TEST

### **Quick Test (5 minutes):**

1. **Go to Supabase dashboard**
   - Storage → Check 'ads' bucket exists
   - If not, create it manually (Public bucket)

2. **Hot restart app**
   ```
   Press 'R' in terminal
   ```

3. **Test in app:**
   - Admin → Ads → +
   - Title: "Test Ad"
   - Click "Pick Image"
   - Select any image
   - **Wait 3 seconds**
   - Should see preview
   - Click "Publish"

4. **Verify:**
   - Ad appears in list with image
   - Image loads correctly

---

## ✅ VERIFICATION CHECKLIST

After following fixes:

- [ ] Storage bucket 'ads' exists in Supabase
- [ ] Bucket is set to public
- [ ] Storage policies are configured
- [ ] App has image permission (Android)
- [ ] Hot restarted Flutter app
- [ ] Can pick image from gallery
- [ ] Image preview appears after pick
- [ ] Green checkmark shows filename
- [ ] Can click Publish successfully
- [ ] Ad appears in list with image
- [ ] Image loads in list view

---

## 🚀 IF STILL NOT WORKING

**Share these details:**

1. **Console logs** after picking image
2. **Error messages** when publishing
3. **Storage bucket status** in Supabase
4. **Screenshot** of the dialog after picking image

---

**Most common fix:** Run the storage bucket SQL commands above!
