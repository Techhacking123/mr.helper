# LiveKit Backend Setup Guide

## Step 1: Create LiveKit Cloud Project

1. Go to https://cloud.livekit.io/
2. Click "Create Project"
3. Fill in project details:
   - Project Name: `mr-helper-voice`
   - Region: Choose nearest region
4. Click "Create"

## Step 2: Get LiveKit Credentials

1. In your LiveKit project dashboard, go to **Settings** > **API Keys**
2. Copy the **API Key** (looks like: `XYZ...`)
3. Copy the **API Secret** (looks like: `abc...123`)
4. Also copy your **Project URL** (looks like: `https://your-project.livekit.io`)

## Step 3: Configure Backend Environment

Edit `backend/.env`:

```bash
# LiveKit Configuration
LIVEKIT_API_KEY=your_api_key_from_step_2
LIVEKIT_API_SECRET=your_api_secret_from_step_2
LIVEKIT_URL=https://your-project.livekit.io

# Keep existing Supabase and Google Play configs
SUPABASE_URL=https://supabase-deep.phoenixsoftwaresolutions172.workers.dev
SUPABASE_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
GOOGLE_PLAY_PACKAGE_NAME=com.mrhelper.app
GOOGLE_SERVICE_ACCOUNT_KEY_PATH=google-service-account.json
```

## Step 4: Install Backend Dependencies

In the `backend` folder:

```bash
npm install
```

This will install `livekit-server-sdk` which was added in `package.json`.

## Step 5: Deploy to Render

### Method A: New Render Deployment

1. Push code to GitHub repository
2. Go to https://render.com/
3. Create new **Web Service**
4. Connect your repository
5. Set environment variables:
   - `LIVEKIT_API_KEY`
   - `LIVEKIT_API_SECRET`
   - `LIVEKIT_URL`
6. Click **Deploy**

### Method B: Existing Render Deployment

If you already have backend deployed:

1. Go to Render Dashboard
2. Select your existing service
3. Click **Manual Deploy** > **Deploy Latest Commit**
4. Add environment variables in the service settings

## Step 6: Test Backend Endpoint

### Locally (for testing):

```bash
cd backend
node server.js
```

Test with curl:

```bash
curl -X POST http://localhost:3000/getToken \
  -H "Content-Type: application/json" \
  -d '{"roomName":"test_order_123","userName":"test_user@example.com"}'
```

Expected response:

```json
{
  "status": "success",
  "token": "eyJhbGci...",
  "roomName": "test_order_123",
  "identity": "..."
}
```

### On Render (production):

```bash
curl -X POST https://your-backend.onrender.com/getToken \
  -H "Content-Type: application/json" \
  -d '{"roomName":"test_order_123","userName":"test_user@example.com"}'
```

## Step 7: Update Flutter Configuration

Edit `lib/call/livekit_service.dart`:

```dart
/// The base URL of your LiveKit token backend
static const String _backendUrl = 'https://your-backend.onrender.com';

/// LiveKit server URL (cloud or self-hosted)
static const String _livekitUrl = 'wss://your-project.livekit.io';
```

Update with:
- `_backendUrl`: Your Render deployed backend URL
- `_livekitUrl`: Your LiveKit project URL (use `wss://` prefix)

For LiveKit Cloud, the WebSocket URL is typically:
```
wss://your-project.livekit.io
```

## Step 8: Test Voice Call

1. Run Flutter app on device
2. Navigate to any order details
3. Click "Voice Call" button
4. Should see "Connecting..." then "Connected" status
5. Both customer and provider should be able to hear each other

## Troubleshooting

### Error: "Failed to connect to call server"
- Check backend URL in Flutter matches Render URL
- Verify LiveKit credentials in `.env`

### Error: "Token generation failed"
- Verify `LIVEKIT_API_KEY` and `LIVEKIT_API_SECRET` are set in `.env`
- Check LiveKit project URL is correct

### Error: "Microphone permission denied"
- Grant microphone permission on device
- On Android: Settings > Apps > Mr.Helper > Permissions

### Call connects but no audio
- Check device volume
- Try toggling mute/unmute
- Check speaker button (headset vs speakerphone)