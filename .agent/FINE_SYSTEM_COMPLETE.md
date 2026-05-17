# Order Expiry Fine System - Implementation Complete!

## ✅ What Has Been Implemented

### 1. Database Schema (`order_expiry_fine_system.sql`)
- ✅ Fine tracking columns added to orders table
- ✅ Fine totals added to users table  
- ✅ Fine transactions table created
- ✅ Automatic deadline setting (24hr on order creation)
- ✅ RPC functions for:
  - `extend_order_deadline()` - Extends deadline +24hr when "Working" clicked
  - `check_and_mark_expired_orders()` - Finds and marks expired orders with ₹50 fine
  - `get_provider_unpaid_fines()` - Gets provider's unpaid fine list
  - `pay_fine()` - Mark fines as paid separately
  - `pay_fines_with_subscription()` - Pay fines with subscription

### 2. Flutter Components Created
- ✅ `lib/services/order_expiry_service.dart` - Background expiry checker
- ✅ `lib/widgets/fine_badge.dart` - Fine status badges
- ✅ `lib/widgets/deadline_timer.dart` - Countdown timer widget
- ✅ `lib/subscription/fine_management_widget.dart` - Fine display & management

### 3. Updated Flutter Files
- ✅ `lib/orders/order_detail.dart`
  - Shows fine badge if order expired
  - Shows deadline countdown timer
  - Shows extension count
  - "Working" button extends deadline +24hr
  
- ✅ `lib/subscription/subscription_page.dart`
  - Displays fine management widget
  - Shows unpaid fines warning

---

## 🚀 NEXT STEPS - ACTION REQUIRED

### Step 1: Run Database Migration
**Open Supabase SQL Editor** and run the complete migration file:

```bash
.agent/migrations/order_expiry_fine_system.sql
```

This will:
- Create all necessary columns
- Create fine_transactions table
- Set up triggers and RPC functions
- Set Row Level Security  policies

### Step 2: Update Backend Payment Logic
**File:** `backend/app.py`

You need to modify the `/verify-payment` endpoint to handle fines:

```python
@app.route('/verify-payment', methods=['POST'])
def verify_payment():
    # ... existing payment verification code ...
    
    if subscription_active:
        # NEW: Pay all unpaid fines with subscription
        supabase.rpc(
            'pay_fines_with_subscription',
            {
                'p_provider_id': user_id,
                'p_payment_id': razorpay_payment_id
            }
        ).execute()
        
        # Then activate subscription as before
        # ... existing subscription activation code ...
```

### Step 3: Start Expiry Checker Service
**File:** `lib/provider/provider_home.dart` (or wherever providers start)

Add this to `initState()`:

```dart
@override
void initState() {
  super.initState();
  // Start the order expiry checker
  Order ExpiryService.startPeriodicCheck();
}
```

### Step 4: Update Request Cards (OPTIONAL - For Provider)
**File:** `lib/orders/provider_requests.dart`

Add fine indicator to request cards by adding this import and widget:

```dart
import '../widgets/fine_badge.dart';

// Inside _buildRequestCard(), add after the location badge (around line 1625):
if ((req['fine_amount'] ?? 0) > 0)
  FineIndicator(
    fineAmount: (req['fine_amount'] ?? 0).toDouble(),
    isPaid: req['fine_paid'] ?? false,
  ),
```

---

## 🧪 TESTING CHECKLIST

### Test Scenario 1: Order Expires Naturally
1. Create a test order
2. Wait 24 hours (or manually update deadline in database to past time)
3. Run expiry checker: `await OrderExpiryService.checkExpiredOrders()`
4. ✅ Verify: Order marked as expired, ₹50 fine added
5. ✅ Verify: Fine shows on order detail page
6. ✅ Verify: Fine shows on subscription page

### Test Scenario 2: Order Extended with "Working"
1. Create order → 24hr deadline
2. User clicks "Working" button
3. ✅ Verify: Deadline extended by 24hr from NOW
4. ✅ Verify: Extension count = 1
5. Click "Working" again
6. ✅ Verify: Deadline extended again, extension count = 2

### Test Scenario 3: Multiple Expired Orders
1. Create 3 orders
2. Let all expire
3. ✅ Verify: Total unpaid fines = ₹150 (3 × ₹50)
4. ✅ Verify: All 3 fines listed on subscription page

### Test Scenario 4: Pay Subscription with Fines
1. Have unpaid fines
2. Pay subscription
3. ✅ Verify: Fines auto-paid
4. ✅ Verify: Subscription activated
5. ✅ Verify: Next subscription = base fee only

---

## 💡 HOW IT WORKS

### Deadline Logic
```
Order Created → Deadline = Created_at + 24hr
                     ↓
         User clicks "Working"
                     ↓
         Deadline = NOW + 24hr (extended)
                     ↓
         Extension_count += 1
                     ↓
         Can extend N times
                     ↓
         If deadline passes → EXPIRED
```

### Fine Logic
```
Order Expired → Fine = ₹50
                  ↓
         Fine Transaction Created
                  ↓
         Provider total_unpaid_fines += ₹50
                  ↓
    ┌─────────────┴──────────────┐
    ↓                            ↓
Pay Fine Now              Don't Pay Fine
    ↓                            ↓
Fine marked paid          Added to next subscription
    ↓                            ↓
total_unpaid_fines -= ₹50    Subscription fee + ₹50
```

---

## 📊 Database Structure

### orders table (NEW COLUMNS)
- `deadline` (TIMESTAMPTZ) - When order expires
- `is_expired` (BOOLEAN) - If deadline passed
- `fine_amount` (NUMERIC) - Fine for this order (₹50)
- `fine_paid` (BOOLEAN) - If fine was paid
- `extension_count` (INTEGER) - How many times extended

### users table (NEW COLUMNS)
- `total_unpaid_fines` (NUMERIC) - Total unpaid fines
- `total_fines_paid` (NUMERIC) - Total fines paid (history)

### fine_transactions table (NEW)
- `id` - Transaction ID
- `provider_id` - Provider who got fined
- `order_id` - Order that expired (UNIQUE - one fine per order)
- `fine_amount` - ₹50
- `paid_at` - When fine was paid
- `payment_method` - 'razorpay' or 'subscription'
- `razorpay_payment_id` - Payment reference

---

## 🎨 UI Examples

### Order Detail Page:
```
┌──────────────────────────────┐
│  Service Name                │
│  [VERIFIED] [FINE: ₹50]     │
│                              │
│  ⏰ 4h 23m remaining         │
│  Extended 2 time(s)          │
└──────────────────────────────┘
```

### Subscription Page:
```
┌──────────────────────────────┐
│ ⚠️ Outstanding Fines         │
├──────────────────────────────┤
│ Order #1234 - ₹50           │
│ Order #5678 - ₹50           │
├──────────────────────────────┤
│ Total: ₹100                  │
│                              │
│ ⚠️ These will be added to    │
│   your next subscription     │
└──────────────────────────────┘

┌──────────────────────────────┐
│ Next Subscription Payment    │
├──────────────────────────────┤
│ Base Fee: ₹250              │
│ + Unpaid Fines: ₹100        │
├──────────────────────────────┤
│ Total: ₹350                  │
└──────────────────────────────┘
```

---

## 🐛 TROUBLESHOOTING

### Problem: Expiry checker not running
**Solution:** Make sure you call `OrderExpiryService.startPeriodicCheck()` in provider home's initState

### Problem: RPC function not found error
**Solution:** Run the SQL migration file in Supabase SQL Editor

### Problem: Fines not showing
**Solution:** Call `await OrderExpiryService.checkExpiredOrders()` manually to trigger check

### Problem: Deadline not extending
**Solution:** Check order status - can only extend if not completed/cancelled

---

## 📝 Important Notes

1. **One fine per order**: The system prevents duplicate fines via UNIQUE constraint on order_id in fine_transactions
2. **Background checking**: Runs every 15 minutes automatically
3. **Grace period**: Consider adding 1-hour grace period if needed (update SQL)
4. **Admin override**: You can add admin function to waive fines if needed

5. **Fine amount**: Currently hardcoded to ₹50 - can make configurable via settings table

---

## 🎯 SUMMARY

You now have a complete order expiry fine system:
- ✅ 24hr deadlines with unlimited extensions
- ✅ ₹50 fine per expired order
- ✅ Fine tracking and display
- ✅ Automatic fine payment with subscription
- ✅ Visual indicators everywhere
- ✅ Background expiry checking

**Next:** Run the SQL migration and test!
