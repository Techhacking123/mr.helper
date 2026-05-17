import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../supabase_config.dart';
import '../auth/session_manager.dart';
import '../main.dart'; // For navigatorKey
import '../subscription/subscription_page.dart'; // For deep linking
import '../orders/order_detail.dart'; // For deep linking
import 'dart:developer' as developer;
import 'dart:convert';
import 'dart:math';

// Background message handler - MUST be top-level function
// Background message handler - MUST be top-level function
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  developer.log('Background message received: ${message.messageId}');
  developer.log('Message notification: ${message.notification?.title}');

  // Show manual notification for background messages to ensure they appear
  if (message.notification == null) {
    await FCMService.showLocalNotification(message);
  }
}

class FCMService {
  static final FirebaseMessaging _firebaseMessaging =
      FirebaseMessaging.instance;
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  static String? _fcmToken;

  /// Initialize Firebase Cloud Messaging
  static Future<void> initialize() async {
    try {
      // Register background message handler
      FirebaseMessaging.onBackgroundMessage(
        _firebaseMessagingBackgroundHandler,
      );

      // Request notification permissions (iOS)
      NotificationSettings settings = await _firebaseMessaging
          .requestPermission(
            alert: true,
            announcement: false,
            badge: true,
            carPlay: false,
            criticalAlert: false,
            provisional: false,
            sound: true,
          );

      developer.log('FCM Permission status: ${settings.authorizationStatus}');

      if (settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional) {
        // Initialize local notifications
        await _initializeLocalNotifications();

        // CRITICAL: specific for iOS/Android foreground display
        await _firebaseMessaging.setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        );

        // Get FCM token
        _fcmToken = await _firebaseMessaging.getToken();
        developer.log('FCM Token: $_fcmToken');

        // Listen to token refresh
        _firebaseMessaging.onTokenRefresh.listen((newToken) {
          _fcmToken = newToken;
          developer.log('FCM Token refreshed: $newToken');
          _saveTokenToDatabase(newToken);
        });

        // Handle foreground messages
        FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

        // Handle notification taps (when app is in background but not terminated)
        FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

        // Check if app was opened from a terminated state via notification
        RemoteMessage? initialMessage = await _firebaseMessaging
            .getInitialMessage();
        if (initialMessage != null) {
          _handleNotificationTap(initialMessage);
        }

        developer.log('FCM Service initialized successfully');
      } else {
        developer.log('Notification permissions denied');
      }
    } catch (e) {
      developer.log('FCM initialization error: $e');
    }
  }

  /// Initialize local notifications for Android
  static Future<void> _initializeLocalNotifications() async {
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@drawable/ic_notification');

    const DarwinInitializationSettings iosSettings =
        DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: true,
        );

    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        developer.log('Local notification tapped: ${response.payload}');
        // Handle notification tap
      },
    );

    // Create Android notification channel
    // IMPORTANT: This channel ID MUST match the one in AndroidManifest.xml
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'high_importance_channel', // Must match AndroidManifest.xml
      'MrHelper Notifications', // name
      description: 'Notifications for orders, updates, and alerts',
      importance: Importance.max, // MAX importance to show in notification bar
      enableVibration: true,
      playSound: true,
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(channel);
  }

  /// Handle foreground messages (when app is open)
  static Future<void> _handleForegroundMessage(RemoteMessage message) async {
    developer.log('Foreground message received!');
    developer.log('Message ID: ${message.messageId}');
    developer.log('Title: ${message.notification?.title}');
    developer.log('Body: ${message.notification?.body}');

    RemoteNotification? notification = message.notification;

    // Show local notification explicitly
    if (notification != null) {
      developer.log('Attempting to show local notification...');

      try {
        await _localNotifications.show(
          notification.hashCode,
          notification.title,
          notification.body,
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'high_importance_channel', // Must match channel created above
              'MrHelper Notifications',
              channelDescription:
                  'Notifications for orders, updates, and alerts',
              importance: Importance.max,
              priority: Priority.high,
              icon: '@drawable/ic_notification',
              enableVibration: true,
              playSound: true,
            ),
            iOS: DarwinNotificationDetails(
              presentAlert: true,
              presentBadge: true,
              presentSound: true,
            ),
          ),
          payload: message.data.toString(),
        );
        developer.log('Local notification request sent.');
      } catch (e) {
        developer.log('Error showing local notification: $e');
      }
    }
  }

  /// Handle notification tap (when user taps notification)
  static void _handleNotificationTap(RemoteMessage message) {
    developer.log('Notification tapped: ${message.data}');

    try {
      final data = message.data;
      final screen = data['screen'];

      developer.log('Attempting to navigate to screen: $screen');

      // Get the navigator key from main.dart
      final context = navigatorKey.currentContext;

      if (context == null) {
        developer.log('Navigator context is null, cannot navigate');
        return;
      }

      // Handle different screen types
      switch (screen) {
        case 'subscription_page':
          developer.log('Navigating to Subscription Page');
          _navigateToSubscriptionPage(context);
          break;

        case 'order_detail':
          final orderId = data['order_id'];
          if (orderId != null) {
            developer.log('Navigating to Order Detail: $orderId');
            _navigateToOrderDetail(context, orderId);
          }
          break;

        default:
          developer.log('Unknown screen type: $screen');
      }
    } catch (e) {
      developer.log('Error handling notification tap: $e');
    }
  }

  /// Navigate to subscription page
  static void _navigateToSubscriptionPage(BuildContext context) {
    try {
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (context) => const SubscriptionPage()));
      developer.log('✅ Navigated to Subscription Page');
    } catch (e) {
      developer.log('Error navigating to subscription page: $e');
    }
  }

  /// Navigate to order detail page
  static void _navigateToOrderDetail(
    BuildContext context,
    String orderId,
  ) async {
    try {
      // Fetch order data first
      final orderData = await SupabaseConfig.supabase
          .from('orders')
          .select('*')
          .eq('id', orderId)
          .single();

      // Check if user is provider
      final userId = await SessionManager.getUserId();
      final isProvider = orderData['provider_id'] == userId;

      if (context.mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) =>
                OrderDetailPage(order: orderData, isProvider: isProvider),
          ),
        );
        developer.log('✅ Navigated to Order Detail: $orderId');
      }
    } catch (e) {
      developer.log('Error navigating to order detail: $e');
    }
  }

  /// Get current FCM token
  static String? getToken() {
    return _fcmToken;
  }

  /// Save FCM token to Supabase database (Multi-Device Support)
  static Future<void> _saveTokenToDatabase(String token) async {
    final userId = await SessionManager.getUserId();

    if (userId == null) {
      developer.log('No user logged in (SessionManager), skipping token save');
      return;
    }

    try {
      developer.log("💾 Saving FCM Token for user $userId (multi-device)");

      // Generate a unique device ID if not exists
      String? deviceId = await _getOrCreateDeviceId();

      // Use new multi-device RPC function
      final result = await SupabaseConfig.supabase.rpc(
        'add_or_update_fcm_token',
        params: {
          'p_user_id': userId,
          'p_fcm_token': token,
          'p_device_id': deviceId,
          'p_device_name': await _getDeviceName(),
          'p_platform': 'android', // Or detect dynamically
        },
      );

      developer.log('✅ FCM token saved (token_id: $result) for user: $userId');

      // Also update the legacy users.fcm_token column to keep it in sync
      // Use adminClient to bypass RLS (custom auth has no auth.uid())
      try {
        await SupabaseConfig.adminClient
            .from('users')
            .update({'fcm_token': token})
            .eq('id', userId);
        developer.log('✅ users.fcm_token column also updated');
      } catch (e2) {
        developer.log('⚠️ Could not update users.fcm_token column: $e2');
      }
    } catch (e) {
      developer.log('❌ Error saving FCM token: $e');
    }
  }

  /// Get or create a unique device ID for this installation
  static Future<String> _getOrCreateDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    const key = 'fcm_device_id';

    String? deviceId = prefs.getString(key);
    if (deviceId == null) {
      // Generate a unique device ID
      deviceId =
          'device_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(9999)}';
      await prefs.setString(key, deviceId);
      developer.log('📱 Generated new device ID: $deviceId');
    }

    return deviceId;
  }

  /// Get a human-readable device name
  static Future<String> _getDeviceName() async {
    // For now, return a generic name
    // TODO: Use device_info_plus package for actual device name
    return 'Android Device';
  }

  /// Save token to database for current user (call this after login)
  static Future<void> saveTokenForCurrentUser() async {
    if (_fcmToken != null) {
      await _saveTokenToDatabase(_fcmToken!);
    } else {
      // Try to get token if not already fetched
      String? token = await _firebaseMessaging.getToken();
      if (token != null) {
        _fcmToken = token;
        await _saveTokenToDatabase(token);
      }
    }
  }

  /// Clear FCM token from database when user signs out (Multi-Device Support)
  /// This only clears the token for the CURRENT device, not all devices
  static Future<void> clearTokenForCurrentUser() async {
    try {
      final userId = await SessionManager.getUserId();

      if (userId == null) {
        developer.log('No user logged in, skipping token clear');
        return;
      }

      developer.log("🗑️ Clearing FCM Token for user $userId on THIS device");

      // Get current device's token and device ID
      String? currentToken = _fcmToken ?? await _firebaseMessaging.getToken();
      String? deviceId = await _getOrCreateDeviceId();

      // Use new multi-device RPC function
      try {
        final result = await SupabaseConfig.supabase.rpc(
          'remove_fcm_token',
          params: {
            'p_user_id': userId,
            'p_fcm_token': currentToken,
            'p_device_id': deviceId,
          },
        );
        developer.log('✅ Removed $result token(s) for user: $userId');
      } catch (e) {
        developer.log('❌ Error clearing FCM token via RPC: $e');
      }

      // Clear the local token reference
      _fcmToken = null;
      developer.log('Local FCM token reference cleared');
    } catch (e) {
      developer.log('Error clearing FCM token: $e');
    }
  }

  /// Subscribe to a topic (useful for sending notifications to all providers, etc.)
  static Future<void> subscribeToTopic(String topic) async {
    try {
      await _firebaseMessaging.subscribeToTopic(topic);
      developer.log('Subscribed to topic: $topic');
    } catch (e) {
      developer.log('Error subscribing to topic: $e');
    }
  }

  /// Unsubscribe from a topic
  static Future<void> unsubscribeFromTopic(String topic) async {
    try {
      await _firebaseMessaging.unsubscribeFromTopic(topic);
      developer.log('Unsubscribed from topic: $topic');
    } catch (e) {
      developer.log('Error unsubscribing from topic: $e');
    }
  }

  // =========================================================
  // DEBUG & HELPER METHODS
  // =========================================================

  /// Manually show a local notification (Useful for background data messages)
  static Future<void> showLocalNotification(RemoteMessage message) async {
    // Re-initialize for background isolate if needed (safe to call multiple times)
    final FlutterLocalNotificationsPlugin localNotifs =
        FlutterLocalNotificationsPlugin();
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings(
          '@drawable/ic_notification',
        ); // Correct icon
    const InitializationSettings initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);
    await localNotifs.initialize(initializationSettings);

    // CRITICAL: Ensure Channel Exists before showing
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'high_importance_channel', // Must match AndroidManifest.xml
      'MrHelper Notifications', // title
      importance: Importance.max,
      enableVibration: true,
      playSound: true,
    );

    await localNotifs
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(channel);

    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
          'high_importance_channel', // Must match AndroidManifest.xml
          'MrHelper Notifications', // title
          importance: Importance.max,
          priority: Priority.high,
          showWhen: true,
          icon: '@drawable/ic_notification',
          enableVibration: true,
          playSound: true,
        );
    const NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
    );

    // Extract title/body regardless of whether it's in notification or data
    String? title = message.notification?.title ?? message.data['title'];
    String? body =
        message.notification?.body ??
        message.data['body'] ??
        message.data['message'];

    // Fallback: If sent via Supabase Edge Function (raw record payload), parse nested 'record'
    if (title == null || body == null) {
      if (message.data.containsKey('record')) {
        try {
          final record = message.data['record'];
          // 'record' might be a JSON string or a Map depending on FCM adapter
          final Map<String, dynamic> recordMap = record is String
              ? jsonDecode(record)
              : record;

          title ??= recordMap['title'] ?? 'Notification';
          body ??= recordMap['message'] ?? recordMap['body'] ?? 'New Message';
        } catch (e) {
          developer.log('Error parsing nested record data: $e');
        }
      }
    }

    title ??= 'New Notification';
    body ??= 'You have a new update';

    await localNotifs.show(
      message.hashCode,
      title,
      body,
      platformChannelSpecifics,
      payload: jsonEncode(message.data),
    );
  }

  /// Debug method to force save token and return status
  static Future<String> forceSaveTokenDebug() async {
    try {
      String? token = await _firebaseMessaging.getToken();
      if (token == null) {
        return "Error: Token retrieval failed (returned null)";
      }

      // Use SessionManager (custom auth) instead of Supabase Auth
      final userId = await SessionManager.getUserId();
      if (userId == null) {
        return "Error: No User ID in session (SessionManager returned null)";
      }

      // Use adminClient to bypass RLS (custom auth has no auth.uid())
      try {
        await SupabaseConfig.adminClient
            .from('users')
            .update({'fcm_token': token})
            .eq('id', userId);
        developer.log("FCM Token saved manually via forceSaveTokenDebug");
        return "Success: Token saved to Database for user $userId\nToken: ${token.substring(0, 10)}...";
      } catch (dbError) {
        return "Error: DB Update failed ($dbError). Check RLS policies.";
      }
    } catch (e) {
      return "Exception: $e";
    }
  }

  /// Test the Edge Function directly from the app
  static Future<String> testEdgeFunction() async {
    try {
      final userId = SupabaseConfig.supabase.auth.currentUser?.id;
      if (userId == null) return "Error: No User ID logged in.";

      developer.log("Testing Edge Function for User: $userId");

      final response = await SupabaseConfig.supabase.functions.invoke(
        'push_notifications',
        body: {
          'record': {
            'user_id': userId,
            'id': 'manual-test-${DateTime.now().millisecondsSinceEpoch}',
            'message': 'Direct Test: Edge Function is WORKING!',
            'created_at': DateTime.now().toIso8601String(),
          },
        },
      );

      developer.log("Edge Function Status: ${response.status}");

      if (response.status != 200) {
        return "Failure: Function returned ${response.status}.";
      }

      return "Success: Edge Function called (200). Check if you got a notification.";
    } catch (e) {
      return "Exception: $e";
    }
  }

  /// Send push notification to a specific user
  /// This can be used from anywhere in the app to send notifications
  static Future<bool> sendPushNotificationToUser({
    required String userId,
    required String title,
    required String message,
    String? screen,
    String? orderId,
  }) async {
    try {
      developer.log("📤 Sending push notification to user: $userId");

      // Insert into notifications table (this will trigger the Edge Function via webhook)
      await SupabaseConfig.supabase.from('notifications').insert({
        'user_id': userId,
        'title': title,
        'message': message,
        'order_id': orderId,
        'is_read': false,
        'data': {'screen': screen, 'order_id': orderId},
      });

      developer.log("✅ Notification inserted for user: $userId");
      return true;
    } catch (e) {
      developer.log("❌ Error sending notification: $e");

      // Fallback: Try calling edge function directly
      try {
        final response = await SupabaseConfig.supabase.functions.invoke(
          'push_notifications',
          body: {
            'record': {
              'user_id': userId,
              'id': 'direct-${DateTime.now().millisecondsSinceEpoch}',
              'title': title,
              'message': message,
              'created_at': DateTime.now().toIso8601String(),
            },
          },
        );

        if (response.status == 200) {
          developer.log("✅ Notification sent via direct edge function call");
          return true;
        }
      } catch (edgeError) {
        developer.log("❌ Edge function fallback also failed: $edgeError");
      }

      return false;
    }
  }

  /// Send push notification to multiple users
  static Future<void> sendPushNotificationToUsers({
    required List<String> userIds,
    required String title,
    required String message,
    String? screen,
    String? orderId,
  }) async {
    for (final userId in userIds) {
      await sendPushNotificationToUser(
        userId: userId,
        title: title,
        message: message,
        screen: screen,
        orderId: orderId,
      );
    }
  }
}
