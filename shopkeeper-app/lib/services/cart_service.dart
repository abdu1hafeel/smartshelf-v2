// ==============================================================================
// SmartShelf V2 - Cart State Management Service
// ==============================================================================

import 'package:flutter/foundation.dart';
import '../core/uuid.dart';
import '../models/cart_item.dart';
import '../models/product.dart';
import '../models/shop_inventory_item.dart';
import '../models/verified_weight_ticket.dart';

class CartService extends ChangeNotifier {
  final List<CartItem> _items = [];
  String _checkoutId = UuidUtils.generateV4();

  List<CartItem> get items => List.unmodifiable(_items);
  int get itemCount => _items.length;
  bool get isEmpty => _items.isEmpty;
  bool get isNotEmpty => _items.isNotEmpty;
  String get checkoutId => _checkoutId;

  /// Authoritative total computed from database-backed prices and ticket weights
  double get totalAmount {
    return _items.fold(0.0, (sum, item) => sum + item.lineTotal);
  }

  /// Adds a packaged product to cart, or increments quantity if already present.
  /// Returns an error message if stock is insufficient, or null on success.
  String? addPackagedProduct({
    required Product product,
    required ShopInventoryItem inventoryItem,
    int quantity = 1,
  }) {
    if (!product.isPackaged) {
      return 'Product is loose produce. Please weigh on scale to generate a ticket.';
    }

    if (inventoryItem.quantity <= 0) {
      return '${product.name} is out of stock.';
    }

    final existingIndex = _items.indexWhere(
      (item) => item.product.id == product.id && item.isPackaged,
    );

    if (existingIndex >= 0) {
      final existingItem = _items[existingIndex];
      final newQty = existingItem.packagedQuantity + quantity;
      if (newQty > inventoryItem.quantity) {
        return 'Cannot add more. Only ${inventoryItem.quantity.toInt()} available in stock.';
      }
      existingItem.packagedQuantity = newQty;
    } else {
      if (quantity > inventoryItem.quantity) {
        return 'Requested $quantity exceeds available stock of ${inventoryItem.quantity.toInt()}.';
      }
      _items.add(CartItem(
        product: product,
        inventoryItem: inventoryItem,
        packagedQuantity: quantity,
      ));
    }

    notifyListeners();
    return null;
  }

  /// Adds loose goods associated with an authoritative scale weight ticket.
  /// Returns error string or null on success.
  String? addLooseProduct({
    required Product product,
    required ShopInventoryItem inventoryItem,
    required VerifiedWeightTicket ticket,
  }) {
    if (!product.isLoose) {
      return 'Product is not configured as loose produce.';
    }

    if (!ticket.isValidForCheckout) {
      return 'Weight ticket is expired or already consumed. Please weigh item again.';
    }

    if (ticket.productId != product.id) {
      return 'Ticket product mismatch: Ticket belongs to a different item.';
    }

    // Check if this specific ticket ID is already in the cart
    final alreadyAdded = _items.any(
      (item) => item.weightTicket?.id == ticket.id,
    );
    if (alreadyAdded) {
      return 'This scale ticket has already been added to the cart.';
    }

    if (ticket.weightKg > inventoryItem.quantity) {
      return 'Weight (${ticket.weightKg.toStringAsFixed(3)} kg) exceeds current recorded stock of ${inventoryItem.quantity.toStringAsFixed(3)} kg.';
    }

    _items.add(CartItem(
      product: product,
      inventoryItem: inventoryItem,
      weightTicket: ticket,
    ));

    notifyListeners();
    return null;
  }

  /// Increments or decrements a packaged item's quantity
  String? updatePackagedQuantity(int index, int delta) {
    if (index < 0 || index >= _items.length) return 'Item not found in cart';
    final item = _items[index];

    if (!item.isPackaged) {
      return 'Cannot modify weight of loose goods. Weigh item on scale for a new ticket.';
    }

    final newQty = item.packagedQuantity + delta;
    if (newQty <= 0) {
      _items.removeAt(index);
      notifyListeners();
      return null;
    }

    if (newQty > item.inventoryItem.quantity) {
      return 'Cannot exceed available stock of ${item.inventoryItem.quantity.toInt()} pcs.';
    }

    item.packagedQuantity = newQty;
    notifyListeners();
    return null;
  }

  /// Removes an item at specified index
  void removeItem(int index) {
    if (index >= 0 && index < _items.length) {
      _items.removeAt(index);
      notifyListeners();
    }
  }

  /// Clears the cart and regenerates a fresh checkout UUID for the next transaction
  void clear() {
    _items.clear();
    _checkoutId = UuidUtils.generateV4();
    notifyListeners();
  }

  /// Regenerates checkout ID explicitly if user abandons previous attempt
  void resetCheckoutId() {
    _checkoutId = UuidUtils.generateV4();
    notifyListeners();
  }
}
