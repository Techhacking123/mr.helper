import 'package:flutter/material.dart';
import '../supabase_config.dart';

class AdminKycPage extends StatefulWidget {
  const AdminKycPage({super.key});

  @override
  State<AdminKycPage> createState() => _AdminKycPageState();
}

class _AdminKycPageState extends State<AdminKycPage> {
  List<Map<String, dynamic>> _pendingProviders = [];
  bool _isLoading = true;
  // Track subscription toggle for each provider
  final Map<String, bool> _subscriptionToggles = {};

  @override
  void initState() {
    super.initState();
    _fetchPendingProviders();
  }

  Future<void> _fetchPendingProviders() async {
    setState(() => _isLoading = true);
    try {
      final response = await SupabaseConfig.supabase
          .from('pending_providers')
          .select()
          .eq('status', 'pending')
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _pendingProviders = List<Map<String, dynamic>>.from(response);
          // Initialize all toggles to ON by default
          for (var provider in _pendingProviders) {
            _subscriptionToggles[provider['id']] = true;
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching pending providers: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _updateStatus(
    String providerId,
    String newStatus, {
    bool grantSubscription = false,
  }) async {
    try {
      if (newStatus == 'active') {
        // Fetch provider email BEFORE approval (while still in pending_providers)
        String? providerEmail;
        if (grantSubscription) {
          final pendingProvider = await SupabaseConfig.supabase
              .from('pending_providers')
              .select('email')
              .eq('id', providerId)
              .single();
          providerEmail = pendingProvider['email'] as String?;
        }

        // Approve provider - moves to users table
        await SupabaseConfig.supabase.rpc(
          'approve_provider',
          params: {'provider_id': providerId},
        );

        // Grant 3-month subscription if toggle is ON
        // Now the provider is in the users table, so we can update it
        if (grantSubscription && providerEmail != null) {
          final now = DateTime.now();
          final expiryDate = now.add(const Duration(days: 90));
          await SupabaseConfig.supabase
              .from('users')
              .update({
                'is_subscribed': true,
                'subscription_status': 'active',
                'subscription_start_date': now.toIso8601String(),
                'subscription_expiry': expiryDate.toIso8601String(),
                'subscription_end_date': expiryDate.toIso8601String(),
              })
              .eq('email', providerEmail);
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                grantSubscription
                    ? 'Provider approved with 3-month free subscription!'
                    : 'Provider approved successfully! They can now login.',
              ),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else if (newStatus == 'rejected') {
        // Reject provider - stays in pending_providers with rejected status
        await SupabaseConfig.supabase.rpc(
          'reject_provider',
          params: {'provider_id': providerId},
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Provider rejected. They will not be able to login.',
              ),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }

      _fetchPendingProviders();
    } catch (e) {
      debugPrint('Error updating provider status: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pending Approvals'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _pendingProviders.isEmpty
          ? const Center(
              child: Text(
                'No pending approvals',
                style: TextStyle(fontSize: 18, color: Colors.grey),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _pendingProviders.length,
              itemBuilder: (context, index) {
                final provider = _pendingProviders[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 16),
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 30,
                              backgroundImage: provider['avatar_url'] != null
                                  ? NetworkImage(
                                      SupabaseConfig.proxyImageUrl(
                                        provider['avatar_url'],
                                      ),
                                    )
                                  : null,
                              child: provider['avatar_url'] == null
                                  ? const Icon(Icons.person, size: 30)
                                  : null,
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    provider['full_name'] ?? 'No Name',
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    provider['email'] ?? '',
                                    style: TextStyle(color: Colors.grey[600]),
                                  ),
                                  Text(
                                    provider['service_type'] ??
                                        'Unknown Service',
                                    style: const TextStyle(
                                      color: Colors.deepPurple,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    provider['phone_number'] ?? 'No Phone',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  Text(
                                    provider['location'] ?? 'No Location',
                                    style: const TextStyle(color: Colors.grey),
                                  ),
                                  if (provider['price'] != null)
                                    Text(
                                      'Price: ₹${provider['price']}',
                                      style: const TextStyle(
                                        color: Colors.green,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        if (provider['bio'] != null &&
                            provider['bio'].toString().isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Bio: ${provider['bio']}',
                            style: const TextStyle(
                              fontStyle: FontStyle.italic,
                              color: Colors.black54,
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        const Text(
                          'Documents:',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              if (provider['aadhar_card_url'] != null)
                                _buildDocPreview(
                                  'Aadhar',
                                  provider['aadhar_card_url'],
                                ),
                              if (provider['pan_card_url'] != null) ...[
                                const SizedBox(width: 12),
                                _buildDocPreview(
                                  'PAN',
                                  provider['pan_card_url'],
                                ),
                              ],
                              if (provider['aadhar_card_url'] == null &&
                                  provider['pan_card_url'] == null)
                                const Text(
                                  'No documents uploaded',
                                  style: TextStyle(color: Colors.red),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Subscription Toggle
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.blue.shade200),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.card_membership,
                                color: Colors.blue.shade700,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Grant 3-Month Free Subscription',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.blue.shade900,
                                  ),
                                ),
                              ),
                              Switch(
                                value:
                                    _subscriptionToggles[provider['id']] ??
                                    false,
                                onChanged: (value) {
                                  setState(() {
                                    _subscriptionToggles[provider['id']] =
                                        value;
                                  });
                                },
                                activeColor: Colors.blue,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () =>
                                    _updateStatus(provider['id'], 'rejected'),
                                icon: const Icon(Icons.close),
                                label: const Text('Reject'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.red,
                                  side: const BorderSide(color: Colors.red),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  // Check if subscription toggle is ON
                                  final isToggleOn =
                                      _subscriptionToggles[provider['id']] ??
                                      false;
                                  if (!isToggleOn) {
                                    // Show warning dialog
                                    showDialog(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        title: const Row(
                                          children: [
                                            Icon(
                                              Icons.warning,
                                              color: Colors.orange,
                                            ),
                                            SizedBox(width: 8),
                                            Text('Subscription Required'),
                                          ],
                                        ),
                                        content: const Text(
                                          'Please enable the 3-month free subscription toggle before approving the provider.',
                                          style: TextStyle(fontSize: 16),
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.pop(ctx),
                                            child: const Text('OK'),
                                          ),
                                        ],
                                      ),
                                    );
                                    return;
                                  }
                                  // Proceed with approval
                                  _updateStatus(
                                    provider['id'],
                                    'active',
                                    grantSubscription: isToggleOn,
                                  );
                                },
                                icon: const Icon(Icons.check),
                                label: const Text('Approve'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  Widget _buildDocPreview(String label, String url) {
    return GestureDetector(
      onTap: () {
        showDialog(
          context: context,
          builder: (context) => Dialog(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppBar(
                  title: Text(label),
                  leading: IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
                Image.network(SupabaseConfig.proxyImageUrl(url)),
              ],
            ),
          ),
        );
      },
      child: Column(
        children: [
          Container(
            height: 100,
            width: 140,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8),
              image: DecorationImage(
                image: NetworkImage(SupabaseConfig.proxyImageUrl(url)),
                fit: BoxFit.cover,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}
