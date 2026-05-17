# 🗄️ MrHelper AI — Complete Database Schema Reference

> **Project:** helperAI  
> **Supabase Project ID:** `rvrpsqdrbwfvllelyqhf`  
> **Region:** `ap-south-1` (Mumbai)  
> **Database Engine:** PostgreSQL 17  
> **Generated:** 2026-02-26  

---

## 📋 Table of Contents

1. [Users](#1-users)
2. [Pending Providers](#2-pending_providers)
3. [Services](#3-services)
4. [Service Types](#4-service_types)
5. [Locations](#5-locations)
6. [Orders](#6-orders)
7. [Order Offers](#7-order_offers)
8. [Order Images](#8-order_images)
9. [Active Order Timers](#9-active_order_timers)
10. [Notifications](#10-notifications)
11. [Scheduled Notifications](#11-scheduled_notifications)
12. [Chat Messages](#12-chat_messages)
13. [Feedback](#13-feedback)
14. [Provider Reviews](#14-provider_reviews)
15. [Subscriptions](#15-subscriptions)
16. [Subscription Payments](#16-subscription_payments)
17. [Subscription History](#17-subscription_history)
18. [Provider Fines](#18-provider_fines)
19. [Fine Transactions](#19-fine_transactions)
20. [Festival Themes](#20-festival_themes)
21. [Ads](#21-ads)
22. [Reports](#22-reports)
23. [Deletion Requests](#23-deletion_requests)
24. [Blocked Users](#24-blocked_users)
25. [Rate Limits](#25-rate_limits)
26. [Push Logs](#26-push_logs)
27. [User FCM Tokens](#27-user_fcm_tokens)
28. [Database Functions (RPCs)](#-database-functions-rpcs)
29. [Database Triggers](#-database-triggers)
30. [Indexes](#-indexes)
31. [Storage Buckets](#-storage-buckets)
32. [Edge Functions](#-edge-functions)
33. [Enums](#-enums)

---

## 1. `users`

> Core user table for both customers and service providers.

| Column | Type | Nullable | Default | Description |
|--------|------|----------|---------|-------------|
| `id` | UUID | NO | `gen_random_uuid()` | Primary key |
| `email` | TEXT | NO | — | Unique email address |
| `password` | TEXT | NO | — | SHA-256 hashed password |
| `full_name` | TEXT | NO | — | User's full name (used as username for login) |
| `phone_number` | TEXT | YES | — | Contact phone number |
| `bio` | TEXT | YES | — | User bio/description |
| `location` | TEXT | YES | — | User's location name |
| `latitude` | DOUBLE PRECISION | YES | — | GPS latitude |
| `longitude` | DOUBLE PRECISION | YES | — | GPS longitude |
| `avatar_url` | TEXT | YES | — | Profile picture URL |
| `is_provider` | BOOLEAN | NO | `false` | Whether user is a service provider |
| `service_id` | UUID | YES | — | FK → `services(id)` — provider's service |
| `service_type` | TEXT | YES | — | Provider's service type name |
| `aadhar_card_url` | TEXT | YES | — | KYC: Aadhar card image URL |
| `pan_card_url` | TEXT | YES | — | KYC: PAN card image URL |
| `price` | NUMERIC | YES | — | Provider's quoted price |
| `status` | TEXT | YES | `'active'` | Account status (`active`, `pending`, `rejected`, `suspended`) |
| `is_subscribed` | BOOLEAN | YES | `false` | Quick access: is provider subscribed? |
| `subscription_status` | `subscription_status_enum` | YES | — | Enum: `active`, `expired`, `cancelled`, etc. |
| `subscription_expiry` | TIMESTAMPTZ | YES | — | When subscription expires |
| `subscription_end_date` | TIMESTAMPTZ | YES | — | Subscription end date |
| `fcm_token` | TEXT | YES | — | Firebase Cloud Messaging token |
| `cancelled_by_admin` | BOOLEAN | YES | `false` | Was subscription cancelled by admin? |
| `cancellation_reason` | TEXT | YES | — | Reason for admin cancellation |
| `cancelled_at` | TIMESTAMPTZ | YES | — | When subscription was cancelled |
| `cancelled_by_admin_id` | UUID | YES | — | FK → `users(id)` — admin who cancelled |
| `created_at` | TIMESTAMPTZ | YES | `NOW()` | Account creation timestamp |

**RLS:** Enabled  
**Policies:**
- `Public Read Users` — SELECT → `true` (everyone can read)
- `Public Insert Users` — INSERT → `true` (for signup)
- `Update Own Profile` — UPDATE → restricted

---

## 2. `pending_providers`

> Staging table for provider KYC applications. Providers are moved to `users` upon approval.

| Column | Type | Nullable | Default | Description |
|--------|------|----------|---------|-------------|
| `id` | UUID | NO | `gen_random_uuid()` | Primary key |
| `email` | TEXT | NO | — | Unique email |
| `password` | TEXT | NO | — | Hashed password |
| `full_name` | TEXT | NO | — | Full name |
| `phone_number` | TEXT | YES | — | Phone |
| `bio` | TEXT | YES | — | Bio |
| `location` | TEXT | YES | — | Location name |
| `latitude` | DOUBLE PRECISION | YES | — | GPS latitude |
| `longitude` | DOUBLE PRECISION | YES | — | GPS longitude |
| `avatar_url` | TEXT | YES | — | Avatar URL |
| `service_id` | UUID | YES | — | Selected service |
| `service_type` | TEXT | YES | — | Service type name |
| `aadhar_card_url` | TEXT | YES | — | KYC: Aadhar |
| `pan_card_url` | TEXT | YES | — | KYC: PAN |
| `price` | NUMERIC | YES | — | Quoted price |
| `status` | TEXT | NO | `'pending'` | `pending`, `approved`, `rejected` |
| `created_at` | TIMESTAMPTZ | NO | `NOW()` | Applied at |
| `updated_at` | TIMESTAMPTZ | YES | `NOW()` | Last updated |

**RLS:** Enabled — full public access (admin checked in app)

---

## 3. `services`

> List of service categories (Cleaning, Plumbing, Electrical, etc.)

| Column | Type | Nullable | Default | Description |
|--------|------|----------|---------|-------------|
| `id` | UUID | NO | `gen_random_uuid()` | Primary key |
| `name` | TEXT | NO | — | Service name |
| `description` | TEXT | YES | — | Description |
| `base_price` | NUMERIC | YES | — | Base price |
| `image_url` | TEXT | YES | — | Service icon/image URL |
| `subscription_amount` | NUMERIC | YES | `250` | Subscription price for this service (legacy, kept for fallback) |
| `google_subscription_id` | TEXT | YES | `'mrhelper_monthly_pro'` | Google Play subscription product ID. Price is fetched from Google Play. |
| `require_current_location` | BOOLEAN | YES | `false` | Requires user's current location? |
| `require_destination_location` | BOOLEAN | YES | `false` | Requires destination location? |

**RLS:** Enabled

---

## 4. `service_types`

> Sub-types within a service category.

| Column | Type | Nullable | Default | Description |
|--------|------|----------|---------|-------------|
| `id` | UUID | NO | `gen_random_uuid()` | Primary key |
| `name` | TEXT | NO | — | Type name |
| `service_id` | UUID | YES | — | FK → `services(id)` |
| `description` | TEXT | YES | — | Description |

**RLS:** Enabled

---

## 5. `locations`

> Available service locations.

| Column | Type | Nullable | Default | Description |
|--------|------|----------|---------|-------------|
| `id` | UUID | NO | `gen_random_uuid()` | Primary key |
| `name` | TEXT | NO | — | Location name |
| `latitude` | DOUBLE PRECISION | YES | — | GPS latitude |
| `longitude` | DOUBLE PRECISION | YES | — | GPS longitude |
| `created_at` | TIMESTAMPTZ | YES | `NOW()` | Created at |

**RLS:** Enabled

---

## 6. `orders`

> Core orders/bookings table.

| Column | Type | Nullable | Default | Description |
|--------|------|----------|---------|-------------|
| `id` | UUID | NO | `gen_random_uuid()` | Primary key |
| `buyer_id` | UUID | NO | — | FK → `users(id)` — customer |
| `provider_id` | UUID | YES | — | FK → `users(id)` — assigned provider |
| `service_id` | UUID | NO | — | FK → `services(id)` |
| `location_id` | UUID | YES | — | FK → `locations(id)` |
| `status` | TEXT | NO | `'pending'` | `pending`, `accepted`, `completed`, `request_open`, `rejected`, `cancelled` |
| `user_phone` | TEXT | YES | — | Customer's phone |
| `user_price` | NUMERIC | YES | — | Customer's budget |
| `description` | TEXT | YES | — | Order description |
| `latitude` | DOUBLE PRECISION | YES | — | Service location lat |
| `longitude` | DOUBLE PRECISION | YES | — | Service location lng |
| `address` | TEXT | YES | — | Service address |
| `destination_latitude` | DOUBLE PRECISION | YES | — | Destination lat (transport services) |
| `destination_longitude` | DOUBLE PRECISION | YES | — | Destination lng |
| `destination_address` | TEXT | YES | — | Destination address |
| `scheduled_date` | TIMESTAMPTZ | YES | — | Scheduled service date |
| `completed_at` | TIMESTAMPTZ | YES | — | When order was completed |
| `created_at` | TIMESTAMPTZ | NO | `NOW()` | Order creation time |
| `updated_at` | TIMESTAMPTZ | YES | `NOW()` | Last updated |

**RLS:** Enabled — full anon access (`Anon Full Policy Orders`)  
**Constraint:** `orders_status_check` — status must be one of: `pending`, `accepted`, `completed`, `request_open`, `rejected`, `cancelled`

---

## 7. `order_offers`

> Provider offers/bids on open orders.

| Column | Type | Nullable | Default | Description |
|--------|------|----------|---------|-------------|
| `id` | UUID | NO | `gen_random_uuid()` | Primary key |
| `order_id` | UUID | NO | — | FK → `orders(id)` ON DELETE CASCADE |
| `provider_id` | UUID | NO | — | FK → `users(id)` ON DELETE CASCADE |
| `price` | NUMERIC | NO | — | Offered price |
| `status` | TEXT | NO | `'pending'` | `pending`, `accepted`, `rejected` |
| `created_at` | TIMESTAMPTZ | NO | `NOW()` | Offer timestamp |

**RLS:** Enabled — full anon access

---

## 8. `order_images`

> Images attached to orders.

| Column | Type | Nullable | Default | Description |
|--------|------|----------|---------|-------------|
| `id` | UUID | NO | `gen_random_uuid()` | Primary key |
| `order_id` | UUID | NO | — | FK → `orders(id)` |
| `image_url` | TEXT | NO | — | Image URL |
| `created_at` | TIMESTAMPTZ | YES | `NOW()` | Upload time |

---

## 9. `active_order_timers`

> Tracks active order countdown timers.

| Column | Type | Nullable | Default | Description |
|--------|------|----------|---------|-------------|
| `id` | UUID | NO | `gen_random_uuid()` | Primary key |
| `order_id` | UUID | NO | — | FK → `orders(id)` |
| `provider_id` | UUID | NO | — | FK → `users(id)` |
| `deadline` | TIMESTAMPTZ | NO | — | Timer deadline |
| `created_at` | TIMESTAMPTZ | YES | `NOW()` | Timer start |

---

## 10. `notifications`

> In-app notification system.

| Column | Type | Nullable | Default | Description |
|--------|------|----------|---------|-------------|
| `id` | UUID | NO | `gen_random_uuid()` | Primary key |
| `user_id` | UUID | NO | — | FK → `users(id)` — recipient |
| `order_id` | UUID | YES | — | FK → `orders(id)` — related order |
| `message` | TEXT | NO | — | Notification text |
| `is_read` | BOOLEAN | YES | `false` | Has been read? |
| `type` | TEXT | YES | `'general'` | Notification type (`order_request`, `general`, etc.) |
| `created_at` | TIMESTAMPTZ | NO | `NOW()` | Timestamp |

**RLS:** Enabled — full anon access

---

## 11. `scheduled_notifications`

> Pre-scheduled notifications (deadline reminders, etc.)

| Column | Type | Nullable | Default | Description |
|--------|------|----------|---------|-------------|
| `id` | UUID | NO | `gen_random_uuid()` | Primary key |
| `user_id` | UUID | NO | — | FK → `users(id)` |
| `order_id` | UUID | YES | — | Related order |
| `message` | TEXT | NO | — | Notification message |
| `scheduled_at` | TIMESTAMPTZ | NO | — | When to send |
| `sent` | BOOLEAN | YES | `false` | Already sent? |
| `created_at` | TIMESTAMPTZ | YES | `NOW()` | Created at |

---

## 12. `chat_messages`

> In-app chat between user and provider for an order.

| Column | Type | Nullable | Default | Description |
|--------|------|----------|---------|-------------|
| `id` | UUID | NO | `gen_random_uuid()` | Primary key |
| `order_id` | UUID | NO | — | FK → `orders(id)` |
| `sender_id` | UUID | NO | — | FK → `users(id)` |
| `message` | TEXT | NO | — | Message text |
| `is_read` | BOOLEAN | YES | `false` | Read by recipient? |
| `created_at` | TIMESTAMPTZ | NO | `NOW()` | Sent at |

---

## 13. `feedback`

> Order feedback/reviews.

| Column | Type | Nullable | Default | Description |
|--------|------|----------|---------|-------------|
| `id` | UUID | NO | `gen_random_uuid()` | Primary key |
| `order_id` | UUID | YES | — | FK → `orders(id)` |
| `user_id` | UUID | YES | — | FK → `users(id)` — reviewer |
| `rating` | INTEGER | YES | — | Rating (1-5) |
| `comment` | TEXT | YES | — | Review text |
| `created_at` | TIMESTAMPTZ | YES | `NOW()` | Submitted at |

**RLS:** Enabled  
**Policy:** `Public Read Feedback` — SELECT → `true`

---

## 14. `provider_reviews`

> Provider-specific reviews.

| Column | Type | Nullable | Default | Description |
|--------|------|----------|---------|-------------|
| `id` | UUID | NO | `gen_random_uuid()` | Primary key |
| `provider_id` | UUID | NO | — | FK → `users(id)` — provider being reviewed |
| `reviewer_id` | UUID | NO | — | FK → `users(id)` — reviewer |
| `order_id` | UUID | YES | — | FK → `orders(id)` |
| `rating` | INTEGER | NO | — | Rating (1-5) |
| `comment` | TEXT | YES | — | Review text |
| `created_at` | TIMESTAMPTZ | YES | `NOW()` | Submitted at |

---

## 15. `subscriptions`

> Razorpay subscription tracking.

| Column | Type | Nullable | Default | Description |
|--------|------|----------|---------|-------------|
| `id` | UUID | NO | `gen_random_uuid()` | Primary key |
| `user_id` | UUID | NO | — | FK → `users(id)` |
| `razorpay_subscription_id` | TEXT | YES | — | Razorpay subscription ID |
| `razorpay_payment_id` | TEXT | YES | — | Razorpay payment ID |
| `plan_id` | TEXT | YES | — | Subscription plan |
| `status` | TEXT | YES | `'created'` | `created`, `authenticated`, `active`, `halted`, `cancelled`, `expired`, `failed` |
| `start_date` | TIMESTAMPTZ | YES | — | Start date |
| `next_billing_date` | TIMESTAMPTZ | YES | — | Next billing |
| `created_at` | TIMESTAMPTZ | YES | `NOW()` | Created at |
| `updated_at` | TIMESTAMPTZ | YES | `NOW()` | Last updated |

**RLS:** Enabled

---

## 16. `subscription_payments`

> Payment records for subscriptions.

| Column | Type | Nullable | Default | Description |
|--------|------|----------|---------|-------------|
| `id` | UUID | NO | `gen_random_uuid()` | Primary key |
| `provider_id` | UUID | NO | — | FK → `users(id)` |
| `amount` | DECIMAL(10,2) | NO | — | Payment amount |
| `payment_id` | TEXT | YES | — | Payment gateway ID |
| `status` | TEXT | YES | — | Payment status |
| `created_at` | TIMESTAMPTZ | YES | `NOW()` | Payment time |

---

## 17. `subscription_history`

> Audit log for subscription status changes.

| Column | Type | Nullable | Default | Description |
|--------|------|----------|---------|-------------|
| `id` | UUID | NO | `gen_random_uuid()` | Primary key |
| `provider_id` | UUID | NO | — | FK → `users(id)` ON DELETE CASCADE |
| `action` | TEXT | NO | — | `activated`, `renewed`, `expired`, `cancelled_by_admin`, `cancelled_by_user` |
| `previous_status` | BOOLEAN | YES | — | Was subscribed before? |
| `new_status` | BOOLEAN | YES | — | Is subscribed now? |
| `previous_expiry` | TIMESTAMPTZ | YES | — | Previous expiry date |
| `new_expiry` | TIMESTAMPTZ | YES | — | New expiry date |
| `payment_id` | TEXT | YES | — | Payment reference |
| `amount` | DECIMAL(10,2) | YES | — | Amount paid |
| `admin_id` | UUID | YES | — | FK → `users(id)` — admin who acted |
| `cancellation_reason` | TEXT | YES | — | Reason if cancelled |
| `created_at` | TIMESTAMPTZ | YES | `NOW()` | Timestamp |

---

## 18. `provider_fines`

> Fine records for providers.

| Column | Type | Nullable | Default | Description |
|--------|------|----------|---------|-------------|
| `id` | UUID | NO | `gen_random_uuid()` | Primary key |
| `provider_id` | UUID | NO | — | FK → `users(id)` |
| `order_id` | UUID | YES | — | FK → `orders(id)` |
| `amount` | NUMERIC | NO | — | Fine amount |
| `reason` | TEXT | YES | — | Reason for fine |
| `status` | TEXT | YES | `'pending'` | `pending`, `paid`, `waived` |
| `created_at` | TIMESTAMPTZ | YES | `NOW()` | Created at |

---

## 19. `fine_transactions`

> Fine payment transaction records.

| Column | Type | Nullable | Default | Description |
|--------|------|----------|---------|-------------|
| `id` | UUID | NO | `gen_random_uuid()` | Primary key |
| `fine_id` | UUID | NO | — | FK → `provider_fines(id)` |
| `provider_id` | UUID | NO | — | FK → `users(id)` |
| `amount` | NUMERIC | NO | — | Transaction amount |
| `payment_id` | TEXT | YES | — | Payment gateway ID |
| `status` | TEXT | YES | — | Transaction status |
| `created_at` | TIMESTAMPTZ | YES | `NOW()` | Transaction time |

---

## 20. `festival_themes`

> App theming for festivals (Diwali, Christmas, Sankranti, etc.)

| Column | Type | Nullable | Default | Description |
|--------|------|----------|---------|-------------|
| `id` | UUID | NO | `gen_random_uuid()` | Primary key |
| `name` | TEXT | NO | — | Unique theme name (`default`, `diwali`, `christmas`) |
| `display_name` | TEXT | NO | — | Human-readable name |
| `description` | TEXT | YES | — | Description |
| `is_active` | BOOLEAN | YES | `false` | Is this the active theme? |
| `primary_color` | TEXT | NO | — | Hex color |
| `secondary_color` | TEXT | NO | — | Hex color |
| `accent_color` | TEXT | NO | — | Hex color |
| `background_color` | TEXT | NO | — | Hex color |
| `text_color` | TEXT | NO | — | Hex color |
| `card_color` | TEXT | NO | — | Hex color |
| `banner_image_url` | TEXT | YES | — | Banner image URL/path |
| `icon_pack` | TEXT | YES | — | JSON object with icon mappings |
| `decorative_elements` | TEXT | YES | — | JSON array of decorative configs |
| `priority` | INTEGER | YES | `0` | Display order |
| `created_at` | TIMESTAMPTZ | YES | `NOW()` | Created at |
| `updated_at` | TIMESTAMPTZ | YES | `NOW()` | Updated at |

**RLS:** Enabled  
**Trigger:** `enforce_single_active_theme` — ensures only one theme is active at a time

---

## 21. `ads`

> In-app advertisements.

| Column | Type | Nullable | Default | Description |
|--------|------|----------|---------|-------------|
| `id` | UUID | NO | `gen_random_uuid()` | Primary key |
| `title` | TEXT | YES | — | Ad title |
| `image_url` | TEXT | YES | — | Ad image URL |
| `end_date` | TIMESTAMPTZ | YES | — | Expiry date |
| `is_active` | BOOLEAN | YES | `true` | Is ad active? |
| `created_at` | TIMESTAMPTZ | YES | `NOW()` | Created at |

---

## 22. `reports`

> User reports (complaints, issues).

| Column | Type | Nullable | Default | Description |
|--------|------|----------|---------|-------------|
| `id` | UUID | NO | `gen_random_uuid()` | Primary key |
| `reporter_id` | UUID | NO | — | FK → `users(id)` — who reported |
| `reported_id` | UUID | YES | — | FK → `users(id)` — who was reported |
| `order_id` | UUID | YES | — | Related order |
| `reason` | TEXT | NO | — | Report reason |
| `description` | TEXT | YES | — | Details |
| `status` | TEXT | YES | `'pending'` | `pending`, `reviewed`, `resolved` |
| `created_at` | TIMESTAMPTZ | YES | `NOW()` | Reported at |

---

## 23. `deletion_requests`

> Account deletion requests.

| Column | Type | Nullable | Default | Description |
|--------|------|----------|---------|-------------|
| `id` | UUID | NO | `gen_random_uuid()` | Primary key |
| `user_id` | UUID | NO | — | FK → `users(id)` |
| `reason` | TEXT | YES | — | Reason for deletion |
| `status` | TEXT | YES | `'pending'` | Request status |
| `created_at` | TIMESTAMPTZ | YES | `NOW()` | Requested at |

---

## 24. `blocked_users`

> User blocking system.

| Column | Type | Nullable | Default | Description |
|--------|------|----------|---------|-------------|
| `id` | UUID | NO | `gen_random_uuid()` | Primary key |
| `blocker_id` | UUID | NO | — | FK → `users(id)` ON DELETE CASCADE — who blocked |
| `blocked_id` | UUID | NO | — | FK → `users(id)` ON DELETE CASCADE — who was blocked |
| `created_at` | TIMESTAMPTZ | YES | `NOW()` | Blocked at |

**Constraint:** UNIQUE(`blocker_id`, `blocked_id`)

---

## 25. `rate_limits`

> Login rate limiting (brute force protection).

| Column | Type | Nullable | Default | Description |
|--------|------|----------|---------|-------------|
| `id` | UUID | NO | `gen_random_uuid()` | Primary key |
| `ip_address` | TEXT | YES | — | Client IP |
| `action` | TEXT | YES | — | Action type (e.g., `login_attempt`) |
| `identifier` | TEXT | YES | — | Username/email |
| `created_at` | TIMESTAMPTZ | YES | `NOW()` | Timestamp |

---

## 26. `push_logs`

> Log of push notification attempts.

| Column | Type | Nullable | Default | Description |
|--------|------|----------|---------|-------------|
| `id` | UUID | NO | `gen_random_uuid()` | Primary key |
| `user_id` | UUID | YES | — | Target user |
| `title` | TEXT | YES | — | Notification title |
| `body` | TEXT | YES | — | Notification body |
| `created_at` | TIMESTAMPTZ | YES | `NOW()` | Logged at |

---

## 27. `user_fcm_tokens`

> Firebase Cloud Messaging tokens for multi-device push notifications.

| Column | Type | Nullable | Default | Description |
|--------|------|----------|---------|-------------|
| `id` | UUID | NO | `gen_random_uuid()` | Primary key |
| `user_id` | UUID | NO | — | FK → `users(id)` |
| `fcm_token` | TEXT | NO | — | FCM device token |
| `is_active` | BOOLEAN | YES | `true` | Token active? |
| `device_info` | TEXT | YES | — | Device metadata |
| `created_at` | TIMESTAMPTZ | YES | `NOW()` | Token registered at |
| `updated_at` | TIMESTAMPTZ | YES | `NOW()` | Last updated |

---

## 🔧 Database Functions (RPCs)

| Function | Parameters | Returns | Description |
|----------|-----------|---------|-------------|
| `login_secure` | `p_username TEXT, p_password_hash TEXT` | JSON | Secure login with rate limiting and status checks |
| `check_rate_limit` | `p_action, p_window_seconds, p_max_requests, p_identifier` | BOOLEAN | Rate limiting checker |
| `approve_provider` | `provider_id UUID` | VOID | Approves pending provider → moves to `users` |
| `reject_provider` | `provider_id UUID` | VOID | Rejects and deletes pending provider |
| `clear_rejected_user` | `email_input TEXT` | VOID | Cleanup rejected users |
| `admin_cancel_subscription` | `p_provider_id, p_admin_id, p_reason` | JSON | Admin cancels a provider's subscription |
| `get_subscription_stats` | — | JSON | Returns subscription statistics |
| `notify_providers_on_order` | (trigger) | TRIGGER | Batch-notifies matching providers on new order |
| `send_fcm_on_notification` | (trigger) | TRIGGER | Sends FCM push via Edge Function on new notification |
| `log_push_notification` | (trigger) | TRIGGER | Logs push notification attempts |
| `log_subscription_change` | (trigger) | TRIGGER | Auto-logs subscription status changes |
| `ensure_single_active_theme` | (trigger) | TRIGGER | Ensures only one festival theme is active |
| `get_active_theme` | — | SETOF `festival_themes` | Returns the active theme |
| `update_festival_themes_updated_at` | (trigger) | TRIGGER | Auto-updates `updated_at` timestamp |
| `update_updated_at_column` | (trigger) | TRIGGER | Generic `updated_at` trigger function |

---

## ⚡ Database Triggers

| Trigger | Table | Event | Function |
|---------|-------|-------|----------|
| `on_order_created_notify` | `orders` | AFTER INSERT | `notify_providers_on_order()` |
| `trigger_send_fcm_notification` | `notifications` | AFTER INSERT | `send_fcm_on_notification()` |
| `on_notification_push` | `notifications` | AFTER INSERT | `log_push_notification()` |
| `subscription_change_logger` | `users` | AFTER UPDATE | `log_subscription_change()` |
| `enforce_single_active_theme` | `festival_themes` | BEFORE INSERT/UPDATE | `ensure_single_active_theme()` |
| `update_festival_themes_timestamp` | `festival_themes` | BEFORE UPDATE | `update_festival_themes_updated_at()` |
| `update_subscriptions_updated_at` | `subscriptions` | BEFORE UPDATE | `update_updated_at_column()` |

---

## 📇 Indexes

### Orders Table
| Index | Columns | Condition |
|-------|---------|-----------|
| `idx_orders_status` | `status` | — |
| `idx_orders_service_id` | `service_id` | — |
| `idx_orders_location_id` | `location_id` | — |
| `idx_orders_buyer_id` | `buyer_id` | — |
| `idx_orders_provider_id` | `provider_id` | `WHERE provider_id IS NOT NULL` |
| `idx_orders_created_at` | `created_at DESC` | — |
| `idx_orders_provider_matching` | `status, service_id, location_id` | `WHERE status = 'request_open'` |
| `idx_orders_buyer_status` | `buyer_id, status, created_at DESC` | — |
| `idx_orders_provider_status` | `provider_id, status, created_at DESC` | — |
| `idx_orders_active` | `status, created_at DESC` | `WHERE status IN ('request_open','accepted','pending')` |
| `idx_orders_open_requests` | `service_id, location_id, created_at DESC` | `WHERE status = 'request_open'` |
| `idx_orders_completed` | `provider_id, created_at DESC` | `WHERE status = 'completed'` |
| `idx_orders_in_progress` | `provider_id` | `WHERE status = 'accepted'` |

### Users Table
| Index | Columns | Condition |
|-------|---------|-----------|
| `idx_users_is_provider` | `is_provider` | `WHERE is_provider = true` |
| `idx_users_service_subscription` | `service_id, subscription_status` | `WHERE is_provider = true` |
| `idx_users_location` | `location` | `WHERE is_provider = true` |
| `idx_users_provider_active` | `service_id, subscription_status, subscription_end_date` | `WHERE is_provider = true AND subscription_status = 'active'` |
| `idx_users_fcm_token` | `fcm_token` | `WHERE fcm_token IS NOT NULL` |

### Notifications Table
| Index | Columns | Condition |
|-------|---------|-----------|
| `idx_notifications_user_id` | `user_id, created_at DESC` | — |
| `idx_notifications_order_id` | `order_id` | — |
| `idx_notifications_unread` | `user_id, is_read` | `WHERE is_read = false` |

### Other Tables
| Index | Table | Columns |
|-------|-------|---------|
| `idx_order_offers_order_id` | `order_offers` | `order_id` |
| `idx_order_offers_provider_id` | `order_offers` | `provider_id` |
| `idx_pending_providers_status` | `pending_providers` | `status` |
| `idx_pending_providers_email` | `pending_providers` | `email` |
| `idx_subscription_history_provider` | `subscription_history` | `provider_id` |
| `idx_subscription_history_action` | `subscription_history` | `action` |
| `idx_subscription_history_created` | `subscription_history` | `created_at DESC` |
| `idx_rate_limits_ip_action` | `rate_limits` | `ip_address, action` |
| `idx_rate_limits_created_at` | `rate_limits` | `created_at` |
| `idx_festival_themes_active` | `festival_themes` | `is_active` |
| `idx_festival_themes_priority` | `festival_themes` | `priority` |

---

## 📦 Storage Buckets

| Bucket | Purpose | Public? |
|--------|---------|---------|
| `avatars` | User profile pictures | Yes |
| `ads` | Advertisement images | Yes |
| `services` | Service category images | Yes |
| `kyc-documents` | Aadhar/PAN card uploads | No (private) |
| `order-images` | Order attachment images | Yes |

---

## 🛒 Products Marketplace (New)

### `products`
| Column | Type | Attributes | Description |
|--------|------|------------|-------------|
| `id` | UUID | Primary Key, Default: `gen_random_uuid()` | Unique product ID |
| `provider_id` | UUID | FK → `users(id)` ON DELETE CASCADE | Provider owning the product |
| `name` | TEXT | Not Null | Product name |
| `description` | TEXT | Nullable | Product details |
| `price` | NUMERIC | Not Null | Base price |
| `image_url` | TEXT | Nullable | Storage URL for image |
| `is_active` | BOOLEAN | Default: `true` | Visibility toggle |
| `created_at` | TIMESTAMPTZ | Default: `now()` | Creation timestamp |
| `updated_at` | TIMESTAMPTZ | Default: `now()` | Auto-updated on modify |

### `product_orders`
| Column | Type | Attributes | Description |
|--------|------|------------|-------------|
| `id` | UUID | Primary Key, Default: `gen_random_uuid()` | Unique negotiation/order ID |
| `product_id` | UUID | FK → `products(id)` ON DELETE CASCADE | Target product |
| `buyer_id` | UUID | FK → `users(id)` | User attempting to buy |
| `provider_id` | UUID | FK → `users(id)` | Seller (redundant but useful) |
| `status` | TEXT | Default: `'negotiating'` | `'negotiating'`, `'accepted'`, `'cancelled'` |
| `original_price` | NUMERIC | Not Null | Snapshot of product price |
| `final_price` | NUMERIC | Nullable | Agreed upon price |
| `created_at` | TIMESTAMPTZ | Default: `now()` | Started at |
| `updated_at` | TIMESTAMPTZ | Default: `now()` | Auto-updated |

### `negotiation_messages`
| Column | Type | Attributes | Description |
|--------|------|------------|-------------|
| `id` | UUID | Primary Key, Default: `gen_random_uuid()` | Unique message ID |
| `product_order_id` | UUID | FK → `product_orders(id)` ON DELETE CASCADE| The parent negotiation |
| `sender_id` | UUID | FK → `users(id)` | Who sent this |
| `sender_role` | TEXT | Not Null | `'buyer'` or `'provider'` |
| `action` | TEXT | Not Null | `'offer'`, `'counter_offer'`, `'accept'`, `'cancel'` |
| `amount` | NUMERIC | Nullable | Offer amount (if applicable) |
| `created_at` | TIMESTAMPTZ | Default: `now()` | Message time |

---

## 🚀 Edge Functions

| Function | Path | Description |
|----------|------|-------------|
| `push_notifications` | `/functions/v1/push_notifications` | Sends FCM push notifications via Firebase Admin SDK |
| `deadline-reminders` | `/functions/v1/deadline-reminders` | Sends deadline reminder notifications |
| `subscription-reminders` | `/functions/v1/subscription-reminders` | Sends subscription expiry reminders |

---

## 🏷️ Enums

### `subscription_status_enum`
```
'active' | 'expired' | 'cancelled'
```

---

## 🔗 Entity Relationship Diagram

```
users ──┬── orders (buyer_id)
        ├── orders (provider_id)
        ├── order_offers (provider_id)
        ├── notifications (user_id)
        ├── chat_messages (sender_id)
        ├── feedback (user_id)
        ├── provider_reviews (provider_id / reviewer_id)
        ├── subscriptions (user_id)
        ├── subscription_payments (provider_id)
        ├── subscription_history (provider_id)
        ├── provider_fines (provider_id)
        ├── user_fcm_tokens (user_id)
        ├── reports (reporter_id / reported_id)
        ├── deletion_requests (user_id)
        ├── blocked_users (blocker_id / blocked_id)
        ├── products (provider_id)
        ├── product_orders (buyer_id / provider_id)
        └── negotiation_messages (sender_id)

products ── product_orders (product_id)

product_orders ── negotiation_messages (product_order_id)

services ──┬── users (service_id)
           ├── orders (service_id)
           └── service_types (service_id)

orders ──┬── order_offers (order_id)
         ├── order_images (order_id)
         ├── active_order_timers (order_id)
         ├── chat_messages (order_id)
         ├── notifications (order_id)
         └── feedback (order_id)

locations ── orders (location_id)

pending_providers (standalone - staging table)
festival_themes (standalone - app theming)
ads (standalone - advertisements)
rate_limits (standalone - security)
push_logs (standalone - logging)
```

---

> **Note:** This schema was reconstructed from migration files and Dart source code as of 2026-02-26. Some columns in tables like `ads`, `service_types`, `active_order_timers`, `fine_transactions`, and `provider_fines` are inferred from code usage and may have additional columns in the actual database. Run a live query against `information_schema.columns` when Supabase connectivity is restored for the most accurate column-level details.
