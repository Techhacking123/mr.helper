# 🔐 Strict Subscription Enforcement - System Flow

## Order Request Flow with Subscription Checks

```
┌─────────────────────────────────────────────────────────────────────┐
│                        USER PLACES ORDER                            │
└──────────────────────────┬──────────────────────────────────────────┘
                           │
                           ▼
                  ┌────────────────────┐
                  │   Order Created    │
                  │  in Database       │
                  └────────┬───────────┘
                           │
                           ▼
          ┌────────────────────────────────────┐
          │   Database Trigger Fires:          │
          │   notify_providers_on_order()      │
          └────────┬───────────────────────────┘
                   │
                   ▼
   ┌───────────────────────────────────────────────────┐
   │  LAYER 1: Database Level Filtering                │
   │  ✓ Auto-expire outdated subscriptions             │
   │  ✓ SELECT providers WHERE:                        │
   │    - service_id matches                           │
   │    - location matches                             │
   │    - subscription_status = 'active'      ← STRICT │
   │    - subscription_end_date > NOW()       ← STRICT │
   └────────┬──────────────────────────────────────────┘
            │
            ▼
    ┌───────────────┐           ┌───────────────┐
    │  Provider A   │           │  Provider B   │
    │  Status:      │           │  Status:      │
    │  'active'     │           │  'expired'    │
    │  End: Future  │           │  End: Past    │
    └───────┬───────┘           └───────┬───────┘
            │                           │
            ✅ NOTIFIED                 ❌ BLOCKED
            │                           │
            ▼                           ▼
  ┌──────────────────┐        ┌──────────────────┐
  │ Notification     │        │  NO notification │
  │ Created in DB    │        │  NO order shown  │
  └──────────────────┘        └──────────────────┘
```

---

## Provider Dashboard Flow

```
┌─────────────────────────────────────────────────────────┐
│         PROVIDER OPENS DASHBOARD                        │
└────────────────────┬────────────────────────────────────┘
                     │
                     ▼
        ┌────────────────────────────┐
        │  _fetchRequests() called   │
        └────────┬───────────────────┘
                 │
                 ▼
┌────────────────────────────────────────────────────────────┐
│  LAYER 2: Flutter App Level Check                         │
│  Query: SELECT subscription_status, subscription_end_date  │
└────────┬───────────────────────────────────────────────────┘
         │
         ▼
    ┌─────────────────────────────────┐
    │ IF subscription_status == 'active' │
    │ AND end_date > NOW()             │
    └──────┬──────────────┬────────────┘
           │              │
       YES │              │ NO
           │              │
           ▼              ▼
   ┌──────────────┐  ┌────────────────────┐
   │ Load Orders  │  │ Clear All Data     │
   │ Show List    │  │ _requests = []     │
   └──────────────┘  │ _negotiations = [] │
                     │ Show Empty State   │
                     └────────────────────┘
```

---

## Payment Success Flow

```
┌─────────────────────────────────────────────────────┐
│     USER COMPLETES RAZORPAY PAYMENT                 │
└────────────────┬────────────────────────────────────┘
                 │
                 ▼
    ┌────────────────────────────┐
    │  Payment Success Callback  │
    └────────┬───────────────────┘
             │
             ▼
┌────────────────────────────────────────────────────────┐
│  Backend: /verify-payment                              │
│  1. Verify Razorpay signature                          │
│  2. Calculate: end_date = NOW() + 7 days               │
│  3. Update Database:                                   │
│     - subscription_status = 'active'      ← NEW        │
│     - subscription_end_date = end_date    ← NEW        │
│     - is_subscribed = TRUE                             │
│     - subscription_expiry = end_date                   │
└────────┬───────────────────────────────────────────────┘
         │
         ▼
┌────────────────────────────────────────────────────────┐
│  Database Trigger: validate_subscription_on_update()   │
│  ✓ Validates end_date is in future                     │
│  ✓ Ensures active status has end_date                  │
└────────┬───────────────────────────────────────────────┘
         │
         ▼
┌────────────────────────────────────────────────────────┐
│  PROVIDER NOW HAS ACTIVE SUBSCRIPTION                  │
│  ✅ Can receive order notifications                    │
│  ✅ Can see orders in dashboard                        │
│  ✅ Duration: 7 days from payment                      │
└────────────────────────────────────────────────────────┘
```

---

## Auto-Expiry Flow

```
┌─────────────────────────────────────────────────────┐
│         TIME PASSES → end_date REACHED              │
└────────────────┬────────────────────────────────────┘
                 │
                 ▼
         Two Expiry Triggers:
         
1. AUTOMATIC (on any order):
   ┌────────────────────────────────┐
   │  New Order → Trigger fires     │
   │  auto_expire_subscriptions()   │
   │  Scans ALL 'active' providers  │
   │  IF end_date <= NOW():         │
   │    status = 'expired'          │
   └────────┬───────────────────────┘
            │
            
2. ON UPDATE (when provider accessed):
   ┌────────────────────────────────┐
   │  Provider logs in/refreshes    │
   │  validate_subscription_trigger │
   │  IF end_date <= NOW():         │
   │    status = 'expired'          │
   └────────┬───────────────────────┘
            │
            ▼
   ┌────────────────────────────────────┐
   │  SUBSCRIPTION EXPIRED               │
   │  ❌ NO MORE notifications           │
   │  ❌ NO MORE orders in dashboard     │
   │  ⚠️  Shows: "Subscription Expired"  │
   └─────────────────────────────────────┘
```

---

## Multi-Layer Protection Summary

```
┌──────────────────────────────────────────────────────────────┐
│                    PROTECTION LAYERS                         │
└──────────────────────────────────────────────────────────────┘

Layer 1: DATABASE TRIGGER
├─ Function: notify_providers_on_order()
├─ When: On every order INSERT/UPDATE
├─ Check: subscription_status = 'active' AND end_date > NOW()
└─ Result: BLOCKS notification creation

Layer 2: PROVIDER DASHBOARD (Flutter)
├─ File: provider_requests.dart
├─ When: Provider opens dashboard
├─ Check: subscription_status = 'active' AND end_date > NOW()
└─ Result: HIDES all orders if not active

Layer 3: DIRECT HIRE (Flutter)
├─ File: order_create.dart
├─ When: User hires specific provider
├─ Check: subscription_status = 'active' AND end_date > NOW()
└─ Result: BLOCKS notification to unsubscribed provider

Layer 4: PAYMENT ACTIVATION (Backend)
├─ File: main.py
├─ When: Payment verified
├─ Action: Sets subscription_status = 'active'
└─ Result: ACTIVATES subscription for 7 days

Layer 5: AUTO-EXPIRY (Database)
├─ Function: auto_expire_subscriptions()
├─ When: On every order notification OR provider access
├─ Check: end_date <= NOW()
└─ Result: AUTO-EXPIRES outdated subscriptions

Layer 6: VALIDATION TRIGGER (Database)
├─ Trigger: validate_subscription_on_update()
├─ When: On every user record INSERT/UPDATE
├─ Check: Consistency of status and end_date
└─ Result: PREVENTS invalid subscription states
```

---

## Subscription States Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                     SUBSCRIPTION LIFECYCLE                  │
└─────────────────────────────────────────────────────────────┘

        ┌──────────┐
        │  'none'  │  ← Default state (new provider)
        │  ❌ NO   │
        └────┬─────┘
             │
             │ Payment Success
             │ activate_subscription()
             ▼
        ┌──────────┐
        │ 'active' │  ← Can receive orders
        │  ✅ YES  │
        │ 7 days   │
        └────┬─────┘
             │
             │ Time passes
             │ end_date reached
             ▼
        ┌──────────┐
        │'expired' │  ← Subscription ended
        │  ❌ NO   │
        └────┬─────┘
             │
             │ Renew payment
             │ activate_subscription()
             ▼
        ┌──────────┐
        │ 'active' │  ← Reactivated
        │  ✅ YES  │
        └──────────┘
```

---

## Data Flow: Order to Notification

```
Order Created → Trigger → Filter Providers → Create Notifications
    (1)          (2)            (3)                  (4)

(1) INSERT INTO orders (..., status='request_open')
    │
(2) notify_providers_on_order() fires
    │
(3) SELECT id FROM users WHERE:
    ├─ is_provider = TRUE
    ├─ service_id = order.service_id
    ├─ location matches
    ├─ subscription_status = 'active'     ← FILTER
    └─ subscription_end_date > NOW()      ← FILTER
    │
(4) FOR EACH filtered provider:
    └─ INSERT INTO notifications (provider_id, order_id, ...)

RESULT: Only subscribed providers get notified ✅
```

---

## Testing Scenarios

### ✅ Scenario 1: Active Subscription
```
Provider:
├─ subscription_status: 'active'
├─ subscription_end_date: 2025-12-29 (future)
│
Order Placed → ✅ NOTIFIED → ✅ SEES ORDER IN DASHBOARD
```

### ❌ Scenario 2: No Subscription
```
Provider:
├─ subscription_status: 'none'
├─ subscription_end_date: NULL
│
Order Placed → ❌ NO NOTIFICATION → ❌ NO ORDER IN DASHBOARD
```

### ❌ Scenario 3: Expired Subscription
```
Provider:
├─ subscription_status: 'expired'
├─ subscription_end_date: 2025-12-20 (past)
│
Order Placed → ❌ NO NOTIFICATION → ❌ NO ORDER IN DASHBOARD
         └─ auto_expire_subscriptions() confirms expired status
```

### ✅ Scenario 4: Just Expired (Auto-Expiry)
```
Provider at 2025-12-22 10:00am:
├─ subscription_status: 'active'
├─ subscription_end_date: 2025-12-22 09:00am (just passed)
│
Order Placed at 10:05am:
├─ auto_expire_subscriptions() runs
├─ Detects end_date < NOW()
├─ Updates: subscription_status = 'expired'
│
Result → ❌ NO NOTIFICATION (instantly blocked)
```

---

## Summary: STRICT ENFORCEMENT ACHIEVED ✅

**Rule:** ONLY providers with `subscription_status = 'active'` AND `subscription_end_date > NOW()` receive orders

**Enforcement:**
- ✅ Database level (cannot bypass)
- ✅ App level (additional safety)
- ✅ Backend level (payment activation)
- ✅ Auto-expiry (time-based blocking)

**Result:** 🔒 **100% SUBSCRIPTION ENFORCEMENT**
