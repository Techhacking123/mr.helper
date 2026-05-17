# 🛠️ Mr. Helper

Mr. Helper is a comprehensive, real-time Service and Products Marketplace application built with **Flutter**, powered by **Supabase** (Database, Auth, Storage, Edge Functions), and integrated with **Firebase Cloud Messaging (FCM)** for push notifications. 

The platform bridges the gap between everyday users looking for home services (plumbers, electricians, cleaners) and service providers looking for freelance jobs, complete with real-time bidding, GPS location tracking, and an integrated e-commerce marketplace.

---

## ✨ Key Features

### 👤 For Users (Customers)
* **Service Booking:** Browse and hire nearby service professionals dynamically filtered by distance.
* **Products Marketplace:** Discover tools and products uploaded by providers.
* **Live Negotiation System:** Real-time chat-based negotiation system for buying products with counter-offers.
* **OTP Verification:** Secure job tracking with 24-hour expiration timers and OTP verification upon completion.
* **Smart Search:** Voice-activated and AI-assisted search functionality to find exact services or products instantly.
* **Real-time Order Tracking:** Live status updates from "Pending" to "Working" to "Completed".
* **Dynamic Festival Themes:** App theme dynamically updates based on cloud settings (e.g., Diwali, Christmas themes).

### 👷 For Service Providers
* **Provider Dashboard:** Track active requests, ongoing jobs, and total earnings.
* **Marketplace Inventory:** Upload product photos, descriptions, and prices to sell directly to users.
* **Premium Subscriptions:** Google Play Billing integration allowing providers to unlock premium visibility and limitless job acceptances.
* **Location-Based Visibility:** Automatically matches with customers in a specific radius using reverse geocoding.

### 🛡️ Admin & System Integrity
* **Red Star Penalty System:** Automated cron-jobs and Edge Functions assign penalty "Red Stars" to providers who miss 24-hour job deadlines.
* **Account Moderation:** Providers with 3+ red stars are automatically blocked until manual admin intervention.
* **Supabase Realtime:** Instant syncing of all chat messages, order statuses, and negotiation states.

---

## 🚀 Setup & Installation

### 1. Prerequisites
To run this project locally, ensure you have the following installed:
* [Flutter SDK](https://docs.flutter.dev/get-started/install) (latest stable version)
* [Dart SDK](https://dart.dev/get-dart)
* Android Studio / Xcode (for emulation/compilation)
* A [Supabase](https://supabase.com/) Account (for the backend)
* A [Firebase](https://firebase.google.com/) Account (for push notifications)

### 2. Clone the Repository
```bash
git clone https://github.com/Techhacking123/mr.helper.git
cd mr.helper
```

### 3. Fetch Dependencies
```bash
flutter pub get
```

### 4. Environment Configuration
You need to configure the backend API keys for the app to function.
1. Locate `lib/supabase_config.dart`.
2. Update the `supabaseUrl` and `supabaseAnonKey` with your project's credentials from the Supabase Dashboard.
3. Configure `android/app/google-services.json` with your Firebase project credentials to enable FCM push notifications.

### 5. Database Setup
The complete database schema is documented in `DATABASE_SCHEMA.md`. 
1. Open your Supabase SQL Editor.
2. Run the migration files located in the `supabase_migrations/` folder in sequential order to generate all the necessary tables, Row Level Security (RLS) policies, and RPC functions.

### 6. Run the App
Connect a physical device or start an emulator, then run:
```bash
flutter run
```

---

## 📦 Tech Stack
* **Frontend:** Flutter (Dart), Google Nav Bar, Cached Network Image, Google Mobile Ads.
* **Backend as a Service:** Supabase (PostgreSQL, Auth, Storage Bucket, Realtime Channels).
* **Push Notifications:** Firebase Cloud Messaging (FCM).
* **Monetization:** `in_app_purchase` (Google Play Billing).
* **Maps & Location:** `geolocator`, `geocoding`.

---
*Created for the Techhacking123 Team.*
