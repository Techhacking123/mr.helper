import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../supabase_config.dart';
import '../auth/session_manager.dart';
import 'order_detail.dart';
import '../services/otp_verification_service.dart';

class ProviderRequestsPage extends StatefulWidget {
  const ProviderRequestsPage({super.key});

  @override
  State<ProviderRequestsPage> createState() => _ProviderRequestsPageState();
}

class _ProviderRequestsPageState extends State<ProviderRequestsPage>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  List<Map<String, dynamic>> _allOrders = []; // Merged list
  Map<String, String> _myOffersStatus = {};
  bool _isLoading = true;

  late RealtimeChannel _channel;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _fetchRequests();
    _setupRealtime();

    // Animation setup
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );
    WidgetsBinding.instance.addObserver(this);
    _animationController.forward();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint('App resumed - refreshing requests page...');
      _fetchRequests();
    }
  }

  Future<void> _setupRealtime() async {
    final userId = await SessionManager.getUserId();

    var channel = SupabaseConfig.supabase.channel('public:orders:requests');

    // Listen for Order changes
    channel = channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'orders',
      callback: (payload) {
        _fetchRequests();
      },
    );

    // Listen for Offer changes
    channel = channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'order_offers',
      callback: (payload) {
        _fetchRequests();
      },
    );

    // Listen for User Subscription changes
    if (userId != null) {
      channel = channel.onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'users',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'id',
          value: userId,
        ),
        callback: (payload) {
          debugPrint(
            'User profile updated (likely subscription), refreshing...',
          );
          _fetchRequests();
        },
      );
    }

    _channel = channel.subscribe();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SupabaseConfig.supabase.removeChannel(_channel);
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _fetchRequests() async {
    try {
      final userId = await SessionManager.getUserId();
      if (userId == null) return;

      // Check subscription status FIRST
      final providerData = await SupabaseConfig.supabase
          .from('users')
          .select(
            'service_id, location, subscription_status, subscription_end_date, is_blocked, red_stars',
          )
          .eq('id', userId)
          .single();

      // Check if provider is blocked (3+ red stars)
      final isBlocked = providerData['is_blocked'] == true ||
          ((providerData['red_stars'] as int?) ?? 0) >= 3;

      if (isBlocked) {
        if (mounted) {
          setState(() {
            _allOrders = [];
            _myOffersStatus = {};
            _isLoading = false;
          });
        }
        return; // Blocked provider cannot receive orders
      }

      // Check subscription status
      final subscriptionStatus = providerData['subscription_status'];
      final endDateStr = providerData['subscription_end_date'];

      bool hasActiveSubscription = false;
      if (subscriptionStatus == 'active' && endDateStr != null) {
        final endDate = DateTime.parse(endDateStr);
        hasActiveSubscription = endDate.isAfter(DateTime.now());
      }

      // Provider can receive orders only if subscription is active
      if (!hasActiveSubscription) {
        if (mounted) {
          setState(() {
            _allOrders = [];
            _myOffersStatus = {};
            _isLoading = false;
          });
        }
        return; // Don't fetch orders
      }

      // 1. Get Provider Details (already fetched above)

      final serviceId = providerData['service_id'];
      final String providerLocation = (providerData['location'] ?? '')
          .toString()
          .trim()
          .toLowerCase();

      // Get provider's registration date
      final providerCreatedAt = await SupabaseConfig.supabase
          .from('users')
          .select('created_at')
          .eq('id', userId)
          .single();

      DateTime? providerRegistrationDate;
      if (providerCreatedAt['created_at'] != null) {
        final regDateTime = DateTime.parse(providerCreatedAt['created_at']);
        // Use start of registration day to include all orders from that day onwards
        providerRegistrationDate = DateTime(
          regDateTime.year,
          regDateTime.month,
          regDateTime.day,
        );
      }

      debugPrint(
        'Provider registered on: $providerRegistrationDate (start of day)',
      );

      // 2. Fetch 'request_open' orders CREATED AFTER provider registration
      var ordersQuery = SupabaseConfig.supabase
          .from('orders')
          .select('*, locations(name), buyer:users!buyer_id(full_name)')
          .eq('status', 'request_open')
          .eq('service_id', serviceId);

      // Filter by registration date - show orders from registration day onwards
      if (providerRegistrationDate != null) {
        ordersQuery = ordersQuery.gte(
          'created_at',
          providerRegistrationDate.toIso8601String(),
        );
        debugPrint(
          'Filtering orders created on or after: ${providerRegistrationDate.toIso8601String()}',
        );
      }

      final allServiceRequests = await ordersQuery;

      // Filter by Location
      final newRequests = (allServiceRequests as List).where((req) {
        final orderLoc = (req['locations']?['name'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
        return orderLoc == providerLocation;
      }).toList();

      debugPrint(
        'Found ${newRequests.length} orders after filtering by registration date and location',
      );

      // 3. Fetch offers made by me
      final myOffers = await SupabaseConfig.supabase
          .from('order_offers')
          .select('order_id, status')
          .eq('provider_id', userId);

      final Map<String, String> offerStatusMap = {};
      final Set<String> ignoredOrderIds = {};
      final Set<String> interactedOrderIds = {};

      for (var o in myOffers) {
        final oid = o['order_id'].toString();
        final status = o['status'] as String;
        offerStatusMap[oid] = status;

        if (status == 'ignored') {
          ignoredOrderIds.add(oid);
        } else {
          interactedOrderIds.add(oid);
        }
      }

      // 4. Fetch orders I have interacted with (excluding ignored)
      List<Map<String, dynamic>> myInteractedOrders = [];
      if (interactedOrderIds.isNotEmpty) {
        final response = await SupabaseConfig.supabase
            .from('orders')
            .select('*, locations(name), buyer:users!buyer_id(full_name)')
            .filter('id', 'in', interactedOrderIds.toList());
        myInteractedOrders = List<Map<String, dynamic>>.from(response);
      }

      // 5. Merge (Exclude Ignored from New Requests)
      final Map<String, Map<String, dynamic>> merged = {};

      // Add new requests ONLY if not ignored
      for (var r in newRequests) {
        final oid = r['id'].toString();
        if (!ignoredOrderIds.contains(oid)) {
          merged[oid] = r;
        }
      }

      // Add interacted orders (these are already filtered to not be ignored)
      for (var r in myInteractedOrders) {
        final status = r['status'];
        final isMine = r['provider_id'] == userId;
        // If it's officially my order and past negotiation, it belongs in "My Work", not here
        if (isMine && ['accepted', 'confirmed', 'in_progress', 'working', 'verified', 'completed'].contains(status)) {
           continue; 
        }
        merged[r['id'].toString()] = r;
      }

      final finalList = merged.values.toList();
      finalList.sort((a, b) => b['created_at'].compareTo(a['created_at']));

      // 6. Fetch Direct Negotiations
      // Direct orders are created with status 'pending' when a user hires a specific provider
      // They may become 'negotiating' if the provider counters
      // They become 'accepted' when price is agreed upon
      // Keep showing them here until they move to 'in_progress' or other statuses
      final negotiationsResponse = await SupabaseConfig.supabase
          .from('orders')
          .select('*, locations(name), buyer:users!buyer_id(full_name)')
          .eq('provider_id', userId)
          .inFilter('status', ['pending', 'negotiating'])
          .order('created_at', ascending: false);

      final negotiations = List<Map<String, dynamic>>.from(
        negotiationsResponse,
      );

      // Merge marketplace requests and direct orders into one list
      final allOrders = [...finalList, ...negotiations];
      // Sort by created_at descending
      allOrders.sort((a, b) => b['created_at'].compareTo(a['created_at']));

      if (mounted) {
        setState(() {
          _allOrders = allOrders;
          _myOffersStatus = offerStatusMap;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching provider requests: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleNegotiation(
    String orderId,
    String action, {
    double? amount,
    String? buyerId,
  }) async {
    try {
      if (action == 'accept') {
        final userId = await SessionManager.getUserId(); // Fetch User ID
        await SupabaseConfig.supabase
            .from('orders')
            .update({
              'status': 'accepted',
              'price': amount,
              'provider_id': userId, // Assign provider!
            })
            .eq('id', orderId);

        // FIX: Insert an 'accepted' offer so this order persists in the Requests list
        // just like marketplace orders do (Consistency).
        await SupabaseConfig.supabase.from('order_offers').insert({
          'order_id': orderId,
          'provider_id': userId,
          'price': amount ?? 0,
          'status': 'accepted',
        });

        // Set 24-hour OTP verification deadline for the provider
        await OtpVerificationService.setOtpDeadline(orderId);

        _notifyUser(
          buyerId,
          orderId,
          'Your offer of ₹$amount has been ACCEPTED by the provider!',
        );
      } else if (action == 'reject') {
        await SupabaseConfig.supabase
            .from('orders')
            .update({'status': 'rejected'})
            .eq('id', orderId);
        _notifyUser(
          buyerId,
          orderId,
          'Your request was rejected by the provider.',
        );
      } else if (action == 'counter') {
        if (amount == null) return;
        await SupabaseConfig.supabase
            .from('orders')
            .update({'provider_price': amount, 'last_offer_by': 'provider'})
            .eq('id', orderId);
        _notifyUser(
          buyerId,
          orderId,
          'Provider sent a counter-offer: ₹$amount',
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              action == 'accept'
                  ? 'Order Accepted! Moved to "My Work"'
                  : 'Action: $action completed successfully!',
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
        _fetchRequests();
      }
    } catch (e) {
      debugPrint("Error handling negotiation: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _notifyUser(String? userId, String orderId, String msg) async {
    if (userId == null) return;

    // Insert into notifications table - FCM will be sent automatically by database trigger
    await SupabaseConfig.supabase.from('notifications').insert({
      'user_id': userId,
      'order_id': orderId,
      'title': 'Order Update',
      'message': msg,
      'is_read': false,
    });
  }

  Future<double?> _getMyQuotedPrice(String orderId) async {
    try {
      final userId = await SessionManager.getUserId();
      if (userId == null) return null;

      final offers = await SupabaseConfig.supabase
          .from('order_offers')
          .select('price')
          .eq('order_id', orderId)
          .eq('provider_id', userId)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (offers != null) {
        return double.tryParse(offers['price'].toString());
      }
      return null;
    } catch (e) {
      debugPrint('Error fetching quoted price: $e');
      return null;
    }
  }

  Future<void> _showCounterDialog(Map<String, dynamic> order) async {
    final priceController = TextEditingController();
    final success = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Colors.deepPurple.shade50, Colors.white],
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.deepPurple.shade100,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.local_offer,
                  color: Colors.deepPurple.shade700,
                  size: 32,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Counter Offer',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Enter your counter-offer amount',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: priceController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  prefixText: '₹ ',
                  labelText: 'Amount',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: Colors.deepPurple.shade400,
                      width: 2,
                    ),
                  ),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: () {
                        if (priceController.text.isNotEmpty) {
                          Navigator.pop(ctx, true);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepPurple,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        'Send Offer',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (success == true) {
      final amt = double.tryParse(priceController.text.trim());
      if (amt != null) {
        _handleNegotiation(
          order['id'],
          'counter',
          amount: amt,
          buyerId: order['buyer_id'],
        );
      }
    }
  }

  Future<void> _sendQuote(Map<String, dynamic> order) async {
    final priceController = TextEditingController();
    final orderId = order['id'];
    final originalPrice = order['user_price'] ?? 0;

    final success = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Colors.green.shade50, Colors.white],
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green.shade100,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.check_circle_outline,
                  color: Colors.green.shade700,
                  size: 32,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Send Quotation',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Enter your offer price for this job',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: Colors.orange.shade700,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Customer Budget:',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade700,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      '₹$originalPrice',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: Colors.orange.shade700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: priceController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  prefixText: '₹ ',
                  labelText: 'Your Quote',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: Colors.green.shade400,
                      width: 2,
                    ),
                  ),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: () {
                        if (priceController.text.isNotEmpty) {
                          Navigator.pop(ctx, true);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        'Send Offer',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (success != true) return;

    try {
      final userId = await SessionManager.getUserId();
      final price = double.parse(priceController.text.trim());

      // 1. Insert Offer
      await SupabaseConfig.supabase.from('order_offers').insert({
        'order_id': orderId,
        'provider_id': userId,
        'price': price,
        'status': 'pending',
      });

      // 2. Notify User
      final order = await SupabaseConfig.supabase
          .from('orders')
          .select('buyer_id')
          .eq('id', orderId)
          .single();
      final buyerId = order['buyer_id'];

      // Insert notification - FCM will be sent automatically by database trigger
      await SupabaseConfig.supabase.from('notifications').insert({
        'user_id': buyerId,
        'order_id': orderId,
        'title': 'New Offer Received!',
        'message': 'A provider has sent you an offer of ₹$price!',
        'is_read': false,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: const [
                    Icon(Icons.check_circle, color: Colors.white),
                    SizedBox(width: 12),
                    Text(
                      'Offer Sent Successfully!',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Original: ₹$originalPrice → Your Quote: ₹$price',
                  style: const TextStyle(fontSize: 13),
                ),
              ],
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
        _fetchRequests(); // Refresh
      }
    } catch (e) {
      debugPrint('Error sending offer: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send offer'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _showFullOrderDetails(Map<String, dynamic> order) {
    final buyerName = order['buyer']?['full_name'] ?? 'Unknown User';
    final locationName = order['locations']?['name'] ?? 'Unknown Location';
    final addressGps = order['address_gps'] ?? 'No specific address provided';
    final description = order['description'] ?? 'No description provided';
    final budget = order['user_price'] ?? '?';
    final createdAt = order['created_at'] != null
        ? order['created_at'].toString().substring(0, 16).replaceAll('T', ' ')
        : 'Unknown Date';

    // Destination location fields
    final destinationAddress = order['destination_address'];
    final hasDestination =
        destinationAddress != null && destinationAddress.toString().isNotEmpty;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: Column(
          children: [
            // Drag Handle
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Header with Gradient
            Container(
              margin: const EdgeInsets.all(20),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.deepPurple.shade400,
                    Colors.deepPurple.shade600,
                  ],
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.deepPurple.withOpacity(0.3),
                    blurRadius: 15,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Order Details',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '₹$budget',
                          style: TextStyle(
                            color: Colors.deepPurple.shade700,
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Scrollable Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    // Customer Info Card
                    _buildModernDetailCard(
                      icon: Icons.person_outline,
                      title: 'Customer Name',
                      value: buyerName,
                      gradient: LinearGradient(
                        colors: [Colors.blue.shade400, Colors.blue.shade600],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Location Card
                    _buildModernDetailCard(
                      icon: Icons.location_city_outlined,
                      title: 'Location',
                      value: locationName,
                      gradient: LinearGradient(
                        colors: [
                          Colors.orange.shade400,
                          Colors.orange.shade600,
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Address Card
                    _buildModernDetailCard(
                      icon: Icons.location_on_outlined,
                      title: 'Address',
                      value: addressGps,
                      gradient: LinearGradient(
                        colors: [Colors.red.shade400, Colors.red.shade600],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Destination Card (only show if destination exists)
                    if (hasDestination) ...[
                      _buildModernDetailCard(
                        icon: Icons.flag_outlined,
                        title: 'Destination',
                        value: destinationAddress,
                        gradient: LinearGradient(
                          colors: [Colors.teal.shade400, Colors.teal.shade600],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Date Card
                    _buildModernDetailCard(
                      icon: Icons.calendar_today_outlined,
                      title: 'Posted On',
                      value: createdAt,
                      gradient: LinearGradient(
                        colors: [
                          Colors.purple.shade400,
                          Colors.purple.shade600,
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Privacy Note
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.blue.shade50, Colors.cyan.shade50],
                        ),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.blue.shade200,
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.privacy_tip_outlined,
                            color: Colors.blue.shade700,
                            size: 24,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Contact details will be shared after customer accepts your quote',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.blue.shade900,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Order Images Section
                    if (order['images'] != null &&
                        (order['images'] as List).isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.grey.shade200),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.03),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: [
                                            Colors.purple.shade400,
                                            Colors.purple.shade600,
                                          ],
                                        ),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: const Icon(
                                        Icons.photo_library,
                                        color: Colors.white,
                                        size: 20,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Text(
                                      'Order Images',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 18,
                                        color: Colors.grey.shade800,
                                      ),
                                    ),
                                  ],
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.purple.shade50,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    '${(order['images'] as List).length}',
                                    style: TextStyle(
                                      color: Colors.purple.shade700,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 2,
                                    crossAxisSpacing: 12,
                                    mainAxisSpacing: 12,
                                    childAspectRatio: 1,
                                  ),
                              itemCount: (order['images'] as List).length,
                              itemBuilder: (context, imgIndex) {
                                final imageUrl =
                                    (order['images'] as List)[imgIndex];
                                return GestureDetector(
                                  onTap: () {
                                    showDialog(
                                      context: context,
                                      builder: (ctx) => Dialog(
                                        backgroundColor: Colors.black,
                                        child: Stack(
                                          children: [
                                            Center(
                                              child: InteractiveViewer(
                                                child: Image.network(
                                                  SupabaseConfig.proxyImageUrl(
                                                    imageUrl,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            Positioned(
                                              top: 16,
                                              right: 16,
                                              child: IconButton(
                                                icon: const Icon(
                                                  Icons.close,
                                                  color: Colors.white,
                                                  size: 30,
                                                ),
                                                onPressed: () =>
                                                    Navigator.pop(ctx),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: Image.network(
                                      SupabaseConfig.proxyImageUrl(imageUrl),
                                      fit: BoxFit.cover,
                                      errorBuilder:
                                          (context, error, stackTrace) {
                                            return Container(
                                              decoration: BoxDecoration(
                                                color: Colors.grey.shade200,
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                              child: Icon(
                                                Icons.broken_image,
                                                size: 40,
                                                color: Colors.grey.shade600,
                                              ),
                                            );
                                          },
                                      loadingBuilder: (context, child, loadingProgress) {
                                        if (loadingProgress == null) {
                                          return child;
                                        }
                                        return Container(
                                          decoration: BoxDecoration(
                                            color: Colors.grey.shade100,
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                          child: Center(
                                            child: CircularProgressIndicator(
                                              strokeWidth: 3,
                                              value:
                                                  loadingProgress
                                                          .expectedTotalBytes !=
                                                      null
                                                  ? loadingProgress
                                                            .cumulativeBytesLoaded /
                                                        loadingProgress
                                                            .expectedTotalBytes!
                                                  : null,
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Description Card
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.description_outlined,
                                color: Colors.grey.shade700,
                                size: 22,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Requirements',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                  color: Colors.grey.shade800,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            description,
                            style: TextStyle(
                              fontSize: 15,
                              height: 1.5,
                              color: Colors.grey.shade800,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),

            // Action Buttons
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, -5),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        Navigator.pop(ctx);
                        try {
                          final userId = await SessionManager.getUserId();
                          await SupabaseConfig.supabase
                              .from('order_offers')
                              .insert({
                                'order_id': order['id'],
                                'provider_id': userId,
                                'price': 0,
                                'status': 'ignored',
                              });
                          if (mounted) {
                            setState(() {
                              _myOffersStatus[order['id'].toString()] =
                                  'ignored';
                            });
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: const Text('Request Ignored'),
                                backgroundColor: Colors.grey.shade700,
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            );
                          }
                        } catch (e) {
                          debugPrint('Error ignoring: $e');
                        }
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: BorderSide(color: Colors.red.shade300, width: 2),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Ignore',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _sendQuote(order);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 2,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.check_circle, size: 20),
                          SizedBox(width: 8),
                          Text(
                            'ACCEPT & QUOTE',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModernDetailCard({
    required IconData icon,
    required String title,
    required String value,
    required Gradient gradient,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: gradient,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNegotiationCard(Map<String, dynamic> req, int index) {
    final buyerName = req['buyer']?['full_name'] ?? 'User';
    final lastBy = req['last_offer_by'] ?? 'user';
    final bool isProviderTurn = lastBy == 'user';

    final activePrice = lastBy == 'user'
        ? (req['user_price'] ?? 0)
        : (req['provider_price'] ?? 0);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.purple.shade50, Colors.pink.shade50],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.purple.withOpacity(0.15),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: Colors.purple.shade100,
                        child: Icon(
                          Icons.person,
                          color: Colors.purple.shade700,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              buyerName,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              req['locations']?['name'] ??
                                  req['address_gps'] ??
                                  'Unknown Location',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.purple.shade600,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    "Negotiating",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            Text(
              req['description'] ?? "No Description",
              style: TextStyle(
                color: Colors.grey.shade700,
                fontSize: 14,
                height: 1.4,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),

            const SizedBox(height: 16),

            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.purple.shade100, width: 1.5),
              ),
              child: Column(
                children: [
                  Text(
                    isProviderTurn ? "User Offered:" : "You Requested:",
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "₹$activePrice",
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: isProviderTurn
                          ? Colors.green.shade700
                          : Colors.orange.shade700,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            if (isProviderTurn) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.notification_important,
                      color: Colors.red.shade700,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        "Action Required: Respond to user offer",
                        style: TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _handleNegotiation(
                        req['id'],
                        'reject',
                        buyerId: req['buyer_id'],
                      ),
                      icon: const Icon(Icons.close, size: 18),
                      label: const Text("Reject"),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _showCounterDialog(req),
                      icon: const Icon(Icons.swap_horiz, size: 18),
                      label: const Text("Counter"),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.orange,
                        side: const BorderSide(color: Colors.orange),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _handleNegotiation(
                        req['id'],
                        'accept',
                        amount: double.tryParse(activePrice.toString()),
                        buyerId: req['buyer_id'],
                      ),
                      icon: const Icon(Icons.check, size: 18),
                      label: const Text("Accept"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        elevation: 0,
                      ),
                    ),
                  ),
                ],
              ),
            ] else ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(
                          Colors.orange.shade700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      "Waiting for user response...",
                      style: TextStyle(
                        fontStyle: FontStyle.italic,
                        color: Colors.orange.shade700,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRequestCard(Map<String, dynamic> req, int index) {
    final locName =
        req['locations']?['name'] ?? req['address_gps'] ?? 'Unknown Location';
    final myStatus = _myOffersStatus[req['id'].toString()];

    // Destination location
    final destinationAddress = req['destination_address'];
    final hasDestination =
        destinationAddress != null && destinationAddress.toString().isNotEmpty;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.green.shade400,
                              Colors.green.shade600,
                            ],
                          ),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.attach_money,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Flexible(
                        child: FutureBuilder<double?>(
                          future: _getMyQuotedPrice(req['id']),
                          builder: (context, snapshot) {
                            final originalPrice = req['user_price'] ?? 0;
                            final quotedPrice = snapshot.data;
                            final displayPrice = quotedPrice ?? originalPrice;
                            final isQuoted = quotedPrice != null;

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '₹$displayPrice',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 22,
                                    color: isQuoted
                                        ? Colors.orange
                                        : Colors.green,
                                  ),
                                ),
                                if (isQuoted) ...[
                                  Text(
                                    'Your Quote',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.orange.shade700,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Original: ₹$originalPrice',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.grey.shade600,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ],
                              ],
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.location_on,
                        size: 14,
                        color: Colors.blue.shade700,
                      ),
                      const SizedBox(width: 4),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 140),
                        child: Text(
                          locName,
                          style: TextStyle(
                            color: Colors.blue.shade900,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.description_outlined,
                        size: 16,
                        color: Colors.grey.shade600,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Description:',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    req['description'] ?? "No description",
                    style: const TextStyle(fontSize: 14, height: 1.4),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),

            // Destination Section (only show if destination exists)
            if (hasDestination) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.teal.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.teal.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.flag_outlined,
                          size: 16,
                          color: Colors.teal.shade700,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Destination:',
                          style: TextStyle(
                            color: Colors.teal.shade700,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      destinationAddress,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.4,
                        color: Colors.teal.shade900,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],

            // Order Images Section
            if (req['images'] != null &&
                (req['images'] as List).isNotEmpty) ...[
              const SizedBox(height: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.photo_library,
                        size: 16,
                        color: Colors.grey.shade600,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Order Images (${(req['images'] as List).length})',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 80,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: (req['images'] as List).length,
                      itemBuilder: (context, imgIndex) {
                        final imageUrl = (req['images'] as List)[imgIndex];
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: GestureDetector(
                            onTap: () {
                              showDialog(
                                context: context,
                                builder: (ctx) => Dialog(
                                  backgroundColor: Colors.black,
                                  child: Stack(
                                    children: [
                                      Center(
                                        child: InteractiveViewer(
                                          child: Image.network(
                                            SupabaseConfig.proxyImageUrl(
                                              imageUrl,
                                            ),
                                          ),
                                        ),
                                      ),
                                      Positioned(
                                        top: 16,
                                        right: 16,
                                        child: IconButton(
                                          icon: const Icon(
                                            Icons.close,
                                            color: Colors.white,
                                            size: 30,
                                          ),
                                          onPressed: () => Navigator.pop(ctx),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(
                                SupabaseConfig.proxyImageUrl(imageUrl),
                                width: 80,
                                height: 80,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  return Container(
                                    width: 80,
                                    height: 80,
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade300,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Icon(
                                      Icons.broken_image,
                                      color: Colors.grey.shade600,
                                    ),
                                  );
                                },
                                loadingBuilder:
                                    (context, child, loadingProgress) {
                                      if (loadingProgress == null) return child;
                                      return Container(
                                        width: 80,
                                        height: 80,
                                        decoration: BoxDecoration(
                                          color: Colors.grey.shade200,
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: Center(
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            value:
                                                loadingProgress
                                                        .expectedTotalBytes !=
                                                    null
                                                ? loadingProgress
                                                          .cumulativeBytesLoaded /
                                                      loadingProgress
                                                          .expectedTotalBytes!
                                                : null,
                                          ),
                                        ),
                                      );
                                    },
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 16),
            Divider(color: Colors.grey.shade200, height: 1),
            const SizedBox(height: 16),

            if (myStatus == 'pending')
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.hourglass_bottom,
                      color: Colors.orange.shade700,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'Waiting for approval',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange,
                      ),
                    ),
                  ],
                ),
              )
            else if (myStatus == 'accepted')
              GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        OrderDetailPage(order: req, isProvider: true),
                  ),
                ),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.green.shade400, Colors.green.shade600],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.check_circle,
                        color: Colors.white,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Flexible(
                        child: Text(
                          '${req['buyer']?['full_name'] ?? 'User'} approved your request',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.arrow_forward,
                        color: Colors.white,
                        size: 18,
                      ),
                    ],
                  ),
                ),
              )
            else if (myStatus == 'rejected')
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.cancel, color: Colors.red.shade700, size: 20),
                    const SizedBox(width: 12),
                    const Text(
                      'Your request was rejected',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.red,
                      ),
                    ),
                  ],
                ),
              )
            else if (myStatus == 'ignored')
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.block, color: Colors.grey, size: 20),
                    SizedBox(width: 12),
                    Text(
                      'You have ignored this order',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              )
            else
              Column(
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _showFullOrderDetails(req),
                    icon: const Icon(Icons.info_outline, size: 18),
                    label: const Text('View Full Details'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.deepPurple,
                      side: BorderSide(color: Colors.deepPurple.shade200),
                      padding: const EdgeInsets.symmetric(
                        vertical: 12,
                        horizontal: 24,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () async {
                            try {
                              final userId = await SessionManager.getUserId();
                              await SupabaseConfig.supabase
                                  .from('order_offers')
                                  .insert({
                                    'order_id': req['id'],
                                    'provider_id': userId,
                                    'price': 0,
                                    'status': 'ignored',
                                  });
                              if (mounted) {
                                setState(() {
                                  _myOffersStatus[req['id'].toString()] =
                                      'ignored';
                                });
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: const Text('Request Ignored'),
                                    backgroundColor: Colors.grey.shade700,
                                    behavior: SnackBarBehavior.floating,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                );
                              }
                            } catch (e) {
                              debugPrint('Error ignoring: $e');
                            }
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                            side: const BorderSide(color: Colors.red),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'Ignore',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton(
                          onPressed: () => _sendQuote(req),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 2,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: const [
                              Icon(Icons.check_circle, size: 18),
                              SizedBox(width: 8),
                              Text(
                                'ACCEPT & QUOTE',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // Custom App Bar
            Container(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.deepPurple.shade400,
                          Colors.deepPurple.shade600,
                        ],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.work_outline,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Job Requests',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'All marketplace and direct orders',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Content
            Expanded(
              child: _isLoading
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation(
                              Colors.deepPurple.shade400,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Loading requests...',
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    )
                  : _buildAllOrdersList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAllOrdersList() {
    if (_allOrders.isEmpty) {
      return RefreshIndicator(
        onRefresh: _fetchRequests,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.6,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(40),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.inbox_outlined,
                      size: 80,
                      color: Colors.grey.shade300,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      "No orders available",
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "New orders will appear here",
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return FadeTransition(
      opacity: _fadeAnimation,
      child: RefreshIndicator(
        onRefresh: _fetchRequests,
        color: Colors.deepPurple,
        child: ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: _allOrders.length,
          itemBuilder: (context, index) {
            final order = _allOrders[index];
            final status = order['status'] ?? '';
            final providerId = order['provider_id'];

            // Show accepted direct orders as request cards
            // Show pending/negotiating direct orders as negotiation cards
            // Show marketplace orders as request cards
            if (providerId != null &&
                (status == 'pending' || status == 'negotiating')) {
              // Direct order in negotiation
              return _buildNegotiationCard(order, index);
            } else {
              // Marketplace order or accepted direct order
              return _buildRequestCard(order, index);
            }
          },
        ),
      ),
    );
  }
}
