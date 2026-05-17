import 'dart:convert';
import 'package:flutter/material.dart';

class FestivalTheme {
  final String id;
  final String name;
  final String displayName;
  final String? description;
  final bool isActive;
  final int priority;

  // Theme colors
  final Color primaryColor;
  final Color secondaryColor;
  final Color accentColor;
  final Color backgroundColor;
  final Color textColor;
  final Color cardColor;

  // Theme assets
  final String? bannerImageUrl;
  final Map<String, String> iconPack;
  final List<DecorativeElement> decorativeElements;

  // Metadata
  final DateTime createdAt;
  final DateTime updatedAt;

  FestivalTheme({
    required this.id,
    required this.name,
    required this.displayName,
    this.description,
    required this.isActive,
    required this.priority,
    required this.primaryColor,
    required this.secondaryColor,
    required this.accentColor,
    required this.backgroundColor,
    required this.textColor,
    required this.cardColor,
    this.bannerImageUrl,
    required this.iconPack,
    required this.decorativeElements,
    required this.createdAt,
    required this.updatedAt,
  });

  factory FestivalTheme.fromJson(Map<String, dynamic> json) {
    return FestivalTheme(
      id: json['id'] as String,
      name: json['name'] as String,
      displayName: json['display_name'] as String,
      description: json['description'] as String?,
      isActive: json['is_active'] as bool? ?? false,
      priority: json['priority'] as int? ?? 0,
      primaryColor: _parseColor(json['primary_color'] as String),
      secondaryColor: _parseColor(json['secondary_color'] as String),
      accentColor: _parseColor(json['accent_color'] as String),
      backgroundColor: _parseColor(json['background_color'] as String),
      textColor: _parseColor(json['text_color'] as String),
      cardColor: _parseColor(json['card_color'] as String),
      bannerImageUrl: json['banner_image_url'] as String?,
      iconPack: _parseIconPack(json['icon_pack'] as String?),
      decorativeElements: _parseDecorativeElements(
        json['decorative_elements'] as String?,
      ),
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'display_name': displayName,
      'description': description,
      'is_active': isActive,
      'priority': priority,
      'primary_color': _colorToHex(primaryColor),
      'secondary_color': _colorToHex(secondaryColor),
      'accent_color': _colorToHex(accentColor),
      'background_color': _colorToHex(backgroundColor),
      'text_color': _colorToHex(textColor),
      'card_color': _colorToHex(cardColor),
      'banner_image_url': bannerImageUrl,
      'icon_pack': jsonEncode(iconPack),
      'decorative_elements': jsonEncode(
        decorativeElements.map((e) => e.toJson()).toList(),
      ),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  static Color _parseColor(String hexColor) {
    // Remove # if present
    hexColor = hexColor.replaceAll('#', '');

    // Add FF for alpha if not present
    if (hexColor.length == 6) {
      hexColor = 'FF$hexColor';
    }

    return Color(int.parse(hexColor, radix: 16));
  }

  static String _colorToHex(Color color) {
    return '#${color.value.toRadixString(16).substring(2).toUpperCase()}';
  }

  static Map<String, String> _parseIconPack(String? iconPackJson) {
    if (iconPackJson == null || iconPackJson.isEmpty || iconPackJson == '{}') {
      return {};
    }

    try {
      final Map<String, dynamic> decoded = jsonDecode(iconPackJson);
      return decoded.map((key, value) => MapEntry(key, value.toString()));
    } catch (e) {
      return {};
    }
  }

  static List<DecorativeElement> _parseDecorativeElements(
    String? elementsJson,
  ) {
    if (elementsJson == null || elementsJson.isEmpty || elementsJson == '[]') {
      return [];
    }

    try {
      final List<dynamic> decoded = jsonDecode(elementsJson);
      return decoded
          .map((e) => DecorativeElement.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      return [];
    }
  }

  FestivalTheme copyWith({
    String? id,
    String? name,
    String? displayName,
    String? description,
    bool? isActive,
    int? priority,
    Color? primaryColor,
    Color? secondaryColor,
    Color? accentColor,
    Color? backgroundColor,
    Color? textColor,
    Color? cardColor,
    String? bannerImageUrl,
    Map<String, String>? iconPack,
    List<DecorativeElement>? decorativeElements,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return FestivalTheme(
      id: id ?? this.id,
      name: name ?? this.name,
      displayName: displayName ?? this.displayName,
      description: description ?? this.description,
      isActive: isActive ?? this.isActive,
      priority: priority ?? this.priority,
      primaryColor: primaryColor ?? this.primaryColor,
      secondaryColor: secondaryColor ?? this.secondaryColor,
      accentColor: accentColor ?? this.accentColor,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      textColor: textColor ?? this.textColor,
      cardColor: cardColor ?? this.cardColor,
      bannerImageUrl: bannerImageUrl ?? this.bannerImageUrl,
      iconPack: iconPack ?? this.iconPack,
      decorativeElements: decorativeElements ?? this.decorativeElements,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class DecorativeElement {
  final String type;
  final String position;
  final double? size;
  final double? opacity;

  DecorativeElement({
    required this.type,
    required this.position,
    this.size,
    this.opacity,
  });

  factory DecorativeElement.fromJson(Map<String, dynamic> json) {
    return DecorativeElement(
      type: json['type'] as String,
      position: json['position'] as String,
      size: json['size'] != null ? (json['size'] as num).toDouble() : null,
      opacity: json['opacity'] != null
          ? (json['opacity'] as num).toDouble()
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'position': position,
      if (size != null) 'size': size,
      if (opacity != null) 'opacity': opacity,
    };
  }
}
