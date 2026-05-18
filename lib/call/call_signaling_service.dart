import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../supabase_config.dart';
import '../auth/session_manager.dart';
import '../main.dart';
import 'voice_call_screen.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

/// Real-time call signaling service using Supabase Realtime Broadcast.
/// This provides instant (sub-second) call signaling between devices.
class CallSignalingService {
  static CallSignalingService? _instance;
  static CallSignalingService get instance {
    _instance ??= CallSignalingService._internal();
    return _instance!;
  }

  CallSignalingService._internal();

  RealtimeChannel? _myChannel;
  String? _myUserId;
  bool _isListening = false;

  /// Initialize the signaling service — call this ONCE after user logs in.
  Future<void> startListening() async {
    if (_isListening) return;

    _myUserId = await SessionManager.getUserId();
    if (_myUserId == null) {
      developer.log('CallSignaling: No user ID, cannot start listening');
      return;
    }

    developer.log('📞 CallSignaling: Starting listener for user $_myUserId');

    // Subscribe to a personal broadcast channel
    _myChannel = SupabaseConfig.supabase.channel(
      'calls:$_myUserId',
      opts: const RealtimeChannelConfig(self: true),
    );

    _myChannel!.onBroadcast(
      event: 'incoming_call',
      callback: (payload) {
        developer.log('📞 CallSignaling: Incoming call received! $payload');
        _handleIncomingCall(payload);
      },
    );

    _myChannel!.onBroadcast(
      event: 'call_rejected',
      callback: (payload) {
        developer.log('📞 CallSignaling: Call was rejected');
        _handleCallRejected(payload);
      },
    );

    _myChannel!.onBroadcast(
      event: 'call_cancelled',
      callback: (payload) async {
        developer.log('📞 CallSignaling: Call was cancelled');
        await FlutterCallkitIncoming.endAllCalls();
        final context = navigatorKey.currentContext;
        if (context != null) {
          if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          }
        }
      },
    );

    await _myChannel!.subscribe();
    _isListening = true;
    developer.log('📞 CallSignaling: Listening on channel calls:$_myUserId');
  }

  /// Stop listening (call on logout)
  Future<void> stopListening() async {
    if (_myChannel != null) {
      await SupabaseConfig.supabase.removeChannel(_myChannel!);
      _myChannel = null;
    }
    _isListening = false;
    _myUserId = null;
    developer.log('📞 CallSignaling: Stopped listening');
  }

  /// Send a call signal to another user
  Future<bool> sendCallSignal({
    required String calleeId,
    required String callerName,
    required String orderId,
    required String callerId,
  }) async {
    try {
      developer.log('📞 CallSignaling: Sending call signal to $calleeId');

      // Join the callee's channel temporarily to broadcast
      final calleeChannel = SupabaseConfig.supabase.channel(
        'calls:$calleeId',
        opts: const RealtimeChannelConfig(self: false),
      );

      await calleeChannel.subscribe();

      // Small delay to ensure subscription is established
      await Future.delayed(const Duration(milliseconds: 500));

      // Send the call signal
      await calleeChannel.sendBroadcastMessage(
        event: 'incoming_call',
        payload: {
          'caller_id': callerId,
          'caller_name': callerName,
          'order_id': orderId,
          'timestamp': DateTime.now().toIso8601String(),
        },
      );

      developer.log('📞 CallSignaling: Call signal sent to $calleeId');

      // Leave the callee's channel after a short delay
      Future.delayed(const Duration(seconds: 2), () {
        SupabaseConfig.supabase.removeChannel(calleeChannel);
      });

      return true;
    } catch (e) {
      developer.log('📞 CallSignaling: Error sending call signal: $e');
      return false;
    }
  }

  /// Send rejection back to the caller
  Future<void> sendRejection({
    required String callerId,
    required String orderId,
  }) async {
    try {
      final callerChannel = SupabaseConfig.supabase.channel(
        'calls:$callerId',
        opts: const RealtimeChannelConfig(self: false),
      );

      await callerChannel.subscribe();
      await Future.delayed(const Duration(milliseconds: 500));

      await callerChannel.sendBroadcastMessage(
        event: 'call_rejected',
        payload: {
          'order_id': orderId,
          'timestamp': DateTime.now().toIso8601String(),
        },
      );

      Future.delayed(const Duration(seconds: 2), () {
        SupabaseConfig.supabase.removeChannel(callerChannel);
      });

      // 2. Also trigger FCM Push Notification to ensure delivery if caller app is in background
      try {
        await http.post(
          Uri.parse('https://mrhelper-backend.onrender.com/sendCallRejection'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'callerId': callerId,
            'orderId': orderId,
          }),
        );
      } catch (e) {
        developer.log('CallSignaling: Error triggering FCM call rejection: $e');
      }

      developer.log('📞 CallSignaling: Rejection sent to $callerId');
    } catch (e) {
      developer.log('📞 CallSignaling: Error sending rejection: $e');
    }
  }

  /// Caller cancels the call before receiver answers
  Future<void> sendCancellation({
    required String calleeId,
    required String orderId,
  }) async {
    try {
      final calleeChannel = SupabaseConfig.supabase.channel(
        'public:call_signaling_$calleeId',
      );
      
      calleeChannel.subscribe((status, error) async {
        if (status == ChannelStatus.subscribed) {
          await calleeChannel.sendBroadcastMessage(
            event: 'call_cancelled',
            payload: {'order_id': orderId},
          );
          developer.log('📞 CallSignaling: Cancellation broadcast sent to $calleeId');
        }
      });

      Future.delayed(const Duration(seconds: 2), () {
        SupabaseConfig.supabase.removeChannel(calleeChannel);
      });

      // Trigger FCM cancellation
      try {
        await http.post(
          Uri.parse('https://mrhelper-backend.onrender.com/sendCallCancellation'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'calleeId': calleeId,
            'orderId': orderId,
          }),
        );
      } catch (e) {
        developer.log('CallSignaling: Error triggering FCM call cancellation: $e');
      }

    } catch (e) {
      developer.log('📞 CallSignaling: Error sending cancellation: $e');
    }
  }

  /// Handle incoming call — show native CallKit UI
  void _handleIncomingCall(Map<String, dynamic> payload) async {
    final orderId = payload['order_id'] ?? 'unknown';
    final callerName = payload['caller_name'] ?? 'Someone';
    final callerId = payload['caller_id'] ?? '';

    developer.log('📞 Showing CallKit for call from $callerName');

    // Show native incoming call screen
    CallKitParams callKitParams = CallKitParams(
      id: orderId,
      nameCaller: callerName,
      appName: 'MrHelper',
      handle: 'Voice Call',
      type: 0, // audio
      textAccept: 'Accept',
      textDecline: 'Decline',
      missedCallNotification: const NotificationParams(
        showNotification: true,
        isShowCallback: false,
        subtitle: 'Missed call',
      ),
      duration: 30000,
      extra: <String, dynamic>{
        'order_id': orderId,
        'caller_name': callerName,
        'caller_id': callerId,
      },
      android: const AndroidParams(
        isCustomNotification: true,
        isShowLogo: false,
        ringtonePath: 'system_ringtone_default',
        backgroundColor: '#0955fa',
        actionColor: '#4CAF50',
        textColor: '#ffffff',
      ),
      ios: const IOSParams(
        iconName: 'CallKitLogo',
        handleType: '',
        supportsVideo: false,
        maximumCallGroups: 2,
        maximumCallsPerCallGroup: 1,
        audioSessionMode: 'default',
        audioSessionActive: true,
        audioSessionPreferredSampleRate: 44100.0,
        audioSessionPreferredIOBufferDuration: 0.005,
        supportsDTMF: true,
        supportsHolding: true,
        supportsGrouping: false,
        supportsUngrouping: false,
        ringtonePath: 'system_ringtone_default',
      ),
    );

    await FlutterCallkitIncoming.showCallkitIncoming(callKitParams);
  }

  /// Handle call rejection — show dialog to caller
  void _handleCallRejected(Map<String, dynamic> payload) {
    final context = navigatorKey.currentContext;
    if (context != null) {
      // Pop the VoiceCallScreen if it's open
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Call Rejected'),
          content: const Text('The recipient declined your call.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  /// Setup CallKit event listeners (Accept/Decline)
  void setupCallKitListeners() {
    FlutterCallkitIncoming.onEvent.listen((CallEvent? event) {
      if (event == null) return;
      switch (event.event) {
        case Event.actionCallAccept:
          developer.log('📞 CallKit: ACCEPTED');
          final body = event.body;
          final orderId = body['extra']?['order_id'];
          final callerName = body['extra']?['caller_name'];
          if (orderId != null) {
            final context = navigatorKey.currentContext;
            if (context != null) {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => VoiceCallScreen(
                    orderId: orderId,
                    callerName: callerName ?? 'Someone',
                    calleeName: 'You',
                    isCaller: false,
                  ),
                ),
              );
            }
          }
          break;
        case Event.actionCallDecline:
          developer.log('📞 CallKit: DECLINED');
          final body = event.body;
          final callerId = body['extra']?['caller_id'];
          final orderId = body['extra']?['order_id'];
          if (callerId != null) {
            sendRejection(
              callerId: callerId,
              orderId: orderId ?? '',
            );
          }
          break;
        default:
          break;
      }
    });
  }
}
