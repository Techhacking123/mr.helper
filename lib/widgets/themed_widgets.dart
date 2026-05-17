import 'package:flutter/material.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import '../models/festival_theme.dart';
import '../services/theme_service.dart';
import '../supabase_config.dart';

/// Widget that applies festival theme decorations and styling
class ThemedContainer extends StatelessWidget {
  final Widget child;
  final bool showDecorations;
  final bool showBanner;

  const ThemedContainer({
    super.key,
    required this.child,
    this.showDecorations = true,
    this.showBanner = false,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeService(),
      builder: (context, _) {
        final theme = ThemeService().activeTheme ?? ThemeService().defaultTheme;

        return Container(
          color: theme.backgroundColor,
          child: Stack(
            children: [
              // Background banner (if enabled and available)
              if (showBanner && theme.bannerImageUrl != null)
                _buildBanner(theme),

              // Main content
              child,

              // Decorative elements
              if (showDecorations)
                ...theme.decorativeElements.map(
                  (element) => _buildDecorativeElement(context, theme, element),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBanner(FestivalTheme theme) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        height: 200,
        decoration: BoxDecoration(
          image: DecorationImage(
            image: theme.bannerImageUrl!.startsWith('http')
                ? NetworkImage(
                        SupabaseConfig.proxyImageUrl(theme.bannerImageUrl!),
                      )
                      as ImageProvider
                : AssetImage(theme.bannerImageUrl!),
            fit: BoxFit.cover,
            opacity: 0.3,
          ),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              theme.primaryColor.withOpacity(0.2),
              theme.backgroundColor.withOpacity(0),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDecorativeElement(
    BuildContext context,
    FestivalTheme theme,
    DecorativeElement element,
  ) {
    // Get icon path from theme's icon pack
    final iconPath = theme.iconPack[element.type];
    if (iconPath == null) return const SizedBox.shrink();

    // Parse position
    final position = _parsePosition(context, element.position);

    return Positioned(
      top: position['top'],
      left: position['left'],
      right: position['right'],
      bottom: position['bottom'],
      child: IgnorePointer(
        child: Opacity(
          opacity: element.opacity ?? 0.4,
          child: Image.asset(
            iconPath,
            width: element.size ?? 60,
            height: element.size ?? 60,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) =>
                const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }

  Map<String, double?> _parsePosition(BuildContext context, String position) {
    final screenSize = MediaQuery.of(context).size;

    switch (position.toLowerCase()) {
      case 'top-left':
        return {'top': 10, 'left': 10, 'right': null, 'bottom': null};
      case 'top-right':
        return {'top': 10, 'left': null, 'right': 10, 'bottom': null};
      case 'top-center':
        return {
          'top': 10,
          'left': screenSize.width / 2 - 30,
          'right': null,
          'bottom': null,
        };
      case 'bottom-left':
        return {'top': null, 'left': 10, 'right': null, 'bottom': 10};
      case 'bottom-right':
        return {'top': null, 'left': null, 'right': 10, 'bottom': 10};
      case 'bottom-center':
        return {
          'top': null,
          'left': screenSize.width / 2 - 30,
          'right': null,
          'bottom': 10,
        };
      case 'center':
        return {
          'top': screenSize.height / 2 - 30,
          'left': screenSize.width / 2 - 30,
          'right': null,
          'bottom': null,
        };
      default:
        return {'top': 10, 'left': 10, 'right': null, 'bottom': null};
    }
  }
}

/// Themed card widget with festival colors
class ThemedCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;
  final EdgeInsets? margin;
  final double? elevation;
  final VoidCallback? onTap;

  const ThemedCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.elevation,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeService(),
      builder: (context, _) {
        final theme = ThemeService().activeTheme ?? ThemeService().defaultTheme;

        return Card(
          color: theme.cardColor,
          elevation: elevation ?? 2,
          margin:
              margin ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: theme.primaryColor.withOpacity(0.1),
              width: 1,
            ),
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: padding ?? const EdgeInsets.all(16),
              child: child,
            ),
          ),
        );
      },
    );
  }
}

/// Themed app bar with festival colors
class ThemedAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final List<Widget>? actions;
  final Widget? leading;
  final bool centerTitle;
  final PreferredSizeWidget? bottom;

  const ThemedAppBar({
    super.key,
    required this.title,
    this.actions,
    this.leading,
    this.centerTitle = true,
    this.bottom,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeService(),
      builder: (context, _) {
        final theme = ThemeService().activeTheme ?? ThemeService().defaultTheme;

        return AppBar(
          title: Text(
            title,
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          centerTitle: centerTitle,
          leading: leading,
          actions: actions,
          bottom: bottom,
          flexibleSpace: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [theme.primaryColor, theme.secondaryColor],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Size get preferredSize =>
      Size.fromHeight(kToolbarHeight + (bottom?.preferredSize.height ?? 0));
}

/// Themed button with festival colors
class ThemedButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isOutlined;
  final IconData? icon;
  final bool isLoading;

  const ThemedButton({
    super.key,
    required this.text,
    this.onPressed,
    this.isOutlined = false,
    this.icon,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeService(),
      builder: (context, _) {
        final theme = ThemeService().activeTheme ?? ThemeService().defaultTheme;

        if (isLoading) {
          return Center(
            child: SpinKitThreeBounce(color: theme.primaryColor, size: 24.0),
          );
        }

        if (isOutlined) {
          return OutlinedButton.icon(
            onPressed: onPressed,
            icon: icon != null
                ? Icon(icon, color: theme.primaryColor)
                : const SizedBox.shrink(),
            label: Text(text),
            style: OutlinedButton.styleFrom(
              foregroundColor: theme.primaryColor,
              side: BorderSide(color: theme.primaryColor, width: 2),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );
        }

        return ElevatedButton.icon(
          onPressed: onPressed,
          icon: icon != null
              ? Icon(icon, color: Colors.white)
              : const SizedBox.shrink(),
          label: Text(text),
          style: ElevatedButton.styleFrom(
            foregroundColor: Colors.white,
            backgroundColor: theme.primaryColor,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            elevation: 4,
          ),
        );
      },
    );
  }
}

/// Theme-aware gradient background
class ThemedGradientBackground extends StatelessWidget {
  final Widget child;

  const ThemedGradientBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeService(),
      builder: (context, _) {
        final theme = ThemeService().activeTheme ?? ThemeService().defaultTheme;

        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                theme.primaryColor.withOpacity(0.1),
                theme.secondaryColor.withOpacity(0.05),
                theme.backgroundColor,
              ],
            ),
          ),
          child: child,
        );
      },
    );
  }
}

/// Festival theme banner widget for home pages
class FestivalBanner extends StatelessWidget {
  final double height;
  final Widget? overlayWidget;

  const FestivalBanner({super.key, this.height = 150, this.overlayWidget});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeService(),
      builder: (context, _) {
        final theme = ThemeService().activeTheme ?? ThemeService().defaultTheme;

        debugPrint('🎪 FestivalBanner: Building with theme: ${theme.name}');
        debugPrint('🎪 FestivalBanner: Banner URL: ${theme.bannerImageUrl}');

        // Only show banner for festival themes (not default)
        if (theme.name == 'default' || theme.bannerImageUrl == null) {
          debugPrint(
            '🎪 FestivalBanner: Hiding banner (theme is default or no banner URL)',
          );
          return const SizedBox.shrink();
        }

        debugPrint(
          '🎪 FestivalBanner: Showing banner for ${theme.displayName}',
        );

        return Container(
          height: height,
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: theme.primaryColor.withOpacity(0.3),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Banner image
                theme.bannerImageUrl!.startsWith('http')
                    ? Image.network(
                        SupabaseConfig.proxyImageUrl(theme.bannerImageUrl!),
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  theme.primaryColor,
                                  theme.secondaryColor,
                                ],
                              ),
                            ),
                          );
                        },
                      )
                    : Image.asset(
                        theme.bannerImageUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  theme.primaryColor,
                                  theme.secondaryColor,
                                ],
                              ),
                            ),
                          );
                        },
                      ),

                // Gradient overlay
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withOpacity(0.3),
                        Colors.black.withOpacity(0.6),
                      ],
                    ),
                  ),
                ),

                // Content overlay
                if (overlayWidget != null)
                  Positioned.fill(child: overlayWidget!),

                // Festival name badge
                Positioned(
                  bottom: 12,
                  right: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: theme.accentColor,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                    child: Text(
                      '✨ ${theme.displayName}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
