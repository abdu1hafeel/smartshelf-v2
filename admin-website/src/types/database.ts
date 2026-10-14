// ==============================================================================
// SmartShelf V2 - Database TypeScript Definitions
// Corresponds strictly to schema: 20261014191500_initial_schema.sql
// ==============================================================================

export type UnitType = 'PACKAGED' | 'LOOSE';
export type OrgRole = 'ORG_ADMIN' | 'ORG_MEMBER';
export type ShopRole = 'SHOP_ADMIN' | 'SHOPKEEPER';
export type MembershipStatus = 'ACTIVE' | 'INVITED' | 'SUSPENDED';
export type PaymentMethod = 'CASH' | 'CARD' | 'UPI' | 'CREDIT';
export type PaymentStatus = 'COMPLETED' | 'PENDING' | 'CANCELLED' | 'REFUNDED';
export type StockMovementType = 'SALE' | 'RESTOCK' | 'ADJUSTMENT' | 'RETURN' | 'DAMAGE' | 'INITIAL';

export interface Profile {
  id: string;
  full_name: string | null;
  created_at: string;
  updated_at: string;
}

export interface Organization {
  id: string;
  name: string;
  created_at: string;
  updated_at: string;
}

export interface OrganizationMembership {
  id: string;
  organization_id: string;
  user_id: string;
  role: OrgRole;
  status: MembershipStatus;
  created_at: string;
  updated_at: string;
  profile?: Profile;
}

export interface Shop {
  id: string;
  organization_id: string;
  name: string;
  location: string | null;
  currency: string;
  created_at: string;
  updated_at: string;
}

export interface ShopMembership {
  id: string;
  shop_id: string;
  user_id: string;
  role: ShopRole;
  status: MembershipStatus;
  created_at: string;
  updated_at: string;
  profile?: Profile;
}

export interface Category {
  id: string;
  organization_id: string;
  name: string;
  description: string | null;
  created_at: string;
  updated_at: string;
}

export interface Product {
  id: string;
  organization_id: string;
  category_id: string | null;
  name: string;
  barcode: string | null;
  sku: string | null;
  unit_type: UnitType;
  description: string | null;
  is_active: boolean;
  created_at: string;
  updated_at: string;
  category?: Category;
}

export interface ShopInventoryItem {
  shop_id: string;
  product_id: string;
  organization_id: string;
  selling_price: number;
  quantity: number;
  low_stock_threshold: number;
  is_available: boolean;
  created_at: string;
  updated_at: string;
  product?: Product;
}

export interface Device {
  id: string;
  shop_id: string;
  device_identifier: string;
  name: string;
  calibration_factor: number;
  tare_offset: number;
  current_epoch: number;
  last_sequence_number: number;
  is_active: boolean;
  last_boot_at: string | null;
  last_boot_reason: string | null;
  hourly_boot_count: number;
  hourly_boot_window_start: string;
  last_seen_at: string | null;
  created_at: string;
  updated_at: string;
}

export interface StockMovement {
  id: string;
  shop_id: string;
  product_id: string;
  movement_type: StockMovementType;
  delta_quantity: number;
  quantity_before: number;
  quantity_after: number;
  reference_id: string | null;
  reason: string | null;
  performed_by: string | null;
  created_at: string;
  product?: Product;
}

export interface Sale {
  id: string;
  shop_id: string;
  cashier_user_id: string;
  checkout_id: string;
  sale_number: string;
  total_amount: number;
  payment_method: PaymentMethod;
  payment_status: PaymentStatus;
  notes: string | null;
  created_at: string;
}

export interface SaleItem {
  id: string;
  sale_id: string;
  product_id: string;
  product_name: string;
  unit_type: UnitType;
  quantity: number;
  unit_price: number;
  line_total: number;
  weight_ticket_id: string | null;
  created_at: string;
}

// ------------------------------------------------------------------------------
// Stored Procedure Return Types
// ------------------------------------------------------------------------------

export interface OnboardingResult {
  organization_id: string;
  organization_name: string;
  membership_id: string;
  role: OrgRole;
}

export interface CreateShopResult {
  shop_id: string;
  organization_id: string;
  name: string;
  currency: string;
}

export interface CreateProductResult {
  product_id: string;
  organization_id: string;
  name: string;
  unit_type: UnitType;
}

export interface DeviceEnrollmentResult {
  device_id: string;
  shop_id: string;
  device_identifier: string;
  device_secret: string;
  warning: string;
}

export interface DeviceRotationResult {
  device_id: string;
  new_device_secret: string;
  warning: string;
}

export interface DeviceRecoveryResult {
  device_id: string;
  new_device_secret: string;
  assigned_starting_epoch: number;
  previous_epoch: number;
  instructions: string;
}
