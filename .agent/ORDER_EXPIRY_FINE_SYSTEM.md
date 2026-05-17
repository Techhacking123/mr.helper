# Order Expiry Fine System Implementation Plan

## Overview
Implement a comprehensive fine system for expired orders where providers are charged ₹50 per expired order.

## Requirements Summary

### Expiry Rules
1. Every order starts with 24-hour deadline from creation
2. Each time user clicks "Working" → Add 24hr extension from that moment
3. User can extend multiple times (N extensions possible)
4. If order not completed/cancelled within deadline → Mark as EXPIRED
5. Expired order = ₹50 fine applied to provider (once per order)

### Fine Management
- Track all fines across multiple orders
- Display total accumulated fines
- Provider can pay fines separately OR with next subscription
- If fine paid → Next subscription = Regular fee
- If fine NOT paid → Next subscription = Regular fee + Total fines

### UI Display Requirements
- **Order Details Page**: Show fine badge if order expired
- **Request Cards**: Show fine indicator on expired orders
- **Subscription Page**: Show total fines + Pay Fine button

---

## Implementation Steps

### Phase 1: Database Schema Updates

#### 1.1 Add Fine Tracking Columns to `orders` Table
```sql
ALTER TABLE orders ADD COLUMN IF NOT EXISTS deadline TIMESTAMPTZ;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS is_expired BOOLEAN DEFAULT FALSE;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS fine_amount NUMERIC(10,2) DEFAULT 0;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS fine_paid BOOLEAN DEFAULT FALSE;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS extension_count INTEGER DEFAULT 0;
```

#### 1.2 Add Fine Tracking to `users` Table (Providers)
```sql
ALTER TABLE users ADD COLUMN IF NOT EXISTS total_unpaid_fines NUMERIC(10,2) DEFAULT 0;
ALTER TABLE users ADD COLUMN IF NOT EXISTS total_fines_paid NUMERIC(10,2) DEFAULT 0;
```

#### 1.3 Create Fine Transactions Table
```sql
CREATE TABLE IF NOT EXISTS fine_transactions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  provider_id UUID REFERENCES users(id) ON DELETE CASCADE,
  order_id UUID REFERENCES orders(id) ON DELETE CASCADE,
  fine_amount NUMERIC(10,2) NOT NULL,
  paid_at TIMESTAMPTZ,
  payment_method TEXT,
  razorpay_payment_id TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Index for faster queries
CREATE INDEX idx_fine_transactions_provider ON fine_transactions(provider_id);
CREATE INDEX idx_fine_transactions_order ON fine_transactions(order_id);
```

#### 1.4 Create Trigger to Update Provider Total Fines
```sql
CREATE OR REPLACE FUNCTION update_provider_fines()
RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    -- Add fine to provider's total
    UPDATE users 
    SET total_unpaid_fines = COALESCE(total_unpaid_fines, 0) + NEW.fine_amount
    WHERE id = NEW.provider_id;
  ELSIF TG_OP = 'UPDATE' AND NEW.paid_at IS NOT NULL AND OLD.paid_at IS NULL THEN
    -- Fine was just paid
    UPDATE users 
    SET 
      total_unpaid_fines = GREATEST(COALESCE(total_unpaid_fines, 0) - NEW.fine_amount, 0),
      total_fines_paid = COALESCE(total_fines_paid, 0) + NEW.fine_amount
    WHERE id = NEW.provider_id;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_provider_fines
AFTER INSERT OR UPDATE ON fine_transactions
FOR EACH ROW EXECUTE FUNCTION update_provider_fines();
```

---

### Phase 2: Backend Logic (Database Functions)

#### 2.1 Function to Set Initial Deadline (on order creation)
```sql
CREATE OR REPLACE FUNCTION set_order_deadline()
RETURNS TRIGGER AS $$
BEGIN
  -- Set initial 24hr deadline from order creation
  NEW.deadline = NEW.created_at + INTERVAL '24 hours';
  NEW.extension_count = 0;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_set_order_deadline
BEFORE INSERT ON orders
FOR EACH ROW EXECUTE FUNCTION set_order_deadline();
```

#### 2.2 Function to Extend Deadline (when "Working" clicked)
```sql
CREATE OR REPLACE FUNCTION extend_order_deadline(order_uuid UUID)
RETURNS JSON AS $$
DECLARE
  result JSON;
  new_deadline TIMESTAMPTZ;
BEGIN
  -- Extend deadline by 24hr from NOW
  new_deadline := NOW() + INTERVAL '24 hours';
  
  UPDATE orders
  SET 
    deadline = new_deadline,
    extension_count = extension_count + 1,
    updated_at = NOW()
  WHERE id = order_uuid
  RETURNING 
    json_build_object(
      'success', TRUE,
      'new_deadline', deadline,
      'extension_count', extension_count
    ) INTO result;
    
  RETURN result;
END;
$$ LANGUAGE plpgsql;
```

#### 2.3 Function to Check & Mark Expired Orders
```sql
CREATE OR REPLACE FUNCTION check_and_mark_expired_orders()
RETURNS JSON AS $$
DECLARE
  expired_order RECORD;
  expired_count INTEGER := 0;
  fine_per_order NUMERIC := 50.00;
BEGIN
  -- Find all orders that are past deadline and not completed/cancelled
  FOR expired_order IN
    SELECT id, provider_id 
    FROM orders
    WHERE 
      deadline < NOW()
      AND status NOT IN ('completed', 'cancelled')
      AND is_expired = FALSE
      AND fine_amount = 0
  LOOP
    -- Mark order as expired
    UPDATE orders
    SET 
      is_expired = TRUE,
      fine_amount = fine_per_order,
      fine_paid = FALSE,
      updated_at = NOW()
    WHERE id = expired_order.id;
    
    -- Create fine transaction
    INSERT INTO fine_transactions (provider_id, order_id, fine_amount)
    VALUES (expired_order.provider_id, expired_order.id, fine_per_order);
    
    expired_count := expired_count + 1;
  END LOOP;
  
  RETURN json_build_object(
    'success', TRUE,
    'expired_orders_count', expired_count,
    'fine_per_order', fine_per_order
  );
END;
$$ LANGUAGE plpgsql;
```

#### 2.4 Function to Pay Fine (separate payment)
```sql
CREATE OR REPLACE FUNCTION pay_fine(
  p_provider_id UUID,
  p_fine_transaction_ids UUID[],
  p_payment_id TEXT
)
RETURNS JSON AS $$
DECLARE
  total_paid NUMERIC := 0;
BEGIN
  -- Update fine transactions as paid
  UPDATE fine_transactions
  SET 
    paid_at = NOW(),
    payment_method = 'razorpay',
    razorpay_payment_id = p_payment_id
  WHERE 
    id = ANY(p_fine_transaction_ids)
    AND provider_id = p_provider_id
    AND paid_at IS NULL
  RETURNING SUM(fine_amount) INTO total_paid;
  
  -- Mark orders as fine paid
  UPDATE orders
  SET fine_paid = TRUE
  WHERE id IN (
    SELECT order_id FROM fine_transactions WHERE id = ANY(p_fine_transaction_ids)
  );
  
  RETURN json_build_object(
    'success', TRUE,
    'total_paid', COALESCE(total_paid, 0)
  );
END;
$$ LANGUAGE plpgsql;
```

---

### Phase 3: Flutter Frontend Updates

#### 3.1 Update Order Model
**File**: `lib/models/order.dart`

Add fields:
```dart
final DateTime? deadline;
final bool isExpired;
final double fineAmount;
final bool finePaid;
final int extensionCount;
```

#### 3.2 Update Order Details Page
**File**: `lib/orders/order_details.dart`

Add:
- Fine badge display if order expired
- Countdown timer showing time remaining until deadline
- Visual warning when approaching deadline

#### 3.3 Update Request Cards
**File**: `lib/provider/widgets/request_card.dart`

Add:
- Fine indicator badge on expired orders
- Deadline display
- Visual warning for approaching deadline

#### 3.4 Update "Working" Button Logic
**File**: `lib/orders/order_details.dart` (or wherever Working button is)

When clicked:
1. Call `extend_order_deadline()` RPC
2. Show success message: "Deadline extended by 24 hours"
3. Update UI with new deadline

#### 3.5 Create Fine Management Widget
**File**: `lib/subscription/fine_management_widget.dart`

Display:
- List of all unpaid fines with order details
- Total unpaid fines
- "Pay All Fines" button
- Payment history

#### 3.6 Update Subscription Page
**File**: `lib/subscription/subscription_page.dart`

Add:
- Fine summary section
- Total unpaid fines display
- Pay Fine button
- Logic to add fines to subscription payment

#### 3.7 Background Task for Expiry Check
**File**: `lib/services/order_expiry_service.dart`

Create service to:
- Periodically call `check_and_mark_expired_orders()`
- Run on app start
- Run in background (every 15-30 minutes)

---

### Phase 4: Integration with Subscription Payment

#### 4.1 Update Subscription Payment Logic
**File**: `lib/subscription/subscription_page.dart`

Calculate total payment:
```dart
double getTotalSubscriptionAmount() {
  double baseAmount = 100.00; // Regular subscription fee
  double unpaidFines = providerData['total_unpaid_fines'] ?? 0;
  return baseAmount + unpaidFines;
}
```

#### 4.2 Update Backend Payment Verification
**File**: `backend/app.py` (Flask backend)

On successful subscription payment:
1. If fines included in payment → Mark all fines as paid
2. Update subscription
3. Clear provider's unpaid fines

---

## UI/UX Specifications

### Fine Badge Design
```
┌─────────────────┐
│  ⚠️ EXPIRED     │
│  Fine: ₹50     │
└─────────────────┘
```

### Deadline Display
```
Deadline: 23h 45m remaining ⏰
```

### Subscription Page Fine Section
```
┌──────────────────────────────┐
│ Outstanding Fines            │
├──────────────────────────────┤
│ Order #1234 - ₹50           │
│ Order #5678 - ₹50           │
│ Order #9012 - ₹50           │
├──────────────────────────────┤
│ Total: ₹150                  │
│                              │
│ [ Pay Fines Now ]   ₹150    │
└──────────────────────────────┘

┌──────────────────────────────┐
│ Next Subscription Payment    │
├──────────────────────────────┤
│ Base Fee: ₹100              │
│ + Unpaid Fines: ₹150        │
├──────────────────────────────┤
│ Total: ₹250                  │
│                              │
│ [ Pay Subscription ] ₹250   │
└──────────────────────────────┘
```

---

## Testing Checklist

### Scenario 1: Order Expires Naturally
- [ ] Create order → verify 24hr deadline set
- [ ] Wait for deadline to pass
- [ ] Verify order marked as expired
- [ ] Verify ₹50 fine added
- [ ] Verify fine shows on order details
- [ ] Verify fine shows on subscription page

### Scenario 2: Order Extended Then Expires
- [ ] Create order → 24hr deadline
- [ ] Click "Working" → verify deadline extended
- [ ] Click "Working" again → verify another extension
- [ ] Let extended deadline pass
- [ ] Verify only ONE ₹50 fine applied

### Scenario 3: Order Completed Before Deadline
- [ ] Create order → 24hr deadline
- [ ] Complete order before deadline
- [ ] Verify NO fine applied

### Scenario 4: Multiple Expired Orders
- [ ] Create 3 orders
- [ ] Let all 3 expire
- [ ] Verify 3 × ₹50 = ₹150 total fines
- [ ] Verify displayed on subscription page

### Scenario 5: Pay Fines Separately
- [ ] Have unpaid fines
- [ ] Pay fines separately
- [ ] Verify fines marked as paid
- [ ] Verify next subscription = base fee only

### Scenario 6: Pay Fines with Subscription
- [ ] Have unpaid fines
- [ ] Pay subscription (includes fines)
- [ ] Verify fines cleared
- [ ] Verify subscription activated

---

## Files to Create/Modify

### New Files
1. `lib/services/order_expiry_service.dart` - Expiry checking service
2. `lib/subscription/fine_management_widget.dart` - Fine display widget
3. `lib/widgets/fine_badge.dart` - Reusable fine badge
4. `lib/widgets/deadline_timer.dart` - Countdown timer widget
5. `.agent/migrations/order_expiry_fine_system.sql` - Complete SQL migration

### Modified Files
1. `lib/models/order.dart` - Add fine fields
2. `lib/orders/order_details.dart` - Show fine, deadline, extend button
3. `lib/provider/widgets/request_card.dart` - Show fine badge
4. `lib/subscription/subscription_page.dart` - Fine management
5. `backend/app.py` - Subscription payment logic

---

## Implementation Priority

### Phase 1 (High Priority) - Core Functionality
1. Database schema migration
2. SQL functions for expiry checking
3. Basic fine tracking

### Phase 2 (Medium Priority) - UI Updates
1. Order details page updates
2. Request card updates
3. Subscription page updates

### Phase 3 (Low Priority) - Polish
1. Background expiry checker
2. Push notifications for approaching deadlines
3. Fine payment history

---

## Notes & Considerations

1. **Time Zone Handling**: All deadlines use TIMESTAMPTZ (UTC)
2. **Grace Period**: Consider adding 1-hour grace period?
3. **Notifications**: Send notification when deadline approaching (2hr warning?)
4. **Admin Override**: Allow admin to waive fines?
5. **Fine Amount**: Currently hardcoded ₹50, consider making configurable?

