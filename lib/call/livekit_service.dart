import 'package:dio/dio.dart';
import 'package:flutter/material.dart' hide ConnectionState;
import 'package:livekit_client/livekit_client.dart';
import 'package:mrhelper/supabase_config.dart';
import '../auth/session_manager.dart';

/// LiveKit Service for voice calling functionality
class LiveKitService {
  static final LiveKitService _instance = LiveKitService._internal();
  factory LiveKitService() => _instance;

  LiveKitService._internal();

  /// The base URL of your LiveKit token backend
  /// Update this with your Render deployment URL
  static String _backendUrl = 'https://mrhelper-livekit-voice-call.onrender.com';

  /// LiveKit server URL (cloud or self-hosted)
  static String _livekitUrl = 'wss://mr-helper-t6v5dsu9.livekit.cloud';

  /// Set the backend URL
  static void setBackendUrl(String url) {
    _backendUrl = url;
  }

  /// Set the LiveKit server URL
  static void setLivekitUrl(String url) {
    _livekitUrl = url;
  }

  /// Base URL for the token endpoint
  static const String _getTokenUrl = '/getToken';

  /// Generate and fetch LiveKit token from backend
  /// 
  /// [roomName] - The name of the room (typically order ID)
  /// [userName] - The name/ID of the current user
  Future<String?> fetchToken({
    required String roomName,
    required String userName,
  }) async {
    try {
      final response = await Dio().post(
        '$_backendUrl$_getTokenUrl',
        data: {
          'roomName': roomName,
          'userName': userName,
        },
        options: Options(
          contentType: 'application/json',
        ),
      );

      if (response.statusCode == 200) {
        final token = response.data['token'];
        debugPrint('LiveKit token fetched successfully for room: $roomName');
        return token;
      } else {
        debugPrint('Failed to fetch token: ${response.statusCode}');
        debugPrint('Response: ${response.data}');
        return null;
      }
    } on DioException catch (e) {
      debugPrint('Dio error fetching LiveKit token: ${e.message}');
      debugPrint('Response data: ${e.response?.data}');
      return null;
    } catch (e) {
      debugPrint('Unexpected error fetching LiveKit token: $e');
      return null;
    }
  }

  /// Create a LiveKit room connection
  /// 
  /// [token] - The LiveKit token
  /// [roomName] - The name of the room to join
  /// [onConnected] - Callback when connected
  /// [onDisconnected] - Callback when disconnected
  /// [onError] - Callback for errors
  Future<Room?> connectRoom({
    required String token,
    required String roomName,
    Function(Room)? onConnected,
    Function(Room)? onDisconnected,
    Function(String)? onError,
  }) async {
    try {
      final room = Room();

      // Setup event listener using EventsListener (livekit_client v2 API)
      final listener = room.createListener();

      listener.on<RoomConnectedEvent>((event) {
        debugPrint('Connected to LiveKit room: $roomName');
        onConnected?.call(room);
      });

      listener.on<RoomDisconnectedEvent>((event) {
        debugPrint('Disconnected from LiveKit room: $roomName');
        onDisconnected?.call(room);
      });


      // Connect to the room — livekit_client v2 uses positional args: (url, token)
      await room.connect(
        _livekitUrl,
        token,
      );

      // Enable microphone after connecting (audio-only call)
      await room.localParticipant?.setMicrophoneEnabled(true);

      debugPrint('Successfully connected to room: $roomName');
      return room;
    } catch (e) {
      debugPrint('Error connecting to LiveKit room: $e');
      onError?.call(e.toString());
      return null;
    }
  }

  /// Get current user ID from session
  Future<String?> getCurrentUserId() async {
    try {
      final userId = await SessionManager.getUserId();
      if (userId != null) {
        debugPrint('Current user ID: $userId');
        return userId;
      }
      return null;
    } catch (e) {
      debugPrint('Error getting current user ID: $e');
      return null;
    }
  }

  /// Get current user email/username as name for the call
  Future<String?> getCurrentUserEmail() async {
    try {
      final username = await SessionManager.getUsername();
      if (username != null) {
        debugPrint('Current user username: $username');
        return username;
      }
      return null;
    } catch (e) {
      debugPrint('Error getting current user username: $e');
      return null;
    }
  }

  /// Send a call notification to the callee via the backend.
  /// The backend sends a DATA-ONLY FCM message so CallKit always shows.
  Future<bool> sendCallNotification({
    required String calleeId,
    required String callerName,
    required String orderId,
    required String callerId,
  }) async {
    try {
      debugPrint('Sending call notification via backend to $calleeId');
      final response = await Dio().post(
        '$_backendUrl/sendCallNotification',
        data: {
          'calleeId': calleeId,
          'callerName': callerName,
          'orderId': orderId,
          'callerId': callerId,
        },
        options: Options(contentType: 'application/json'),
      );
      if (response.statusCode == 200) {
        debugPrint('Call notification sent successfully');
        return true;
      }
      debugPrint('Call notification failed: ${response.data}');
      return false;
    } catch (e) {
      debugPrint('Error sending call notification: $e');
      return false;
    }
  }

  /// Send a call rejection notification to the caller via the backend.
  Future<bool> sendCallRejection({
    required String callerId,
    required String orderId,
  }) async {
    try {
      debugPrint('Sending call rejection via backend to $callerId');
      final response = await Dio().post(
        '$_backendUrl/sendCallRejection',
        data: {
          'callerId': callerId,
          'orderId': orderId,
        },
        options: Options(contentType: 'application/json'),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Error sending call rejection: $e');
      return false;
    }
  }
}