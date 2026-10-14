// ==============================================================================
// SmartShelf V2 - Authentication & Shop Authorization Service
// ==============================================================================

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import '../models/shop.dart';

class SignUpResult {
  final bool success;
  final bool requiresEmailConfirmation;
  final String? message;

  const SignUpResult({
    required this.success,
    this.requiresEmailConfirmation = false,
    this.message,
  });
}

class AuthService extends ChangeNotifier {
  static const Duration _networkTimeout = Duration(seconds: 12);

  final SupabaseClient? _client;
  User? _currentUser;
  String? _userFullName;
  List<Shop> _authorizedShops = [];
  Shop? _selectedShop;
  bool _isLoading = true;
  String? _errorMessage;

  AuthService({SupabaseClient? client}) : _client = client ?? _tryResolveClient() {
    final c = _client;
    if (c != null) {
      _initAuth(c);
    } else {
      _isLoading = false;
    }
  }

  static SupabaseClient? _tryResolveClient() {
    try {
      return SupabaseConfig.client;
    } catch (_) {
      return null;
    }
  }

  User? get currentUser => _currentUser;
  bool get isAuthenticated => _currentUser != null;
  String? get userFullName => _userFullName;
  List<Shop> get authorizedShops => _authorizedShops;
  Shop? get selectedShop => _selectedShop;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  void _initAuth(SupabaseClient client) {
    _currentUser = client.auth.currentUser;
    client.auth.onAuthStateChange.listen((data) async {
      _currentUser = data.session?.user;
      if (_currentUser != null) {
        await loadUserTenantContext();
      } else {
        _userFullName = null;
        _authorizedShops = [];
        _selectedShop = null;
        _isLoading = false;
        notifyListeners();
      }
    });

    if (_currentUser != null) {
      loadUserTenantContext();
    } else {
      _isLoading = false;
    }
  }

  /// Authenticates user credentials via Supabase GoTrue Auth
  Future<bool> signIn(String email, String password) async {
    final client = _client;
    if (client == null) {
      _errorMessage = 'Supabase client is not initialized.';
      _isLoading = false;
      notifyListeners();
      return false;
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final res = await client.auth
          .signInWithPassword(
            email: email.trim(),
            password: password,
          )
          .timeout(_networkTimeout);

      _currentUser = res.user;
      if (_currentUser != null) {
        await loadUserTenantContext();
        return true;
      } else {
        _errorMessage = 'Authentication failed: No user returned';
        _isLoading = false;
        notifyListeners();
        return false;
      }
    } on TimeoutException {
      _errorMessage =
          'Network timeout: Server did not respond within ${_networkTimeout.inSeconds} seconds. Check ADB reverse port forwarding.';
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (err) {
      _errorMessage = _cleanErrorMessage(err);
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Registers a new user account with Supabase GoTrue Auth
  Future<SignUpResult> signUp({
    required String email,
    required String password,
    required String fullName,
  }) async {
    final client = _client;
    if (client == null) {
      _errorMessage = 'Supabase client is not initialized.';
      _isLoading = false;
      notifyListeners();
      return const SignUpResult(
        success: false,
        message: 'Supabase client is not initialized.',
      );
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final res = await client.auth
          .signUp(
            email: email.trim(),
            password: password,
            data: {'full_name': fullName.trim()},
          )
          .timeout(_networkTimeout);

      final user = res.user;
      final session = res.session;

      if (user == null) {
        _errorMessage = 'Registration failed: No user returned from server.';
        _isLoading = false;
        notifyListeners();
        return SignUpResult(success: false, message: _errorMessage);
      }

      if (session == null) {
        // Email confirmation is required by Supabase Auth configuration
        _isLoading = false;
        _errorMessage = null;
        notifyListeners();
        return SignUpResult(
          success: true,
          requiresEmailConfirmation: true,
          message:
              'Account created! A verification link has been sent to ${user.email}. Please verify your email before signing in.',
        );
      }

      _currentUser = user;
      _userFullName = fullName.trim();
      await loadUserTenantContext();
      return const SignUpResult(success: true, requiresEmailConfirmation: false);
    } on TimeoutException {
      _errorMessage =
          'Network timeout: Registration timed out. Please check your network or ADB reverse port forwarding.';
      _isLoading = false;
      notifyListeners();
      return SignUpResult(success: false, message: _errorMessage);
    } catch (err) {
      _errorMessage = _cleanErrorMessage(err);
      _isLoading = false;
      notifyListeners();
      return SignUpResult(success: false, message: _errorMessage);
    }
  }

  /// Requests a password reset email via Supabase GoTrue Auth
  Future<bool> sendPasswordReset(String email) async {
    final client = _client;
    if (client == null) {
      _errorMessage = 'Supabase client is not initialized.';
      notifyListeners();
      return false;
    }

    _errorMessage = null;
    try {
      await client.auth
          .resetPasswordForEmail(email.trim())
          .timeout(_networkTimeout);
      return true;
    } catch (err) {
      _errorMessage = _cleanErrorMessage(err);
      notifyListeners();
      return false;
    }
  }

  /// Resends signup email confirmation
  Future<bool> resendVerificationEmail(String email) async {
    final client = _client;
    if (client == null) {
      _errorMessage = 'Supabase client is not initialized.';
      notifyListeners();
      return false;
    }

    _errorMessage = null;
    try {
      await client.auth
          .resend(type: OtpType.signup, email: email.trim())
          .timeout(_networkTimeout);
      return true;
    } catch (err) {
      _errorMessage = _cleanErrorMessage(err);
      notifyListeners();
      return false;
    }
  }

  /// Redeems a store invitation code to join an existing shop
  Future<Map<String, dynamic>?> redeemInvitation(String inviteCode) async {
    final client = _client;
    if (client == null) {
      _errorMessage = 'Supabase client is not initialized.';
      _isLoading = false;
      notifyListeners();
      return null;
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final res = await client.rpc(
        'redeem_shop_invitation',
        params: {'p_invite_code': inviteCode.trim().toUpperCase()},
      ).timeout(_networkTimeout);

      final data = Map<String, dynamic>.from(res as Map);
      await loadUserTenantContext();
      return data;
    } catch (err) {
      _errorMessage = _cleanErrorMessage(err);
      _isLoading = false;
      notifyListeners();
      return null;
    }
  }

  /// Provisions a new organization and primary store atomically (Option B)
  Future<Map<String, dynamic>?> createOrganizationAndShop({
    required String orgName,
    required String shopName,
    String? location,
    String currency = 'INR',
  }) async {
    final client = _client;
    if (client == null) {
      _errorMessage = 'Supabase client is not initialized.';
      _isLoading = false;
      notifyListeners();
      return null;
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final res = await client.rpc(
        'create_organization_and_shop',
        params: {
          'p_org_name': orgName.trim(),
          'p_shop_name': shopName.trim(),
          'p_location': location != null && location.trim().isNotEmpty ? location.trim() : null,
          'p_currency': currency.trim(),
        },
      ).timeout(_networkTimeout);

      final data = Map<String, dynamic>.from(res as Map);
      await loadUserTenantContext();
      return data;
    } catch (err) {
      _errorMessage = _cleanErrorMessage(err);
      _isLoading = false;
      notifyListeners();
      return null;
    }
  }

  /// Signs out active session
  Future<void> signOut() async {
    final client = _client;
    if (client != null) {
      try {
        await client.auth.signOut().timeout(_networkTimeout);
      } catch (_) {
        // Allow local logout to proceed even if offline or server timed out
      }
    }
    _currentUser = null;
    _userFullName = null;
    _authorizedShops = [];
    _selectedShop = null;
    _isLoading = false;
    _errorMessage = null;
    notifyListeners();
  }

  /// Loads authorized organization and shop memberships respecting RLS
  Future<void> loadUserTenantContext() async {
    final user = _currentUser;
    final client = _client;
    if (user == null || client == null) {
      _isLoading = false;
      notifyListeners();
      return;
    }

    _isLoading = true;
    notifyListeners();

    try {
      // 1. Fetch user profile
      final prof = await client
          .from('profiles')
          .select('full_name')
          .eq('id', user.id)
          .maybeSingle()
          .timeout(_networkTimeout);

      if (prof != null) {
        _userFullName = prof['full_name'] as String?;
      }

      // 2. Load shops where user has direct active shop membership
      final shopMemRows = await client
          .from('shop_memberships')
          .select('shop_id, status, shops(*)')
          .eq('user_id', user.id)
          .eq('status', 'ACTIVE')
          .timeout(_networkTimeout);

      final List<Shop> shops = [];
      final Set<String> loadedShopIds = {};

      for (final row in shopMemRows) {
        if (row['shops'] != null && row['shops'] is Map<String, dynamic>) {
          final shop = Shop.fromJson(row['shops'] as Map<String, dynamic>);
          if (!loadedShopIds.contains(shop.id)) {
            shops.add(shop);
            loadedShopIds.add(shop.id);
          }
        }
      }

      // 3. Also check if user is an ORG_ADMIN in any organization
      final orgMemRows = await client
          .from('organization_memberships')
          .select('organization_id, role, status')
          .eq('user_id', user.id)
          .eq('role', 'ORG_ADMIN')
          .eq('status', 'ACTIVE')
          .timeout(_networkTimeout);

      for (final orgRow in orgMemRows) {
        final orgId = orgRow['organization_id'] as String?;
        if (orgId != null) {
          final orgShops = await client
              .from('shops')
              .select('*')
              .eq('organization_id', orgId)
              .timeout(_networkTimeout);
          for (final sMap in orgShops) {
            final s = Shop.fromJson(sMap);
            if (!loadedShopIds.contains(s.id)) {
              shops.add(s);
              loadedShopIds.add(s.id);
            }
          }
        }
      }

      _authorizedShops = shops;

      // Select first shop if none currently selected or previously selected is no longer authorized
      if (_selectedShop == null || !loadedShopIds.contains(_selectedShop!.id)) {
        _selectedShop = shops.isNotEmpty ? shops.first : null;
      }

      _errorMessage = null;
    } on TimeoutException {
      _errorMessage =
          'Network timeout loading store memberships. Please verify network or ADB reverse port forwarding.';
    } catch (err) {
      _errorMessage = 'Failed to load shops: ${_cleanErrorMessage(err)}';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Sets active shop context
  void selectShop(Shop shop) {
    if (_authorizedShops.any((s) => s.id == shop.id)) {
      _selectedShop = shop;
      notifyListeners();
    }
  }

  String _cleanErrorMessage(dynamic err) {
    if (err is TimeoutException) {
      return 'Connection timed out. Please check network or ADB reverse port forwarding.';
    } else if (err is AuthException) {
      final m = err.message.toLowerCase();
      if (m.contains('user already registered') || m.contains('already exists')) {
        return 'An account with this email address already exists. Please sign in instead.';
      }
      if (m.contains('invalid login credentials') || m.contains('invalid credentials')) {
        return 'Invalid email or password. Please verify your credentials and try again.';
      }
      if (m.contains('email not confirmed')) {
        return 'Your email address has not been verified. Please check your inbox or resend verification.';
      }
      return err.message;
    } else if (err is PostgrestException) {
      return err.message;
    }
    final msg = err.toString().replaceFirst('Exception: ', '');
    if (msg.contains('SocketException') ||
        msg.contains('Failed host lookup') ||
        msg.contains('Connection refused') ||
        msg.contains('Connection reset') ||
        msg.contains('ClientException') ||
        msg.contains('Network is unreachable')) {
      return 'Network connection error: Unable to reach server. Please check ADB reverse port forwarding.';
    }
    return msg;
  }
}
