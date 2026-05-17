import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'full_screen_profile_viewer.dart';
import '../supabase_config.dart';

/// A robust network image widget that handles errors gracefully,
/// uses disk/memory caching, and prevents connection errors from crashing the app.
class SafeNetworkImage extends StatelessWidget {
  final String? imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget? placeholder;
  final Widget? errorWidget;
  final BorderRadius? borderRadius;
  final BoxShape shape;
  final Color? backgroundColor;

  const SafeNetworkImage({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.errorWidget,
    this.borderRadius,
    this.shape = BoxShape.rectangle,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final proxiedUrl = SupabaseConfig.proxyImageUrl(imageUrl);
    // Handle null or empty URLs
    if (proxiedUrl.isEmpty) {
      return _buildContainer(child: errorWidget ?? _defaultErrorWidget());
    }

    return _buildContainer(
      child: CachedNetworkImage(
        imageUrl: proxiedUrl,
        width: width,
        height: height,
        fit: fit,
        memCacheWidth: width != null ? (width! * 2).toInt() : null,
        memCacheHeight: height != null ? (height! * 2).toInt() : null,
        fadeInDuration: const Duration(milliseconds: 200),
        fadeOutDuration: const Duration(milliseconds: 200),
        placeholder: (context, url) => placeholder ?? _defaultPlaceholder(),
        errorWidget: (context, url, error) {
          debugPrint('SafeNetworkImage error loading $url: $error');
          return errorWidget ?? _defaultErrorWidget();
        },
      ),
    );
  }

  Widget _buildContainer({required Widget child}) {
    if (shape == BoxShape.circle) {
      return ClipOval(
        child: Container(
          width: width,
          height: height,
          color: backgroundColor ?? Colors.grey.shade200,
          child: child,
        ),
      );
    }

    if (borderRadius != null) {
      return ClipRRect(
        borderRadius: borderRadius!,
        child: Container(
          width: width,
          height: height,
          color: backgroundColor ?? Colors.grey.shade200,
          child: child,
        ),
      );
    }

    return Container(
      width: width,
      height: height,
      color: backgroundColor ?? Colors.grey.shade200,
      child: child,
    );
  }

  Widget _defaultPlaceholder() {
    return Container(
      width: width,
      height: height,
      color: Colors.grey.shade200,
      child: Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Colors.grey.shade400,
          ),
        ),
      ),
    );
  }

  Widget _defaultErrorWidget() {
    return Container(
      width: width,
      height: height,
      color: Colors.grey.shade200,
      child: Icon(
        Icons.person,
        color: Colors.grey.shade400,
        size: (width ?? 40) * 0.5,
      ),
    );
  }
}

/// A specialized avatar widget for user profile pictures
/// Now with full screen viewer support (like Instagram)
class SafeAvatar extends StatelessWidget {
  final String? imageUrl;
  final double radius;
  final Widget? fallbackIcon;
  final Color? backgroundColor;

  /// Enable full screen viewer on tap (default: true)
  final bool enableFullScreen;

  /// User name to show in full screen viewer
  final String? userName;

  /// The ID of the profile being displayed
  final String? odId;

  /// The logged-in user's ID (if same as odId, full screen is disabled)
  final String? currentUserId;

  /// Custom onTap handler (overrides full screen behavior)
  final VoidCallback? onTap;

  const SafeAvatar({
    super.key,
    required this.imageUrl,
    this.radius = 24,
    this.fallbackIcon,
    this.backgroundColor,
    this.enableFullScreen = true,
    this.userName,
    this.odId,
    this.currentUserId,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final size = radius * 2;
    final bgColor = backgroundColor ?? Colors.grey.shade200;

    // Check if this is the user's own profile
    final isOwnProfile =
        currentUserId != null && odId != null && currentUserId == odId;

    // Should we enable tap to view full screen?
    final canOpenFullScreen =
        enableFullScreen && !isOwnProfile && onTap == null;

    Widget avatar;
    final proxiedUrl = SupabaseConfig.proxyImageUrl(imageUrl);

    if (proxiedUrl.isEmpty) {
      avatar = CircleAvatar(
        radius: radius,
        backgroundColor: bgColor,
        child:
            fallbackIcon ??
            Icon(Icons.person, color: Colors.grey.shade400, size: radius),
      );
    } else {
      avatar = CachedNetworkImage(
        imageUrl: proxiedUrl,
        width: size,
        height: size,
        memCacheWidth: (size * 2).toInt(),
        memCacheHeight: (size * 2).toInt(),
        fit: BoxFit.cover,
        fadeInDuration: const Duration(milliseconds: 200),
        imageBuilder: (context, imageProvider) => CircleAvatar(
          radius: radius,
          backgroundColor: bgColor,
          backgroundImage: imageProvider,
        ),
        placeholder: (context, url) => CircleAvatar(
          radius: radius,
          backgroundColor: bgColor,
          child: SizedBox(
            width: radius * 0.6,
            height: radius * 0.6,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.grey.shade400,
            ),
          ),
        ),
        errorWidget: (context, url, error) {
          debugPrint('SafeAvatar error loading $url: $error');
          return CircleAvatar(
            radius: radius,
            backgroundColor: bgColor,
            child:
                fallbackIcon ??
                Icon(Icons.person, color: Colors.grey.shade400, size: radius),
          );
        },
      );
    }

    // Wrap with GestureDetector if tappable
    if (onTap != null || canOpenFullScreen) {
      return GestureDetector(
        onTap: () {
          if (onTap != null) {
            onTap!();
          } else if (canOpenFullScreen) {
            FullScreenProfileViewer.show(
              context: context,
              imageUrl: imageUrl,
              userName: userName,
            );
          }
        },
        child: avatar,
      );
    }

    return avatar;
  }
}

/// Provides a safe ImageProvider for use with existing CircleAvatar/Image widgets.
/// Falls back gracefully on error.
class SafeNetworkImageProvider {
  /// Returns a CachedNetworkImageProvider if url is valid, null otherwise.
  /// Use with null-aware operators: `backgroundImage: SafeNetworkImageProvider.get(url)`
  static ImageProvider? get(String? url) {
    final proxiedUrl = SupabaseConfig.proxyImageUrl(url);
    if (proxiedUrl.isEmpty) return null;
    return CachedNetworkImageProvider(proxiedUrl);
  }
}
