import 'package:flutter/material.dart';
import '../supabase_config.dart';

class AdminLocationsTab extends StatefulWidget {
  final List<Map<String, dynamic>> locations;
  final VoidCallback onRefresh;

  const AdminLocationsTab({
    super.key,
    required this.locations,
    required this.onRefresh,
  });

  @override
  State<AdminLocationsTab> createState() => _AdminLocationsTabState();
}

class _AdminLocationsTabState extends State<AdminLocationsTab> {
  Future<void> _addOrEditLocation({
    String? id,
    String? currentName,
    bool? currentIsActive,
  }) async {
    final nameController = TextEditingController(text: currentName);
    bool isActive = currentIsActive ?? true;
    final isEditing = id != null;
    bool isSaving = false;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) {
          return AlertDialog(
            title: Text(isEditing ? 'Edit Location' : 'Add Location'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Location Name',
                    hintText: 'e.g. Mumbai, Delhi',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.location_city),
                  ),
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  title: const Text('Active'),
                  subtitle: Text(
                    isActive
                        ? 'Location is visible to users'
                        : 'Location is hidden from users',
                  ),
                  value: isActive,
                  onChanged: (value) {
                    setStateDialog(() => isActive = value);
                  },
                  activeColor: Colors.green,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: isSaving ? null : () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: isSaving
                    ? null
                    : () async {
                        if (nameController.text.trim().isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Please enter a location name'),
                            ),
                          );
                          return;
                        }

                        setStateDialog(() => isSaving = true);

                        try {
                          if (isEditing) {
                            await SupabaseConfig.adminClient
                                .from('locations')
                                .update({
                                  'name': nameController.text.trim(),
                                  'is_active': isActive,
                                })
                                .eq('id', id);
                          } else {
                            await SupabaseConfig.adminClient
                                .from('locations')
                                .insert({
                                  'name': nameController.text.trim(),
                                  'is_active': isActive,
                                });
                          }
                          if (mounted) {
                            Navigator.pop(context);
                            widget.onRefresh();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  isEditing
                                      ? 'Location updated successfully'
                                      : 'Location added successfully',
                                ),
                                backgroundColor: Colors.green,
                              ),
                            );
                          }
                        } catch (e) {
                          debugPrint('Error saving location: $e');
                          if (mounted) {
                            setStateDialog(() => isSaving = false);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Error: $e'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        }
                      },
                child: isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
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

  Future<void> _deleteLocation(String id, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Location?'),
        content: Text(
          'Are you sure you want to delete "$name"?\n\nThis location will be removed from all dropdowns in the app.',
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
        await SupabaseConfig.adminClient
            .from('locations')
            .delete()
            .eq('id', id);
        widget.onRefresh();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Location "$name" deleted successfully'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  Future<void> _toggleLocationStatus(String id, bool currentStatus) async {
    try {
      await SupabaseConfig.adminClient
          .from('locations')
          .update({'is_active': !currentStatus})
          .eq('id', id);
      widget.onRefresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeLocations = widget.locations
        .where((l) => l['is_active'] == true)
        .toList();
    final inactiveLocations = widget.locations
        .where((l) => l['is_active'] != true)
        .toList();

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addOrEditLocation(),
        label: const Text('Add Location'),
        icon: const Icon(Icons.add_location),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
      body: widget.locations.isEmpty
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.location_off, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    'No locations found.\nAdd one to get started!',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey, fontSize: 16),
                  ),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: 80, top: 10),
              children: [
                if (activeLocations.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.check_circle,
                          color: Colors.green,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Active Locations (${activeLocations.length})',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ...activeLocations.map(
                    (location) => _buildLocationCard(location, true),
                  ),
                ],
                if (inactiveLocations.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                    child: Row(
                      children: [
                        const Icon(Icons.cancel, color: Colors.red, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Inactive Locations (${inactiveLocations.length})',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.red,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ...inactiveLocations.map(
                    (location) => _buildLocationCard(location, false),
                  ),
                ],
              ],
            ),
    );
  }

  Widget _buildLocationCard(Map<String, dynamic> location, bool isActive) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isActive ? Colors.green.shade100 : Colors.red.shade100,
          width: 1,
        ),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isActive ? Colors.green.shade50 : Colors.red.shade50,
          child: Icon(
            Icons.location_on,
            color: isActive ? Colors.green : Colors.red,
          ),
        ),
        title: Text(
          location['name'],
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        subtitle: Text(
          isActive ? 'Visible to users' : 'Hidden from users',
          style: TextStyle(
            color: isActive ? Colors.green.shade700 : Colors.red.shade700,
            fontSize: 12,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(
                isActive ? Icons.visibility_off : Icons.visibility,
                color: isActive ? Colors.orange : Colors.green,
              ),
              tooltip: isActive ? 'Deactivate' : 'Activate',
              onPressed: () => _toggleLocationStatus(location['id'], isActive),
            ),
            IconButton(
              icon: const Icon(Icons.edit_outlined, color: Colors.blue),
              tooltip: 'Edit',
              onPressed: () => _addOrEditLocation(
                id: location['id'],
                currentName: location['name'],
                currentIsActive: location['is_active'],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              tooltip: 'Delete',
              onPressed: () =>
                  _deleteLocation(location['id'], location['name']),
            ),
          ],
        ),
      ),
    );
  }
}
