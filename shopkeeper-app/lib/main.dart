// ==============================================================================
// SmartShelf V2 - Shopkeeper Mobile Application Entrypoint
// ==============================================================================

import 'package:flutter/material.dart';
import 'config/supabase_config.dart';
import 'screens/auth_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/shop_selection_screen.dart';
import 'services/auth_service.dart';
import 'services/cart_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Supabase client using compile-time or local fallback configuration
  try {
    await SupabaseConfig.initialize();
  } catch (err) {
    debugPrint('Supabase initialization error: $err');
  }

  runApp(const SmartShelfApp());
}

class SmartShelfApp extends StatefulWidget {
  const SmartShelfApp({super.key});

  @override
  State<SmartShelfApp> createState() => _SmartShelfAppState();
}

class _SmartShelfAppState extends State<SmartShelfApp> {
  late final AuthService _authService;
  late final CartService _cartService;

  @override
  void initState() {
    super.initState();
    _authService = AuthService();
    _cartService = CartService();
  }

  @override
  void dispose() {
    _authService.dispose();
    _cartService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SmartShelf POS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF4F46E5),
          primary: const Color(0xFF4F46E5),
          secondary: const Color(0xFF16A34A),
          surface: Colors.white,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Color(0xFF0F172A),
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: false,
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.grey.shade200),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF4F46E5), width: 2),
          ),
        ),
      ),
      home: ListenableBuilder(
        listenable: _authService,
        builder: (context, _) {
          if (_authService.isLoading) {
            return const Scaffold(
              body: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: Color(0xFF4F46E5)),
                    SizedBox(height: 16),
                    Text(
                      'Loading SmartShelf...',
                      style: TextStyle(
                        fontSize: 14,
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          // 1. Not Authenticated -> Show Sign-In screen
          if (!_authService.isAuthenticated) {
            return AuthScreen(authService: _authService);
          }

          // 2. Authenticated but no Shop selected -> Show Shop Selection screen
          if (_authService.selectedShop == null) {
            return ShopSelectionScreen(
              authService: _authService,
              onShopSelected: () {
                setState(() {});
              },
            );
          }

          // 3. Authenticated and Shop Selected -> Show Main Dashboard
          return DashboardScreen(
            authService: _authService,
            cartService: _cartService,
          );
        },
      ),
    );
  }
}
