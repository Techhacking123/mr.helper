import 'package:flutter/material.dart';
import '../supabase_config.dart';
import '../call/call_launcher.dart';
import '../auth/session_manager.dart';
import '../profile/profile_page.dart';
import '../firebase/fcm_service.dart';
import '../services/otp_verification_service.dart';

class UserOffersPage extends StatefulWidget {
  final String orderId;
  const UserOffersPage({super.key, required this.orderId});

  @override
  State<UserOffersPage> createState() => _UserOffersPageState();
}

class _UserOffersPageState extends State<UserOffersPage> {
  List<Map<String, dynamic>> _offers = [];
  bool _isLoading = true;
  bool _isOrderApproved = false;

  bool _isBuyer = false;

  @override
  void initState() {
    super.initState();
    _fetchOffers();
  }

  Future<void> _fetchOffers() async {
    try {
      // Fetch offers with provider details
      final response = await SupabaseConfig.supabase
          .from('order_offers')
          .select(
            '*, provider:users!provider_id(full_name, avatar_url, price, phone_number)',
          )
          .eq('order_id', widget.orderId)
          .order('price', ascending: true); // Show cheapest first

      // Check current order status
      final order = await SupabaseConfig.supabase
          .from('orders')
          .select('status, provider_id, buyer_id')
          .eq('id', widget.orderId)
          .single();

      final currentUserId = await SessionManager.getUserId();

      setState(() {
        _offers = List<Map<String, dynamic>>.from(response);
        _isOrderApproved = order['status'] == 'accepted';
        _isBuyer = currentUserId == order['buyer_id'];
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error fetching offers: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _approveOffer(
    String offerId,
    String providerId,
    double price,
  ) async {
    setState(() => _isLoading = true);
    try {
      // 1. Identify Rejected Providers (for notifications)
      final rejectedProviders = _offers
          .where((o) => o['provider_id'] != providerId)
          .map((o) => o['provider_id'])
          .toList();

      // 2. Update Order: Accepted, Assigned Provider, AND PRICE
      await SupabaseConfig.supabase
          .from('orders')
          .update({
            'status': 'accepted',
            'provider_id': providerId,
            'price': price, // VITAL: Copy agreed price to orders table
          })
          .eq('id', widget.orderId);

      // Set 24-hour OTP verification deadline for the provider
      await OtpVerificationService.setOtpDeadline(widget.orderId);

      // 3. Update Offer Statuses
      // Accepted Offer
      await SupabaseConfig.supabase
          .from('order_offers')
          .update({'status': 'accepted'})
          .eq('id', offerId);

      // Reject others
      await SupabaseConfig.supabase
          .from('order_offers')
          .update({'status': 'rejected'})
          .eq('order_id', widget.orderId)
          .neq('id', offerId);

      // 4. Notify Winning Provider with push notification
      await FCMService.sendPushNotificationToUser(
        userId: providerId,
        title: 'Offer Accepted!',
        message: 'CONGRATS! Your offer was accepted. Call the customer now.',
        screen: 'order_detail',
        orderId: widget.orderId,
      );

      // 5. Notify Rejected Providers with push notifications
      for (var pId in rejectedProviders) {
        await FCMService.sendPushNotificationToUser(
          userId: pId,
          title: 'Offer Not Selected',
          message: 'Your offer was not selected for this order.',
          screen: 'order_detail',
          orderId: widget.orderId,
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Offer Accepted! Redirecting to order details...'),
            duration: Duration(seconds: 2),
            backgroundColor: Colors.green,
          ),
        );
        // Navigate back to Order Detail Page
        Navigator.pop(context, true);
      }
    } catch (e) {
      debugPrint('Error approving: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Error approving offer')));
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Review Offers')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _offers.isEmpty
          ? const Center(
              child: Text('No providers have offered yet. Check back later.'),
            )
          : ListView.builder(
              itemCount: _offers.length,
              itemBuilder: (context, index) {
                final offer = _offers[index];
                final provider = offer['provider'];
                final isWinning = offer['status'] == 'accepted';
                final isRejected = offer['status'] == 'rejected';

                return Card(
                  color: isWinning
                      ? Colors.green.shade50
                      : (isRejected ? Colors.grey.shade200 : Colors.white),
                  margin: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        ListTile(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    ProfilePage(userId: offer['provider_id']),
                              ),
                            );
                          },
                          leading: CircleAvatar(
                            backgroundImage: provider['avatar_url'] != null
                                ? NetworkImage(
                                    SupabaseConfig.proxyImageUrl(
                                      provider['avatar_url'],
                                    ),
                                  )
                                : null,
                            child: provider['avatar_url'] == null
                                ? const Icon(Icons.person)
                                : null,
                          ),
                          title: Text(provider['full_name'] ?? 'Provider'),
                          subtitle: Text(
                            isWinning
                                ? "WINNER"
                                : (isRejected ? "Rejected" : "Pending Offer"),
                          ),
                          trailing: Text(
                            '₹${offer['price']}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 20,
                              color: Colors.green,
                            ),
                          ),
                        ),
                        const Divider(),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            // Call Button (Only for winner)
                            ElevatedButton.icon(
                              icon: const Icon(Icons.call),
                              label: const Text('Call'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isWinning
                                    ? Colors.green
                                    : Colors.grey,
                              ),
                              onPressed: isWinning
                                  ? () => CallLauncher.makeCall(
                                      provider['phone_number'] ?? '',
                                    )
                                  : null,
                            ),
                            // Approve/Reject Buttons (Only if no winner yet AND I am the buyer)
                            if (!_isOrderApproved &&
                                !isRejected &&
                                _isBuyer) ...[
                              TextButton.icon(
                                icon: const Icon(
                                  Icons.close,
                                  color: Colors.red,
                                ),
                                label: const Text(
                                  'Reject',
                                  style: TextStyle(color: Colors.red),
                                ),
                                onPressed: () async {
                                  try {
                                    await SupabaseConfig.supabase
                                        .from('order_offers')
                                        .update({'status': 'rejected'})
                                        .eq('id', offer['id']);

                                    // Notify Provider with push notification
                                    await FCMService.sendPushNotificationToUser(
                                      userId: offer['provider_id'],
                                      title: 'Offer Rejected',
                                      message:
                                          'Your offer was rejected by the user.',
                                      screen: 'order_detail',
                                      orderId: widget.orderId,
                                    );

                                    if (mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text('Offer Rejected'),
                                        ),
                                      );
                                      _fetchOffers();
                                    }
                                  } catch (e) {
                                    debugPrint('Error rejecting: $e');
                                  }
                                },
                              ),
                              ElevatedButton.icon(
                                icon: const Icon(Icons.check),
                                label: const Text('Approve'),
                                onPressed: () => _approveOffer(
                                  offer['id'],
                                  offer['provider_id'],
                                  (offer['price'] as num).toDouble(),
                                ),
                              ),
                            ],
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
}
