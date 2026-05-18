# 📞 LiveKit Voice Calling Implementation

Complete voice calling system for Mr.Helper app using LiveKit and LiveKit Server SDK.

## ✅ What's Been Implemented

### Backend (`backend/`)
- ✅ LiveKit token generation endpoint (`POST /getToken`)
- ✅ CORS enabled for Flutter API calls
- ✅ Secure JWT token generation with room access
- ✅ Render deployment ready

### Flutter App (`lib/`)
- ✅ `lib/call/livekit_service.dart` - Token fetching & room management
- ✅ `lib/call/voice_call_screen.dart` - Modern voice call UI
- ✅ Updated `lib/orders/order_detail.dart` - Voice Call button
- ✅ New dependencies added (livekit_client, dio, permission_handler)
- ✅ Android Bluetooth & audio permissions added

## 🚀 Quick Start Guide

### 1. Set Up LiveKit Cloud (5 minutes)

1. Go to https://cloud.livekit.io/
2. **Create Project** → Name: `mr-helper-voice`
3. **Copy Credentials** from Settings > API Keys:
   - API Key: `XXX`
   - API Secret: `YYY`
   - Project URL: `https://your-project.livekit.io`

### 2. Configure Backend (5 minutes)

Edit `backend/.env`:

```bash
# LiveKit Cloud
LIVEKIT_API_KEY=your_api_key_here
LIVEKIT_API_SECRET=your_api_secret_here
LIVEKIT_URL=https://your-project.livekit.io

# Keep existing configs
SUPABASE_URL=https://supabase-deep.phoenixsoftwaresolutions172.workers.dev
SUPABASE_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
GOOGLE_PLAY_PACKAGE_NAME=com.mrhelper.app
GOOGLE_SERVICE_ACCOUNT_KEY_PATH=google-service-account.json
```

### 3. Deploy Backend to Render (5 minutes)

1. Push `backend/` folder to GitHub
2. Go to https://render.com/ → **New Web Service**
3. Connect repository
4. Add environment variables:
   - `LIVEKIT_API_KEY`
   - `LIVEKIT_API_SECRET`
   - `LIVEKIT_URL`
5. Deploy! (URL: `https://your-backend.onrender.com`)

### 4. Configure Flutter (2 minutes)

Edit `lib/call/livekit_service.dart`:

```dart
static const String _backendUrl = 'https://your-backend.onrender.com';
static const String _livekitUrl = 'wss://your-project.livekit.io';
```

Update with your:
- Backend Render URL (from step 3)
- LiveKit WebSocket URL (from step 1, use `wss://` prefix)

### 5. Test (10 minutes)

```bash
# Install dependencies (already done)
flutter pub get

# Run on device
flutter run

# Test flow:
# 1. Navigate to Order Details
# 2. Click "Voice Call" button
# 3. Should see "Connecting..." then "Connected"
# 4. Both parties can hear each other
```

## 📖 Detailed Documentation

- [VOICE_CALLING_SETUP.md](VOICE_CALLING_SETUP.md) - Complete implementation guide
- [BACKEND_SETUP.md](BACKEND_SETUP.md) - Backend configuration steps
- [LIVEKIT_CLOUD_TUTORIAL.md](https://docs.livekit.io/) - LiveKit docs

## 🔧 Environment Variables Reference

### Backend (`.env`)

| Variable | Required | Description |
|----------|----------|-------------|
| `LIVEKIT_API_KEY` | ✅ | From LiveKit Cloud project |
| `LIVEKIT_API_SECRET` | ✅ | From LiveKit Cloud project |
| `LIVEKIT_URL` | ✅ | Your LiveKit project URL |
| `SUPABASE_URL` | ✅ | Supabase instance URL |
| `SUPABASE_KEY` | ✅ | Supabase anon key |

### Flutter (code config)

| Variable | Default | Description |
|----------|---------|-------------|
| `_backendUrl` | `https://your-backend.onrender.com` | Render backend URL |
| `_livekitUrl` | `wss://your-project.livekit.io` | LiveKit WebSocket URL |

## 📱 User Flow

### Customer (Caller)
1. Opens Order Details
2. Clicks **"Voice Call"** button
3. App fetches token from backend
4. Connects to LiveKit room (order ID)
5. Voice call starts

### Provider (Callee)
1. Receives notification (optional)
2. Opens same order details
3. Room auto-joins (same order ID)
4. Both parties connected

## 🎨 Call Screen Features

| Feature | Status | Description |
|---------|--------|-------------|
| Modern UI | ✅ | Black background, clean design |
| Mute Toggle | ✅ | Microphone on/off |
| Speaker Toggle | ✅ | Headset vs speakerphone |
| Call Status | ✅ | Connecting/Connected/Ended |
| End Call | ✅ | Large red hangup button |
| Caller Info | ✅ | Shows name |
| Error Handling | ✅ | Graceful failures |

## 🧪 API Reference

### GET `/health` (Backend Health)

```bash
curl https://your-backend.onrender.com/health
```

Response: `{"status":"ok","service":"mr-helper-backend","billing":"google_play"}`
```

### POST `/getToken` (Generate LiveKit Token)

**Request:**
```bash
curl -X POST https://your-backend.onrender.com/getToken \
  -H "Content-Type: application/json" \
  -d '{"roomName":"order_123","userName":"customer@example.com"}'
```

**Success Response (200):**
```json
{
  "status": "success",
  "token": "eyJhbGciOiJIUzI1NiIs...",
  "roomName": "order_123",
  "identity": "customer@example.com_abc123"
}
```

**Error Response (400):**
```json
{
  "status": "error",
  "message": "Missing required fields: roomName and userName"
}
```

## 🔐 Security Notes

1. **API Secret never exposed** - Only used in backend
2. **Tokens expire** - 24 hour expiry on all tokens
3. **CORS enabled** - Only from your app domain
4. **Room isolation** - Orders can only communicate with relevant parties
5. **Authentication required** - Only logged-in users can call

## 🐛 Troubleshooting

### "Microphone permission denied"
```bash
# Grant on device:
Android: Settings > Apps > Mr.Helper > Permissions > Microphone
iOS: Settings > Mr.Helper > Microphone > Allow
```

### "Failed to connect to call server"
1. Check `LIVEKIT_URL` in `.env`
2. Verify API key/secret are correct
3. Check network connection
4. Verify backend is running on Render

### "Token generation failed"
1. Check `LIVEKIT_API_KEY` in Render environment
2. Verify LiveKit project is active
3. Check Render logs: `https://render.com/dashboard/service/.../logs`

### Audio not working
1. Grant microphone permission
2. Try toggling mute/unmute
3. Check device volume
4. Test on different device/network

## 📦 Dependencies Added

| Package | Version | Purpose |
|---------|---------|---------|
| `livekit_client` | ^2.0.1 | LiveKit SDK for Flutter |
| `dio` | ^5.4.0 | HTTP client for API calls |
| `permission_handler` | ^11.0.1 | Request permissions |

## 📁 Files Changed

**New Files:**
- `lib/call/livekit_service.dart` (140 lines)
- `lib/call/voice_call_screen.dart` (400 lines)
- `backend/.env` (8 lines)
- `backend/.env.example` (17 lines)
- `VOICE_CALLING_SETUP.md` (100+ lines)
- `BACKEND_SETUP.md` (100+ lines)

**Modified Files:**
- `backend/server.js` (added LiveKit endpoint)
- `backend/package.json` (added livekit-server-sdk)
- `pubspec.yaml` (added 3 new dependencies)
- `android/app/src/main/AndroidManifest.xml` (added permissions)
- `lib/orders/order_detail.dart` (replaced call button)

## 🎯 Testing Checklist

Before production release:

- [ ] LiveKit project created and credentials configured
- [ ] Backend deployed and reachable on Render
- [ ] `/getToken` endpoint returns valid tokens
- [ ] Flutter app compiles without errors
- [ ] Voice call screen appears on button click
- [ ] Microphone permission granted
- [ ] "Connecting..." status appears
- [ ] "Connected" status appears after 2-3 seconds
- [ ] Both parties can hear each other
- [ ] Mute/unmute works
- [ ] Speaker toggle works
- [ ] "End Call" button works
- [ ] Room disconnects cleanly

## 🚦 Deployment Checklist

For production release:

### Backend
- [ ] `.env` with production credentials
- [ ] Deployed to Render
- [ ] Environment variables set in Render
- [ ] Health endpoint responds
- [ ] `/getToken` returns valid tokens

### Flutter
- [ ] Updated `_backendUrl` in code
- [ ] Updated `_livekitUrl` in code
- [ ] Tested on Android device
- [ ] Tested on iOS device (if applicable)
- [ ] All permissions granted
- [ ] No console errors

### Both
- [ ] Voice call works in development
- [ ] Voice call works in production
- [ ] Error handling tested
- [ ] Documentation updated

## 📞 Support

For LiveKit-specific questions:
- Docs: https://docs.livekit.io/
- Discord: https://discord.gg/livekit

For backend issues:
- Check Render logs
- Verify `.env` is set correctly
- Test endpoint locally first

For Flutter issues:
- Run `flutter clean && flutter pub get`
- Check device permissions
- Verify backend URL configuration

---

**Made with ❤️ for Mr.Helper**