# Chat Feature Flow Diagram

## 🔄 Complete Flow Visualization

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         CHAT FEATURE LIFECYCLE                          │
└─────────────────────────────────────────────────────────────────────────┘

1️⃣ ORDER CREATION & ACCEPTANCE
═══════════════════════════════════════════════════════════════════════════

   User                    Orders Table              Provider
    │                           │                         │
    │  Creates Order            │                         │
    ├──────────────────────────►│                         │
    │  status: 'pending'        │                         │
    │                           │                         │
    │                           │  Views Order Request    │
    │                           │◄────────────────────────┤
    │                           │                         │
    │                           │  Accepts Order          │
    │                           │◄────────────────────────┤
    │                           │  status: 'accepted'     │
    │                           │                         │


2️⃣ AUTOMATIC CHAT SESSION CREATION
═══════════════════════════════════════════════════════════════════════════

   Orders Table          Database Trigger       Chat Sessions Table
        │                       │                        │
        │  Status changed to    │                        │
        │  'accepted'           │                        │
        ├──────────────────────►│                        │
        │                       │  Trigger Fires:        │
        │                       │  create_chat_session   │
        │                       │  _on_approval()        │
        │                       ├───────────────────────►│
        │                       │                        │
        │                       │  Creates new session:  │
        │                       │  - order_id            │
        │                       │  - user_id             │
        │                       │  - provider_id         │
        │                       │  - is_active: true     │
        │                       │                        │


3️⃣ CHAT BUTTONS APPEAR
═══════════════════════════════════════════════════════════════════════════

   Order Detail Page (User View)
   ┌─────────────────────────────────────┐
   │ Order #1234 - Plumber Service       │
   │ Status: ACCEPTED ✓                  │
   ├─────────────────────────────────────┤
   │ Provider: John Doe                  │
   │ Price: ₹500                         │
   │                                     │
   │ ┌──────────────┐  ┌──────────────┐ │
   │ │ Call Provider│  │    Chat      │ │
   │ │   📞 GREEN   │  │  💬 BLUE     │ │◄── Buttons Appear!
   │ └──────────────┘  └──────────────┘ │
   └─────────────────────────────────────┘

   Order Detail Page (Provider View)
   ┌─────────────────────────────────────┐
   │ Order #1234 - Plumber Service       │
   │ Status: ACCEPTED ✓                  │
   ├─────────────────────────────────────┤
   │ Customer: Jane Smith                │
   │ Price: ₹500                         │
   │ Phone: 9876543210                   │
   │                                     │
   │ ┌──────────────┐  ┌──────────────┐ │
   │ │  Call Now    │  │    Chat      │ │◄── Buttons Appear!
   │ │  📞 GREEN    │  │  💬 BLUE     │ │
   │ └──────────────┘  └──────────────┘ │
   └─────────────────────────────────────┘


4️⃣ REAL-TIME MESSAGING
═══════════════════════════════════════════════════════════════════════════

   User App              Supabase Realtime           Provider App
      │                         │                         │
      │  User clicks "Chat"     │                         │
      │  Opens OrderChatPage    │                         │
      │                         │                         │
      │  get_or_create_chat     │                         │
      │  _session(order_id)     │                         │
      ├────────────────────────►│                         │
      │◄────────────────────────┤                         │
      │  Returns session_id     │                         │
      │                         │                         │
      │  Subscribe to           │                         │
      │  chat_messages channel  │                         │
      ├────────────────────────►│                         │
      │                         │  Subscribe to           │
      │                         │  chat_messages channel  │
      │                         │◄────────────────────────┤
      │                         │                         │
      │  User types: "Hello"    │                         │
      │  send_chat_message()    │                         │
      ├────────────────────────►│                         │
      │                         │  INSERT into            │
      │                         │  chat_messages          │
      │                         │                         │
      │                         │  Realtime Broadcast     │
      │                         ├────────────────────────►│
      │                         │  "Hello" appears        │
      │                         │  instantly!             │
      │                         │                         │
      │                         │  Provider replies       │
      │                         │  "Hi there!"            │
      │  Realtime Broadcast     │◄────────────────────────┤
      │◄────────────────────────┤                         │
      │  "Hi there!" appears    │                         │
      │  instantly!             │                         │
      │                         │                         │


5️⃣ CHAT INTERFACE (UI)
═══════════════════════════════════════════════════════════════════════════

   ┌──────────────────────────────────────────┐
   │ ← Chat                                   │
   │   Plumber Service Order                  │
   ├──────────────────────────────────────────┤
   │ ℹ️ Chat deleted on order completion      │
   ├──────────────────────────────────────────┤
   │                                          │
   │           ┌─────────────────────┐        │
   │           │ Hello, I'll be there│        │  Received
   │           │ in 30 minutes       │        │  (Gray bubble)
   │           └─────────────────────┘        │
   │                   10:30 AM               │
   │                                          │
   │  ┌──────────────────────┐                │
   │  │ Great! I'm ready     │                │  Sent
   │  │ Waiting for you      │                │  (Blue bubble)
   │  └──────────────────────┘                │
   │          10:31 AM                        │
   │                                          │
   │           ┌─────────────────────┐        │
   │           │ On my way now!      │        │  Received
   │           └─────────────────────┘        │
   │                   Just now               │
   │                                          │
   ├──────────────────────────────────────────┤
   │ ┌────────────────────────┐  ┌────┐      │
   │ │ Type a message...      │  │ 📤 │      │
   │ └────────────────────────┘  └────┘      │
   └──────────────────────────────────────────┘


6️⃣ NOTIFICATION SYSTEM
═══════════════════════════════════════════════════════════════════════════

   User sends message              Notifications Table           Provider
         │                                 │                         │
         │  Message: "Hello"               │                         │
         ├────────────────────────────────►│                         │
         │                                 │  Creates notification:  │
         │                                 │  - type: 'chat_message' │
         │                                 │  - title: 'New Chat'    │
         │                                 │  - message: 'Hello'     │
         │                                 │  - user_id: provider_id │
         │                                 │                         │
         │                                 │  FCM Push Notification  │
         │                                 ├────────────────────────►│
         │                                 │  🔔 "New Chat Message"  │
         │                                 │     "Hello"             │
         │                                 │                         │


7️⃣ ORDER COMPLETION & CLEANUP
═══════════════════════════════════════════════════════════════════════════

   User                Orders Table        Database Trigger      Chat Tables
    │                      │                      │                    │
    │  Clicks "Service     │                      │                    │
    │  Completed"          │                      │                    │
    ├─────────────────────►│                      │                    │
    │                      │  Status changes to   │                    │
    │                      │  'completed'         │                    │
    │                      ├─────────────────────►│                    │
    │                      │                      │  Trigger Fires:    │
    │                      │                      │  cleanup_chat_on   │
    │                      │                      │  _order_closure()  │
    │                      │                      │                    │
    │                      │                      │  DELETE all        │
    │                      │                      │  messages          │
    │                      │                      ├───────────────────►│
    │                      │                      │                    │
    │                      │                      │  DELETE chat       │
    │                      │                      │  session           │
    │                      │                      ├───────────────────►│
    │                      │                      │                    │
    │                      │                      │  ✨ Clean!         │
    │                      │                      │  No orphan records │
    │                      │                      │                    │


8️⃣ SECURITY LAYERS
═══════════════════════════════════════════════════════════════════════════

   ┌─────────────────────────────────────────────────────────────────┐
   │                      SECURITY ARCHITECTURE                      │
   └─────────────────────────────────────────────────────────────────┘

   Level 1: Application Level
   ─────────────────────────────────────────────────────────────────
   ✓ Chat button only visible if order status in approved states
   ✓ Navigation requires valid order_id
   ✓ User must be either customer or provider of that order

   Level 2: RPC Functions
   ─────────────────────────────────────────────────────────────────
   ✓ get_or_create_chat_session() validates:
     - User is customer OR provider of the order
     - Order is in valid status for chat
   ✓ send_chat_message() validates:
     - User is participant in the session
     - Session exists and is active

   Level 3: Row Level Security (RLS)
   ─────────────────────────────────────────────────────────────────
   ✓ chat_sessions: SELECT only if auth.uid() = user_id OR provider_id
   ✓ chat_messages: SELECT only if session belongs to auth.uid()
   ✓ chat_messages: INSERT only if session belongs to auth.uid()
   ✓ All policies enforced at PostgreSQL level

   Level 4: Realtime Security
   ─────────────────────────────────────────────────────────────────
   ✓ Realtime subscriptions filtered by session_id
   ✓ Only authorized users receive updates
   ✓ No cross-contamination between chats


9️⃣ DATA FLOW SUMMARY
═══════════════════════════════════════════════════════════════════════════

   ┌───────────────┐
   │ Order Created │
   └───────┬───────┘
           │
           ▼
   ┌───────────────┐
   │Provider Accepts│ ──────┐
   └───────┬───────┘        │ Trigger
           │                ▼
           │        ┌───────────────┐
           │        │ Chat Session  │
           │        │   Created     │
           │        └───────┬───────┘
           │                │
           ▼                ▼
   ┌────────────────────────────────┐
   │  Chat Buttons Appear on Both   │
   │      User & Provider Sides     │
   └────────────┬───────────────────┘
                │
                ▼
   ┌────────────────────────────────┐
   │    Real-time Messaging         │
   │    Messages Exchanged          │
   │    Notifications Sent          │
   └────────────┬───────────────────┘
                │
                ▼
   ┌────────────────────────────────┐
   │ Order Completed or Cancelled   │ ──────┐
   └────────────────────────────────┘        │ Trigger
                                             ▼
                                    ┌────────────────┐
                                    │  All Chat Data │
                                    │    Deleted     │
                                    │  ✨ Clean DB   │
                                    └────────────────┘


🔟 STATUS TRANSITIONS
═══════════════════════════════════════════════════════════════════════════

   State                Chat Available?    Button Visible?
   ───────────────────────────────────────────────────────────────
   pending              ❌ No              ❌ No
   request_open         ❌ No              ❌ No
   accepted             ✅ Yes             ✅ Yes
   confirmed            ✅ Yes             ✅ Yes
   verified             ✅ Yes             ✅ Yes
   working              ✅ Yes             ✅ Yes
   completed            ❌ Deleted         ❌ No
   cancelled            ❌ Deleted         ❌ No
   expired              ❌ Deleted         ❌ No
   negotiating          ❌ No              ❌ No


═══════════════════════════════════════════════════════════════════════════
                            END OF FLOW DIAGRAM
═══════════════════════════════════════════════════════════════════════════
