import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'dart:async';
import 'dart:math' as math;
import '../supabase_config.dart';
import '../profile/profile_page.dart';
import '../widgets/safe_network_image.dart';
import 'service_result_page.dart';
import 'location_providers_page.dart';
import '../marketplace/product_detail_page.dart';

class SearchPage extends StatefulWidget {
  final bool activateVoiceSearch;
  const SearchPage({super.key, this.activateVoiceSearch = false});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  List<Map<String, dynamic>> _searchResults = [];
  bool _isSearching = false;

  // Voice search
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isListening = false;
  bool _speechAvailable = false;

  // Rotating placeholder
  Timer? _placeholderTimer;
  int _currentPlaceholderIndex = 0;
  final List<String> _searchPlaceholders = [
    'Search services, providers, locations...',
    'Try "Plumbing"...',
    'Search for Electrician...',
    'Find Carpenter...',
    'Looking for Cleaning Services?',
    'AC Repair services...',
    'Search Painters...',
    'Appliance Repair...',
  ];

  @override
  void initState() {
    super.initState();
    _initSpeech();
    _startPlaceholderRotation();

    // Auto-focus the search field when page opens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!widget.activateVoiceSearch) {
        _searchFocusNode.requestFocus();
      }
      // Voice search will auto-start after initialization completes
    });
  }

  void _startPlaceholderRotation() {
    _placeholderTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (!mounted) return;
      setState(() {
        _currentPlaceholderIndex =
            (_currentPlaceholderIndex + 1) % _searchPlaceholders.length;
      });
    });
  }

  Future<void> _initSpeech() async {
    try {
      _speechAvailable = await _speech.initialize(
        onStatus: (status) {
          debugPrint('Speech status: $status');
          if (status == 'done' || status == 'notListening') {
            if (mounted) {
              setState(() => _isListening = false);
            }
          }
        },
        onError: (error) {
          debugPrint('Speech error: $error');
          if (mounted) {
            setState(() => _isListening = false);
          }
        },
      );
      if (mounted) {
        setState(() {});
        // Auto-start voice search after initialization if requested
        if (widget.activateVoiceSearch && _speechAvailable) {
          _startListening();
        }
      }
    } catch (e) {
      debugPrint('Speech init error: $e');
      _speechAvailable = false;
      if (mounted && widget.activateVoiceSearch) {
        // Show error if voice search was requested but failed to initialize
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Voice search initialization failed'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _startListening() async {
    if (!_speechAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Voice search is not available'),
          backgroundColor: Colors.orangeAccent,
        ),
      );
      return;
    }

    // Clear previous search results and text when starting new voice search
    setState(() {
      _isListening = true;
      _searchResults = [];
      _searchController.clear();
    });

    // Show Google Assistant style bottom sheet
    _showVoiceSearchBottomSheet();

    await _speech.listen(
      onResult: (result) {
        setState(() {
          _searchController.text = result.recognizedWords;
        });
        // Trigger search when speech recognition completes
        if (result.finalResult) {
          Navigator.of(context).pop(); // Close bottom sheet
          _onSearchChanged(result.recognizedWords);
        }
      },
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 3),
      listenOptions: stt.SpeechListenOptions(partialResults: true),
      localeId: 'en_IN',
    );
  }

  void _showVoiceSearchBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: true,
      enableDrag: true,
      builder: (context) => _VoiceSearchBottomSheet(
        searchController: _searchController,
        onStop: () {
          _stopListening();
          Navigator.of(context).pop();
        },
        onRestart: () {
          _restartListening();
        },
        isListeningNotifier: () => _isListening,
      ),
    ).whenComplete(() {
      // Ensure listening stops when bottom sheet is dismissed
      if (_isListening) {
        _stopListening();
      }
    });
  }

  Future<void> _restartListening() async {
    if (!_speechAvailable) return;

    setState(() {
      _isListening = true;
      _searchController.clear();
    });

    await _speech.listen(
      onResult: (result) {
        setState(() {
          _searchController.text = result.recognizedWords;
        });
        // Trigger search when speech recognition completes
        if (result.finalResult) {
          Navigator.of(context).pop(); // Close bottom sheet
          _onSearchChanged(result.recognizedWords);
        }
      },
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 3),
      listenOptions: stt.SpeechListenOptions(partialResults: true),
      localeId: 'en_IN',
    );
  }

  Future<void> _stopListening() async {
    await _speech.stop();
    setState(() => _isListening = false);
  }

  void _toggleVoiceSearch() {
    if (_isListening) {
      _stopListening();
    } else {
      _startListening();
    }
  }

  @override
  void dispose() {
    _placeholderTimer?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _speech.stop();
    super.dispose();
  }

  Future<void> _onSearchChanged(String query) async {
    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }

    setState(() => _isSearching = true);

    try {
      // Clean and split query into individual words for fuzzy matching
      final cleanQuery = query.trim().toLowerCase();
      List<String> queryWords = cleanQuery
          .split(RegExp(r'\s+'))
          .where((w) => w.length > 1)
          .toList();

      // If no valid words after split, use the clean query itself
      if (queryWords.isEmpty && cleanQuery.length > 1) {
        queryWords = [cleanQuery];
      }

      // If still empty, return no results
      if (queryWords.isEmpty) {
        if (mounted) {
          setState(() {
            _searchResults = [];
            _isSearching = false;
          });
        }
        return;
      }

      // Use Maps with ID as key to prevent duplicates
      final Map<String, Map<String, dynamic>> serviceResults = {};

      // Search services - match any word in name
      for (final word in queryWords) {
        final response = await SupabaseConfig.supabase
            .from('services')
            .select()
            .ilike('name', '%$word%')
            .limit(10);
        for (var item in response) {
          final id = item['id'].toString();
          if (!serviceResults.containsKey(id)) {
            serviceResults[id] = Map<String, dynamic>.from(item);
          }
        }
      }
      // Also search with full query
      final fullQueryServices = await SupabaseConfig.supabase
          .from('services')
          .select()
          .ilike('name', '%$cleanQuery%')
          .limit(5);
      for (var item in fullQueryServices) {
        final id = item['id'].toString();
        if (!serviceResults.containsKey(id)) {
          serviceResults[id] = Map<String, dynamic>.from(item);
        }
      }

      // Search service_types for even better matching
      final Set<String> matchedServiceIds = {};
      for (final word in queryWords) {
        final serviceTypeResponse = await SupabaseConfig.supabase
            .from('service_types')
            .select('service_id, name')
            .ilike('name', '%$word%')
            .limit(10);
        for (var st in serviceTypeResponse) {
          matchedServiceIds.add(st['service_id'].toString());
        }
      }
      // Fetch services that have matching service types
      if (matchedServiceIds.isNotEmpty) {
        final servicesFromTypes = await SupabaseConfig.supabase
            .from('services')
            .select()
            .inFilter('id', matchedServiceIds.toList())
            .limit(10);
        for (var item in servicesFromTypes) {
          final id = item['id'].toString();
          if (!serviceResults.containsKey(id)) {
            serviceResults[id] = Map<String, dynamic>.from(item);
          }
        }
      }

      // Search providers - match any word in name, location, or service
      final Map<String, Map<String, dynamic>> providerResults = {};
      for (final word in queryWords) {
        // Search by name
        final nameResponse = await SupabaseConfig.supabase
            .from('users')
            .select('*, services(name)')
            .eq('is_provider', true)
            .ilike('full_name', '%$word%')
            .limit(5);
        for (var item in nameResponse) {
          final id = item['id'].toString();
          if (!providerResults.containsKey(id)) {
            providerResults[id] = Map<String, dynamic>.from(item);
          }
        }

        // Search by location
        final locationResponse = await SupabaseConfig.supabase
            .from('users')
            .select('*, services(name)')
            .eq('is_provider', true)
            .ilike('location', '%$word%')
            .limit(5);
        for (var item in locationResponse) {
          final id = item['id'].toString();
          if (!providerResults.containsKey(id)) {
            providerResults[id] = Map<String, dynamic>.from(item);
          }
        }
      }

      // Search locations - match any word
      final Map<String, Map<String, dynamic>> locationResults = {};
      for (final word in queryWords) {
        final response = await SupabaseConfig.supabase
            .from('locations')
            .select()
            .ilike('name', '%$word%')
            .limit(5);
        for (var item in response) {
          final id = item['id'].toString();
          if (!locationResults.containsKey(id)) {
            locationResults[id] = Map<String, dynamic>.from(item);
          }
        }
      }

      // Search products
      final Map<String, Map<String, dynamic>> productResults = {};
      for (final word in queryWords) {
        final response = await SupabaseConfig.supabase
            .from('products')
            .select('*, provider:users!provider_id(full_name, location, avatar_url, latitude, longitude)')
            .ilike('name', '%$word%')
            .eq('is_active', true)
            .limit(5);
        for (var item in response) {
          final id = item['id'].toString();
          if (!productResults.containsKey(id)) {
            productResults[id] = Map<String, dynamic>.from(item);
          }
        }
      }

      final List<Map<String, dynamic>> combinedResults = [];

      // Add services first (most relevant for service booking app)
      for (var s in serviceResults.values.take(8)) {
        combinedResults.add({'type': 'service', 'data': s});
      }
      // Then providers
      for (var p in providerResults.values.take(5)) {
        combinedResults.add({'type': 'provider', 'data': p});
      }
      // Then products
      for (var pr in productResults.values.take(5)) {
        combinedResults.add({'type': 'product', 'data': pr});
      }
      // Then locations
      for (var l in locationResults.values.take(5)) {
        combinedResults.add({'type': 'location', 'data': l});
      }

      if (mounted) {
        setState(() {
          _searchResults = combinedResults;
          _isSearching = false;
        });
      }
    } catch (e) {
      debugPrint('Search error: $e');
      if (mounted) setState(() => _isSearching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: TextField(
          controller: _searchController,
          focusNode: _searchFocusNode,
          autofocus: true,
          decoration: InputDecoration(
            hintText: _isListening
                ? 'Listening...'
                : _searchPlaceholders[_currentPlaceholderIndex],
            border: InputBorder.none,
            hintStyle: TextStyle(
              color: _isListening ? Colors.redAccent : Colors.grey.shade400,
              fontStyle: _isListening ? FontStyle.italic : FontStyle.normal,
            ),
          ),
          onChanged: _onSearchChanged,
        ),
        actions: [
          // Mic button
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: _isListening
                  ? Colors.red.withOpacity(0.1)
                  : Colors.transparent,
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: Icon(
                _isListening ? Icons.mic : Icons.mic_none,
                color: _isListening ? Colors.redAccent : Colors.blueAccent,
              ),
              onPressed: _toggleVoiceSearch,
              tooltip: _isListening ? 'Stop listening' : 'Voice search',
            ),
          ),
          if (_searchController.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear, color: Colors.black54),
              onPressed: () {
                _searchController.clear();
                setState(() {
                  _searchResults = [];
                });
              },
            ),
        ],
      ),
      body: Stack(
        children: [
          // Main content
          _isSearching
              ? const Center(child: CircularProgressIndicator())
              : _searchResults.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.search, size: 64, color: Colors.grey.shade300),
                      const SizedBox(height: 16),
                      Text(
                        _searchController.text.isEmpty
                            ? 'Start typing to search'
                            : 'No results found',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _searchResults.length,
                  padding: const EdgeInsets.all(16),
                  itemBuilder: (context, index) {
                    final item = _searchResults[index];
                    if (item['type'] == 'service') {
                      return _buildServiceTile(item['data']);
                    } else if (item['type'] == 'provider') {
                      return _buildProviderTile(item['data']);
                    } else if (item['type'] == 'product') {
                      return _buildProductTile(item['data']);
                    } else {
                      return _buildLocationTile(item['data']);
                    }
                  },
                ),
        ],
      ),
    );
  }

  Widget _buildServiceTile(Map<String, dynamic> service) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        contentPadding: const EdgeInsets.all(12),
        leading: SafeNetworkImage(
          imageUrl: service['image_url'],
          width: 56,
          height: 56,
          borderRadius: BorderRadius.circular(8),
          errorWidget: Container(
            width: 56,
            height: 56,
            color: Colors.grey.shade200,
            child: const Icon(Icons.work, color: Colors.grey),
          ),
        ),
        title: Text(
          service['name'] ?? 'Unknown Service',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: const Text('Service'),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ServiceResultPage(
                serviceName: service['name'],
                serviceId: service['id'],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildProviderTile(Map<String, dynamic> provider) {
    // Extract service name from joined data
    final services = provider['services'];
    String serviceName = 'Service Provider';
    if (services != null) {
      if (services is Map) {
        serviceName = services['name'] ?? 'Service Provider';
      } else if (services is List && services.isNotEmpty) {
        serviceName = services[0]['name'] ?? 'Service Provider';
      }
    }

    // Get rating and price
    final double rating = (provider['average_rating'] ?? 0).toDouble();
    final int totalReviews = provider['total_reviews'] ?? 0;
    final dynamic priceValue = provider['price'];
    final String? serviceType = provider['service_type'];

    // Format price
    String priceText = '';
    if (priceValue != null) {
      final price = priceValue is int
          ? priceValue
          : (priceValue as num).toInt();
      priceText = '₹$price';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ProfilePage(userId: provider['id']),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Profile Picture
              SafeAvatar(
                imageUrl: provider['avatar_url'],
                radius: 30,
                userName: provider['full_name'],
              ),
              const SizedBox(width: 12),

              // Provider Details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Name
                    Text(
                      provider['full_name'] ?? 'Unknown Provider',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),

                    // Service Type + Sub-service
                    Row(
                      children: [
                        Icon(
                          Icons.work_outline,
                          size: 14,
                          color: Colors.blue.shade600,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            serviceType != null && serviceType.isNotEmpty
                                ? '$serviceName • $serviceType'
                                : serviceName,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.blue.shade600,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),

                    // Location
                    Row(
                      children: [
                        Icon(
                          Icons.location_on_outlined,
                          size: 14,
                          color: Colors.grey.shade600,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            provider['location'] ?? 'Unknown Location',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),

                    // Rating and Price Row
                    Row(
                      children: [
                        // Rating
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: rating >= 4.0
                                ? Colors.green.shade50
                                : rating >= 3.0
                                ? Colors.orange.shade50
                                : Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.star,
                                size: 14,
                                color: rating >= 4.0
                                    ? Colors.green.shade700
                                    : rating >= 3.0
                                    ? Colors.orange.shade700
                                    : Colors.grey.shade600,
                              ),
                              const SizedBox(width: 2),
                              Text(
                                rating > 0 ? rating.toStringAsFixed(1) : 'New',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: rating >= 4.0
                                      ? Colors.green.shade700
                                      : rating >= 3.0
                                      ? Colors.orange.shade700
                                      : Colors.grey.shade600,
                                ),
                              ),
                              if (totalReviews > 0) ...[
                                Text(
                                  ' ($totalReviews)',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),

                        // Price
                        if (priceText.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.deepPurple.shade50,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              priceText,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.deepPurple.shade700,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),

              // Arrow
              Icon(
                Icons.arrow_forward_ios,
                size: 16,
                color: Colors.grey.shade400,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProductTile(Map<String, dynamic> product) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        contentPadding: const EdgeInsets.all(12),
        leading: SafeNetworkImage(
          imageUrl: product['image_url'],
          width: 56,
          height: 56,
          borderRadius: BorderRadius.circular(8),
          errorWidget: Container(
            width: 56,
            height: 56,
            color: Colors.grey.shade200,
            child: const Icon(Icons.storefront, color: Colors.grey),
          ),
        ),
        title: Text(
          product['name'] ?? 'Unknown Product',
          style: const TextStyle(fontWeight: FontWeight.bold),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Product • ₹${product['price']}'),
            if (product['provider'] != null)
              Text(
                'By ${product['provider']['full_name']}',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ProductDetailPage(product: product),
            ),
          );
        },
      ),
    );
  }

  Widget _buildLocationTile(Map<String, dynamic> location) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        contentPadding: const EdgeInsets.all(12),
        leading: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(Icons.location_on, color: Colors.blue.shade700),
        ),
        title: Text(
          location['name'] ?? 'Unknown Location',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: const Text('Location'),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  LocationProvidersPage(locationName: location['name']),
            ),
          );
        },
      ),
    );
  }
}

// Google Assistant Style Voice Search Bottom Sheet
class _VoiceSearchBottomSheet extends StatefulWidget {
  final TextEditingController searchController;
  final VoidCallback onStop;
  final VoidCallback onRestart;
  final bool Function() isListeningNotifier;

  const _VoiceSearchBottomSheet({
    required this.searchController,
    required this.onStop,
    required this.onRestart,
    required this.isListeningNotifier,
  });

  @override
  State<_VoiceSearchBottomSheet> createState() =>
      _VoiceSearchBottomSheetState();
}

class _VoiceSearchBottomSheetState extends State<_VoiceSearchBottomSheet>
    with TickerProviderStateMixin {
  late AnimationController _waveController;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  Timer? _listeningCheckTimer;
  bool _isListening = true;

  @override
  void initState() {
    super.initState();
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Listen to text changes
    widget.searchController.addListener(_onTextChanged);

    // Periodically check listening state to update UI
    _listeningCheckTimer = Timer.periodic(const Duration(milliseconds: 100), (
      _,
    ) {
      if (mounted) {
        final newListeningState = widget.isListeningNotifier();
        if (_isListening != newListeningState) {
          setState(() {
            _isListening = newListeningState;
          });
          // Stop/start animations based on listening state
          if (_isListening) {
            _waveController.repeat();
            _pulseController.repeat(reverse: true);
          } else {
            _waveController.stop();
            _pulseController.stop();
          }
        }
      }
    });
  }

  void _onTextChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _listeningCheckTimer?.cancel();
    widget.searchController.removeListener(_onTextChanged);
    _waveController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(28),
          topRight: Radius.circular(28),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 32),

              // Voice wave animation - only show when listening is ON
              SizedBox(
                height: 120,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Animated wave bars - only visible when listening
                    if (_isListening)
                      AnimatedBuilder(
                        animation: _waveController,
                        builder: (context, child) {
                          return Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(4, (index) {
                              final colors = [
                                const Color(0xFFFF9800), // Orange (theme)
                                const Color(0xFFFFA726), // Orange Light
                                const Color(0xFFFF9800), // Orange (theme)
                                const Color(0xFFE65100), // Orange Dark
                              ];
                              final delay = index * 0.15;
                              final animValue =
                                  ((_waveController.value + delay) % 1.0);
                              final height = 20 + (40 * _waveHeight(animValue));

                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 100),
                                  width: 8,
                                  height: height,
                                  decoration: BoxDecoration(
                                    color: colors[index],
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                              );
                            }),
                          );
                        },
                      ),

                    // Mic button overlay - always visible but pulse only when listening
                    Positioned(
                      bottom: 0,
                      child: _isListening
                          ? ScaleTransition(
                              scale: _pulseAnimation,
                              child: _buildMicButton(),
                            )
                          : GestureDetector(
                              onTap: widget.onRestart,
                              child: _buildMicButton(),
                            ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Status text - changes based on listening state
              Text(
                _isListening ? 'Listening...' : 'Tap mic to speak again',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w500,
                  color: _isListening
                      ? Colors.grey.shade800
                      : const Color(0xFFFF9800),
                ),
              ),

              const SizedBox(height: 12),

              // Recognized text display
              Container(
                constraints: const BoxConstraints(maxWidth: 300, minHeight: 48),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Text(
                  !_isListening
                      ? (widget.searchController.text.isEmpty
                            ? 'Tap the microphone to try again'
                            : '\"${widget.searchController.text}\"')
                      : (widget.searchController.text.isEmpty
                            ? 'Speak now...'
                            : '\"${widget.searchController.text}\"'),
                  style: TextStyle(
                    fontSize: 16,
                    color: widget.searchController.text.isEmpty
                        ? Colors.grey.shade500
                        : Colors.grey.shade800,
                    fontStyle: widget.searchController.text.isEmpty
                        ? FontStyle.italic
                        : FontStyle.normal,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),

              const SizedBox(height: 24),

              // Cancel button (minimal, text only)
              TextButton(
                onPressed: widget.onStop,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 12,
                  ),
                ),
                child: Text(
                  'Cancel',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  double _waveHeight(double value) {
    // Creates a smooth wave pattern using proper sine function
    return (1 + math.sin(value * math.pi * 2)) / 2;
  }

  Widget _buildMicButton() {
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: _isListening
              ? [const Color(0xFFFF9800), const Color(0xFFE65100)]
              : [const Color(0xFFFFE0B2), const Color(0xFFFFCC80)],
        ),
        border: _isListening
            ? null
            : Border.all(color: const Color(0xFFFF9800), width: 3),
        boxShadow: _isListening
            ? [
                BoxShadow(
                  color: const Color(0xFFFF9800).withOpacity(0.3),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ]
            : [
                BoxShadow(
                  color: const Color(0xFFFF9800).withOpacity(0.2),
                  blurRadius: 10,
                  spreadRadius: 1,
                ),
              ],
      ),
      child: Icon(
        Icons.mic,
        color: _isListening ? Colors.white : const Color(0xFFE65100),
        size: 32,
      ),
    );
  }
}
