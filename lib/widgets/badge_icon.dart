import 'package:flutter/material.dart';

class BadgeIcon extends StatelessWidget {
  final Widget icon;
  final bool showBadge;
  final Color badgeColor;

  const BadgeIcon({
    super.key,
    required this.icon,
    this.showBadge = false,
    this.badgeColor = Colors.red,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        icon,
        if (showBadge)
          Positioned(
            right: 0,
            top: 0,
            child: Container(
              padding: const EdgeInsets.all(1),
              decoration: BoxDecoration(
                color: badgeColor,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              constraints: const BoxConstraints(minWidth: 10, minHeight: 10),
            ),
          ),
      ],
    );
  }
}
