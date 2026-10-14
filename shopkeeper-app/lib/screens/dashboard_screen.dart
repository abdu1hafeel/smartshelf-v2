// ==============================================================================
// SmartShelf V2 - Shopkeeper Mobile Dashboard Screen
// ==============================================================================

import 'package:flutter/material.dart';
import '../models/sale.dart';
import '../models/shop.dart';
import '../services/auth_service.dart';
import '../services/cart_service.dart';
import '../services/inventory_service.dart';
import '../services/sales_service.dart';
import '../widgets/stat_card.dart';
import 'ai_assistant_screen.dart';
import 'barcode_scanner_screen.dart';
import 'cart_screen.dart';
import 'inventory_screen.dart';
import 'loose_weight_picker_screen.dart';
import 'sales_history_screen.dart';
import 'shop_selection_screen.dart';

class DashboardScreen extends StatefulWidget {
  final AuthService authService;
  final CartService cartService;

  const DashboardScreen({
    super.key,
    required this.authService,
    required this.cartService,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final InventoryService _inventoryService = InventoryService();
  final SalesService _salesService = SalesService();

  bool _isLoading = true;
  String? _errorMessage;

  // Real Database Metrics
  int _totalProducts = 0;
  int _lowStockCount = 0;
  int _outOfStockCount = 0;
  int _activeScaleCount = 0;
  int _todaySalesCount = 0;
  double _todayRevenue = 0.0;
  List<Sale> _recentSales = [];

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  Shop? get _activeShop => widget.authService.selectedShop;

  Future<void> _loadDashboardData() async {
    final shop = _activeShop;
    if (shop == null) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // 1. Fetch shop inventory items
      final inventoryItems = await _inventoryService.fetchShopInventory(shop.id);
      int total = inventoryItems.length;
      int lowStock = 0;
      int outOfStock = 0;

      for (final item in inventoryItems) {
        if (item.isOutOfStock) {
          outOfStock++;
        } else if (item.isLowStock) {
          lowStock++;
        }
      }

      // 2. Fetch active scale count
      final scaleCount = await _inventoryService.fetchActiveScaleCount(shop.id);

      // 3. Fetch today's sales metrics
      final todayMetrics = await _salesService.fetchTodayMetrics(shop.id);

      // 4. Fetch latest 5 sales
      final recentSales = await _salesService.fetchRecentSales(shopId: shop.id, limit: 5);

      if (!mounted) return;

      setState(() {
        _totalProducts = total;
        _lowStockCount = lowStock;
        _outOfStockCount = outOfStock;
        _activeScaleCount = scaleCount;
        _todaySalesCount = todayMetrics['count'] as int? ?? 0;
        _todayRevenue = todayMetrics['revenue'] as double? ?? 0.0;
        _recentSales = recentSales;
        _isLoading = false;
      });
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to load dashboard metrics: $err';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final shop = _activeShop;
    if (shop == null) {
      return ShopSelectionScreen(
        authService: widget.authService,
        onShopSelected: () => setState(() => _loadDashboardData()),
      );
    }

    final currency = shop.currency;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF0F172A),
        elevation: 0,
        titleSpacing: 16,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.storefront_rounded, size: 16, color: Color(0xFF4F46E5)),
                const SizedBox(width: 6),
                Text(
                  shop.name,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
            if (shop.location != null)
              Text(
                shop.location!,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.normal),
              ),
          ],
        ),
        actions: [
          // Switch Shop button
          if (widget.authService.authorizedShops.length > 1)
            IconButton(
              icon: const Icon(Icons.swap_horiz_rounded),
              tooltip: 'Switch Shop',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ShopSelectionScreen(
                      authService: widget.authService,
                      onShopSelected: () {
                        Navigator.pop(context);
                        _loadDashboardData();
                      },
                    ),
                  ),
                );
              },
            ),

          // AI Assistant Quick Icon
          IconButton(
            icon: const Icon(Icons.auto_awesome_rounded, color: Color(0xFF6366F1)),
            tooltip: 'AI Shopkeeper Assistant',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AiAssistantScreen(
                    shop: shop,
                    authService: widget.authService,
                  ),
                ),
              );
            },
          ),

          // Cart Quick Icon with item badge
          ListenableBuilder(
            listenable: widget.cartService,
            builder: (context, _) {
              return Stack(
                alignment: Alignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.shopping_bag_outlined),
                    tooltip: 'View Cart',
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => CartScreen(
                            shop: shop,
                            cartService: widget.cartService,
                          ),
                        ),
                      );
                    },
                  ),
                  if (widget.cartService.isNotEmpty)
                    Positioned(
                      right: 6,
                      top: 8,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Color(0xFFE11D48),
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '${widget.cartService.itemCount}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),

          // User Sign Out
          IconButton(
            icon: const Icon(Icons.logout_rounded, size: 20),
            tooltip: 'Sign Out',
            onPressed: () => widget.authService.signOut(),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadDashboardData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
              if (_errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF1F2),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFFECDD3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded, size: 20, color: Color(0xFFE11D48)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(fontSize: 12, color: Color(0xFFBE123C)),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Quick Actions Bar
              const Text(
                'QUICK ACTIONS',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                  color: Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 10),

              // AI Assistant Hero Card
              InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AiAssistantScreen(
                        shop: shop,
                        authService: widget.authService,
                      ),
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF4F46E5).withValues(alpha: 0.22),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.auto_awesome, color: Colors.white, size: 20),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'AI Shopkeeper Assistant',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Ask revenue, low stock alerts, restock orders...',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded, color: Colors.white70),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: _buildQuickActionButton(
                      label: 'Scan Barcode',
                      icon: Icons.qr_code_scanner_rounded,
                      color: const Color(0xFF4F46E5),
                      bgColor: const Color(0xFFEEF2FF),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => BarcodeScannerScreen(
                              shop: shop,
                              cartService: widget.cartService,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildQuickActionButton(
                      label: 'Weigh Produce',
                      icon: Icons.scale_rounded,
                      color: const Color(0xFF16A34A),
                      bgColor: const Color(0xFFF0FDF4),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => LooseWeightPickerScreen(
                              shop: shop,
                              cartService: widget.cartService,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _buildQuickActionButton(
                      label: 'Cart / Checkout',
                      icon: Icons.point_of_sale_rounded,
                      color: const Color(0xFF0284C7),
                      bgColor: const Color(0xFFF0F9FF),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => CartScreen(
                              shop: shop,
                              cartService: widget.cartService,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildQuickActionButton(
                      label: 'Store Stock',
                      icon: Icons.inventory_2_outlined,
                      color: const Color(0xFF8B5CF6),
                      bgColor: const Color(0xFFF5F3FF),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => InventoryScreen(shop: shop),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // KPI Metrics Section
              const Text(
                'SHOP METRICS',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                  color: Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 10),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.45,
                children: [
                  StatCard(
                    title: "Today's Revenue",
                    value: '$currency ${_todayRevenue.toStringAsFixed(2)}',
                    icon: Icons.currency_rupee_rounded,
                    iconColor: const Color(0xFF16A34A),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => SalesHistoryScreen(shop: shop),
                        ),
                      );
                    },
                  ),
                  StatCard(
                    title: "Today's Sales",
                    value: '$_todaySalesCount bills',
                    icon: Icons.receipt_long_rounded,
                    iconColor: const Color(0xFF4F46E5),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => SalesHistoryScreen(shop: shop),
                        ),
                      );
                    },
                  ),
                  StatCard(
                    title: 'Total Stocked Items',
                    value: '$_totalProducts',
                    icon: Icons.inventory_outlined,
                    iconColor: const Color(0xFF0284C7),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => InventoryScreen(shop: shop),
                        ),
                      );
                    },
                  ),
                  StatCard(
                    title: 'Stock Alerts',
                    value: '$_lowStockCount low / $_outOfStockCount out',
                    icon: Icons.notification_important_rounded,
                    iconColor: (_lowStockCount > 0 || _outOfStockCount > 0)
                        ? const Color(0xFFE11D48)
                        : const Color(0xFF64748B),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => InventoryScreen(shop: shop),
                        ),
                      );
                    },
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Device / Hardware Scale Connection Status Card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _activeScaleCount > 0 ? const Color(0xFFF0FDF4) : const Color(0xFFFFFBEB),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.sensors_rounded,
                        color: _activeScaleCount > 0 ? const Color(0xFF16A34A) : Colors.amber.shade700,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _activeScaleCount > 0
                                ? '$_activeScaleCount Smart Scale Device(s) Online'
                                : 'No Active Scales Registered',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _activeScaleCount > 0
                                ? 'Firmware telemetry & stable tickets ready for loose goods.'
                                : 'Enroll ESP32 scales in Admin Console to enable verified weigh-ins.',
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Recent Sales Section
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'RECENT TRANSACTIONS',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                      color: Color(0xFF64748B),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => SalesHistoryScreen(shop: shop),
                        ),
                      );
                    },
                    child: const Text('View All', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
              const SizedBox(height: 6),

              if (_recentSales.isEmpty)
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Center(
                    child: Text(
                      'No sales recorded today yet.',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                    ),
                  ),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _recentSales.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final sale = _recentSales[index];
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.receipt_rounded, size: 16, color: Color(0xFF4F46E5)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '#${sale.saleNumber}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                                Text(
                                  '${sale.createdAt.toLocal().toString().substring(11, 16)} • ${sale.paymentMethod}',
                                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            '$currency ${sale.totalAmount.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: Color(0xFF16A34A),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickActionButton({
    required String label,
    required IconData icon,
    required Color color,
    required Color bgColor,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.grey.shade200),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F172A),
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
