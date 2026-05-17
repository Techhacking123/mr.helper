import 'package:flutter/material.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import '../supabase_config.dart';
import '../profile/profile_page.dart';
import '../widgets/skeleton_loader.dart';

class ServiceResultPage extends StatefulWidget {
  final String serviceId;
  final String serviceName;
  final String? locationFilter;

  const ServiceResultPage({
    super.key,
    required this.serviceId,
    required this.serviceName,
    this.locationFilter,
  });

  @override
  State<ServiceResultPage> createState() => _ServiceResultPageState();
}

class _ServiceResultPageState extends State<ServiceResultPage> {
  // Data
  List<Map<String, dynamic>> _allProviders = [];
  List<Map<String, dynamic>> _filteredProviders = [];
  bool _isLoading = true;

  // Filters State
  List<String> _availableServiceTypes = [];
  String? _selectedServiceType; // null = All
  double _minRating = 0.0;
  RangeValues _priceRange = const RangeValues(0, 10000);
  double _maxPriceInList = 500.0;
  double _minPriceInList = 0.0;
  String? _locationQuery;

  @override
  void initState() {
    super.initState();
    _locationQuery = widget.locationFilter;
    _fetchProviders();
  }

  Future<void> _fetchProviders() async {
    setState(() => _isLoading = true);
    try {
      var query = SupabaseConfig.supabase
          .from('users')
          .select('*') // Removed feedback join - using average_rating instead
          .eq('is_provider', true)
          .eq('service_id', widget.serviceId);

      if (_locationQuery != null && _locationQuery!.trim().isNotEmpty) {
        query = query.ilike('location', '%${_locationQuery!.trim()}%');
      }

      final response = await query;

      // ✅ FILTER OUT UNSUBSCRIBED PROVIDERS
      final activeProviders = (response as List).where((provider) {
        final isSubscribed = provider['is_subscribed'] ?? false;
        final expiryStr = provider['subscription_expiry'];

        if (isSubscribed && expiryStr != null) {
          try {
            final expiry = DateTime.parse(expiryStr);
            final isActive = expiry.isAfter(DateTime.now());
            if (!isActive) {
              debugPrint(
                '❌ Filtered out provider ${provider['full_name']}: subscription expired on $expiry',
              );
            }
            return isActive;
          } catch (e) {
            debugPrint('Error parsing expiry for ${provider['full_name']}: $e');
            return false;
          }
        }
        debugPrint(
          '❌ Filtered out provider ${provider['full_name']}: not subscribed',
        );
        return false; // Not subscribed or no expiry
      }).toList();

      debugPrint(
        '✅ Found ${activeProviders.length} subscribed providers out of ${response.length} total',
      );

      final List<Map<String, dynamic>> formatted = [];
      final Set<String> types = {};
      double minP = double.infinity;
      double maxP = 0.0;

      for (var provider in activeProviders) {
        // Rating - use auto-calculated average_rating from users table
        double avg = (provider['average_rating'] as num?)?.toDouble() ?? 0.0;
        int reviewCount = (provider['total_reviews'] as int?) ?? 0;

        // Price
        final price = (provider['price'] as num?)?.toDouble() ?? 0.0;
        if (price < minP) minP = price;
        if (price > maxP) maxP = price;

        // Service Type
        final sType = provider['service_type'] as String?;
        if (sType != null && sType.isNotEmpty) {
          types.add(sType);
        }

        formatted.add({
          ...provider,
          'avg_rating': avg,
          'rating_count': reviewCount,
          'real_price': price,
        });
      }

      // Handle generic price ranges if no data
      if (minP == double.infinity) minP = 0;
      if (maxP == 0) maxP = 500;
      if (minP == maxP) maxP = minP + 100;

      setState(() {
        _allProviders = formatted;
        _availableServiceTypes = types.toList()..sort();
        _minPriceInList = minP;
        _maxPriceInList = maxP;
        // Check if current range is valid, else reset
        if (_priceRange.start < minP || _priceRange.end > maxP) {
          _priceRange = RangeValues(minP, maxP);
        }

        _applyFilters();
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error fetching providers: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  void _applyFilters() {
    final filtered = _allProviders.where((p) {
      // Service Type
      if (_selectedServiceType != null) {
        if (p['service_type'] != _selectedServiceType) return false;
      }

      // Rating
      final rating = p['avg_rating'] as double;
      if (rating < _minRating) return false;

      // Price
      final price = p['real_price'] as double;
      if (price < _priceRange.start || price > _priceRange.end) {
        return false;
      }

      return true;
    }).toList();

    filtered.sort(
      (a, b) =>
          (b['avg_rating'] as double).compareTo(a['avg_rating'] as double),
    );

    setState(() {
      _filteredProviders = filtered;
    });
  }

  void _showFilterModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: _FilterModal(
          availableTypes: _availableServiceTypes,
          currentType: _selectedServiceType,
          currentMinRating: _minRating,
          currentPriceRange: _priceRange,
          currentLocation: _locationQuery,
          minPrice: _minPriceInList,
          maxPrice: _maxPriceInList,
          onApply: (type, rating, range, location) {
            // Apply visual filters
            _selectedServiceType = type;
            _minRating = rating;
            _priceRange = range;

            // If location changed, re-fetch; otherwise just filter local list
            if (location != _locationQuery) {
              _locationQuery = location;
              Navigator.pop(context); // close modal first
              _fetchProviders();
            } else {
              _applyFilters();
              Navigator.pop(context);
            }
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      body: CustomScrollView(
        slivers: [
          // App Bar
          SliverAppBar(
            pinned: true,
            expandedHeight: 140,
            backgroundColor: Colors.deepPurple,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                '${widget.serviceName} Experts',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              background: Stack(
                fit: StackFit.expand,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.deepPurple.shade700,
                          Colors.deepPurple.shade400,
                        ],
                        begin: Alignment.bottomLeft,
                        end: Alignment.topRight,
                      ),
                    ),
                  ),
                  Positioned(
                    right: -20,
                    bottom: -20,
                    child: Icon(
                      Icons.handyman_outlined,
                      size: 150,
                      color: Colors.white.withOpacity(0.1),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.tune),
                onPressed: _showFilterModal,
              ),
            ],
          ),

          // Filters Bar
          SliverToBoxAdapter(
            child: Container(
              height: 60,
              padding: const EdgeInsets.fromLTRB(16, 12, 0, 12),
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  if (_locationQuery != null && _locationQuery!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Chip(
                        avatar: const Icon(
                          Icons.location_on,
                          size: 16,
                          color: Colors.white,
                        ),
                        label: Text(_locationQuery!),
                        backgroundColor: Colors.deepPurple,
                        labelStyle: const TextStyle(color: Colors.white),
                        onDeleted: () {
                          setState(() {
                            _locationQuery = '';
                            _fetchProviders();
                          });
                        },
                        deleteIconColor: Colors.white70,
                      ),
                    ),

                  _buildQuickChoiceChip(null, 'All Types'),
                  ..._availableServiceTypes.map(
                    (t) => _buildQuickChoiceChip(t, t),
                  ),
                ],
              ),
            ),
          ),

          // Content
          _isLoading
              ? SliverPadding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => const ProviderCardSkeleton(),
                      childCount: 5, // Show 5 skeleton cards
                    ),
                  ),
                )
              : _filteredProviders.isEmpty
              ? SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.search_off_rounded,
                          size: 80,
                          color: Colors.grey.shade300,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No providers found',
                          style: TextStyle(
                            fontSize: 20,
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Try adjusting your filters or location',
                          style: TextStyle(color: Colors.grey.shade500),
                        ),
                        if (_locationQuery != null &&
                            _locationQuery!.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          TextButton.icon(
                            onPressed: () {
                              setState(() {
                                _locationQuery = '';
                                _fetchProviders();
                              });
                            },
                            icon: const Icon(
                              Icons.clear,
                              color: Colors.deepPurple,
                            ),
                            label: const Text(
                              'Clear Location Filter',
                              style: TextStyle(color: Colors.deepPurple),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                )
              : SliverPadding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate((context, index) {
                      return _buildProviderCard(_filteredProviders[index]);
                    }, childCount: _filteredProviders.length),
                  ),
                ),
        ],
      ),
    );
  }

  Widget _buildQuickChoiceChip(String? value, String label) {
    final isSelected = _selectedServiceType == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (selected) {
          setState(() {
            _selectedServiceType = selected ? value : null;
            _applyFilters();
          });
        },
        backgroundColor: Colors.white,
        selectedColor: Colors.deepPurple.shade100,
        checkmarkColor: Colors.deepPurple,
        shape: StadiumBorder(
          side: BorderSide(
            color: isSelected ? Colors.deepPurple : Colors.grey.shade300,
          ),
        ),
        labelStyle: TextStyle(
          color: isSelected ? Colors.deepPurple : Colors.black87,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildProviderCard(Map<String, dynamic> provider) {
    final type = provider['service_type'] ?? 'Expert';
    final price = provider['real_price'];

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
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
                // Avatar
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    image: provider['avatar_url'] != null
                        ? DecorationImage(
                            image: NetworkImage(
                              SupabaseConfig.proxyImageUrl(
                                provider['avatar_url'],
                              ),
                            ),
                            fit: BoxFit.cover,
                          )
                        : null,
                    color: Colors.deepPurple.shade50,
                  ),
                  child: provider['avatar_url'] == null
                      ? Icon(
                          Icons.person,
                          color: Colors.deepPurple.shade200,
                          size: 40,
                        )
                      : null,
                ),
                const SizedBox(width: 16),

                // Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              provider['full_name'] ?? 'Provider',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.green.shade50,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '₹$price',
                              style: TextStyle(
                                color: Colors.green.shade700,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        type,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.deepPurple.shade400,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(
                            Icons.location_on,
                            size: 14,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              provider['location'] ?? 'Unknown',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          RatingBarIndicator(
                            rating: provider['avg_rating'],
                            itemBuilder: (context, index) => const Icon(
                              Icons.star_rounded,
                              color: Colors.amber,
                            ),
                            itemCount: 5,
                            itemSize: 16.0,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '${provider['avg_rating'].toStringAsFixed(1)} (${provider['rating_count']})',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FilterModal extends StatefulWidget {
  final List<String> availableTypes;
  final String? currentType;
  final double currentMinRating;
  final RangeValues currentPriceRange;
  final String? currentLocation;
  final double minPrice;
  final double maxPrice;
  final Function(String?, double, RangeValues, String?) onApply;

  const _FilterModal({
    required this.availableTypes,
    required this.currentType,
    required this.currentMinRating,
    required this.currentPriceRange,
    required this.currentLocation,
    required this.minPrice,
    required this.maxPrice,
    required this.onApply,
  });

  @override
  State<_FilterModal> createState() => _FilterModalState();
}

class _FilterModalState extends State<_FilterModal> {
  late String? _selectedType;
  late double _selectedRating;
  late RangeValues _selectedPriceRange;
  late TextEditingController _locationController;

  List<Map<String, dynamic>> _availableLocations = [];
  bool _isLoadingLocations = false;
  String? _selectedLocation;

  @override
  void initState() {
    super.initState();
    _selectedType = widget.currentType;
    _selectedRating = widget.currentMinRating;
    _selectedPriceRange = widget.currentPriceRange;
    _locationController = TextEditingController(text: widget.currentLocation);
    _selectedLocation = widget.currentLocation;

    // Range Validation
    if (_selectedPriceRange.start < widget.minPrice) {
      _selectedPriceRange = RangeValues(
        widget.minPrice,
        _selectedPriceRange.end,
      );
    }
    if (_selectedPriceRange.end > widget.maxPrice) {
      _selectedPriceRange = RangeValues(
        _selectedPriceRange.start,
        widget.maxPrice,
      );
    }

    _loadLocations();
  }

  Future<void> _loadLocations() async {
    setState(() => _isLoadingLocations = true);
    try {
      final response = await SupabaseConfig.supabase
          .from('locations')
          .select('name')
          .eq('is_active', true)
          .order('name');

      setState(() {
        _availableLocations = List<Map<String, dynamic>>.from(response);
        _isLoadingLocations = false;
      });
    } catch (e) {
      debugPrint('Error loading locations: $e');
      setState(() => _isLoadingLocations = false);
    }
  }

  @override
  void dispose() {
    _locationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
      height: MediaQuery.of(context).size.height * 0.85,
      child: Column(
        children: [
          // Handle Bar
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 24),

          Expanded(
            child: ListView(
              children: [
                const Text(
                  'Filters',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 24),

                // Location Filter - CHANGED TO DROPDOWN
                const Text(
                  'Location',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                _isLoadingLocations
                    ? Container(
                        height: 56,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: const Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : DropdownButtonFormField<String>(
                        value: _selectedLocation,
                        decoration: InputDecoration(
                          hintText: 'Select a location',
                          prefixIcon: const Icon(Icons.location_on_outlined),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          filled: true,
                          fillColor: Colors.grey.shade50,
                        ),
                        items: [
                          const DropdownMenuItem<String>(
                            value: null,
                            child: Text('All Locations'),
                          ),
                          ..._availableLocations.map((location) {
                            final name = location['name'] as String;
                            return DropdownMenuItem<String>(
                              value: name,
                              child: Text(name),
                            );
                          }),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _selectedLocation = value;
                            _locationController.text = value ?? '';
                          });
                        },
                      ),
                const SizedBox(height: 24),

                // Service Types
                if (widget.availableTypes.isNotEmpty) ...[
                  const Text(
                    'Specialization',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('All'),
                        selected: _selectedType == null,
                        onSelected: (val) =>
                            setState(() => _selectedType = null),
                        selectedColor: Colors.deepPurple,
                        labelStyle: TextStyle(
                          color: _selectedType == null
                              ? Colors.white
                              : Colors.black,
                        ),
                        checkmarkColor: Colors.white,
                      ),
                      ...widget.availableTypes.map(
                        (t) => ChoiceChip(
                          label: Text(t),
                          selected: _selectedType == t,
                          onSelected: (val) =>
                              setState(() => _selectedType = val ? t : null),
                          selectedColor: Colors.deepPurple,
                          labelStyle: TextStyle(
                            color: _selectedType == t
                                ? Colors.white
                                : Colors.black,
                          ),
                          checkmarkColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                ],

                // Price Range
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Price Range',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '₹${_selectedPriceRange.start.round()} - ₹${_selectedPriceRange.end.round()}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.deepPurple,
                      ),
                    ),
                  ],
                ),
                RangeSlider(
                  values: _selectedPriceRange,
                  min: widget.minPrice,
                  max: widget.maxPrice,
                  activeColor: Colors.deepPurple,
                  divisions: 100,
                  onChanged: (val) => setState(() => _selectedPriceRange = val),
                ),
                const SizedBox(height: 24),

                // Rating
                const Text(
                  'Minimum Rating',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Slider(
                        value: _selectedRating,
                        min: 0,
                        max: 5,
                        divisions: 10,
                        activeColor: Colors.amber,
                        onChanged: (val) =>
                            setState(() => _selectedRating = val),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Text(
                            _selectedRating.toStringAsFixed(1),
                            style: TextStyle(
                              color: Colors.amber.shade900,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Icon(Icons.star, size: 16, color: Colors.amber),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),

          SafeArea(
            top: false,
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      setState(() {
                        _selectedType = null;
                        _selectedRating = 0.0;
                        _locationController.clear();
                        _selectedLocation = null;
                        _selectedPriceRange = RangeValues(
                          widget.minPrice,
                          widget.maxPrice,
                        );
                      });
                    },
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Reset'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: () {
                      widget.onApply(
                        _selectedType,
                        _selectedRating,
                        _selectedPriceRange,
                        _locationController.text.trim(),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Apply Results'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
