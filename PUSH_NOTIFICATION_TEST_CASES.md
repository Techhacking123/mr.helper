# 🔔 Push Notification Test Cases - MrHelper App

**Test Plan Version:** 1.0  
**Created Date:** February 11, 2026  
**Test Type:** Functional Testing  
**Test Scope:** All Push Notification Types

---

## 📋 Table of Contents

1. [Test Environment Setup](#test-environment-setup)
2. [Test Data Requirements](#test-data-requirements)
3. [Notification Types Overview](#notification-types-overview)
4. [Test Cases](#test-cases)
5. [Expected Results Summary](#expected-results-summary)
6. [Known Issues](#known-issues)

---

## 🔧 Test Environment Setup

### Prerequisites:
1. **Two test devices/accounts:**
   - **Device A**: User/Buyer account
   - **Device B**: Provider account (with active subscription and KYC approved)
2. **Both devices must have:**
   - App installed and logged in
   - FCM tokens registered
   - Notification permissions granted
   - Internet connectivity
3. **Backend verification access:**
   - Supabase Dashboard access to check `notifications` table
   - FCM logs access (Edge Function logs)
   - Database trigger logs

### Test Setup Verification:
- [ ] Verify FCM tokens are saved in `fcm_tokens` table for both users
- [ ] Verify provider has `is_subscribed = true` and `subscription_status = 'active'`
- [ ] Verify both users have `status = 'active'` in users table
- [ ] Check Edge Function `push_notifications` is deployed and active

---

## 📊 Test Data Requirements

### User Account (Buyer):
- **User ID**: Record from test
- **Phone Number**: Verified
- **Location**: Active location in the system
- **Status**: Active

### Provider Account:
- **Provider ID**: Record from test
- **Service**: Assigned service (e.g., Electrician, Plumber)
- **Location**: Matching buyer's location
- **Subscription Status**: Active
- **KYC Status**: Approved
- **Status**: Active

---

## 🔍 Notification Types Overview

Based on the codebase analysis, the following push notification types are implemented:

### Category 1: Order Lifecycle Notifications
1. New Order Request (to Providers)
2. New Offer Received (to User)
3. Offer Accepted (to Provider)
4. Offer Rejected (to Provider)
5. Order Cancelled (to Provider)

### Category 2: Order Execution Notifications
6. OTP for Service Verification (to User)
7. Service Verified / Job Started (to User)
8. Deadline Extended (to Provider)
9. Service Completed (to User)

### Category 3: Review & Rating Notifications
10. New Review Received (to Provider)

### Category 4: System Notifications
11. Order Update (general notifications)
12. Fine Notification (to Provider - via database trigger)
13. Subscription Expiry Warning (to Provider - via database trigger)

### Category 5: Admin Broadcast Notifications
14. Admin Scheduled Notifications (to all/specific users)

---

## 🧪 Test Cases

### **TEST CASE 1: New Order Request Notification (To Provider)**

**Test ID:** TC_PN_001  
**Priority:** High  
**Trigger:** User creates a new order request

**Preconditions:**
- User is logged in
- Provider has active subscription
- Provider's service and location match the order

**Test Steps:**
1. Login as **User (Device A)**
2. Navigate to "Place Order" page
3. Select service (e.g., "Electrician")
4. Select location matching provider's location
5. Fill in order description
6. Submit the order request

**Expected Result:**
- [ ] Provider receives push notification on **Device B**
- [ ] Notification title: "MrHelper Notifications" (or custom title)
- [ ] Notification message: "New Request: [Service Name] in [Location Name]"
- [ ] Notification appears in notification tray
- [ ] Notification entry created in `notifications` table
- [ ] FCM trigger successfully invoked (check database logs)
- [ ] Clicking notification opens the app and navigates to order details

**Database Verification:**
```sql
SELECT * FROM notifications 
WHERE user_id = '<provider_id>' 
AND order_id = '<order_id>' 
AND type = 'order_request'
ORDER BY created_at DESC LIMIT 1;
```

**Status:** ⬜ Not Tested | ✅ Pass | ❌ Fail  
**Tested By:** ____________  
**Test Date:** ____________  
**Notes:** ____________

---

### **TEST CASE 2: New Offer Received Notification (To User)**

**Test ID:** TC_PN_002  
**Priority:** High  
**Trigger:** Provider sends an offer to the user

**Preconditions:**
- Open order request exists
- Provider is logged in

**Test Steps:**
1. Login as **Provider (Device B)**
2. Navigate to "Provider Requests" page
3. Select an open order request
4. Enter offer price (e.g., ₹500)
5. Click "Send Offer"

**Expected Result:**
- [ ] User receives push notification on **Device A**
- [ ] Notification title: "New Offer Received!"
- [ ] Notification message: "A provider has sent you an offer of ₹[price]!"
- [ ] **ONLY ONE notification received** (no duplicates)
- [ ] Notification entry in `notifications` table
- [ ] Clicking notification navigates to offers page

**Database Verification:**
```sql
SELECT * FROM notifications 
WHERE user_id = '<buyer_id>' 
AND order_id = '<order_id>' 
AND title = 'New Offer Received!'
ORDER BY created_at DESC;
```
**Check count should be 1, not 2 (duplicate fix validation)**

**Status:** ⬜ Not Tested | ✅ Pass | ❌ Fail  
**Tested By:** ____________  
**Test Date:** ____________  
**Notes:** ____________

---

### **TEST CASE 3: Offer Accepted Notification (To Provider)**

**Test ID:** TC_PN_003  
**Priority:** High  
**Trigger:** User accepts a provider's offer

**Preconditions:**
- Provider has sent an offer
- Offer is in "pending" status

**Test Steps:**
1. Login as **User (Device A)**
2. Navigate to "Review Offers" page
3. Select a provider's offer
4. Click "Accept Offer"

**Expected Result:**
- [ ] Provider receives push notification on **Device B**
- [ ] Notification title: "Offer Accepted!"
- [ ] Notification message: "[User Name] accepted your offer of ₹[price]!"
- [ ] Order status updated to 'approved' in database
- [ ] Notification appears immediately (real-time)

**Database Verification:**
```sql
SELECT * FROM notifications 
WHERE user_id = '<provider_id>' 
AND order_id = '<order_id>' 
AND title = 'Offer Accepted!';
```

**Status:** ⬜ Not Tested | ✅ Pass | ❌ Fail  
**Tested By:** ____________  
**Test Date:** ____________  
**Notes:** ____________

---

### **TEST CASE 4: Offer Rejected Notification (To Provider)**

**Test ID:** TC_PN_004  
**Priority:** Medium  
**Trigger:** User rejects a provider's offer

**Preconditions:**
- Provider has sent an offer
- Multiple offers exist (optional)

**Test Steps:**
1. Login as **User (Device A)**
2. Navigate to "Review Offers" page
3. Select a provider's offer
4. Click "Reject"

**Expected Result:**
- [ ] Provider receives push notification on **Device B**
- [ ] Notification title: "Offer Rejected"
- [ ] Notification message: "Your offer was not selected by the customer."
- [ ] Offer status updated to 'rejected'

**Database Verification:**
```sql
SELECT * FROM notifications 
WHERE user_id = '<provider_id>' 
AND order_id = '<order_id>' 
AND title = 'Offer Rejected';
```

**Status:** ⬜ Not Tested | ✅ Pass | ❌ Fail  
**Tested By:** ____________  
**Test Date:** ____________  
**Notes:** ____________

---

### **TEST CASE 5: OTP for Service Verification (To User)**

**Test ID:** TC_PN_005  
**Priority:** High  
**Trigger:** Provider generates OTP to start the job

**Preconditions:**
- Order is in 'approved' status
- Provider is assigned to the order

**Test Steps:**
1. Login as **Provider (Device B)**
2. Navigate to order detail page
3. Click "Generate OTP" button
4. Observe User's **Device A**

**Expected Result:**
- [ ] User receives push notification on **Device A**
- [ ] Notification title: "OTP for Service Verification"
- [ ] Notification message: "Your Service Verification OTP is: [6-digit OTP]. Share this with the provider to start the job."
- [ ] OTP is valid for 10 minutes
- [ ] Screen parameter: "order_detail"

**Database Verification:**
```sql
SELECT otp_code, otp_expires_at FROM orders 
WHERE id = '<order_id>';
```

**Status:** ⬜ Not Tested | ✅ Pass | ❌ Fail  
**Tested By:** ____________  
**Test Date:** ____________  
**Notes:** ____________

---

### **TEST CASE 6: Service Verified / Job Started (To User)**

**Test ID:** TC_PN_006  
**Priority:** High  
**Trigger:** Provider enters correct OTP

**Preconditions:**
- OTP generated and sent to user
- Provider has access to valid OTP

**Test Steps:**
1. From **Device A**, check the OTP received
2. On **Device B** (Provider), enter the OTP
3. Click "Verify"
4. Observe **Device A**

**Expected Result:**
- [ ] User receives push notification on **Device A**
- [ ] Notification title: "Service Verified!"
- [ ] Notification message: "The provider is verified and work has started! You have 24 hours to update the status."
- [ ] Order status updated to 'verified'
- [ ] Timer started (24-hour deadline)

**Database Verification:**
```sql
SELECT status, verified_at FROM orders 
WHERE id = '<order_id>';
```

**Status:** ⬜ Not Tested | ✅ Pass | ❌ Fail  
**Tested By:** ____________  
**Test Date:** ____________  
**Notes:** ____________

---

### **TEST CASE 7: Order Cancelled Notification (To Provider)**

**Test ID:** TC_PN_007  
**Priority:** High  
**Trigger:** User cancels the order

**Preconditions:**
- Order is in any active status (not completed)

**Test Steps:**
1. Login as **User (Device A)**
2. Navigate to order detail page
3. Click "Cancel Order"
4. Confirm cancellation

**Expected Result:**
- [ ] Provider receives push notification on **Device B**
- [ ] Notification title: "Order Cancelled"
- [ ] Notification message: "Customer has cancelled the order."
- [ ] Order status updated to 'cancelled'

**Database Verification:**
```sql
SELECT status FROM orders WHERE id = '<order_id>';
SELECT * FROM notifications 
WHERE user_id = '<provider_id>' 
AND title = 'Order Cancelled';
```

**Status:** ⬜ Not Tested | ✅ Pass | ❌ Fail  
**Tested By:** ____________  
**Test Date:** ____________  
**Notes:** ____________

---

### **TEST CASE 8: Deadline Extended Notification (To Provider)**

**Test ID:** TC_PN_008  
**Priority:** Medium  
**Trigger:** User marks order as "Working" before deadline expires

**Preconditions:**
- Order is in 'verified' status
- Deadline is approaching or expired

**Test Steps:**
1. Login as **User (Device A)**
2. Navigate to order detail page
3. Click "Still Working" button
4. Observe **Device B**

**Expected Result:**
- [ ] Provider receives push notification on **Device B**
- [ ] Notification title: "Deadline Extended"
- [ ] Notification message: "Customer marked the order as 'Working'. Deadline extended by 24 hours."
- [ ] Deadline extended in database (new `deadline_at` value)
- [ ] Timer reset successful

**Database Verification:**
```sql
SELECT deadline_at, reminded FROM orders 
WHERE id = '<order_id>';
```

**Status:** ⬜ Not Tested | ✅ Pass | ❌ Fail  
**Tested By:** ____________  
**Test Date:** ____________  
**Notes:** ____________

---

### **TEST CASE 9: Service Completed Notification (To User)**

**Test ID:** TC_PN_009  
**Priority:** High  
**Trigger:** Provider marks service as completed OR completion function is called

**Preconditions:**
- Order is in 'verified' status
- Job has been ongoing

**Test Steps:**
1. Login as **User (Device A)**
2. Navigate to order detail page
3. Click "Service Completed" button
4. Optionally submit review

**Expected Result:**
- [ ] User receives push notification on **Device A**
- [ ] Notification title: "Service Completed!"
- [ ] Notification message: "[Provider Name] has completed your service. Please review the work and leave feedback!"
- [ ] Order status updated to 'completed'
- [ ] Provider's earnings updated
- [ ] **This notification must be sent** (previously was missing - fixed)

**Database Verification:**
```sql
SELECT status FROM orders WHERE id = '<order_id>';
SELECT * FROM notifications 
WHERE user_id = '<buyer_id>' 
AND title = 'Service Completed!';
```

**Status:** ⬜ Not Tested | ✅ Pass | ❌ Fail  
**Tested By:** ____________  
**Test Date:** ____________  
**Notes:** ____________

---

### **TEST CASE 10: New Review Received Notification (To Provider)**

**Test ID:** TC_PN_010  
**Priority:** Medium  
**Trigger:** User submits a review for the provider

**Preconditions:**
- Order completed
- User has not yet reviewed

**Test Steps:**
1. Login as **User (Device A)**
2. Navigate to order detail or review page
3. Rate the provider (1-5 stars)
4. Write review comment
5. Submit review

**Expected Result:**
- [ ] Provider receives push notification on **Device B**
- [ ] Notification title: "New Review Received!"
- [ ] Notification message: "You received a [X]-star review from [User Name]!"
- [ ] Review entry created in `provider_reviews` table

**Database Verification:**
```sql
SELECT * FROM provider_reviews 
WHERE provider_id = '<provider_id>' 
AND order_id = '<order_id>';
```

**Status:** ⬜ Not Tested | ✅ Pass | ❌ Fail  
**Tested By:** ____________  
**Test Date:** ____________  
**Notes:** ____________

---

### **TEST CASE 11: Order Update Notification (Generic)**

**Test ID:** TC_PN_011  
**Priority:** Medium  
**Trigger:** Various order status changes

**Preconditions:**
- Active order exists

**Test Steps:**
1. Perform various order updates:
   - User accepts counter-offer
   - User rejects counter-offer
   - Provider updates order status

**Expected Result:**
- [ ] Relevant party receives push notification
- [ ] Notification title: "Order Update"
- [ ] Notification message: Contextual message based on action
- [ ] Screen parameter: "order_detail"

**Status:** ⬜ Not Tested | ✅ Pass | ❌ Fail  
**Tested By:** ____________  
**Test Date:** ____________  
**Notes:** ____________

---

### **TEST CASE 12: Fine Notification (To Provider)**

**Test ID:** TC_PN_012  
**Priority:** High  
**Trigger:** Database trigger fires when fine is assigned

**Preconditions:**
- Provider account with active subscription
- Fine assignment scenario (e.g., order deadline expired)

**Test Steps:**
1. Simulate a fine assignment:
   - Let order deadline expire
   - OR manually assign fine via admin panel
2. Observe **Device B** (Provider)

**Expected Result:**
- [ ] Provider receives push notification on **Device B**
- [ ] Notification title: "Fine Assigned"
- [ ] Notification message: Details about the fine and reason
- [ ] Fine entry created in `provider_fines` table
- [ ] Notification created via database trigger

**Database Verification:**
```sql
SELECT * FROM provider_fines 
WHERE provider_id = '<provider_id>' 
ORDER BY created_at DESC LIMIT 1;
```

**Status:** ⬜ Not Tested | ✅ Pass | ❌ Fail  
**Tested By:** ____________  
**Test Date:** ____________  
**Notes:** ____________

---

### **TEST CASE 13: Multi-Device Support Test**

**Test ID:** TC_PN_013  
**Priority:** High  
**Trigger:** User has multiple devices logged in

**Preconditions:**
- Same user account logged in on 2+ devices
- All devices have valid FCM tokens

**Test Steps:**
1. Login with **same user account** on:
   - **Device A**: Primary phone
   - **Device C**: Secondary phone/tablet
2. Trigger any notification event (e.g., new order)
3. Observe both devices

**Expected Result:**
- [ ] Notification received on **both Device A and Device C**
- [ ] Same notification content on both devices
- [ ] Both FCM tokens stored in `fcm_tokens` table with different `device_id`
- [ ] Edge function successfully sends to multiple tokens

**Database Verification:**
```sql
SELECT * FROM fcm_tokens 
WHERE user_id = '<user_id>' 
AND is_active = true;
```

**Status:** ⬜ Not Tested | ✅ Pass | ❌ Fail  
**Tested By:** ____________  
**Test Date:** ____________  
**Notes:** ____________

---

### **TEST CASE 14: Foreground vs Background Notification**

**Test ID:** TC_PN_014  
**Priority:** High  
**Trigger:** Any notification event

**Preconditions:**
- Valid notification trigger

**Test Steps:**
1. **Foreground Test:**
   - Keep app OPEN on **Device A**
   - Trigger notification event
   - Observe notification display

2. **Background Test:**
   - Minimize app on **Device A** (app in background)
   - Trigger notification event
   - Observe notification display

3. **Terminated Test:**
   - Force close app on **Device A**
   - Trigger notification event
   - Observe notification display

**Expected Result:**

**Foreground:**
- [ ] Notification appears in-app (local notification shown)
- [ ] Notification tray shows notification
- [ ] Sound and vibration play

**Background:**
- [ ] Notification appears in notification tray
- [ ] Sound and vibration play
- [ ] Tapping notification opens app to correct screen

**Terminated:**
- [ ] Notification appears in notification tray
- [ ] Tapping notification launches app
- [ ] App opens to correct screen based on payload

**Status:** ⬜ Not Tested | ✅ Pass | ❌ Fail  
**Tested By:** ____________  
**Test Date:** ____________  
**Notes:** ____________

---

### **TEST CASE 15: Notification Deep Linking**

**Test ID:** TC_PN_015  
**Priority:** High  
**Trigger:** User taps on notification

**Preconditions:**
- Notification received with valid payload

**Test Steps:**
1. Receive notification with `screen: "order_detail"`
2. Tap the notification
3. Observe app navigation

**Expected Result:**
- [ ] App opens/foregrounds correctly
- [ ] Navigates to Order Detail page
- [ ] Correct order is displayed (based on `order_id` in payload)
- [ ] No crash or navigation error

**Test Cases to Cover:**
- [ ] Navigation from terminated state
- [ ] Navigation from background state
- [ ] Navigation when app is already open

**Status:** ⬜ Not Tested | ✅ Pass | ❌ Fail  
**Tested By:** ____________  
**Test Date:** ____________  
**Notes:** ____________

---

### **TEST CASE 16: Notification Permission Denied Scenario**

**Test ID:** TC_PN_016  
**Priority:** Medium  
**Trigger:** User denies notification permission

**Preconditions:**
- Fresh app install OR notification permission not granted

**Test Steps:**
1. Install app on **Device A**
2. When prompted for notification permission, select "Deny"
3. Login and trigger notification event
4. Check device notification tray

**Expected Result:**
- [ ] No notification appears in tray (expected behavior)
- [ ] Notification entry still created in database
- [ ] App handles gracefully (no crash)
- [ ] FCM token may not be generated/saved

**Database Verification:**
```sql
SELECT * FROM fcm_tokens 
WHERE user_id = '<user_id>';
-- Should be empty or inactive
```

**Status:** ⬜ Not Tested | ✅ Pass | ❌ Fail  
**Tested By:** ____________  
**Test Date:** ____________  
**Notes:** ____________

---

### **TEST CASE 17: Invalid/Expired FCM Token Handling**

**Test ID:** TC_PN_017  
**Priority:** Medium  
**Trigger:** FCM token becomes invalid

**Preconditions:**
- User logged in with valid token
- Simulate token expiry (app reinstall on new device without logout)

**Test Steps:**
1. Login on **Device A** and record FCM token
2. Uninstall and reinstall app (new FCM token generated)
3. Login again (old token still in database)
4. Trigger notification

**Expected Result:**
- [ ] Edge Function attempts to send to old token
- [ ] FCM returns error for invalid token
- [ ] Edge Function gracefully handles error
- [ ] Notification sent to new active token
- [ ] Old token marked as inactive (optional enhancement)

**Edge Function Log Verification:**
Check logs for error handling when invalid token is encountered

**Status:** ⬜ Not Tested | ✅ Pass | ❌ Fail  
**Tested By:** ____________  
**Test Date:** ____________  
**Notes:** ____________

---

### **TEST CASE 18: Notification Rate Limiting (Optional)**

**Test ID:** TC_PN_018  
**Priority:** Low  
**Trigger:** Rapid notification triggers

**Preconditions:**
- Multiple notification events in quick succession

**Test Steps:**
1. Trigger 10+ notifications within 1 minute
2. Observe notification delivery

**Expected Result:**
- [ ] All notifications delivered (unless rate limiting implemented)
- [ ] No notification loss
- [ ] No system overload
- [ ] FCM handles gracefully

**Status:** ⬜ Not Tested | ✅ Pass | ❌ Fail  
**Tested By:** ____________  
**Test Date:** ____________  
**Notes:** ____________

---

## ✅ Expected Results Summary

| Test Case | Notification Type | Recipient | Priority | Status |
|-----------|------------------|-----------|----------|---------|
| TC_PN_001 | New Order Request | Provider | High | ⬜ |
| TC_PN_002 | New Offer Received | User | High | ⬜ |
| TC_PN_003 | Offer Accepted | Provider | High | ⬜ |
| TC_PN_004 | Offer Rejected | Provider | Medium | ⬜ |
| TC_PN_005 | OTP Verification | User | High | ⬜ |
| TC_PN_006 | Service Verified | User | High | ⬜ |
| TC_PN_007 | Order Cancelled | Provider | High | ⬜ |
| TC_PN_008 | Deadline Extended | Provider | Medium | ⬜ |
| TC_PN_009 | Service Completed | User | High | ⬜ |
| TC_PN_010 | New Review Received | Provider | Medium | ⬜ |
| TC_PN_011 | Order Update | Both | Medium | ⬜ |
| TC_PN_012 | Fine Notification | Provider | High | ⬜ |
| TC_PN_013 | Multi-Device Support | Any | High | ⬜ |
| TC_PN_014 | Foreground/Background | Any | High | ⬜ |
| TC_PN_015 | Deep Linking | Any | High | ⬜ |
| TC_PN_016 | Permission Denied | Any | Medium | ⬜ |
| TC_PN_017 | Invalid Token | Any | Medium | ⬜ |
| TC_PN_018 | Rate Limiting | Any | Low | ⬜ |

---

## 🐛 Known Issues

Based on previous fixes documented in `NOTIFICATION_FIX_SUMMARY.md`:

### ✅ FIXED Issues:
1. **Double Notifications (TC_PN_002)**: 
   - **Issue**: Provider sending offer caused 2 notifications
   - **Fix**: Removed manual FCM calls, relying only on database trigger
   - **Test Focus**: Verify ONLY ONE notification received

2. **Missing Service Completion Notification (TC_PN_009)**:
   - **Issue**: No notification sent when service completed
   - **Fix**: Added notification insert to `complete_order_and_pay()` function
   - **Test Focus**: Verify notification IS sent

### ⚠️ Potential Issues to Watch:
1. **Multiple Order Triggers**: Database has 3 triggers for new order notifications (potential duplicates)
2. **Token Refresh**: Ensure token refresh listener properly updates database
3. **Network Failures**: Edge Function retry logic on network failures

---

## 📈 Test Execution Guidelines

### Before Testing:
1. Clear all previous notifications from devices
2. Verify backend services are running
3. Check Supabase Edge Function logs are accessible
4. Prepare test data (user accounts, services, locations)

### During Testing:
1. Test one scenario at a time
2. Document exact timestamps of actions
3. Check both device notification tray AND database entries
4. Screenshot notifications for evidence
5. Log any unexpected behavior immediately

### After Testing:
1. Compile test results in summary table
2. Create bug reports for failures
3. Document actual vs expected behavior
4. Verify database cleanup (remove test data if needed)

---

## 📝 Test Sign-Off

**Tester Name:** ____________________  
**Test Date:** ____________________  
**Overall Test Result:** ⬜ Pass | ⬜ Pass with Issues | ⬜ Fail  

**Summary of Issues Found:**
_______________________________________________
_______________________________________________
_______________________________________________

**Recommendations:**
_______________________________________________
_______________________________________________
_______________________________________________

---

## 🔗 Related Documents

- `NOTIFICATION_FIX_SUMMARY.md` - Previous notification fixes
- `lib/firebase/fcm_service.dart` - FCM service implementation
- `supabase/functions/push_notifications/index.ts` - Edge function
- `supabase/migrations/20241225221003_setup_fcm_trigger.sql` - FCM trigger setup

---

**END OF TEST PLAN**
