// lib/models/restaurant.dart
// All restaurant-related models used across the app.

import 'package:flutter/foundation.dart';

/// Full Restaurant model (from your schema).
class Restaurant {
  final String id;
  final String name;
  final String username;
  final String password;
  final DateTime? createdAt;
  final String? ownerId;
  final String? logoUrl;
  final String? coverUrl;
  final String? description;
  final int? prepTimeMin;
  final int? prepTimeMax;
  final String? category;
  final double? deliveryFee;
  final String? coverPath;
  final String? logoPath;
  final bool isOpen;

  Restaurant({
    required this.id,
    required this.name,
    required this.username,
    required this.password,
    this.createdAt,
    this.ownerId,
    this.logoUrl,
    this.coverUrl,
    this.description,
    this.prepTimeMin,
    this.prepTimeMax,
    this.category,
    this.deliveryFee,
    this.coverPath,
    this.logoPath,
    this.isOpen = false,
  });

  factory Restaurant.fromJson(Map<String, dynamic> json) {
    return Restaurant(
      id: json['id'] as String,
      name: json['name'] as String,
      username: json['username'] as String,
      password: json['password'] as String,
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at']) : null,
      ownerId: json['owner_id'] as String?,
      logoUrl: json['logo_url'] as String?,
      coverUrl: json['cover_url'] as String?,
      description: json['description'] as String?,
      prepTimeMin: json['prep_time_min'] as int?,
      prepTimeMax: json['prep_time_max'] as int?,
      category: json['category'] as String?,
      deliveryFee: json['delivery_fee'] != null ? double.tryParse(json['delivery_fee'].toString()) : null,
      coverPath: json['cover_path'] as String?,
      logoPath: json['logo_path'] as String?,
      isOpen: json['is_open'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'username': username,
      'password': password,
      'created_at': createdAt?.toIso8601String(),
      'owner_id': ownerId,
      'logo_url': logoUrl,
      'cover_url': coverUrl,
      'description': description,
      'prep_time_min': prepTimeMin,
      'prep_time_max': prepTimeMax,
      'category': category,
      'delivery_fee': deliveryFee,
      'cover_path': coverPath,
      'logo_path': logoPath,
      'is_open': isOpen,
    };
  }
}

/// Small subset used by the detail screen (faster to fetch).
class RestaurantBasic {
  final String id;
  final String name;
  final String? logoUrl;
  final String? coverUrl;
  final String? description;
  final int? prepMin;
  final int? prepMax;
  final double? deliveryFee;

  RestaurantBasic({
    required this.id,
    required this.name,
    this.logoUrl,
    this.coverUrl,
    this.description,
    this.prepMin,
    this.prepMax,
    this.deliveryFee,
  });

  factory RestaurantBasic.fromMap(Map<String, dynamic> m) {
    return RestaurantBasic(
      id: m['id'] as String,
      name: m['name'] ?? '',
      logoUrl: m['logo_url'] as String?,
      coverUrl: m['cover_url'] as String?,
      description: m['description'] as String?,
      prepMin: m['prep_time_min'] as int?,
      prepMax: m['prep_time_max'] as int?,
      deliveryFee: m['delivery_fee'] != null ? double.tryParse(m['delivery_fee'].toString()) : null,
    );
  }
}

/// Menu item model used in the detail screen.
class MenuItemModel {
  final String id;
  final String name;
  final String? description;
  final double price;
  final String? imageUrl;
  final String? categoryId;

  MenuItemModel({
    required this.id,
    required this.name,
    this.description,
    required this.price,
    this.imageUrl,
    this.categoryId,
  });

  factory MenuItemModel.fromMap(Map<String, dynamic> m) {
    return MenuItemModel(
      id: m['id'] as String,
      name: m['name'] ?? '',
      description: m['description'] as String?,
      price: (m['price'] as num).toDouble(),
      imageUrl: m['image_url'] as String?,
      categoryId: m['category_id'] as String?,
    );
  }
}

/// Short category representation.
class CategoryShort {
  final String id;
  final String name;

  CategoryShort({required this.id, required this.name});

  factory CategoryShort.fromMap(Map<String, dynamic> m) {
    return CategoryShort(id: m['id'] as String, name: m['name'] ?? '');
  }
}
