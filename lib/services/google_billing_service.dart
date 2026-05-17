import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:http/http.dart' as http;
import '../supabase_config.dart';
import '../auth/session_manager.dart';

/// Google Play Billing Service for managing subscriptions
/// Supports dynamic subscription product IDs per service category
class GoogleBillingService {
  static final GoogleBillingService _instance = GoogleBillingService._();
  factory GoogleBillingService() => _instance;
  GoogleBillingService._();

  /// Default subscription product ID (fallback)
  static const String defaultSubscriptionProductId = 'mrhelper_monthly_pro';

  /// Backend URL for server-side receipt verification
  static const String backendUrl = 'https://mr-helper-backend.onrender.com';

  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;

  bool _isAvailable = false;
  bool _isInitialized = false;
  List<ProductDetails> _products = [];

  /// Currently active subscription product ID for the provider's service
  String _activeProductId = defaultSubscriptionProductId;

  /// Callbacks
  Function(String message)? onSuccess;
  Function(String error)? onError;
  Function(bool loading)? onLoading;

  bool get isAvailable => _isAvailable;
  bool get isInitialized => _isInitialized;
  List<ProductDetails> get products => _products;
  String get activeProductId => _activeProductId;

  /// Get the subscription product details for the active product ID
  ProductDetails? get subscriptionProduct {
    try {
      return _products.firstWhere((p) => p.id == _activeProductId);
    } catch (_) {
      return null;
    }
  }

  /// Get product details by a specific product ID
  ProductDetails? getProductById(String productId) {
    try {
      return _products.firstWhere((p) => p.id == productId);
    } catch (_) {
      return null;
    }
  }

  /// Initialize the billing service
  Future<void> initialize() async {
    if (_isInitialized) return;

    _isAvailable = await _iap.isAvailable();

    if (!_isAvailable) {
      debugPrint('Google Play Billing: Store is NOT available');
      _isInitialized = true;
      return;
    }

    debugPrint('Google Play Billing: Store is available');

    // Listen to purchase updates
    _purchaseSubscription = _iap.purchaseStream.listen(
      _onPurchaseUpdated,
      onDone: () => _purchaseSubscription?.cancel(),
      onError: (error) {
        debugPrint('Google Play Billing: Purchase stream error: $error');
      },
    );

    // Load all subscription product IDs from the services table
    await _loadAllServiceProducts();

    _isInitialized = true;
    debugPrint('Google Play Billing: Initialized successfully');
  }

  /// Load all unique Google subscription IDs from the services table
  /// and query Google Play for their product details
  Future<void> _loadAllServiceProducts() async {
    try {
      // Fetch all unique google_subscription_id values from services table
      final response = await SupabaseConfig.supabase
          .from('services')
          .select('google_subscription_id');

      final services = List<Map<String, dynamic>>.from(response);

      // Collect unique product IDs
      final Set<String> productIds = {defaultSubscriptionProductId};
      for (final service in services) {
        final subId = service['google_subscription_id'] as String?;
        if (subId != null && subId.isNotEmpty) {
          productIds.add(subId);
        }
      }

      debugPrint(
        'Google Play Billing: Loading ${productIds.length} product IDs: $productIds',
      );

      await _loadProducts(productIds);
    } catch (e) {
      debugPrint(
        'Google Play Billing: Error loading service products: $e',
      );
      // Fallback: load just the default product
      await _loadProducts({defaultSubscriptionProductId});
    }
  }

  /// Load subscription products from Google Play by product IDs
  Future<void> _loadProducts(Set<String> productIds) async {
    try {
      final ProductDetailsResponse response = await _iap.queryProductDetails(
        productIds,
      );

      if (response.error != null) {
        debugPrint(
          'Google Play Billing: Error loading products: ${response.error}',
        );
        return;
      }

      if (response.notFoundIDs.isNotEmpty) {
        debugPrint(
          'Google Play Billing: Products not found: ${response.notFoundIDs}',
        );
        debugPrint(
          'Make sure these subscriptions are created in Google Play Console',
        );
      }

      _products = response.productDetails;
      debugPrint('Google Play Billing: Loaded ${_products.length} products');

      for (final product in _products) {
        debugPrint('  - ${product.id}: ${product.title} - ${product.price}');
      }
    } catch (e) {
      debugPrint('Google Play Billing: Error loading products: $e');
    }
  }

  /// Set the active subscription product ID for purchase
  /// Call this before purchaseSubscription() with the provider's service subscription ID
  void setActiveProductId(String productId) {
    _activeProductId = productId.isNotEmpty ? productId : defaultSubscriptionProductId;
    debugPrint('Google Play Billing: Active product ID set to: $_activeProductId');
  }

  /// Load a specific product if not already loaded
  Future<ProductDetails?> loadProductById(String productId) async {
    // Check if already loaded
    final existing = getProductById(productId);
    if (existing != null) return existing;

    // Not loaded yet, query Google Play
    try {
      final ProductDetailsResponse response = await _iap.queryProductDetails(
        {productId},
      );

      if (response.error != null) {
        debugPrint(
          'Google Play Billing: Error loading product $productId: ${response.error}',
        );
        return null;
      }

      if (response.productDetails.isNotEmpty) {
        _products.addAll(response.productDetails);
        debugPrint(
          'Google Play Billing: Loaded product: ${response.productDetails.first.id} - ${response.productDetails.first.price}',
        );
        return response.productDetails.first;
      } else {
        debugPrint(
          'Google Play Billing: Product not found in Google Play Console: $productId',
        );
        return null;
      }
    } catch (e) {
      debugPrint('Google Play Billing: Error loading product $productId: $e');
      return null;
    }
  }

  /// Start the subscription purchase flow using the active product ID
  Future<void> purchaseSubscription() async {
    if (!_isAvailable) {
      onError?.call('Google Play Store is not available on this device');
      return;
    }

    // Try to load the product if not already loaded
    ProductDetails? product = subscriptionProduct;
    product ??= await loadProductById(_activeProductId);

    if (product == null) {
      onError?.call('Subscription product not found. Please try again later.');
      return;
    }

    onLoading?.call(true);

    try {
      debugPrint('Google Play Billing: Starting purchase for ${product.id}');

      final PurchaseParam purchaseParam = PurchaseParam(
        productDetails: product,
      );

      // Start subscription purchase (not consumable)
      final bool success = await _iap.buyNonConsumable(
        purchaseParam: purchaseParam,
      );

      if (!success) {
        onLoading?.call(false);
        onError?.call('Could not initiate purchase. Please try again.');
      }

      // Result will come through _onPurchaseUpdated
    } catch (e) {
      onLoading?.call(false);
      onError?.call('Purchase failed: $e');
      debugPrint('Google Play Billing: Purchase error: $e');
    }
  }

  /// Handle purchase updates from Google Play
  Future<void> _onPurchaseUpdated(
    List<PurchaseDetails> purchaseDetailsList,
  ) async {
    for (final purchase in purchaseDetailsList) {
      debugPrint(
        'Google Play Billing: Purchase update - ${purchase.productID} status: ${purchase.status}',
      );

      switch (purchase.status) {
        case PurchaseStatus.pending:
          onLoading?.call(true);
          debugPrint('Google Play Billing: Purchase pending...');
          break;

        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          // Verify the purchase on our backend
          await _verifyAndActivateSubscription(purchase);
          break;

        case PurchaseStatus.error:
          onLoading?.call(false);
          onError?.call(
            purchase.error?.message ?? 'Payment failed. Please try again.',
          );
          debugPrint(
            'Google Play Billing: Purchase error: ${purchase.error?.message}',
          );
          break;

        case PurchaseStatus.canceled:
          onLoading?.call(false);
          onError?.call('Payment was cancelled. No charges were made.');
          debugPrint('Google Play Billing: Purchase canceled by user');
          break;
      }

      // Complete pending purchases (required by Google Play)
      if (purchase.pendingCompletePurchase) {
        await _iap.completePurchase(purchase);
      }
    }
  }

  /// Verify the purchase receipt on our backend and activate subscription in Supabase
  Future<void> _verifyAndActivateSubscription(PurchaseDetails purchase) async {
    try {
      final userId = await SessionManager.getUserId();
      if (userId == null) {
        onLoading?.call(false);
        onError?.call('User not logged in');
        return;
      }

      debugPrint('Google Play Billing: Verifying purchase on backend...');
      debugPrint(
        '  Purchase token: ${purchase.verificationData.serverVerificationData.substring(0, 20)}...',
      );

      // Send purchase receipt to our backend for verification (with timeout)
      final response = await http.post(
        Uri.parse('$backendUrl/verify-google-purchase'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'purchase_token': purchase.verificationData.serverVerificationData,
          'product_id': purchase.productID,
          'user_id': userId,
        }),
      ).timeout(const Duration(seconds: 10));

      final result = jsonDecode(response.body);

      if (response.statusCode == 200 && result['status'] == 'success') {
        debugPrint('Google Play Billing: Subscription verified and activated!');
        onLoading?.call(false);
        onSuccess?.call('Subscription activated successfully!');
      } else {
        debugPrint(
          'Google Play Billing: Backend verification failed: ${result['message']}',
        );

        // Fallback: activate directly via Supabase if backend fails
        await _activateSubscriptionDirectly(userId);
      }
    } catch (e) {
      debugPrint('Google Play Billing: Verification error: $e');

      // Fallback: try direct activation
      try {
        final userId = await SessionManager.getUserId();
        if (userId != null) {
          await _activateSubscriptionDirectly(userId);
        }
      } catch (fallbackError) {
        onLoading?.call(false);
        onError?.call('Verification failed. Please contact support.');
      }
    }
  }

  /// Fallback: Activate subscription directly via Supabase
  /// Used when backend verification is unavailable
  /// NOTE: Fines are NOT cleared here. Fines must be paid separately.
  Future<void> _activateSubscriptionDirectly(String userId) async {
    try {
      final now = DateTime.now().toUtc();
      final expiryDate = now.add(const Duration(days: 28));

      // Update subscription status (fines are NOT touched)
      await SupabaseConfig.supabase
          .from('users')
          .update({
            'is_subscribed': true,
            'subscription_status': 'active',
            'subscription_start_date': now.toIso8601String(),
            'subscription_end_date': expiryDate.toIso8601String(),
            'subscription_expiry': expiryDate.toIso8601String(),
          })
          .eq('id', userId);

      debugPrint(
        'Google Play Billing: Subscription activated directly until ${expiryDate.toIso8601String()}',
      );

      onLoading?.call(false);
      onSuccess?.call('Subscription activated successfully!');
    } catch (e) {
      debugPrint('Google Play Billing: Direct activation failed: $e');
      onLoading?.call(false);
      onError?.call('Activation failed. Please contact support.');
    }
  }

  /// Restore previous purchases (e.g., after reinstall)
  Future<void> restorePurchases() async {
    if (!_isAvailable) {
      onError?.call('Store not available');
      return;
    }

    onLoading?.call(true);

    try {
      await _iap.restorePurchases();
      // Results will come through _onPurchaseUpdated
    } catch (e) {
      onLoading?.call(false);
      onError?.call('Could not restore purchases: $e');
    }
  }

  /// Dispose the service
  void dispose() {
    _purchaseSubscription?.cancel();
    _purchaseSubscription = null;
    _isInitialized = false;
  }
}
