// ==============================================================================
// SmartShelf V2 - Shop Location Selection Screen
// ==============================================================================

import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'onboarding_screen.dart';

class ShopSelectionScreen extends StatelessWidget {
  final AuthService authService;
  final VoidCallback onShopSelected;

  const ShopSelectionScreen({
    super.key,
    required this.authService,
    required this.onShopSelected,
  });

  @override
  Widget build(BuildContext context) {
    final shops = authService.authorizedShops;

    if (shops.isEmpty) {
      return OnboardingScreen(
        authService: authService,
        onStoreJoined: onShopSelected,
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text(
          'Select Store Location',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF0F172A),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_business_rounded, color: Color(0xFF4F46E5), size: 20),
            tooltip: 'Join or Create Store',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => OnboardingScreen(
                    authService: authService,
                    onStoreJoined: () {
                      Navigator.pop(context);
                      onShopSelected();
                    },
                  ),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded, size: 20),
            tooltip: 'Sign Out',
            onPressed: () => authService.signOut(),
          ),
        ],
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(20),
        itemCount: shops.length + 1,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          if (index == shops.length) {
            // Join / Create another store button at bottom
            return OutlinedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => OnboardingScreen(
                      authService: authService,
                      onStoreJoined: () {
                        Navigator.pop(context);
                        onShopSelected();
                      },
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Join or Create Another Store'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF4F46E5),
                side: BorderSide(color: Colors.indigo.shade200),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            );
          }

          final shop = shops[index];
          final isSelected = authService.selectedShop?.id == shop.id;

          return InkWell(
            onTap: () {
              authService.selectShop(shop);
              onShopSelected();
            },
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isSelected ? const Color(0xFF4F46E5) : Colors.grey.shade200,
                  width: isSelected ? 2 : 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.02),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFF4F46E5).withValues(alpha: 0.1)
                          : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.storefront_rounded,
                      color: isSelected
                          ? const Color(0xFF4F46E5)
                          : const Color(0xFF64748B),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          shop.name,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        if (shop.location != null && shop.location!.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            shop.location!,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ],
                        const SizedBox(height: 4),
                        Text(
                          'Currency: ${shop.currency}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.indigo.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 16,
                    color: Color(0xFF94A3B8),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
