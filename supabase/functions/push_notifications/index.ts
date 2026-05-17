import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.0.0";
// @deno-types="npm:@types/firebase-admin@11.11.0"
import admin from "npm:firebase-admin@11.11.0";

console.log("Push Notification Function Initialized");

// Initialize Firebase Admin with Service Account
// You MUST set the 'FIREBASE_SERVICE_ACCOUNT' secret in your Supabase Dashboard
const serviceAccountStr = Deno.env.get("FIREBASE_SERVICE_ACCOUNT");
if (!serviceAccountStr) {
    console.error("Missing FIREBASE_SERVICE_ACCOUNT environment variable");
} else {
    try {
        const serviceAccount = JSON.parse(serviceAccountStr);
        if (admin.apps.length === 0) {
            admin.initializeApp({
                credential: admin.credential.cert(serviceAccount),
            });
        }
    } catch (e) {
        console.error("Error parsing FIREBASE_SERVICE_ACCOUNT", e);
    }
}

serve(async (req) => {
    try {
        const { record } = await req.json();

        // Check if record exists (it should be the new row from 'notifications' table)
        if (!record) {
            return new Response(JSON.stringify({ error: 'No record provided' }), { status: 400 });
        }

        const userId = record.user_id;
        const messageBody = record.message || "You have a new update";
        const notificationTitle = record.title || "Mr.Helper"; // Use sender's name from DB
        const notificationId = record.id;

        if (!userId) {
            console.log("No user_id in record");
            return new Response(JSON.stringify({ message: 'No user_id' }), { status: 200 });
        }

        // Initialize Supabase Client to fetch user's FCM tokens
        const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
        const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
        const supabase = createClient(supabaseUrl, supabaseKey);

        // ============================================================
        // MULTI-DEVICE SUPPORT: Fetch ALL active FCM tokens for user
        // ============================================================
        const { data: tokenData, error: tokenError } = await supabase
            .from('user_fcm_tokens')
            .select('fcm_token')
            .eq('user_id', userId)
            .eq('is_active', true);

        if (tokenError || !tokenData || tokenData.length === 0) {
            console.log("No active FCM tokens found for user", userId);
            return new Response(JSON.stringify({ message: 'No active tokens' }), { status: 200 });
        }

        // Extract FCM tokens from the result
        const fcmTokens = tokenData.map(row => row.fcm_token).filter(token => token != null);

        if (fcmTokens.length === 0) {
            console.log("No valid FCM tokens after filtering for user", userId);
            return new Response(JSON.stringify({ message: 'No valid tokens' }), { status: 200 });
        }

        console.log(`📱 Found ${fcmTokens.length} active device(s) for user ${userId}`);

        // Construct the FCM message payload
        const messagePayload = {
            notification: {
                title: notificationTitle, // Sender's name
                body: messageBody,
            },
            data: {
                title: notificationTitle, // Sender's name
                body: messageBody,
                click_action: 'FLUTTER_NOTIFICATION_CLICK',
                notification_id: notificationId ? String(notificationId) : '0',
            },
            android: {
                priority: 'high',
                notification: {
                    channelId: 'high_importance_channel',
                    defaultSound: true,
                    defaultVibrateTimings: true,
                    priority: 'max',
                },
            },
        };

        // ============================================================
        // Send to ALL devices using multicast
        // ============================================================
        try {
            const response = await admin.messaging().sendEachForMulticast({
                tokens: fcmTokens,
                ...messagePayload,
            });

            console.log(`✅ Notification sent to ${response.successCount}/${fcmTokens.length} devices`);

            // Handle failed tokens (remove inactive/invalid ones)
            if (response.failureCount > 0) {
                const failedTokens: string[] = [];
                response.responses.forEach((resp, idx) => {
                    if (!resp.success) {
                        failedTokens.push(fcmTokens[idx]);
                        console.log(`Failed to send to token ${idx}: ${resp.error?.message}`);
                    }
                });

                // Remove invalid tokens from database
                if (failedTokens.length > 0) {
                    await supabase
                        .from('user_fcm_tokens')
                        .delete()
                        .in('fcm_token', failedTokens);
                    console.log(`🗑️ Removed ${failedTokens.length} invalid token(s)`);
                }
            }

            return new Response(
                JSON.stringify({
                    success: true,
                    sent: response.successCount,
                    failed: response.failureCount
                }),
                { headers: { "Content-Type": "application/json" } },
            );
        } catch (sendError: any) {
            console.error("Error sending multicast:", sendError);
            throw sendError;
        }
    } catch (error: any) {
        console.error("Error sending notification:", error);
        return new Response(JSON.stringify({ error: error.message }), {
            headers: { "Content-Type": "application/json" },
            status: 400,
        });
    }
});
