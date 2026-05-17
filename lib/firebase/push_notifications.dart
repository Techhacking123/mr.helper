/*
  MRHELPERAI FIREBASE PUSH NOTIFICATION SETUP GUIDE
  
  Since we cannot run cloud functions for you, follow these steps to enable REAL-TIME Push Notifications.

  1. SETUP FIREBASE PROJECT
     - Go to console.firebase.google.com
     - Create a project "mrhelperAI"
     - Add Android App (package: com.example.mrhelperAI)
     - Download google-services.json -> Place in android/app/

  2. FLUTTER INTEGRATION
     - The firebase_messaging package is already added.
     - Add the following code to main.dart to initialize:

     await Firebase.initializeApp();
     FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  3. SERVER-SIDE SENDING (The Logic)
     - Since you are using Supabase, you need an Edge Function or Database Webhook to call FCM.
     - We provided a Supabase Trigger in SQL that inserts into 'notifications' table.
     - EFFECTIVE ARCHITECTURE WITHOUT SERVER:
       The "Client" app listens to the Supabase Realtime Stream of the 'notifications' table.
       When a new row is inserted (by the SQL trigger), the App shows a LOCAL Notification.
       This mimics Push Notifications without needing a complex Node.js backend!

  BELOW IS THE CODE TO HANDLE THIS "LOCAL PUSH" VIA SUPABASE REALTIME
*/

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../supabase_config.dart';

class PushNotificationService {
  static void initialize(BuildContext context, String myUserId) {
    // Listen to INSERT events on notifications table for THIS user
    SupabaseConfig.supabase
        .from('notifications')
        .stream(primaryKey: ['id'])
        .eq('user_id', myUserId)
        .listen((List<Map<String, dynamic>> data) {
          // data contains the list of notifications.
          // Since stream returns the whole list or snapshots, we need to handle "New" ones.
          // Better approach for alerts: filtering for new timestamps or using .on PostgresChanges (v2)
        });

    // V2 Realtime approach
    SupabaseConfig.supabase
        .channel('public:notifications')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: myUserId,
          ),
          callback: (payload) {
            final msg = payload.newRecord['message'];
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('🔔 $msg'),
                duration: const Duration(seconds: 5),
                action: SnackBarAction(
                  label: 'VIEW',
                  onPressed: () {
                    // Navigate to notifications
                  },
                ),
              ),
            );
          },
        )
        .subscribe();
  }
}
