import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../supabase_config.dart';

/// A full-screen circular profile picture viewer like Instagram
///
/// Usage:
/// ```dart
/// FullScreenProfileViewer.show(
///   context: context,
///   imageUrl: 'https://example.com/avatar.jpg',
///   heroTag: 'profile_123', // optional, for hero animation
///   userName: 'John Doe', // optional, shows name at bottom
/// );
/// ```
class FullScreenProfileViewer extends StatefulWidget {
  final String? imageUrl;
  final String? heroTag;
  final String? userName;

  const FullScreenProfileViewer({
    super.key,
    required this.imageUrl,
    this.heroTag,
    this.userName,
  });

  /// Static method to show the full screen viewer
  static void show({
    required BuildContext context,
    required String? imageUrl,
    String? heroTag,
    String? userName,
  }) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black87,
        barrierDismissible: true,
        pageBuilder: (context, animation, secondaryAnimation) {
          return FullScreenProfileViewer(
            imageUrl: imageUrl,
            heroTag: heroTag,
            userName: userName,
          );
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.8, end: 1.0).animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
              ),
              child: child,
            ),
          );
        },
        transitionDuration: const Duration(milliseconds: 300),
        reverseTransitionDuration: const Duration(milliseconds: 200),
      ),
    );
  }

  @override
  State<FullScreenProfileViewer> createState() =>
      _FullScreenProfileViewerState();
}

class _FullScreenProfileViewerState extends State<FullScreenProfileViewer>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  double _currentScale = 1.0;
  double _baseScale = 1.0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleDoubleTap() {
    if (_currentScale == 1.0) {
      setState(() => _currentScale = 2.0);
    } else {
      setState(() => _currentScale = 1.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final circleSize = size.width * 0.85; // 85% of screen width

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        child: Container(
          color: Colors.transparent,
          child: Stack(
            children: [
              // Main content - Profile picture
              Center(
                child: GestureDetector(
                  onTap: () {}, // Prevent closing when tapping on image
                  onDoubleTap: _handleDoubleTap,
                  onScaleStart: (details) {
                    _baseScale = _currentScale;
                  },
                  onScaleUpdate: (details) {
                    setState(() {
                      _currentScale = (_baseScale * details.scale).clamp(
                        1.0,
                        3.0,
                      );
                    });
                  },
                  onScaleEnd: (details) {
                    if (_currentScale < 1.2) {
                      setState(() => _currentScale = 1.0);
                    }
                  },
                  child: AnimatedScale(
                    scale: _currentScale,
                    duration: const Duration(milliseconds: 200),
                    child: Container(
                      width: circleSize,
                      height: circleSize,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.3),
                            blurRadius: 20,
                            spreadRadius: 5,
                          ),
                        ],
                      ),
                      child: ClipOval(
                        child: widget.heroTag != null
                            ? Hero(
                                tag: widget.heroTag!,
                                child: _buildImage(circleSize),
                              )
                            : _buildImage(circleSize),
                      ),
                    ),
                  ),
                ),
              ),

              // Close button
              Positioned(
                top: MediaQuery.of(context).padding.top + 16,
                right: 16,
                child: GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ),
              ),

              // User name at bottom (optional)
              if (widget.userName != null && widget.userName!.isNotEmpty)
                Positioned(
                  bottom: MediaQuery.of(context).padding.bottom + 40,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        widget.userName!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),

              // Zoom hint
              Positioned(
                bottom: MediaQuery.of(context).padding.bottom + 100,
                left: 0,
                right: 0,
                child: Center(
                  child: AnimatedOpacity(
                    opacity: _currentScale == 1.0 ? 0.7 : 0.0,
                    duration: const Duration(milliseconds: 300),
                    child: Text(
                      'Double tap to zoom',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImage(double size) {
    if (widget.imageUrl == null || widget.imageUrl!.isEmpty) {
      return Container(
        width: size,
        height: size,
        color: Colors.grey[300],
        child: Icon(Icons.person, size: size * 0.5, color: Colors.grey[600]),
      );
    }

    return CachedNetworkImage(
      imageUrl: SupabaseConfig.proxyImageUrl(widget.imageUrl),
      width: size,
      height: size,
      fit: BoxFit.cover,
      placeholder: (context, url) => Container(
        color: Colors.grey[300],
        child: const Center(
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Colors.deepPurple,
          ),
        ),
      ),
      errorWidget: (context, url, error) => Container(
        color: Colors.grey[300],
        child: Icon(Icons.person, size: size * 0.5, color: Colors.grey[600]),
      ),
    );
  }
}

/// A reusable tappable profile avatar widget
/// Automatically opens full screen viewer when tapped (unless it's the user's own profile)
class TappableProfileAvatar extends StatelessWidget {
  final String? imageUrl;
  final double size;
  final String? userName;
  final String? odId; // The ID of the profile being displayed
  final String? currentUserId; // The logged-in user's ID
  final String? heroTag;
  final VoidCallback? onTap; // Custom onTap override
  final BoxBorder? border;

  const TappableProfileAvatar({
    super.key,
    required this.imageUrl,
    this.size = 50,
    this.userName,
    this.odId,
    this.currentUserId,
    this.heroTag,
    this.onTap,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    // Check if this is the user's own profile
    final isOwnProfile =
        currentUserId != null && odId != null && currentUserId == odId;

    return GestureDetector(
      onTap: () {
        if (onTap != null) {
          onTap!();
        } else if (!isOwnProfile) {
          // Open full screen viewer only if not own profile
          FullScreenProfileViewer.show(
            context: context,
            imageUrl: imageUrl,
            heroTag: heroTag,
            userName: userName,
          );
        }
      },
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border:
              border ??
              Border.all(color: Colors.grey.withValues(alpha: 0.3), width: 1),
        ),
        child: heroTag != null
            ? Hero(
                tag: heroTag!,
                child: ClipOval(child: _buildImage()),
              )
            : ClipOval(child: _buildImage()),
      ),
    );
  }

  Widget _buildImage() {
    if (imageUrl == null || imageUrl!.isEmpty) {
      return Container(
        color: Colors.grey[300],
        child: Icon(Icons.person, size: size * 0.6, color: Colors.grey[600]),
      );
    }

    return CachedNetworkImage(
      imageUrl: SupabaseConfig.proxyImageUrl(imageUrl),
      fit: BoxFit.cover,
      placeholder: (context, url) => Container(
        color: Colors.grey[300],
        child: Icon(Icons.person, size: size * 0.6, color: Colors.grey[400]),
      ),
      errorWidget: (context, url, error) => Container(
        color: Colors.grey[300],
        child: Icon(Icons.person, size: size * 0.6, color: Colors.grey[600]),
      ),
    );
  }
}
