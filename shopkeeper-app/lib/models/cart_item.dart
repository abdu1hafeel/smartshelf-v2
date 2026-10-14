// ==============================================================================
// SmartShelf V2 - POS Cart Item Model
// ==============================================================================

import 'product.dart';
import 'shop_inventory_item.dart';
import 'verified_weight_ticket.dart';

class CartItem {
  final Product product;
  final ShopInventoryItem inventoryItem;
  int packagedQuantity;
  final VerifiedWeightTicket? weightTicket;

  CartItem({
    required this.product,
    required this.inventoryItem,
    this.packagedQuantity = 1,
    this.weightTicket,
  }) {
    if (product.isPackaged && packagedQuantity < 1) {
      packagedQuantity = 1;
    }
  }

  bool get isPackaged => product.isPackaged;
  bool get isLoose => product.isLoose;

  /// Quantity value (integer pieces for packaged goods, kilograms for loose goods)
  double get quantity {
    if (isPackaged) {
      return packagedQuantity.toDouble();
    }
    return weightTicket?.weightKg ?? 0.0;
  }

  /// Authoritative line total calculated from inventory selling price
  double get lineTotal {
    return quantity * inventoryItem.sellingPrice;
  }

  /// Converts item into canonical payload dictionary required by process_sale_tx RPC
  Map<String, dynamic> toRpcPayload() {
    if (isPackaged) {
      return {
        'product_id': product.id,
        'quantity': packagedQuantity,
      };
    } else {
      return {
        'product_id': product.id,
        'weight_ticket_id': weightTicket!.id,
      };
    }
  }
}
