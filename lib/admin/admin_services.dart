import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase_config.dart';
import 'admin_locations.dart';

class AdminServicesPage extends StatefulWidget {
  const AdminServicesPage({super.key});

  @override
  State<AdminServicesPage> createState() => _AdminServicesPageState();
}

class _AdminServicesPageState extends State<AdminServicesPage>
    with SingleTickerProviderStateMixin {
  List<Map<String, dynamic>> _businessTypes = [];
  Map<String, List<Map<String, dynamic>>> _serviceTypes = {};
  List<Map<String, dynamic>> _locations = [];
  bool _isLoading = true;

  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);
    try {
      // Fetch Business Types (services table)
      final businessResponse = await SupabaseConfig.supabase
          .from('services')
          .select(
            'id, name, image_url, google_subscription_id, require_current_location, require_destination_location',
          )
          .order('name');

      final businessTypes = List<Map<String, dynamic>>.from(businessResponse);

      // Fetch Service Types (service_types table)
      // We fetch all and organize them in memory to avoid N+1 queries
      final serviceTypesResponse = await SupabaseConfig.supabase
          .from('service_types')
          .select('id, name, service_id')
          .order('name');

      final allServiceTypes = List<Map<String, dynamic>>.from(
        serviceTypesResponse,
      );

      final Map<String, List<Map<String, dynamic>>> groupedServiceTypes = {};

      for (var type in allServiceTypes) {
        final serviceId = type['service_id'] as String;
        if (!groupedServiceTypes.containsKey(serviceId)) {
          groupedServiceTypes[serviceId] = [];
        }
        groupedServiceTypes[serviceId]!.add(type);
      }

      // Fetch Locations
      final locationsResponse = await SupabaseConfig.supabase
          .from('locations')
          .select()
          .order('name');

      final locations = List<Map<String, dynamic>>.from(locationsResponse);

      if (mounted) {
        setState(() {
          _businessTypes = businessTypes;
          _serviceTypes = groupedServiceTypes;
          _locations = locations;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching services: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<String?> _uploadImage(File imageFile) async {
    try {
      final user = SupabaseConfig.supabase.auth.currentUser;
      debugPrint('Current User ID: ${user?.id}');
      debugPrint(
        'Auth Session: ${SupabaseConfig.supabase.auth.currentSession?.accessToken != null ? "Token Present" : "No Token"}',
      );
      debugPrint('Using admin client for upload (bypasses RLS)');

      final fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';
      debugPrint('Attempting to upload to services bucket: $fileName');

      // Use adminClient instead of regular supabase client to bypass RLS
      await SupabaseConfig.adminClient.storage
          .from('services')
          .upload(
            fileName,
            imageFile,
            fileOptions: const FileOptions(cacheControl: '3600', upsert: false),
          );

      final publicUrl = SupabaseConfig.adminClient.storage
          .from('services')
          .getPublicUrl(fileName);

      debugPrint('Upload successful. Public URL: $publicUrl');
      return publicUrl;
    } catch (e) {
      debugPrint('Error uploading image to storage: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Upload failed: $e')));
      }
      return null;
    }
  }

  Future<void> _addOrEditBusinessType({
    String? id,
    String? currentName,
    String? currentImageUrl,
    String? currentGoogleSubscriptionId,
    bool? currentRequireCurrentLocation,
    bool? currentRequireDestinationLocation,
  }) async {
    final nameController = TextEditingController(text: currentName);
    final googleSubscriptionIdController = TextEditingController(
      text: currentGoogleSubscriptionId ?? 'mrhelper_monthly_pro',
    );
    File? selectedImage;
    String? imageUrl = currentImageUrl; // Keep existing URL if editing
    final isEditing = id != null;
    bool isSaving = false;
    bool requireCurrentLocation = currentRequireCurrentLocation ?? false;
    bool requireDestinationLocation =
        currentRequireDestinationLocation ?? false;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) {
          return AlertDialog(
            title: Text(isEditing ? 'Edit Business Type' : 'Add Business Type'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Business Name',
                      hintText: 'e.g. Cleaning, Plumbing',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: googleSubscriptionIdController,
                    keyboardType: TextInputType.text,
                    decoration: const InputDecoration(
                      labelText: 'Google Subscription ID',
                      hintText: 'e.g. mrhelper_monthly_pro',
                      helperText:
                          'Enter the subscription product ID from Google Play Console.\nThe price will be fetched automatically from Google Play.',
                      helperMaxLines: 3,
                      prefixIcon: Icon(Icons.subscriptions_outlined),
                    ),
                  ),
                  const SizedBox(height: 16),
                  GestureDetector(
                    onTap: () async {
                      final picker = ImagePicker();
                      final picked = await picker.pickImage(
                        source: ImageSource.gallery,
                        maxWidth: 800,
                        maxHeight: 800,
                      );
                      if (picked != null) {
                        setStateDialog(() {
                          selectedImage = File(picked.path);
                        });
                      }
                    },
                    child: Container(
                      height: 150,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: selectedImage != null
                          ? Image.file(selectedImage!, fit: BoxFit.cover)
                          : (imageUrl != null && imageUrl!.isNotEmpty)
                          ? Image.network(
                              SupabaseConfig.proxyImageUrl(imageUrl!),
                              fit: BoxFit.cover,
                            )
                          : Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: const [
                                Icon(
                                  Icons.add_a_photo,
                                  size: 40,
                                  color: Colors.grey,
                                ),
                                SizedBox(height: 8),
                                Text(
                                  'Tap to add image',
                                  style: TextStyle(color: Colors.grey),
                                ),
                              ],
                            ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Divider(),
                  const SizedBox(height: 8),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Location Options',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Colors.deepPurple,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'When enabled, users will be asked for these locations during booking',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    title: const Text('Require Current Location'),
                    subtitle: const Text(
                      'User must provide their current location',
                      style: TextStyle(fontSize: 12),
                    ),
                    value: requireCurrentLocation,
                    onChanged: (val) {
                      setStateDialog(() {
                        requireCurrentLocation = val;
                      });
                    },
                    activeColor: Colors.deepPurple,
                    contentPadding: EdgeInsets.zero,
                  ),
                  SwitchListTile(
                    title: const Text('Require Destination Location'),
                    subtitle: const Text(
                      'User must provide destination (e.g., for transport)',
                      style: TextStyle(fontSize: 12),
                    ),
                    value: requireDestinationLocation,
                    onChanged: (val) {
                      setStateDialog(() {
                        requireDestinationLocation = val;
                      });
                    },
                    activeColor: Colors.deepPurple,
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSaving ? null : () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(100, 45), // Ensure consistent size
                ),
                onPressed: isSaving
                    ? null
                    : () async {
                        if (nameController.text.isNotEmpty) {
                          setStateDialog(() {
                            isSaving = true;
                          });

                          // Upload new image if selected
                          if (selectedImage != null) {
                            final uploadedUrl = await _uploadImage(
                              selectedImage!,
                            );
                            if (uploadedUrl != null) {
                              imageUrl = uploadedUrl;
                            }
                          }

                          try {
                            final googleSubId =
                                googleSubscriptionIdController.text.trim().isNotEmpty
                                    ? googleSubscriptionIdController.text.trim()
                                    : 'mrhelper_monthly_pro';

                            if (isEditing) {
                              await SupabaseConfig.adminClient
                                  .from('services')
                                  .update({
                                    'name': nameController.text.trim(),
                                    'image_url': imageUrl,
                                    'google_subscription_id': googleSubId,
                                    'require_current_location':
                                        requireCurrentLocation,
                                    'require_destination_location':
                                        requireDestinationLocation,
                                  })
                                  .eq('id', id);
                            } else {
                              await SupabaseConfig.adminClient
                                  .from('services')
                                  .insert({
                                    'name': nameController.text.trim(),
                                    'image_url': imageUrl,
                                    'google_subscription_id': googleSubId,
                                    'require_current_location':
                                        requireCurrentLocation,
                                    'require_destination_location':
                                        requireDestinationLocation,
                                  });
                            }
                            if (mounted) Navigator.pop(context);
                            _fetchData();
                          } catch (e) {
                            debugPrint('Error saving service: $e');
                            if (mounted) {
                              setStateDialog(() => isSaving = false);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Error: $e')),
                              );
                            }
                          }
                        }
                      },
                child: isSaving
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(isEditing ? 'Save' : 'Add'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _deleteBusinessType(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Business Type?'),
        content: const Text(
          'This will delete the business type and ALL its service types. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        // Delete image if exists
        final business = _businessTypes.firstWhere(
          (e) => e['id'] == id,
          orElse: () => {},
        );
        final imageUrl = business['image_url'] as String?;

        if (imageUrl != null && imageUrl.contains('/services/')) {
          final fileName = imageUrl.split('/services/').last;
          if (fileName.isNotEmpty) {
            await SupabaseConfig.adminClient.storage.from('services').remove([
              fileName,
            ]);
          }
        }

        await SupabaseConfig.adminClient.from('services').delete().eq('id', id);
        _fetchData();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error: $e')));
        }
      }
    }
  }

  Future<void> _addServiceType(String serviceId) async {
    final controller = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Service Type'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Service Name',
            hintText: 'e.g. Kitchen Cleaning',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (controller.text.isNotEmpty) {
                try {
                  await SupabaseConfig.adminClient.from('service_types').insert(
                    {'name': controller.text.trim(), 'service_id': serviceId},
                  );
                  Navigator.pop(context, true);
                } catch (e) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('Error: $e')));
                }
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (result == true) {
      _fetchData();
    }
  }

  Future<void> _deleteServiceType(String id) async {
    try {
      await SupabaseConfig.adminClient
          .from('service_types')
          .delete()
          .eq('id', id);
      _fetchData();
    } catch (e) {
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
        title: const Text('Manage Services & Locations'),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(icon: Icon(Icons.business_center), text: 'Services'),
            Tab(icon: Icon(Icons.location_on), text: 'Locations'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                // Services Tab
                _buildServicesTab(),
                // Locations Tab
                AdminLocationsTab(locations: _locations, onRefresh: _fetchData),
              ],
            ),
    );
  }

  Widget _buildServicesTab() {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addOrEditBusinessType(),
        label: const Text('Add Business Type'),
        icon: const Icon(Icons.add),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
      body: _businessTypes.isEmpty
          ? const Center(
              child: Text(
                'No business types found.\nAdd one to get started!',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 16),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.only(bottom: 80, top: 10),
              itemCount: _businessTypes.length,
              itemBuilder: (context, index) {
                final business = _businessTypes[index];
                final businessId = business['id'];
                final subServices = _serviceTypes[businessId] ?? [];

                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ExpansionTile(
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        width: 50,
                        height: 50,
                        color: Colors.deepPurple.shade50,
                        child: (business['image_url'] != null)
                            ? Image.network(
                                SupabaseConfig.proxyImageUrl(
                                  business['image_url'],
                                ),
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  return Icon(
                                    Icons.business_center_rounded,
                                    color: Colors.deepPurple.shade300,
                                    size: 24,
                                  );
                                },
                              )
                            : Icon(
                                Icons.business_center_rounded,
                                color: Colors.deepPurple.shade300,
                                size: 24,
                              ),
                      ),
                    ),
                    title: Text(
                      business['name'],
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${subServices.length} Service Types',
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                        Text(
                          'Sub ID: ${business['google_subscription_id'] ?? 'mrhelper_monthly_pro'}',
                          style: TextStyle(
                            color: Colors.green.shade700,
                            fontWeight: FontWeight.w500,
                            fontSize: 12,
                          ),
                        ),
                        if (business['require_current_location'] == true ||
                            business['require_destination_location'] == true)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Wrap(
                              spacing: 6,
                              children: [
                                if (business['require_current_location'] ==
                                    true)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.blue.shade50,
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(
                                        color: Colors.blue.shade200,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.my_location,
                                          size: 10,
                                          color: Colors.blue.shade700,
                                        ),
                                        const SizedBox(width: 3),
                                        Text(
                                          'Current',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: Colors.blue.shade700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                if (business['require_destination_location'] ==
                                    true)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.orange.shade50,
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(
                                        color: Colors.orange.shade200,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.location_on,
                                          size: 10,
                                          color: Colors.orange.shade700,
                                        ),
                                        const SizedBox(width: 3),
                                        Text(
                                          'Destination',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: Colors.orange.shade700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline),
                          color: Colors.blue,
                          tooltip: 'Add Service Type',
                          onPressed: () => _addServiceType(businessId),
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit_outlined),
                          color: Colors.orange,
                          tooltip: 'Edit Business Type',
                          onPressed: () => _addOrEditBusinessType(
                            id: businessId,
                            currentName: business['name'],
                            currentImageUrl: business['image_url'],
                            currentGoogleSubscriptionId:
                                business['google_subscription_id'],
                            currentRequireCurrentLocation:
                                business['require_current_location'] ?? false,
                            currentRequireDestinationLocation:
                                business['require_destination_location'] ??
                                false,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          color: Colors.red,
                          tooltip: 'Delete Business Type',
                          onPressed: () => _deleteBusinessType(businessId),
                        ),
                        const Icon(Icons.expand_more),
                      ],
                    ),
                    children: [
                      if (subServices.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Text(
                            'No service types yet.',
                            style: TextStyle(
                              fontStyle: FontStyle.italic,
                              color: Colors.grey,
                            ),
                          ),
                        )
                      else
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: subServices.length,
                          separatorBuilder: (ctx, i) => const Divider(
                            height: 1,
                            indent: 16,
                            endIndent: 16,
                          ),
                          itemBuilder: (context, subIndex) {
                            final sub = subServices[subIndex];
                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 0,
                              ),
                              title: Text(sub['name']),
                              trailing: IconButton(
                                icon: const Icon(
                                  Icons.remove_circle_outline,
                                  size: 20,
                                  color: Colors.redAccent,
                                ),
                                onPressed: () => _deleteServiceType(sub['id']),
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
