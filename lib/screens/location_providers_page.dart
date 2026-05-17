import 'package:flutter/material.dart';
import '../supabase_config.dart';
import '../profile/profile_page.dart';

class LocationProvidersPage extends StatefulWidget {
  final String locationName;
  const LocationProvidersPage({super.key, required this.locationName});

  @override
  State<LocationProvidersPage> createState() => _LocationProvidersPageState();
}

class _LocationProvidersPageState extends State<LocationProvidersPage> {
  List<Map<String, dynamic>> _providers = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchProvidersByLocation();
  }

  Future<void> _fetchProvidersByLocation() async {
    try {
      final response = await SupabaseConfig.supabase
          .from('users')
          .select(
            'id, full_name, avatar_url, location, service_id, services(name)',
          )
          .eq('is_provider', true)
          .ilike('location', widget.locationName); // Case-insensitive match

      if (mounted) {
        setState(() {
          _providers = List<Map<String, dynamic>>.from(response);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching providers for location: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Providers in ${widget.locationName}'),
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _providers.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.location_off_outlined,
                    size: 64,
                    color: Colors.grey,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No providers found in ${widget.locationName}',
                    style: const TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _providers.length,
              itemBuilder: (context, index) {
                final provider = _providers[index];
                final serviceName = provider['services']?['name'] ?? 'Provider';

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 2,
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(12),
                    leading: ClipOval(
                      child: Container(
                        width: 50,
                        height: 50,
                        color: Colors.grey.shade200,
                        child: provider['avatar_url'] != null
                            ? Image.network(
                                SupabaseConfig.proxyImageUrl(
                                  provider['avatar_url'],
                                ),
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const Icon(
                                  Icons.person,
                                  color: Colors.grey,
                                ),
                              )
                            : const Icon(Icons.person, color: Colors.grey),
                      ),
                    ),
                    title: Text(
                      provider['full_name'] ?? 'Unknown Name',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(serviceName),
                        Row(
                          children: [
                            const Icon(
                              Icons.location_on,
                              size: 12,
                              color: Colors.grey,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              provider['location'] ?? 'Unknown',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ProfilePage(userId: provider['id']),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
    );
  }
}
