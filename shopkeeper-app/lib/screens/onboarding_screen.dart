// ==============================================================================
// SmartShelf V2 - Shopkeeper Onboarding Screen (Join or Create Store)
// ==============================================================================

import 'package:flutter/material.dart';
import '../services/auth_service.dart';

class OnboardingScreen extends StatefulWidget {
  final AuthService authService;
  final VoidCallback onStoreJoined;

  const OnboardingScreen({
    super.key,
    required this.authService,
    required this.onStoreJoined,
  });

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  // Option A: Join Existing Shop
  final _inviteCodeController = TextEditingController();
  final _joinFormKey = GlobalKey<FormState>();
  bool _isJoining = false;
  String? _joinError;

  // Option B: Create New Shop
  final _orgNameController = TextEditingController();
  final _shopNameController = TextEditingController();
  final _locationController = TextEditingController();
  String _selectedCurrency = 'INR';
  final _createFormKey = GlobalKey<FormState>();
  bool _isCreating = false;
  String? _createError;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _inviteCodeController.dispose();
    _orgNameController.dispose();
    _shopNameController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  Future<void> _handleJoinStore() async {
    if (!_joinFormKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();

    setState(() {
      _isJoining = true;
      _joinError = null;
    });

    final res = await widget.authService.redeemInvitation(_inviteCodeController.text.trim());

    if (!mounted) return;
    setState(() => _isJoining = false);

    if (res != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Successfully joined ${res['shop_name']} as ${res['role']}!'),
          backgroundColor: const Color(0xFF10B981),
        ),
      );
      widget.onStoreJoined();
    } else {
      setState(() {
        _joinError = widget.authService.errorMessage ?? 'Failed to redeem invitation code';
      });
    }
  }

  Future<void> _handleCreateStore() async {
    if (!_createFormKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();

    setState(() {
      _isCreating = true;
      _createError = null;
    });

    final res = await widget.authService.createOrganizationAndShop(
      orgName: _orgNameController.text.trim(),
      shopName: _shopNameController.text.trim(),
      location: _locationController.text.trim(),
      currency: _selectedCurrency,
    );

    if (!mounted) return;
    setState(() => _isCreating = false);

    if (res != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Store "${res['shop_name']}" created successfully!'),
          backgroundColor: const Color(0xFF10B981),
        ),
      );
      widget.onStoreJoined();
    } else {
      setState(() {
        _createError = widget.authService.errorMessage ?? 'Failed to create store';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final userEmail = widget.authService.currentUser?.email ?? 'Shopkeeper';

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Store Onboarding',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            Text(
              userEmail,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded, size: 20),
            tooltip: 'Sign Out',
            onPressed: () => widget.authService.signOut(),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: const Color(0xFF4F46E5),
          unselectedLabelColor: const Color(0xFF64748B),
          indicatorColor: const Color(0xFF4F46E5),
          indicatorWeight: 3,
          tabs: const [
            Tab(
              icon: Icon(Icons.qr_code_rounded, size: 18),
              text: 'Join with Code',
            ),
            Tab(
              icon: Icon(Icons.add_business_rounded, size: 18),
              text: 'Create New Store',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildJoinTab(),
          _buildCreateTab(),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Option A: Join Existing Store
  // ---------------------------------------------------------------------------
  Widget _buildJoinTab() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFEEF2FF),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: const BoxDecoration(
                        color: Color(0xFF4F46E5),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.vpn_key_rounded, color: Colors.white, size: 22),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Join an Existing Store',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: Color(0xFF1E1B4B),
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Enter the invitation code provided by your Store Administrator (e.g. SH-XXXX-YYYY).',
                            style: TextStyle(fontSize: 11.5, color: Color(0xFF4338CA)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              if (_joinError != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF1F2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFFECDD3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: Color(0xFFBE123C), size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _joinError!,
                          style: const TextStyle(color: Color(0xFFBE123C), fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.grey.shade200),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.03),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Form(
                  key: _joinFormKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextFormField(
                        controller: _inviteCodeController,
                        textCapitalization: TextCapitalization.characters,
                        decoration: InputDecoration(
                          labelText: 'Invitation Code',
                          hintText: 'e.g. SH-1AEC-A562',
                          prefixIcon: const Icon(Icons.tag_rounded, size: 20),
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                        ),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return 'Please enter your invitation code';
                          }
                          if (val.trim().length < 4) {
                            return 'Invalid code format';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton(
                        onPressed: _isJoining ? null : _handleJoinStore,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF4F46E5),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        child: _isJoining
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              )
                            : const Text(
                                'Validate & Join Store',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Option B: Create New Store
  // ---------------------------------------------------------------------------
  Widget _buildCreateTab() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0FDF4),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: const BoxDecoration(
                        color: Color(0xFF16A34A),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.storefront_rounded, color: Colors.white, size: 22),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Register a New Retail Business',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: Color(0xFF14532D),
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Creates an organization and primary store with full administrator permissions.',
                            style: TextStyle(fontSize: 11.5, color: Color(0xFF15803D)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              if (_createError != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF1F2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFFECDD3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: Color(0xFFBE123C), size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _createError!,
                          style: const TextStyle(color: Color(0xFFBE123C), fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.grey.shade200),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.03),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Form(
                  key: _createFormKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextFormField(
                        controller: _orgNameController,
                        textCapitalization: TextCapitalization.words,
                        decoration: InputDecoration(
                          labelText: 'Organization / Business Name',
                          hintText: 'e.g. Apex Retail Enterprises',
                          prefixIcon: const Icon(Icons.business_rounded, size: 20),
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                        ),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return 'Please enter business name';
                          }
                          if (val.trim().length < 2) {
                            return 'Must be at least 2 characters';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),

                      TextFormField(
                        controller: _shopNameController,
                        textCapitalization: TextCapitalization.words,
                        decoration: InputDecoration(
                          labelText: 'Store Branch Name',
                          hintText: 'e.g. Downtown Flagship',
                          prefixIcon: const Icon(Icons.store_rounded, size: 20),
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                        ),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return 'Please enter store branch name';
                          }
                          if (val.trim().length < 2) {
                            return 'Must be at least 2 characters';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),

                      TextFormField(
                        controller: _locationController,
                        textCapitalization: TextCapitalization.words,
                        decoration: InputDecoration(
                          labelText: 'Location / City (Optional)',
                          hintText: 'e.g. MG Road, Bangalore',
                          prefixIcon: const Icon(Icons.location_on_outlined, size: 20),
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                        ),
                      ),
                      const SizedBox(height: 14),

                      DropdownButtonFormField<String>(
                        initialValue: _selectedCurrency,
                        decoration: InputDecoration(
                          labelText: 'Store Currency',
                          prefixIcon: const Icon(Icons.currency_exchange_rounded, size: 20),
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'INR', child: Text('INR (₹)')),
                          DropdownMenuItem(value: 'USD', child: Text('USD (\$)')),
                          DropdownMenuItem(value: 'EUR', child: Text('EUR (€)')),
                          DropdownMenuItem(value: 'GBP', child: Text('GBP (£)')),
                        ],
                        onChanged: (val) {
                          if (val != null) setState(() => _selectedCurrency = val);
                        },
                      ),
                      const SizedBox(height: 22),

                      ElevatedButton(
                        onPressed: _isCreating ? null : _handleCreateStore,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF16A34A),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        child: _isCreating
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              )
                            : const Text(
                                'Provision Store & Organization',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
