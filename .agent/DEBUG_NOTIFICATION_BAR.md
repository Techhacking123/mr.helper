# 🔧 DEBUG: Notifications Not Showing in Phone Bar

## Quick Checklist

### 1️⃣ **Did you FULLY RESTART the app?**

❌ Hot reload (`r`) - **NOT ENOUGH**  
❌ Hot restart (`R`) - **NOT ENOUGH**  
✅ **Full app restart** - **REQUIRED**

**Do this:**
```bash
# Stop the app completely
q

# Then restart
flutter run
```

Or on phone: **Force stop the app** and reopen.

**Why?** Notification channels are created at app initialization. They don't update with hot restart.

---

### 2️⃣ **Check Phone Settings**

On your **SM E166P** (Android 16):

1. **Long press** the app icon → **App info**
2. **Notifications** → Check:
   - ✅ "Show notifications" is **ON**
   - ✅ Look for **"high_importance_channel"** 
   - ✅ Set it to **"Urgent"** or **"High"** priority
   - ✅ Check "Lock screen" is enabled
   - ✅ Check "Pop on screen" is enabled

**Android 13+:** You might need to **grant notification permission** explicitly when app first launches.

---

### 3️⃣ **Check Notification Permission (Critical for Android 13+)**

Your phone is running **Android 16 (API 36)**, which requires explicit runtime permission for notifications.

**Check if permission is requested:**
- When you first launch the app, you should see a popup asking:
  > "Allow Mr.Helper to send you notifications?"
  
- If you denied it or it never appeared, notifications won't show.

**Fix:**
1. Phone Settings → Apps → Mr.Helper → Permissions
2. Check **"Notifications"** permission is **ALLOWED**

---

### 4️⃣ **Verify Notification Icon Exists**

Check if this file exists:
```
android/app/src/main/res/drawable/ic_notification.png
```

**If missing or invalid**, Android silently fails to show notifications.

**Solution:** Create a simple white icon PNG (24x24 or 48x48) and place it there.

---

### 5️⃣ **Test with Terminal Command**

While app is running, send a test notification via ADB:

```bash
adb shell am broadcast -a com.google.android.c2dm.intent.RECEIVE
```

Or test FCM directly from Firebase Console:
- Go to Firebase Console → Cloud Messaging
- Click "Send test message"
- Enter your FCM token
- Check if notification appears

---

### 6️⃣ **Check Flutter Logs**

When a notification is sent, check terminal for these logs:

**✅ GOOD:**
```
I/flutter: Foreground message received!
I/flutter: Message ID: ...
I/flutter: Title: ...
I/flutter: Attempting to show local notification...
I/flutter: Local notification request sent.
```

**❌ BAD:**
```
I/flutter: Error showing local notification: ...
```

If you see errors, that's the problem. Share the error message.

---

### 7️⃣ **Check Edge Function Payload**

The Edge Function must send **both** `notification` AND `data` payloads.

Check `supabase/functions/push_notifications/index.ts` line 79-100:

```typescript
const message = {
    token: fcmToken,
    notification: {  // ✅ This must exist
        title: 'Mr.Helper',
        body: messageBody,
    },
    data: {
        // ... data fields
    },
    // ...
};
```

If `notification` object is missing, FCM won't create a system notification.

---

## 🔍 MOST LIKELY CAUSES

### **Cause 1: Notification Permission Not Granted (80% probability)**

**Android 13+ requires runtime permission.**

**Fix:**
1. Uninstall the app
2. Reinstall: `flutter run`
3. When app launches, **allow notifications** when prompted
4. Test again

---

### **Cause 2: App Not Fully Restarted (15% probability)**

**Channel changes only apply after full restart.**

**Fix:**
1. Press `q` in terminal to quit
2. `flutter run` again
3. Or force stop on phone and relaunch

---

### **Cause 3: Notification Icon Missing (5% probability)**

**If icon doesn't exist, Android fails silently.**

**Fix:**
Create `android/app/src/main/res/drawable/ic_notification.png`

---

## 🧪 DEBUGGING STEPS

### Step 1: Check Logs After Receiving Notification

Create an order and immediately check terminal logs. Look for:

```
I/flutter: Foreground message received!
I/flutter: Attempting to show local notification...
```

**If you DON'T see these logs**, the FCM message isn't arriving at all.  
**If you DO see these logs** but no notification bar, it's a permission/channel issue.

---

### Step 2: Check Android Logcat

Run this in a separate terminal:
```bash
adb logcat | grep -i "notification"
```

Look for errors like:
- "NotificationManager: blocked by app"
- "NotificationChannel not found"
- "Permission denied"

---

### Step 3: Test with Simple Local Notification

Add this test button to verify local notifications work:

```dart
// In your app somewhere, add a test button:
ElevatedButton(
  onPressed: () async {
    final plugin = FlutterLocalNotificationsPlugin();
    await plugin.show(
      0,
      'Test Notification',
      'Can you see this in the notification bar?',
      NotificationDetails(
        android: AndroidNotificationDetails(
          'high_importance_channel',
          'MrHelper Notifications',
          importance: Importance.max,
          priority: Priority.high,
        ),
      ),
    );
  },
  child: Text('Test Notification'),
)
```

If this shows in notification bar: **FCM integration is the problem**  
If this DOESN'T show: **Permission or channel configuration is the problem**

---

## 💡 QUICK FIX TO TRY NOW

### Option 1: Uninstall and Reinstall

```bash
# Uninstall from phone
adb uninstall com.example.mrhelperAI

# Reinstall
flutter run

# Grant notification permission when prompted
```

### Option 2: Clear App Data

On phone:
- Settings → Apps → Mr.Helper → Storage → **Clear Data**
- Relaunch app
- Grant notification permission

### Option 3: Check Background vs Foreground

Is notification showing when:
- App is **closed** (completely killed)? If YES → Foreground issue
- App is in **background** (minimized)? If YES → Foreground issue
- App is in **foreground** (open)? If NO → This is the issue

---

## 📋 Report Back

Please check and tell me:

1. **Did you fully restart** (not hot restart) the app?
2. **Notification permission** - Is it granted in phone settings?
3. **Does test notification work?** (Try the test button code above)
4. **What do logs show** when you receive a notification?
5. **Android version** - You're on Android 16 (API 36) - very new!

---

Based on your answers, I can pinpoint the exact issue! 🎯
