# Quick Reference: Replace Test Ad IDs with Production IDs

## When You're Ready for Production

### File 1: AndroidManifest.xml
**Location**: `android/app/src/main/AndroidManifest.xml`
**Line**: 23

**Current (Test ID):**
```xml
<meta-data
    android:name="com.google.android.gms.ads.APPLICATION_ID"
    android:value="ca-app-pub-3940256099942544~3347511713"/>
```

**Replace with:**
```xml
<meta-data
    android:name="com.google.android.gms.ads.APPLICATION_ID"
    android:value="YOUR_ADMOB_APP_ID"/>
```

---

### File 2: admob_banner.dart
**Location**: `lib/widgets/admob_banner.dart`
**Line**: 24

**Current (Test ID):**
```dart
const String adUnitId = 'ca-app-pub-3940256099942544/6300978111';
```

**Replace with:**
```dart
const String adUnitId = 'YOUR_BANNER_AD_UNIT_ID';
```

---

## How to Get Your Production IDs

### 1. Go to AdMob
Visit: https://admob.google.com

### 2. Get App ID
1. Apps → Your App → App Settings
2. Copy the **App ID** (starts with `ca-app-pub-`)

### 3. Get Banner Ad Unit ID
1. Apps → Your App → Ad units
2. Find your banner ad unit
3. Copy the **Ad unit ID** (starts with `ca-app-pub-`)

---

## Note About Test vs Production

- **Test IDs**: Show "Test Ad" banner, no revenue, safe to click
- **Production IDs**: Show real ads, generate revenue, DON'T click your own ads!

**⚠️ NEVER click your own production ads** - Google will ban your AdMob account!
