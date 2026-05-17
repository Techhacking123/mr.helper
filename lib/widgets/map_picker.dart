import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';

class MapPicker extends StatefulWidget {
  final double? initialLat;
  final double? initialLng;

  const MapPicker({super.key, this.initialLat, this.initialLng});

  /// Checks if location services are enabled and permissions granted,
  /// then opens the MapPicker. Returns the result map or null.
  static Future<Map<String, dynamic>?> checkLocationAndOpen(
    BuildContext context, {
    double? initialLat,
    double? initialLng,
  }) async {
    // 1. Check if location services are enabled
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (!context.mounted) return null;
      final turnOn = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          icon: Icon(
            Icons.location_off_rounded,
            color: Colors.orange.shade700,
            size: 48,
          ),
          title: const Text(
            'Location Services Off',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: const Text(
            'Location services are turned off. Please enable GPS to pick a location on the map.',
            textAlign: TextAlign.center,
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(
                'Cancel',
                style: TextStyle(color: Colors.grey.shade600),
              ),
            ),
            ElevatedButton.icon(
              onPressed: () async {
                Navigator.pop(ctx, true);
              },
              icon: const Icon(Icons.settings, size: 18),
              label: const Text('Open Settings'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange.shade700,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        ),
      );

      if (turnOn == true) {
        await Geolocator.openLocationSettings();
        // Re-check after returning from settings
        serviceEnabled = await Geolocator.isLocationServiceEnabled();
        if (!serviceEnabled) return null;
      } else {
        return null;
      }
    }

    // 2. Check permissions
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (!context.mounted) return null;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Location permission is required to pick a location.',
            ),
            backgroundColor: Colors.red.shade600,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
        return null;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      if (!context.mounted) return null;
      final openSettings = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          icon: Icon(
            Icons.location_disabled_rounded,
            color: Colors.red.shade700,
            size: 48,
          ),
          title: const Text(
            'Permission Denied',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: const Text(
            'Location permission is permanently denied. Please enable it from app settings.',
            textAlign: TextAlign.center,
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(
                'Cancel',
                style: TextStyle(color: Colors.grey.shade600),
              ),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.settings, size: 18),
              label: const Text('App Settings'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade700,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        ),
      );

      if (openSettings == true) {
        await Geolocator.openAppSettings();
      }
      return null;
    }

    // 3. All good — open the MapPicker
    if (!context.mounted) return null;
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            MapPicker(initialLat: initialLat, initialLng: initialLng),
      ),
    );

    if (result != null && result is Map) {
      return Map<String, dynamic>.from(result);
    }
    return null;
  }

  @override
  State<MapPicker> createState() => _MapPickerState();
}

class _MapPickerState extends State<MapPicker> {
  final MapController _mapController = MapController();
  LatLng _center = const LatLng(17.3850, 78.4867); // Default: Hyderabad
  String _address = "Move map to select location...";
  bool _isLoading = true;
  bool _isGettingAddress = false;
  bool _mapReady = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialLat != null && widget.initialLng != null) {
      _center = LatLng(widget.initialLat!, widget.initialLng!);
      _isLoading = false;
      _getAddress(_center);
    } else {
      _getCurrentLocation();
    }
  }

  Future<void> _getCurrentLocation() async {
    try {
      setState(() => _isLoading = true);

      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint("Location services disabled");
        if (mounted) {
          setState(() => _isLoading = false);
          _showLocationError(
            'Location services are disabled. Please enable GPS.',
          );
        }
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          debugPrint("Location permission denied");
          if (mounted) {
            setState(() => _isLoading = false);
            _showLocationError('Location permission denied.');
          }
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        debugPrint("Location permission denied forever");
        if (mounted) {
          setState(() => _isLoading = false);
          _showLocationError(
            'Location permission permanently denied. Please enable in Settings.',
          );
        }
        return;
      }

      final pos =
          await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.medium,
            ),
          ).timeout(
            const Duration(seconds: 15),
            onTimeout: () {
              throw Exception('Location request timed out. Please try again.');
            },
          );
      final newCenter = LatLng(pos.latitude, pos.longitude);

      if (mounted) {
        setState(() {
          _center = newCenter;
          _isLoading = false;
        });
        if (_mapReady) {
          _mapController.move(_center, 15);
        }
        _getAddress(_center);
      }
    } catch (e) {
      debugPrint("Loc Error: $e");
      if (mounted) {
        setState(() => _isLoading = false);
        _showLocationError(
          'Could not get location: ${e.toString().replaceAll('Exception: ', '')}',
        );
      }
    }
  }

  void _showLocationError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.location_off, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'Settings',
          textColor: Colors.white,
          onPressed: () => Geolocator.openAppSettings(),
        ),
      ),
    );
  }

  Future<void> _getAddress(LatLng pos) async {
    if (_isGettingAddress) return;
    setState(() => _isGettingAddress = true);
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(
        pos.latitude,
        pos.longitude,
      );

      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        final address = [
          p.street,
          p.subLocality,
          p.locality,
          p.postalCode,
        ].where((e) => e != null && e.isNotEmpty).join(', ');

        if (mounted) {
          setState(() => _address = address);
        }
      }
    } catch (e) {
      debugPrint("Geocode Error: $e");
    } finally {
      if (mounted) setState(() => _isGettingAddress = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pick Location')),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _center,
              initialZoom: 15,
              onMapReady: () {
                _mapReady = true;
                if (!_isLoading) {
                  _mapController.move(_center, 15);
                }
              },
              onPositionChanged: (pos, hasGesture) {
                if (hasGesture) {
                  setState(() => _center = pos.center);
                }
              },
              onMapEvent: (evt) {
                if (evt is MapEventMoveEnd) {
                  _getAddress(_center);
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.mrhelper.ai',
              ),
            ],
          ),

          // Center Pin
          const Center(
            child: Padding(
              padding: EdgeInsets.only(
                bottom: 40,
              ), // Lift pin slightly to match tip
              child: Icon(Icons.location_pin, size: 50, color: Colors.red),
            ),
          ),

          // Search / My Location Button
          Positioned(
            top: 20,
            right: 20,
            child: FloatingActionButton(
              mini: true,
              heroTag: 'my_loc',
              onPressed: _getCurrentLocation,
              child: const Icon(Icons.my_location),
            ),
          ),

          // Confirm Button
          Positioned(
            bottom: 30,
            left: 20,
            right: 20,
            child: Card(
              elevation: 8,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.location_on, color: Colors.blue),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _isGettingAddress
                                ? "Fetching address..."
                                : _address,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pop(context, {
                            'lat': _center.latitude,
                            'lng': _center.longitude,
                            'address': _address,
                          });
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('CONFIRM LOCATION'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          if (_isLoading)
            Container(
              color: Colors.black54,
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}
