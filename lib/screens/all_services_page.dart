import 'package:flutter/material.dart';
import '../screens/service_result_page.dart';
import '../supabase_config.dart';
import '../services/ai_search_service.dart';

class AllServicesPage extends StatefulWidget {
  final List<Map<String, dynamic>> services;

  const AllServicesPage({super.key, required this.services});

  @override
  State<AllServicesPage> createState() => _AllServicesPageState();
}

class _AllServicesPageState extends State<AllServicesPage> {
  late List<Map<String, dynamic>> _filteredServices;
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _filteredServices = widget.services;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _filterServices(String query) async {
    if (query.isEmpty) {
      setState(() {
        _filteredServices = widget.services;
        _isSearching = false;
      });
      return;
    }

    setState(() {
      _isSearching = true;
    });

    // 1. Standard search
    final standardMatches = widget.services
        .where(
          (service) => service['name'].toString().toLowerCase().contains(
            query.toLowerCase(),
          ),
        )
        .toList();

    if (standardMatches.isNotEmpty) {
      setState(() {
        _filteredServices = standardMatches;
        _isSearching = false;
      });
      return;
    }

    // 2. AI Search
    final categoryNames = widget.services.map((s) => s['name'].toString()).toList();
    final aiCategoryMatch = await AISearchService.analyzeSearchQuery(
      userQuery: query,
      availableCategories: categoryNames,
    );

    setState(() {
      if (aiCategoryMatch != null && aiCategoryMatch != 'None') {
        _filteredServices = widget.services
            .where((s) => s['name'].toString() == aiCategoryMatch)
            .toList();
      } else {
        _filteredServices = [];
      }
      _isSearching = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text(
          'All Services',
          style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Search Bar
            Container(
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(15),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: TextField(
                controller: _searchController,
                onChanged: _filterServices,
                decoration: InputDecoration(
                  hintText: 'Search for a service...',
                  hintStyle: TextStyle(color: Colors.grey.shade400),
                  prefixIcon: const Icon(
                    Icons.search,
                    color: Colors.blueAccent,
                  ),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, color: Colors.grey),
                          onPressed: () {
                            _searchController.clear();
                            _filterServices('');
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 15,
                  ),
                ),
              ),
            ),

            // Grid View
            _isSearching
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : _filteredServices.isEmpty
                    ? Container(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Column(
                      children: [
                        Icon(
                          Icons.search_off,
                          size: 48,
                          color: Colors.grey.shade300,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No services found',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  )
                : GridView.builder(
                    physics: const NeverScrollableScrollPhysics(),
                    shrinkWrap: true,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                          childAspectRatio: 0.85,
                        ),
                    itemCount: _filteredServices.length,
                    itemBuilder: (context, index) {
                      final service = _filteredServices[index];
                      // Generate a consistent color for the service card
                      final colorIndex = index % 4;
                      final List<Color> cardColors = [
                        Colors.blue.shade50,
                        Colors.purple.shade50,
                        Colors.orange.shade50,
                        Colors.green.shade50,
                      ];
                      final List<Color> iconColors = [
                        Colors.blue,
                        Colors.purple,
                        Colors.orange,
                        Colors.green,
                      ];

                      return GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ServiceResultPage(
                                serviceId: service['id'],
                                serviceName: service['name'],
                              ),
                            ),
                          );
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.grey.withOpacity(0.08),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Stack(
                            children: [
                              // Background Image if available
                              if (service['image_url'] != null)
                                Positioned.fill(
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(20),
                                    child: Image.network(
                                      SupabaseConfig.proxyImageUrl(
                                        service['image_url'],
                                      ),
                                      fit: BoxFit.cover,
                                      errorBuilder:
                                          (context, error, stackTrace) =>
                                              Container(
                                                color: cardColors[colorIndex],
                                              ),
                                    ),
                                  ),
                                ),

                              // Gradient Overlay for better text visibility if image exists
                              if (service['image_url'] != null)
                                Positioned.fill(
                                  child: Container(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(20),
                                      gradient: LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: [
                                          Colors.black.withOpacity(0.1),
                                          Colors.black.withOpacity(0.6),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),

                              Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (service['image_url'] == null)
                                      Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: cardColors[colorIndex],
                                          borderRadius: BorderRadius.circular(
                                            15,
                                          ),
                                        ),
                                        child: Icon(
                                          Icons.build_circle_outlined,
                                          size: 32,
                                          color: iconColors[colorIndex],
                                        ),
                                      ),
                                    const Spacer(),
                                    Text(
                                      service['name'],
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                        color: service['image_url'] != null
                                            ? Colors.white
                                            : Colors.black87,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Available now',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: service['image_url'] != null
                                            ? Colors.white70
                                            : Colors.grey,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ],
        ),
      ),
    );
  }
}
