-- ============================================
-- QUICK DEPLOYMENT SCRIPT
-- ============================================
-- Run this in Supabase SQL Editor to deploy the chat system
-- ============================================

\echo '🚀 Starting Order Chat System Deployment...'

-- Import the main migration
\i order_chat_system.sql

\echo '✅ Chat system deployed successfully!'
\echo ''
\echo '📋 Post-Deployment Checklist:'
\echo '  1. Verify tables created: chat_sessions, chat_messages'
\echo '  2. Check RLS policies are enabled'
\echo '  3. Test RPC functions: get_or_create_chat_session, send_chat_message'
\echo '  4. Verify realtime is enabled for chat tables'
\echo '  5. Test chat UI in Flutter app'
\echo ''
\echo '🎉 Chat feature is ready to use!'
