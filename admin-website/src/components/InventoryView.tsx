// ==============================================================================
// SmartShelf V2 - Shop Inventory & Stock Movements (Zero-Trust Protected DML)
// ==============================================================================

import React, { useState, useEffect, useCallback } from 'react';
import { useAuth } from '../context/AuthContext';
import { supabase } from '../lib/supabase';
import type { ShopInventoryItem, Product, StockMovement } from '../types/database';
import {
  Boxes,
  Plus,
  Sliders,
  AlertTriangle,
  History,
  CheckCircle2,
  AlertCircle,
  Package,
  Scale,
  Search,
} from 'lucide-react';

export const InventoryView: React.FC = () => {
  const { activeOrg, activeShop, isShopAdmin } = useAuth();
  const [inventory, setInventory] = useState<ShopInventoryItem[]>([]);
  const [catalogProducts, setCatalogProducts] = useState<Product[]>([]);
  const [stockMovements, setStockMovements] = useState<StockMovement[]>([]);
  const [activeSubTab, setActiveSubTab] = useState<'inventory' | 'movements'>('inventory');
  const [loading, setLoading] = useState(true);
  const [searchQuery, setSearchQuery] = useState('');

  // Modals
  const [showSetupModal, setShowSetupModal] = useState(false);
  const [showRestockModal, setShowRestockModal] = useState(false);
  const [showAdjustModal, setShowAdjustModal] = useState(false);
  const [showPricingModal, setShowPricingModal] = useState(false);
  const [selectedItem, setSelectedItem] = useState<ShopInventoryItem | null>(null);

  // Form State: Setup New Item
  const [setupProductId, setSetupProductId] = useState('');
  const [setupPrice, setSetupPrice] = useState('');
  const [setupQty, setSetupQty] = useState('0');
  const [setupThreshold, setSetupThreshold] = useState('5');

  // Form State: Restock
  const [restockQty, setRestockQty] = useState('');
  const [restockReason, setRestockReason] = useState('Stock delivery shipment');

  // Form State: Adjust
  const [adjustQty, setAdjustQty] = useState('');
  const [adjustReason, setAdjustReason] = useState('');

  // Form State: Price Update
  const [editPrice, setEditPrice] = useState('');
  const [editThreshold, setEditThreshold] = useState('');
  const [editAvailable, setEditAvailable] = useState(true);

  // Feedback State
  const [actionLoading, setActionLoading] = useState(false);
  const [errorMsg, setErrorMsg] = useState<string | null>(null);
  const [successMsg, setSuccessMsg] = useState<string | null>(null);

  const fetchInventoryData = useCallback(async () => {
    if (!activeShop || !activeOrg) {
      setLoading(false);
      return;
    }
    setLoading(true);

    try {
      // 1. Fetch shop inventory
      const { data: invData, error: invErr } = await supabase
        .from('shop_inventory')
        .select('*, product:products(*)')
        .eq('shop_id', activeShop.id)
        .order('updated_at', { ascending: false });

      if (invErr) console.error('Error fetching inventory:', invErr);
      const items: ShopInventoryItem[] = (invData as ShopInventoryItem[]) || [];
      setInventory(items);

      // 2. Fetch catalog products to allow adding unconfigured items
      const { data: prodData } = await supabase
        .from('products')
        .select('*')
        .eq('organization_id', activeOrg.id)
        .eq('is_active', true);

      setCatalogProducts((prodData as Product[]) || []);

      // 3. Fetch stock movements audit log
      const { data: movData, error: movErr } = await supabase
        .from('stock_movements')
        .select('*')
        .eq('shop_id', activeShop.id)
        .order('created_at', { ascending: false })
        .limit(50);

      if (movErr) console.error('Error fetching stock movements:', movErr);

      const prodMap = new Map(((prodData as Product[]) || []).map((p) => [p.id, p]));
      const movements = ((movData || []) as StockMovement[]).map((m) => ({
        ...m,
        product: prodMap.get(m.product_id) || undefined,
      }));

      setStockMovements(movements);
    } catch (err) {
      console.error('Failed to load inventory data:', err);
    } finally {
      setLoading(false);
    }
  }, [activeShop, activeOrg]);

  useEffect(() => {
    fetchInventoryData();
  }, [fetchInventoryData]);

  // RPC: Setup Inventory
  const handleSetupInventory = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!activeShop) return;
    setErrorMsg(null);
    setSuccessMsg(null);
    setActionLoading(true);

    try {
      const price = parseFloat(setupPrice);
      const initialQty = parseFloat(setupQty);
      const threshold = parseFloat(setupThreshold);

      const { error } = await supabase.rpc('setup_shop_inventory', {
        p_shop_id: activeShop.id,
        p_product_id: setupProductId,
        p_selling_price: price,
        p_initial_quantity: initialQty,
        p_low_stock_threshold: threshold,
      });

      if (error) {
        setErrorMsg(error.message);
      } else {
        setSuccessMsg('Product added to shop inventory successfully.');
        setSetupPrice('');
        setSetupQty('0');
        await fetchInventoryData();
        setTimeout(() => setShowSetupModal(false), 800);
      }
    } catch (err: unknown) {
      setErrorMsg(err instanceof Error ? err.message : 'Inventory setup failed');
    } finally {
      setActionLoading(false);
    }
  };

  // RPC: Restock Inventory
  const handleRestock = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!activeShop || !selectedItem) return;
    setErrorMsg(null);
    setSuccessMsg(null);
    setActionLoading(true);

    try {
      const qty = parseFloat(restockQty);
      const { error } = await supabase.rpc('restock_inventory', {
        p_shop_id: activeShop.id,
        p_product_id: selectedItem.product_id,
        p_quantity: qty,
        p_reason: restockReason.trim() || 'Stock delivery',
      });

      if (error) {
        setErrorMsg(error.message);
      } else {
        setSuccessMsg(`Restocked ${qty} units successfully.`);
        setRestockQty('');
        await fetchInventoryData();
        setTimeout(() => setShowRestockModal(false), 800);
      }
    } catch (err: unknown) {
      setErrorMsg(err instanceof Error ? err.message : 'Restock failed');
    } finally {
      setActionLoading(false);
    }
  };

  // RPC: Adjust Inventory
  const handleAdjust = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!activeShop || !selectedItem) return;
    setErrorMsg(null);
    setSuccessMsg(null);
    setActionLoading(true);

    try {
      const newQty = parseFloat(adjustQty);
      const { error } = await supabase.rpc('adjust_inventory', {
        p_shop_id: activeShop.id,
        p_product_id: selectedItem.product_id,
        p_new_quantity: newQty,
        p_reason: adjustReason.trim(),
      });

      if (error) {
        setErrorMsg(error.message);
      } else {
        setSuccessMsg(`Inventory adjusted to ${newQty} successfully.`);
        setAdjustQty('');
        setAdjustReason('');
        await fetchInventoryData();
        setTimeout(() => setShowAdjustModal(false), 800);
      }
    } catch (err: unknown) {
      setErrorMsg(err instanceof Error ? err.message : 'Adjustment failed');
    } finally {
      setActionLoading(false);
    }
  };

  // RPC: Update Pricing & Availability
  const handleUpdatePricing = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!activeShop || !selectedItem) return;
    setErrorMsg(null);
    setSuccessMsg(null);
    setActionLoading(true);

    try {
      const price = parseFloat(editPrice);
      const threshold = parseFloat(editThreshold);
      const { error } = await supabase.rpc('update_inventory_pricing', {
        p_shop_id: activeShop.id,
        p_product_id: selectedItem.product_id,
        p_selling_price: price,
        p_low_stock_threshold: threshold,
        p_is_available: editAvailable,
      });

      if (error) {
        setErrorMsg(error.message);
      } else {
        setSuccessMsg('Inventory pricing updated successfully.');
        await fetchInventoryData();
        setTimeout(() => setShowPricingModal(false), 800);
      }
    } catch (err: unknown) {
      setErrorMsg(err instanceof Error ? err.message : 'Pricing update failed');
    } finally {
      setActionLoading(false);
    }
  };

  // Filter inventory
  const filteredInventory = inventory.filter((item) => {
    const prodName = item.product?.name?.toLowerCase() || '';
    const sku = item.product?.sku?.toLowerCase() || '';
    const barcode = item.product?.barcode?.toLowerCase() || '';
    const q = searchQuery.toLowerCase();
    return prodName.includes(q) || sku.includes(q) || barcode.includes(q);
  });

  // Unconfigured catalog items for setup modal
  const unconfiguredProducts = catalogProducts.filter(
    (cp) => !inventory.some((inv) => inv.product_id === cp.id)
  );

  if (!activeShop) {
    return (
      <div className="p-8 max-w-md mx-auto text-center mt-12 bg-white rounded-2xl border border-slate-200 p-8">
        <Boxes className="w-10 h-10 text-slate-300 mx-auto mb-3" />
        <h3 className="text-sm font-bold text-slate-800">No Active Shop Selected</h3>
        <p className="text-xs text-slate-500 mt-1">
          Select or create a shop in the top header or organization view to manage inventory.
        </p>
      </div>
    );
  }

  return (
    <div className="p-8 max-w-7xl mx-auto space-y-6">
      {/* Tab Switcher & Action Button */}
      <div className="flex flex-col sm:flex-row items-stretch sm:items-center justify-between gap-4">
        <div className="flex items-center gap-2 bg-slate-200/80 p-1 rounded-xl w-fit">
          <button
            type="button"
            onClick={() => setActiveSubTab('inventory')}
            className={`px-4 py-1.5 text-xs font-semibold rounded-lg transition-all ${
              activeSubTab === 'inventory'
                ? 'bg-white text-slate-900 shadow-xs'
                : 'text-slate-600 hover:text-slate-900'
            }`}
          >
            Current Stock ({inventory.length})
          </button>
          <button
            type="button"
            onClick={() => setActiveSubTab('movements')}
            className={`px-4 py-1.5 text-xs font-semibold rounded-lg transition-all ${
              activeSubTab === 'movements'
                ? 'bg-white text-slate-900 shadow-xs'
                : 'text-slate-600 hover:text-slate-900'
            }`}
          >
            Audit Movements ({stockMovements.length})
          </button>
        </div>

        {activeSubTab === 'inventory' && isShopAdmin && (
          <div className="flex items-center gap-2">
            <div className="relative">
              <Search className="w-4 h-4 text-slate-400 absolute left-3 top-1/2 -translate-y-1/2" />
              <input
                type="text"
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                placeholder="Search stock..."
                className="pl-9 pr-3 py-1.5 bg-white border border-slate-200 rounded-xl text-xs text-slate-800 placeholder-slate-400 focus:outline-none focus:ring-2 focus:ring-indigo-500 shadow-xs"
              />
            </div>

            <button
              type="button"
              onClick={() => {
                setErrorMsg(null);
                setSuccessMsg(null);
                setSetupProductId(unconfiguredProducts[0]?.id || '');
                setShowSetupModal(true);
              }}
              disabled={unconfiguredProducts.length === 0}
              className="px-4 py-2 text-xs font-semibold text-white bg-indigo-600 hover:bg-indigo-500 rounded-xl shadow-xs shadow-indigo-600/30 transition-all flex items-center gap-1.5 disabled:opacity-50"
            >
              <Plus className="w-4 h-4" />
              Stock Product
            </button>
          </div>
        )}
      </div>

      {activeSubTab === 'inventory' ? (
        /* Inventory Table */
        <div className="bg-white rounded-xl border border-slate-200 shadow-xs overflow-hidden">
          <div className="p-4 border-b border-slate-100 flex items-center justify-between">
            <div className="flex items-center gap-2">
              <Boxes className="w-4 h-4 text-indigo-600" />
              <h3 className="text-sm font-bold text-slate-800">
                Shop Inventory - {activeShop.name}
              </h3>
            </div>
            <span className="text-xs font-medium text-slate-400">
              {filteredInventory.length} products enrolled
            </span>
          </div>

          {loading ? (
            <div className="p-12 text-center text-slate-400 text-xs">
              <div className="w-6 h-6 border-2 border-indigo-600/20 border-t-indigo-600 rounded-full animate-spin mx-auto mb-2"></div>
              Loading inventory levels...
            </div>
          ) : filteredInventory.length === 0 ? (
            <div className="p-12 text-center">
              <Boxes className="w-10 h-10 text-slate-300 mx-auto mb-3" />
              <p className="text-sm font-semibold text-slate-700">No items stocked in this shop</p>
              <p className="text-xs text-slate-400 mt-1 max-w-sm mx-auto">
                Select catalog items to configure initial selling price and shelf stock.
              </p>
            </div>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full text-left border-collapse">
                <thead>
                  <tr className="bg-slate-50/70 border-b border-slate-100 text-[11px] font-semibold text-slate-500 uppercase tracking-wider">
                    <th className="py-3 px-5">Product</th>
                    <th className="py-3 px-4">Unit</th>
                    <th className="py-3 px-4 text-right">Selling Price</th>
                    <th className="py-3 px-4 text-right">Quantity</th>
                    <th className="py-3 px-4">Stock Status</th>
                    {isShopAdmin && <th className="py-3 px-4 text-right">Actions</th>}
                  </tr>
                </thead>
                <tbody className="divide-y divide-slate-100 text-xs">
                  {filteredInventory.map((item) => {
                    const qty = Number(item.quantity);
                    const threshold = Number(item.low_stock_threshold);
                    const isOutOfStock = qty <= 0;
                    const isLowStock = qty <= threshold && !isOutOfStock;

                    return (
                      <tr key={item.product_id} className="hover:bg-slate-50/60 transition-colors">
                        <td className="py-3.5 px-5">
                          <div className="font-semibold text-slate-900">
                            {item.product?.name || 'Unnamed Product'}
                          </div>
                          <div className="text-[11px] text-slate-400 font-mono">
                            {item.product?.sku || item.product?.barcode || '-'}
                          </div>
                        </td>
                        <td className="py-3.5 px-4">
                          {item.product?.unit_type === 'PACKAGED' ? (
                            <span className="inline-flex items-center gap-1 text-[11px] font-medium text-slate-600">
                              <Package className="w-3.5 h-3.5 text-slate-400" /> pcs
                            </span>
                          ) : (
                            <span className="inline-flex items-center gap-1 text-[11px] font-medium text-slate-600">
                              <Scale className="w-3.5 h-3.5 text-slate-400" /> kg
                            </span>
                          )}
                        </td>
                        <td className="py-3.5 px-4 text-right font-mono font-semibold text-slate-900">
                          {activeShop.currency} {Number(item.selling_price).toFixed(2)}
                        </td>
                        <td className="py-3.5 px-4 text-right font-mono font-bold text-slate-800">
                          {item.product?.unit_type === 'PACKAGED'
                            ? Math.trunc(qty)
                            : qty.toFixed(3)}
                        </td>
                        <td className="py-3.5 px-4">
                          {isOutOfStock ? (
                            <span className="inline-flex items-center gap-1 px-2.5 py-0.5 rounded-full text-[10px] font-bold bg-rose-50 text-rose-700 border border-rose-200">
                              <AlertTriangle className="w-3 h-3" /> Out of Stock
                            </span>
                          ) : isLowStock ? (
                            <span className="inline-flex items-center gap-1 px-2.5 py-0.5 rounded-full text-[10px] font-bold bg-amber-50 text-amber-700 border border-amber-200">
                              <AlertTriangle className="w-3 h-3" /> Low Stock ({qty})
                            </span>
                          ) : (
                            <span className="inline-flex items-center gap-1 px-2.5 py-0.5 rounded-full text-[10px] font-bold bg-emerald-50 text-emerald-700 border border-emerald-200">
                              <CheckCircle2 className="w-3 h-3" /> In Stock
                            </span>
                          )}
                        </td>
                        {isShopAdmin && (
                          <td className="py-3.5 px-4 text-right space-x-1">
                            <button
                              type="button"
                              onClick={() => {
                                setSelectedItem(item);
                                setRestockQty('');
                                setErrorMsg(null);
                                setSuccessMsg(null);
                                setShowRestockModal(true);
                              }}
                              className="px-2.5 py-1 text-[11px] font-semibold text-emerald-700 bg-emerald-50 hover:bg-emerald-100 rounded-lg transition-colors border border-emerald-200"
                            >
                              Restock
                            </button>
                            <button
                              type="button"
                              onClick={() => {
                                setSelectedItem(item);
                                setAdjustQty(item.quantity.toString());
                                setAdjustReason('');
                                setErrorMsg(null);
                                setSuccessMsg(null);
                                setShowAdjustModal(true);
                              }}
                              className="px-2.5 py-1 text-[11px] font-semibold text-slate-700 bg-slate-100 hover:bg-slate-200 rounded-lg transition-colors border border-slate-200"
                            >
                              Adjust
                            </button>
                            <button
                              type="button"
                              onClick={() => {
                                setSelectedItem(item);
                                setEditPrice(item.selling_price.toString());
                                setEditThreshold(item.low_stock_threshold.toString());
                                setEditAvailable(item.is_available);
                                setErrorMsg(null);
                                setSuccessMsg(null);
                                setShowPricingModal(true);
                              }}
                              aria-label="Edit item pricing and threshold"
                              className="p-1 text-slate-400 hover:text-slate-700 rounded-lg transition-colors"
                            >
                              <Sliders className="w-3.5 h-3.5" />
                            </button>
                          </td>
                        )}
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          )}
        </div>
      ) : (
        /* Stock Movements Audit Log Table */
        <div className="bg-white rounded-xl border border-slate-200 shadow-xs overflow-hidden">
          <div className="p-4 border-b border-slate-100 flex items-center justify-between">
            <div className="flex items-center gap-2">
              <History className="w-4 h-4 text-indigo-600" />
              <h3 className="text-sm font-bold text-slate-800">
                Stock Movements Ledger - {activeShop.name}
              </h3>
            </div>
            <span className="text-xs font-medium text-slate-400">
              Zero-trust auditable movement stream
            </span>
          </div>

          <div className="overflow-x-auto">
            <table className="w-full text-left border-collapse text-xs">
              <thead>
                <tr className="bg-slate-50/70 border-b border-slate-100 text-[11px] font-semibold text-slate-500 uppercase tracking-wider">
                  <th className="py-3 px-5">Timestamp</th>
                  <th className="py-3 px-4">Event Type</th>
                  <th className="py-3 px-4">Product</th>
                  <th className="py-3 px-4 text-right">Quantity Delta</th>
                  <th className="py-3 px-4 text-right">Balance After</th>
                  <th className="py-3 px-4">Auditable Reason</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-100">
                {stockMovements.map((mov) => {
                  const isPositive = Number(mov.delta_quantity) > 0;
                  return (
                    <tr key={mov.id} className="hover:bg-slate-50/60">
                      <td className="py-3 px-5 text-slate-500 font-mono text-[11px]">
                        {new Date(mov.created_at).toLocaleString()}
                      </td>
                      <td className="py-3 px-4">
                        <span
                          className={`px-2 py-0.5 rounded text-[10px] font-bold ${
                            mov.movement_type === 'RESTOCK' || mov.movement_type === 'INITIAL'
                              ? 'bg-emerald-50 text-emerald-700'
                              : mov.movement_type === 'SALE'
                              ? 'bg-blue-50 text-blue-700'
                              : 'bg-amber-50 text-amber-700'
                          }`}
                        >
                          {mov.movement_type}
                        </span>
                      </td>
                      <td className="py-3 px-4 font-semibold text-slate-900">
                        {mov.product?.name || 'Item'}
                      </td>
                      <td className="py-3 px-4 text-right font-mono font-bold">
                        <span className={isPositive ? 'text-emerald-600' : 'text-slate-700'}>
                          {isPositive ? `+${mov.delta_quantity}` : mov.delta_quantity}
                        </span>
                      </td>
                      <td className="py-3 px-4 text-right font-mono text-slate-600">
                        {Number(mov.quantity_after).toFixed(3)}
                      </td>
                      <td className="py-3 px-4 text-slate-500 italic max-w-xs truncate">
                        {mov.reason || '-'}
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {/* Modal: Setup Initial Inventory */}
      {showSetupModal && (
        <div className="fixed inset-0 z-50 bg-slate-900/60 backdrop-blur-xs flex items-center justify-center p-4">
          <div className="bg-white rounded-2xl max-w-md w-full p-6 shadow-2xl border border-slate-200">
            <h3 className="text-base font-bold text-slate-900 mb-1">Add Product to Shop Inventory</h3>
            <p className="text-xs text-slate-500 mb-4">
              Enrolls a catalog product with selling price and starting stock for {activeShop.name}.
            </p>

            {errorMsg && (
              <div className="mb-4 p-3 bg-rose-50 border border-rose-200 text-rose-700 rounded-xl text-xs flex items-start gap-2">
                <AlertCircle className="w-4 h-4 flex-shrink-0 mt-0.5" />
                <span>{errorMsg}</span>
              </div>
            )}

            {successMsg && (
              <div className="mb-4 p-3 bg-emerald-50 border border-emerald-200 text-emerald-700 rounded-xl text-xs flex items-start gap-2">
                <CheckCircle2 className="w-4 h-4 flex-shrink-0 mt-0.5" />
                <span>{successMsg}</span>
              </div>
            )}

            <form onSubmit={handleSetupInventory} className="space-y-3">
              <div>
                <label className="block text-xs font-semibold text-slate-700 mb-1">Select Product *</label>
                <select
                  required
                  value={setupProductId}
                  onChange={(e) => setSetupProductId(e.target.value)}
                  aria-label="Select catalog product for inventory setup"
                  className="w-full px-3 py-2 bg-slate-50 border border-slate-300 rounded-xl text-xs text-slate-800 focus:outline-none focus:ring-2 focus:ring-indigo-500"
                >
                  {unconfiguredProducts.map((p) => (
                    <option key={p.id} value={p.id}>
                      {p.name} ({p.unit_type})
                    </option>
                  ))}
                </select>
              </div>

              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label className="block text-xs font-semibold text-slate-700 mb-1">
                    Selling Price ({activeShop.currency}) *
                  </label>
                  <input
                    type="number"
                    step="0.01"
                    min="0"
                    required
                    value={setupPrice}
                    onChange={(e) => setSetupPrice(e.target.value)}
                    placeholder="99.00"
                    className="w-full px-3 py-2 bg-slate-50 border border-slate-300 rounded-xl text-xs text-slate-800 focus:outline-none focus:ring-2 focus:ring-indigo-500 font-mono"
                  />
                </div>

                <div>
                  <label className="block text-xs font-semibold text-slate-700 mb-1">
                    Starting Stock
                  </label>
                  <input
                    type="number"
                    step="any"
                    min="0"
                    value={setupQty}
                    onChange={(e) => setSetupQty(e.target.value)}
                    placeholder="0"
                    className="w-full px-3 py-2 bg-slate-50 border border-slate-300 rounded-xl text-xs text-slate-800 focus:outline-none focus:ring-2 focus:ring-indigo-500 font-mono"
                  />
                </div>
              </div>

              <div>
                <label className="block text-xs font-semibold text-slate-700 mb-1">
                  Low Stock Warning Threshold
                </label>
                <input
                  type="number"
                  step="any"
                  min="0"
                  value={setupThreshold}
                  onChange={(e) => setSetupThreshold(e.target.value)}
                  className="w-full px-3 py-2 bg-slate-50 border border-slate-300 rounded-xl text-xs text-slate-800 focus:outline-none focus:ring-2 focus:ring-indigo-500 font-mono"
                />
              </div>

              <div className="flex items-center justify-end gap-2 pt-3 border-t border-slate-100">
                <button
                  type="button"
                  onClick={() => setShowSetupModal(false)}
                  className="px-4 py-2 text-xs font-medium text-slate-600 hover:bg-slate-100 rounded-xl"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  disabled={actionLoading}
                  className="px-4 py-2 text-xs font-semibold text-white bg-indigo-600 hover:bg-indigo-500 rounded-xl disabled:opacity-50"
                >
                  {actionLoading ? 'Saving...' : 'Add to Inventory'}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {/* Modal: Restock Inventory */}
      {showRestockModal && selectedItem && (
        <div className="fixed inset-0 z-50 bg-slate-900/60 backdrop-blur-xs flex items-center justify-center p-4">
          <div className="bg-white rounded-2xl max-w-md w-full p-6 shadow-2xl border border-slate-200">
            <h3 className="text-base font-bold text-slate-900 mb-1">
              Restock {selectedItem.product?.name}
            </h3>
            <p className="text-xs text-slate-500 mb-4">
              Current shelf stock: {selectedItem.quantity} ({selectedItem.product?.unit_type})
            </p>

            {errorMsg && (
              <div className="mb-4 p-3 bg-rose-50 border border-rose-200 text-rose-700 rounded-xl text-xs flex items-start gap-2">
                <AlertCircle className="w-4 h-4 flex-shrink-0 mt-0.5" />
                <span>{errorMsg}</span>
              </div>
            )}

            {successMsg && (
              <div className="mb-4 p-3 bg-emerald-50 border border-emerald-200 text-emerald-700 rounded-xl text-xs flex items-start gap-2">
                <CheckCircle2 className="w-4 h-4 flex-shrink-0 mt-0.5" />
                <span>{successMsg}</span>
              </div>
            )}

            <form onSubmit={handleRestock} className="space-y-3">
              <div>
                <label className="block text-xs font-semibold text-slate-700 mb-1">
                  Quantity to Add ({selectedItem.product?.unit_type === 'PACKAGED' ? 'Whole Pieces' : 'kg, max 3 dec'}) *
                </label>
                <input
                  type="number"
                  step={selectedItem.product?.unit_type === 'PACKAGED' ? '1' : '0.001'}
                  min={selectedItem.product?.unit_type === 'PACKAGED' ? '1' : '0.001'}
                  required
                  value={restockQty}
                  onChange={(e) => setRestockQty(e.target.value)}
                  placeholder={selectedItem.product?.unit_type === 'PACKAGED' ? '10' : '5.500'}
                  className="w-full px-3 py-2 bg-slate-50 border border-slate-300 rounded-xl text-xs text-slate-800 focus:outline-none focus:ring-2 focus:ring-indigo-500 font-mono"
                />
              </div>

              <div>
                <label className="block text-xs font-semibold text-slate-700 mb-1">
                  Shipment Reason / Notes
                </label>
                <input
                  type="text"
                  value={restockReason}
                  onChange={(e) => setRestockReason(e.target.value)}
                  placeholder="e.g. Weekly dairy delivery invoice #889"
                  className="w-full px-3 py-2 bg-slate-50 border border-slate-300 rounded-xl text-xs text-slate-800 focus:outline-none focus:ring-2 focus:ring-indigo-500"
                />
              </div>

              <div className="flex items-center justify-end gap-2 pt-3 border-t border-slate-100">
                <button
                  type="button"
                  onClick={() => setShowRestockModal(false)}
                  className="px-4 py-2 text-xs font-medium text-slate-600 hover:bg-slate-100 rounded-xl"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  disabled={actionLoading}
                  className="px-4 py-2 text-xs font-semibold text-white bg-emerald-600 hover:bg-emerald-500 rounded-xl disabled:opacity-50"
                >
                  {actionLoading ? 'Recording...' : 'Confirm Restock'}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {/* Modal: Adjust Inventory */}
      {showAdjustModal && selectedItem && (
        <div className="fixed inset-0 z-50 bg-slate-900/60 backdrop-blur-xs flex items-center justify-center p-4">
          <div className="bg-white rounded-2xl max-w-md w-full p-6 shadow-2xl border border-slate-200">
            <h3 className="text-base font-bold text-slate-900 mb-1">
              Adjust Stock: {selectedItem.product?.name}
            </h3>
            <p className="text-xs text-slate-500 mb-4">
              Current recorded stock: {selectedItem.quantity}. Mandatory reason required for auditable adjustment.
            </p>

            {errorMsg && (
              <div className="mb-4 p-3 bg-rose-50 border border-rose-200 text-rose-700 rounded-xl text-xs flex items-start gap-2">
                <AlertCircle className="w-4 h-4 flex-shrink-0 mt-0.5" />
                <span>{errorMsg}</span>
              </div>
            )}

            {successMsg && (
              <div className="mb-4 p-3 bg-emerald-50 border border-emerald-200 text-emerald-700 rounded-xl text-xs flex items-start gap-2">
                <CheckCircle2 className="w-4 h-4 flex-shrink-0 mt-0.5" />
                <span>{successMsg}</span>
              </div>
            )}

            <form onSubmit={handleAdjust} className="space-y-3">
              <div>
                <label className="block text-xs font-semibold text-slate-700 mb-1">
                  New Exact Shelf Quantity *
                </label>
                <input
                  type="number"
                  step={selectedItem.product?.unit_type === 'PACKAGED' ? '1' : '0.001'}
                  min="0"
                  required
                  value={adjustQty}
                  onChange={(e) => setAdjustQty(e.target.value)}
                  className="w-full px-3 py-2 bg-slate-50 border border-slate-300 rounded-xl text-xs text-slate-800 focus:outline-none focus:ring-2 focus:ring-indigo-500 font-mono"
                />
              </div>

              <div>
                <label className="block text-xs font-semibold text-slate-700 mb-1">
                  Audit Reason (Minimum 3 chars) *
                </label>
                <input
                  type="text"
                  required
                  minLength={3}
                  value={adjustReason}
                  onChange={(e) => setAdjustReason(e.target.value)}
                  placeholder="e.g. Physical inventory count discrepancy / spoilage"
                  className="w-full px-3 py-2 bg-slate-50 border border-slate-300 rounded-xl text-xs text-slate-800 focus:outline-none focus:ring-2 focus:ring-indigo-500"
                />
              </div>

              <div className="flex items-center justify-end gap-2 pt-3 border-t border-slate-100">
                <button
                  type="button"
                  onClick={() => setShowAdjustModal(false)}
                  className="px-4 py-2 text-xs font-medium text-slate-600 hover:bg-slate-100 rounded-xl"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  disabled={actionLoading}
                  className="px-4 py-2 text-xs font-semibold text-white bg-slate-800 hover:bg-slate-700 rounded-xl disabled:opacity-50"
                >
                  {actionLoading ? 'Updating...' : 'Save Adjustment'}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {/* Modal: Edit Pricing */}
      {showPricingModal && selectedItem && (
        <div className="fixed inset-0 z-50 bg-slate-900/60 backdrop-blur-xs flex items-center justify-center p-4">
          <div className="bg-white rounded-2xl max-w-sm w-full p-6 shadow-2xl border border-slate-200">
            <h3 className="text-base font-bold text-slate-900 mb-1">
              Pricing: {selectedItem.product?.name}
            </h3>
            <p className="text-xs text-slate-500 mb-4">Update price without modifying stock levels.</p>

            {errorMsg && (
              <div className="mb-4 p-3 bg-rose-50 border border-rose-200 text-rose-700 rounded-xl text-xs flex items-start gap-2">
                <AlertCircle className="w-4 h-4 flex-shrink-0 mt-0.5" />
                <span>{errorMsg}</span>
              </div>
            )}

            {successMsg && (
              <div className="mb-4 p-3 bg-emerald-50 border border-emerald-200 text-emerald-700 rounded-xl text-xs flex items-start gap-2">
                <CheckCircle2 className="w-4 h-4 flex-shrink-0 mt-0.5" />
                <span>{successMsg}</span>
              </div>
            )}

            <form onSubmit={handleUpdatePricing} className="space-y-3">
              <div>
                <label className="block text-xs font-semibold text-slate-700 mb-1">
                  Selling Price ({activeShop.currency}) *
                </label>
                <input
                  type="number"
                  step="0.01"
                  min="0"
                  required
                  value={editPrice}
                  onChange={(e) => setEditPrice(e.target.value)}
                  className="w-full px-3 py-2 bg-slate-50 border border-slate-300 rounded-xl text-xs text-slate-800 focus:outline-none focus:ring-2 focus:ring-indigo-500 font-mono"
                />
              </div>

              <div>
                <label className="block text-xs font-semibold text-slate-700 mb-1">
                  Low Stock Threshold
                </label>
                <input
                  type="number"
                  step="any"
                  min="0"
                  value={editThreshold}
                  onChange={(e) => setEditThreshold(e.target.value)}
                  className="w-full px-3 py-2 bg-slate-50 border border-slate-300 rounded-xl text-xs text-slate-800 focus:outline-none focus:ring-2 focus:ring-indigo-500 font-mono"
                />
              </div>

              <div className="flex items-center gap-2 pt-1">
                <input
                  type="checkbox"
                  id="availCheck"
                  checked={editAvailable}
                  onChange={(e) => setEditAvailable(e.target.checked)}
                  className="rounded border-slate-300 text-indigo-600 focus:ring-indigo-500"
                />
                <label htmlFor="availCheck" className="text-xs font-medium text-slate-700">
                  Available for Checkout
                </label>
              </div>

              <div className="flex items-center justify-end gap-2 pt-3 border-t border-slate-100">
                <button
                  type="button"
                  onClick={() => setShowPricingModal(false)}
                  className="px-4 py-2 text-xs font-medium text-slate-600 hover:bg-slate-100 rounded-xl"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  disabled={actionLoading}
                  className="px-4 py-2 text-xs font-semibold text-white bg-indigo-600 hover:bg-indigo-500 rounded-xl disabled:opacity-50"
                >
                  {actionLoading ? 'Saving...' : 'Update Price'}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
};
