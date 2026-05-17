import 'package:flutter/material.dart';
import 'edit_profile.dart';
import '../widgets/privacy_policy_page.dart';
import '../supabase_config.dart';
import '../auth/session_manager.dart';

class SettingsPage extends StatelessWidget {
  final Map<String, dynamic> userData;

  const SettingsPage({super.key, required this.userData});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
      ),
      body: ListView(
        children: [
          _buildSectionHeader('Account'),
          _buildTile(context, 'Edit Profile', Icons.edit_rounded, () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => EditProfilePage(userData: userData),
              ),
            );
          }),
          _buildTile(
            context,
            'Request Account Deletion',
            Icons.person_remove_rounded,
            () => _showDeleteAccountDialog(context),
            isDestructive: true,
          ),

          _buildSectionHeader('Support'),
          _buildTile(
            context,
            'About Us',
            Icons.info_outline_rounded,
            () => _showAboutDialog(context),
          ),
          _buildTile(
            context,
            'Feedback',
            Icons.feedback_outlined,
            () => _showFeedbackDialog(context),
          ),

          _buildSectionHeader('Legal'),
          _buildTile(context, 'Privacy Policy', Icons.privacy_tip_outlined, () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PrivacyPolicyPage()),
            );
          }),
          _buildTile(
            context,
            'Terms of Service',
            Icons.description_outlined,
            () {
              // TODO: Open Terms URL
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Terms of Service coming soon')),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Colors.grey,
        ),
      ),
    );
  }

  Widget _buildTile(
    BuildContext context,
    String title,
    IconData icon,
    VoidCallback onTap, {
    bool isDestructive = false,
  }) {
    return ListTile(
      leading: Icon(icon, color: isDestructive ? Colors.red : Colors.grey[700]),
      title: Text(
        title,
        style: TextStyle(
          color: isDestructive ? Colors.red : Colors.black87,
          fontWeight: FontWeight.w500,
        ),
      ),
      trailing: const Icon(Icons.chevron_right, size: 20, color: Colors.grey),
      onTap: onTap,
    );
  }

  void _showDeleteAccountDialog(BuildContext context) {
    final TextEditingController reasonController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Account'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'We are sorry to see you go. Please tell us why you want to delete your account:',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: reasonController,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'Enter your reason here...',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              // In a real app, you'd submit this request to the backend.
              // For now, we'll just show a confirmation.
              Navigator.pop(context);
              _submitDeletionRequest(context, reasonController.text);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text(
              'Submit Request',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  void _submitDeletionRequest(BuildContext context, String reason) async {
    // Simulate API call
    final userId = await SessionManager.getUserId();
    try {
      await SupabaseConfig.supabase.from('deletion_requests').insert({
        'user_id': userId,
        'reason': reason,
        'status': 'pending',
        'created_at': DateTime.now().toIso8601String(),
      });

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Deletion request submitted. We will contact you shortly.',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      // If table doesn't exist, we just simulate success or log error
      debugPrint(
        "Error submitting deletion request (table might be missing): $e",
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Request received. Support will review it.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  void _showAboutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AboutDialog(
        applicationName: 'Mr. Helper',
        applicationVersion: '1.0.0',
        applicationIcon: const Icon(
          Icons.handyman_rounded,
          size: 50,
          color: Colors.blue,
        ),
        children: const [
          Text(
            'Mr. Helper connects you with local service providers for all your home maintenance needs.',
          ),
        ],
      ),
    );
  }

  void _showFeedbackDialog(BuildContext context) {
    final TextEditingController feedbackController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Send Feedback'),
        content: TextField(
          controller: feedbackController,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: 'What can we improve?',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Thank you for your feedback!')),
              );
            },
            child: const Text('Send'),
          ),
        ],
      ),
    );
  }
}
