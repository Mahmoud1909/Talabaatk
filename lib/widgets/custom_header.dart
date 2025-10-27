// lib/widgets/custom_header.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:talabak_users/screens/cart_screen.dart';
import 'package:talabak_users/services/cart_api.dart';
import 'package:talabak_users/services/cart_service.dart';
import 'package:talabak_users/utils/settings_screen.dart';
import 'package:talabak_users/l10n/app_localizations.dart';

class CustomHeader extends StatelessWidget {
  const CustomHeader({super.key});

  final String fallbackImageUrl =
      'https://www.example.com/default-avatar.png';

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final User? user = FirebaseAuth.instance.currentUser;

    final String displayName = user?.displayName ?? loc.guest;
    final List<String> nameParts = displayName.trim().split(RegExp(r'\s+'));
    final String firstName = nameParts.isNotEmpty ? nameParts.first : '';
    final String lastName = nameParts.length > 1 ? nameParts.sublist(1).join(' ') : '';
    final String? photoUrl = user?.photoURL;

    return Container(
      color: const Color(0xFF25AA50),
      child: SafeArea(
        bottom: false,
        child: Container(
          height: 72,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              // صورة + اسم المستخدم
              Expanded(
                child: Row(
                  children: [
                    Semantics(
                      label: displayName.isNotEmpty ? displayName : loc.guest,
                      child: CircleAvatar(
                        radius: 24,
                        backgroundColor: Colors.white.withOpacity(0.2),
                        child: ClipOval(
                          child: SizedBox.expand(
                            child: _buildUserAvatar(photoUrl),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        "$firstName ${lastName.isNotEmpty ? lastName : ''}".trim(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // الأيقونات (يمين)
              Row(
                children: [
                  IconButton(
                    tooltip: loc.cart,
                    onPressed: () async {
                      await CartService.instance.loadFromLocal();
                      unawaited(CartApi.fetchAndSyncAllUserCarts());
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const CartScreen()),
                      );
                    },
                    icon: const Icon(Icons.shopping_cart, color: Colors.white),
                  ),
                  IconButton(
                    tooltip: loc.settings,
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const SettingsScreen()),
                      );
                    },
                    icon: const Icon(Icons.settings, color: Colors.white),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUserAvatar(String? photoUrl) {
    if (photoUrl == null || photoUrl.isEmpty) {
      return _networkImageWithFallback(fallbackImageUrl);
    }
    return Image.network(
      photoUrl,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) {
        return _networkImageWithFallback(fallbackImageUrl);
      },
    );
  }

  Widget _networkImageWithFallback(String url) {
    return Image.network(
      url,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) {
        return const Icon(Icons.person, color: Colors.white, size: 28);
      },
    );
  }
}
