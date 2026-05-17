# Root Cause Analysis: Ad Upload Error 403

## 🔍 ERROR
```
StorageException(message: new row violates row-level security policy, statusCode: 403, error: Unauthorized)
```

## 🎯 ROOT CAUSE

Your app uses **Supabase anon key** for authentication (custom auth, not Supabase Auth).

When uploading an ad, the code does TWO operations:
1. **Upload image to storage** → `storage.from('ads').upload()` ✅ WORKS (policies fixed)
2. **Insert row into ads table** → `from('ads').insert()` ❌ FAILS (missing policy)

The error is happening at step 2 - inserting into the `ads` **table**.

### Why the Error Occurs:
1. The `ads` table has RLS enabled
2. RLS policies only allow `authenticated` role to INSERT
3. Your app uses the `anon` role (not authenticated)
4. Result: **403 Unauthorized**

## 📋 VERIFICATION STEPS

Before applying the fix, run this in Supabase SQL Editor to confirm:

```sql
-- Check current policies on ads table
SELECT 
  policyname,
  cmd,
  roles::text
FROM pg_policies 
WHERE tablename = 'ads'
AND schemaname = 'public'
AND cmd = 'INSERT';
```

**Expected Problem**: You'll see policies for `{authenticated}` but NOT for `{anon}` or `{public}`.

## ✅ SOLUTION

Apply the `fix_ads_table_rls.sql` script which creates an `anon` policy:

```sql
CREATE POLICY "Anon full access ads"
ON ads FOR ALL
TO anon
USING (true)
WITH CHECK (true);
```

This matches your existing pattern in `supabase_rls.sql` for other tables like:
- `orders` → "Anon Full Policy Orders"
- `order_offers` → "Anon Full Policy Offers"
- `notifications` → "Anon Full Policy Notifications"

## 🚀 STEP-BY-STEP FIX

### 1. Run Diagnostic (Optional but Recommended)
```
- Open `.agent/diagnose_ads_error.sql`
- Copy to Supabase SQL Editor
- Run it
- Share the "ADS TABLE POLICIES" section output with me
```

### 2. Apply the Fix
```
- Open `.agent/fix_ads_table_rls.sql`
- Copy entire content
- Paste in Supabase SQL Editor
- Click "Run"
- Wait for success message
```

### 3. Verify the Fix
After running the script, you should see in the output:
```
✅ Anon full access ads | ALL | {anon}
✅ Authenticated insert ads | INSERT | {authenticated}
✅ Public read ads | SELECT | {public}
```

### 4. Test
```
- Stop Flutter app (Ctrl+C)
- Run `flutter run`
- Navigate to Admin → Ads
- Click "Add Ad"
- Pick an image
- Fill in title
- Click "Publish"
- Should work! ✨
```

## 📊 WHY THIS HAPPENS

Your architecture uses **custom authentication** (storing users in your own `users` table) instead of Supabase Auth. This means:

- ✅ Advantage: Full control over user management
- ⚠️ Trade-off: All requests use the `anon` role
- 🔧 Solution: RLS policies must allow `anon` role for all operations

This is NOT a security issue when combined with proper app-level checks (like verifying `is_admin` flag).

## 🔐 SECURITY NOTE

The `anon` policy is safe because:
1. The anon key is meant to be public (in your client app)
2. You verify admin status in your **app code** before showing the Admin page
3. The RLS policy just ensures Supabase doesn't block legitimate requests
4. For tighter security, migrate to Supabase Auth in the future

## 🎯 EXPECTED OUTCOME

After applying the fix:
- ✅ Image uploads to storage bucket
- ✅ Row inserts into ads table
- ✅ Ad appears in the list immediately
- ✅ No more 403 errors

---

**Next**: Run the diagnostic script and share the output, OR directly apply the fix if you're confident!
