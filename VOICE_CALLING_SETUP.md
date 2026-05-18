# LiveKit Voice Calling Implementation Guide

## Overview
This guide covers the complete implementation of Realtime Voice Calling using LiveKit in the Mr.Helper Flutter app.

## What Changed

### 1. Backend (`backend/`)

#### Added LiveKit Token Endpoint
- **File**: `backend/server.js`
- **Route**: `POST /getToken`
- **Functionality**: Generates JWT tokens for LiveKit room access

**Request Body:**
```json
{
  "roomName": "ORDER_ID",
  "userName": "CURRENT_USER_ID"
}
```

**Response:**
```json
{
  "status": "success",
  "token": "YOUR_JWT_TOKEN_HERE",
  "roomName": "ORDER_ID",
  "identity": "uniquely_generated_identity"
}
```

#### Environment Variables (`.env`)
```bash
LIVEKIT_API_KEY=your_livekit_api_key
LIVEKIT_API_SECRET=your_livekit_api_secret
LIVEKIT_URL=https://your-livekit-server.com
```

### 2. Flutter App

#### New Files Created
- **`lib/call/livekit_service.dart`**: Service for token fetching and room management
- **`lib/call/voice_call_screen.dart`**: Modern voice call UI with mute/speaker controls

#### Modified Files
- **`lib/orders/order_detail.dart`**:
  - Replaced "Call" button with "Voice Call" button
  - Added `_startVoiceCall()` method
  - Added LiveKit integration

- **`android/app/src/main/AndroidManifest.xml`**:
  - Added `BLUETOOTH_CONNECT` permission
  - Added `MODIFY_AUDIO_SETTINGS` permission

- **`pubspec.yaml`**:
  - Added `livekit_client: ^2.0.1`
  - Added `dio: ^5.4.0`
  - Added `permission_handler: ^11.0.1`

## Configuration Required

### 1. Set Up LiveKit Server

#### Option A: LiveKit Cloud (Recommended)
1. Visit https://cloud.livekit.io/
2. Create a new project
3. Copy your API Key and API Secret
4. Update `backend/.env`:
   ```bash
   LIVEKIT_API_KEY=your_cloud_api_key
   LIVEKIT_API_SECRET=your_cloud_api_secret
   LIVEKIT_URL=https://your-project.livekit.io
   ```

#### Option B: Self-Hosted LiveKit
1. Deploy LiveKit server (Docker, EC2, etc.)
2. Update `.env`:
   ```bash
   LIVEKIT_URL=http://localhost:7880  # development
   LIVEKIT_URL=https://livekit.yourdomain.com  # production
   ```

### 2. Configure Backend URL in Flutter

**File**: `lib/call/livekit_service.dart`

```dart
static const String _backendUrl = 'https://your-backend.onrender.com';
static const String _livekitUrl = 'wss://your-project.livekit.io';
```

Update these with your actual:
- Backend Render URL (for `/getToken` endpoint)
- LiveKit WebSocket URL (for room connection)

### 3. Deploy to Render

**Backend Steps:**
1. Push backend folder to GitHub
2. Create new Web Service on Render
3. Connect repository
4. Set environment variables in Render Dashboard:
   - `LIVEKIT_API_KEY`
   - `LIVEKIT_API_SECRET`
   - `LIVEKIT_URL`
5. Deploy

**Flutter Steps:**
1. Run `flutter pub get`
2. Build and test on device
3. Deploy to App Stores

## Usage Flow

### Customer Side
1. Opens Order Details page
2. Clicks "Voice Call" button
3. App fetches token from backend
4. App connects to LiveKit room (order ID as room name)
5. Voice call starts with provider

### Provider Side
1. Receives notification (optional)
2. Opens same room with same order ID
3. Joins voice call
4. Both parties can now talk

## Call Screen Features

- **Black background** with modern design
- **Caller name display**
- **Call status indicators**:
  - "Connecting..."
  - "Connected"
  - "Call Ended"
  - "Failed"
- **Mute button**: Toggle microphone
- **Speaker button**: Toggle speakerphone
- **End call button**: Large red hangup button

## Testing Checklist

- [ ] LiveKit API credentials configured
- [ ] Backend deployed with `/getToken` endpoint working
- [ ] Flutter app compiles without errors
- [ ] Microphone permission granted
- [ ] Voice call connects successfully
- [ ] Mute/unmute works
- [ ] Speaker toggle works
- [ ] Both parties can hear each other
- [ ] Call ends cleanly on both sides

## Troubleshooting

### Connection Failed
- Check `LIVEKIT_URL` is correct
- Verify API key/secret in `.env`
- Check network connectivity

### Token Generation Failed
- Verify backend `/getToken` endpoint responds
- Check CORS is enabled on backend
- Ensure `LIVEKIT_API_KEY` and `LIVEKIT_API_SECRET` are set

### Audio Issues
- Grant microphone permission
- Check device volume
- Verify Bluetooth permissions for Android

## Backend API Reference

### POST /getToken
Generate LiveKit token for room access.

**Headers:**
- `Content-Type: application/json`

**Body:**
```json
{
  "roomName": "order_12345",
  "userName": "user@example.com"
}
```

**Success Response (200):**
```json
{
  "status": "success",
  "token": "eyJhbGci...",
  "roomName": "order_12345",
  "identity": "user@example.com_abc123"
}
```

**Error Response (400):**
```json
{
  "status": "error",
  "message": "Missing required fields: roomName and userName"
}
```

**Error Response (500):**
```json
{
  "status": "error",
  "message": "Failed to generate token"
}
```

## Security Notes

1. ** Never expose LiveKit API Secret in client code**
   - Backend generates tokens securely
   - Only return token to authenticated users

2. ** Use HTTPS in production**
   - LiveKit WebSocket connections should use wss://

3. ** Token expiry**
   - Tokens expire in 24 hours
   - Generate new token for each call

4. ** Room access control**
   - Room names use order IDs
   - Users can only join rooms with valid tokens

## Future Enhancements

- Video calling support
- Call recording
- In-call messaging
- Call quality metrics
- Background call notification
- Missed call handling
- Call logs/history