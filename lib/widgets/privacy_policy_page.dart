import 'package:flutter/material.dart';

class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Privacy Policy'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text(
              'Privacy Policy for Mr.Helper',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Color(0xFF2C3E50),
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Last updated: January 25, 2026',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey,
                fontStyle: FontStyle.italic,
              ),
            ),
            SizedBox(height: 24),
            Text(
              'At Mr.Helper, we take your privacy seriously. This Privacy Policy explains how we collect, use, and protect your information when you use our mobile application.',
              style: TextStyle(fontSize: 16, height: 1.5),
            ),
            SizedBox(height: 24),
            Text(
              '1. Information We Collect',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF34495E),
              ),
            ),
            SizedBox(height: 12),
            Text(
              'To provide our services, we may request the following permissions and data:',
              style: TextStyle(fontSize: 16, height: 1.5),
            ),
            SizedBox(height: 8),
            _BulletPoint(
              'Location Data: We collect your precise or approximate location to connect you with nearby service providers and to facilitate service delivery. This data may be used even when the app is running in the background if required for real-time tracking of active orders.',
            ),
            _BulletPoint(
              'Microphone (Audio): We access your device\'s microphone only when you use the voice search feature to find services. Audio data is processed locally or sent temporarily to speech recognition servers and is not permanently stored.',
            ),
            _BulletPoint(
              'Photos and Media: We access your photo gallery only when you choose to upload a profile picture or service images.',
            ),
            _BulletPoint(
              'Contact Information: We collect your email address, phone number, and name during account creation to manage your account and communicate important updates.',
            ),
            _BulletPoint(
              'Device Information: We may collect device details (model, OS version) and unique identifiers for analytics and to send push notifications.',
            ),
            SizedBox(height: 24),
            Text(
              '2. How We Use Your Information',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF34495E),
              ),
            ),
            SizedBox(height: 12),
            Text(
              'We use the collected data for the following purposes:',
              style: TextStyle(fontSize: 16, height: 1.5),
            ),
            SizedBox(height: 8),
            _BulletPoint(
              'To facilitate booking and delivery of home services.',
            ),
            _BulletPoint('To verify your identity and manage your account.'),
            _BulletPoint(
              'To communicate with you regarding your orders and support requests.',
            ),
            _BulletPoint(
              'To improve our app functionality and user experience.',
            ),
            _BulletPoint(
              'To send you transactional notifications and promotional offers (if opted in).',
            ),
            SizedBox(height: 24),
            Text(
              '3. Data Sharing and Disclosure',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF34495E),
              ),
            ),
            SizedBox(height: 12),
            Text(
              'We do not sell your personal data. We may share your information only in the following circumstances:',
              style: TextStyle(fontSize: 16, height: 1.5),
            ),
            SizedBox(height: 8),
            _BulletPoint(
              'With Service Providers: Your location and contact details may be shared with the specific provider you book to enable them to fulfill the service.',
            ),
            _BulletPoint(
              'Legal Requirements: If required by law or to protect our rights and safety.',
            ),
            SizedBox(height: 24),
            Text(
              '4. Data Security',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF34495E),
              ),
            ),
            SizedBox(height: 12),
            Text(
              'We implement industry-standard security measures to protect your data. However, no method of transmission over the internet or electronic storage is 100% secure.',
              style: TextStyle(fontSize: 16, height: 1.5),
            ),
            SizedBox(height: 24),
            Text(
              '5. Your Rights',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF34495E),
              ),
            ),
            SizedBox(height: 12),
            Text(
              'You can access, update, or delete your account information at any time within the app settings. You may also revoke permissions (Location, Microphone, etc.) through your device settings, though this may limit app functionality.',
              style: TextStyle(fontSize: 16, height: 1.5),
            ),
            SizedBox(height: 24),
            Text(
              '6. Contact Us',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF34495E),
              ),
            ),
            SizedBox(height: 12),
            Text(
              'If you have any questions about this Privacy Policy, please contact us at:\nEmail: phoenixsoftwaresolutions172@gmail.com',
              style: TextStyle(fontSize: 16, height: 1.5),
            ),
            SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

class _BulletPoint extends StatelessWidget {
  final String text;
  const _BulletPoint(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '• ',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 16, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
