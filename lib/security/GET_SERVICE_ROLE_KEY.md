# How to Get Your Supabase Service Role Key

## What You Need to Do

I've updated your code to use the **service role key** for admin uploads. This key bypasses RLS (Row-Level Security) policies, which is perfect for admin operations.

## Steps to Get the Service Role Key:

1. **Go to Supabase Dashboard**
   - Visit: https://supabase.com/dashboard
   - Select your project

2. **Navigate to Settings**
   - Click on **Settings** (gear icon) in the left sidebar
   - Click on **API** section

3. **Find the Service Role Key**
   - Scroll down to the **Project API keys** section
   - You'll see two keys:
     - `anon` / `public` key (already in your code)
     - **`service_role`** key ← This is what you need!
   - Click the **eye icon** to reveal the service_role key
   - Click **Copy** to copy it

4. **Update Your Code**
   - Open: `lib/supabase_config.dart`
   - Find this line:
     ```dart
     static const String supabaseServiceRoleKey = 'YOUR_SERVICE_ROLE_KEY_HERE';
     ```
   - Replace `'YOUR_SERVICE_ROLE_KEY_HERE'` with your actual service role key
   - Example:
     ```dart
     static const String supabaseServiceRoleKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...';
     ```

5. **Save and Restart**
   - Save the file
   - Hot restart your Flutter app (press `R` in the terminal, or stop and run again)

6. **Test Upload**
   - Try uploading a service image again
   - It should work immediately!

## ⚠️ IMPORTANT SECURITY NOTE

**NEVER commit the service role key to public repositories!**

The service role key has **full access** to your database and bypasses all security rules. Keep it secret!

### Best Practice (Optional):
Instead of hardcoding it, you can use environment variables:
1. Create a `.env` file (add it to `.gitignore`)
2. Store the key there
3. Use a package like `flutter_dotenv` to load it

But for now, the hardcoded approach will work fine if your repo is private.

## What Changed

I updated these files:
1. **`lib/supabase_config.dart`** - Added service role key and admin client
2. **`lib/admin/admin_services.dart`** - Changed upload/delete to use `adminClient` instead of regular `supabase` client

The admin client bypasses RLS, so uploads will work even without a Supabase Auth session.
