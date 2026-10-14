// ==============================================================================
// SmartShelf V2 - Dashboard Overview (Real Database Metrics)
// ==============================================================================

import React, { useEffect, useState, useCallback } from 'react';
import { useAuth } from '../context/AuthContext';
import { supabase } from '../lib/supabase';
import type { Sale, StockMovement, ShopInventoryItem } from '../types/database';
import {
  Boxes,
  AlertTriangle,
  Scale,
  Receipt,
  TrendingUp,
  Clock,
  ArrowUpRight,
  ArrowDownRight,
  CheckCircle2,
} from 'lucide-react';

export const DashboardView: React.FC = () => {
  const { activeOrg, activeShop } = useAuth();
  const [totalProducts, setTotalProducts] = useState<number>(0);
  const [stockedItems, setStockedItems] = useState<ShopInventoryItem[]>([]);
  const [activeDeviceCount, setActiveDeviceCount] = useState<number>(0);
  const [recentSales, setRecentSales] = useState<Sale[]>([]);
  const [recentMovements, setRecentMovements] = useState<StockMovement[]>([]);
  const [loading, setLoading] = useState<boolean>(true);

  const fetchDashboardData = useCallback(async () => {
    if (!activeOrg) {
      setLoading(false);
      return;
    }
    setLoading(true);

    try {
      // 1. Total Catalog Products in Organization
      const { count: prodCount } = await supabase
        .from('products')
        .select('*', { count: 'exact', head: true })
        .eq('organization_id', activeOrg.id);

      setTotalProducts(prodCount || 0);

      if (activeShop) {
        // 2. Shop Inventory status
        const { data: invData } = await supabase
          .from('shop_inventory')
          .select('*, product:products(*)')
          .eq('shop_id', activeShop.id);

        const inventoryList: ShopInventoryItem[] = (invData as ShopInventoryItem[]) || [];
        setStockedItems(inventoryList);

        // 3. Active Scale Devices
        const { count: devCount } = await supabase
          .from('devices')
          .select('*', { count: 'exact', head: true })
          .eq('shop_id', activeShop.id)
          .eq('is_active', true);

        setActiveDeviceCount(devCount || 0);

        // 4. Recent Sales
        const { data: salesData } = await supabase
          .from('sales')
          .select('*')
          .eq('shop_id', activeShop.id)
          .order('created_at', { ascending: false })
          .limit(5);

        setRecentSales((salesData as Sale[]) || []);

        // 5. Recent Stock Movements
        const { data: movData, error: movErr } = await supabase
          .from('stock_movements')
          .select('*')
          .eq('shop_id', activeShop.id)
          .order('created_at', { ascending: false })
          .limit(6);

        if (movErr) console.error('Error fetching dashboard stock movements:', movErr);

        const invProductMap = new Map(inventoryList.map((item) => [item.product_id, item.product]));
        const movements = ((movData || []) as StockMovement[]).map((m) => ({
          ...m,
          product: invProductMap.get(m.product_id) || undefined,
        }));

        setRecentMovements(movements);
      } else {
        setStockedItems([]);
        setActiveDeviceCount(0);
        setRecentSales([]);
        setRecentMovements([]);
      }
    } catch (err) {
      console.error('Error loading dashboard metrics:', err);
    } finally {
      setLoading(false);
    }
  }, [activeOrg, activeShop]);

  useEffect(() => {
    fetchDashboardData();
  }, [fetchDashboardData]);

  const lowStockCount = stockedItems.filter(
    (item) => Number(item.quantity) <= Number(item.low_stock_threshold) && Number(item.quantity) > 0
  ).length;

  const outOfStockCount = stockedItems.filter((item) => Number(item.quantity) <= 0).length;

  const totalSalesRevenue = recentSales.reduce((acc, sale) => acc + Number(sale.total_amount), 0);

  if (loading) {
    return (
      <div className="p-8 flex items-center justify-center min-h-[400px]">
        <div className="flex flex-col items-center gap-3">
          <div className="w-8 h-8 border-3 border-indigo-600/20 border-t-indigo-600 rounded-full animate-spin"></div>
          <p className="text-xs text-slate-500 font-medium">Loading real-time metrics...</p>
        </div>
      </div>
    );
  }

  if (!activeOrg) {
    return (
      <div className="p-8 max-w-xl mx-auto text-center mt-12 bg-white rounded-2xl border border-slate-200 shadow-sm p-8">
        <Boxes className="w-12 h-12 text-slate-400 mx-auto mb-3" />
        <h3 className="text-base font-bold text-slate-800">No Organization Configured</h3>
        <p className="text-xs text-slate-500 mt-1 mb-4">
          Please complete organization onboarding in the Shops & Organization tab to initialize your tenant.
        </p>
      </div>
    );
  }

  return (
    <div className="p-8 space-y-8 max-w-7xl mx-auto">
      {/* KPI Cards Grid */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-5">
        {/* Total Catalog Products */}
        <div className="bg-white p-5 rounded-xl border border-slate-200/90 shadow-sm flex items-center justify-between">
          <div>
            <p className="text-xs font-semibold text-slate-500 uppercase tracking-wider">Catalog SKUs</p>
            <h3 className="text-2xl font-bold text-slate-900 mt-1">{totalProducts}</h3>
            <span className="text-[11px] text-slate-400 font-medium">Org-wide catalog</span>
          </div>
          <div className="w-11 h-11 rounded-xl bg-slate-100 flex items-center justify-center text-slate-600">
            <Boxes className="w-5 h-5" />
          </div>
        </div>

        {/* Low Stock Warning */}
        <div className="bg-white p-5 rounded-xl border border-slate-200/90 shadow-sm flex items-center justify-between">
          <div>
            <p className="text-xs font-semibold text-slate-500 uppercase tracking-wider">Stock Alerts</p>
            <h3 className="text-2xl font-bold text-amber-600 mt-1">
              {lowStockCount + outOfStockCount}
            </h3>
            <div className="flex items-center gap-1.5 text-[11px] text-slate-500 font-medium">
              <span className="text-amber-600">{lowStockCount} low</span>
              <span>•</span>
              <span className="text-rose-600">{outOfStockCount} out</span>
            </div>
          </div>
          <div className="w-11 h-11 rounded-xl bg-amber-50 flex items-center justify-center text-amber-600">
            <AlertTriangle className="w-5 h-5" />
          </div>
        </div>

        {/* Active Scale Devices */}
        <div className="bg-white p-5 rounded-xl border border-slate-200/90 shadow-sm flex items-center justify-between">
          <div>
            <p className="text-xs font-semibold text-slate-500 uppercase tracking-wider">Active Scales</p>
            <h3 className="text-2xl font-bold text-slate-900 mt-1">{activeDeviceCount}</h3>
            <div className="flex items-center gap-1 text-[11px] text-emerald-600 font-medium">
              <CheckCircle2 className="w-3 h-3" />
              <span>IoT Telemetry Online</span>
            </div>
          </div>
          <div className="w-11 h-11 rounded-xl bg-emerald-50 flex items-center justify-center text-emerald-600">
            <Scale className="w-5 h-5" />
          </div>
        </div>

        {/* Recent Sales Revenue */}
        <div className="bg-white p-5 rounded-xl border border-slate-200/90 shadow-sm flex items-center justify-between">
          <div>
            <p className="text-xs font-semibold text-slate-500 uppercase tracking-wider">Recent Volume</p>
            <h3 className="text-2xl font-bold text-indigo-600 mt-1">
              {activeShop?.currency || 'INR'} {totalSalesRevenue.toFixed(2)}
            </h3>
            <span className="text-[11px] text-slate-400 font-medium">
              {recentSales.length} confirmed checkouts
            </span>
          </div>
          <div className="w-11 h-11 rounded-xl bg-indigo-50 flex items-center justify-center text-indigo-600">
            <TrendingUp className="w-5 h-5" />
          </div>
        </div>
      </div>

      {/* Main Grid: Recent Sales & Stock Movements */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* Recent Confirmed Sales Table */}
        <div className="bg-white rounded-xl border border-slate-200/90 shadow-sm overflow-hidden flex flex-col">
          <div className="p-5 border-b border-slate-100 flex items-center justify-between">
            <div className="flex items-center gap-2">
              <Receipt className="w-4 h-4 text-indigo-600" />
              <h3 className="text-sm font-bold text-slate-800">Recent POS Checkouts</h3>
            </div>
            <span className="text-[11px] font-medium text-slate-400">Live transaction stream</span>
          </div>

          <div className="flex-1 overflow-x-auto">
            {recentSales.length === 0 ? (
              <div className="p-8 text-center text-slate-400 text-xs">
                No checkout transactions recorded for this shop yet.
              </div>
            ) : (
              <table className="w-full text-left border-collapse">
                <thead>
                  <tr className="bg-slate-50/70 border-b border-slate-100 text-[11px] font-semibold text-slate-500 uppercase tracking-wider">
                    <th className="py-2.5 px-4">Receipt #</th>
                    <th className="py-2.5 px-4">Payment</th>
                    <th className="py-2.5 px-4 text-right">Amount</th>
                    <th className="py-2.5 px-4 text-right">Time</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-slate-100 text-xs">
                  {recentSales.map((sale) => (
                    <tr key={sale.id} className="hover:bg-slate-50/50 transition-colors">
                      <td className="py-3 px-4 font-mono font-medium text-slate-900">
                        {sale.sale_number}
                      </td>
                      <td className="py-3 px-4">
                        <span className="px-2 py-0.5 rounded text-[10px] font-bold tracking-wider bg-slate-100 text-slate-700">
                          {sale.payment_method}
                        </span>
                      </td>
                      <td className="py-3 px-4 text-right font-semibold text-slate-900 font-mono">
                        {activeShop?.currency || 'INR'} {Number(sale.total_amount).toFixed(2)}
                      </td>
                      <td className="py-3 px-4 text-right text-slate-400 flex items-center justify-end gap-1">
                        <Clock className="w-3 h-3" />
                        {new Date(sale.created_at).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
          </div>
        </div>

        {/* Stock Movements Audit Trail */}
        <div className="bg-white rounded-xl border border-slate-200/90 shadow-sm overflow-hidden flex flex-col">
          <div className="p-5 border-b border-slate-100 flex items-center justify-between">
            <div className="flex items-center gap-2">
              <Boxes className="w-4 h-4 text-indigo-600" />
              <h3 className="text-sm font-bold text-slate-800">Inventory Movement Stream</h3>
            </div>
            <span className="text-[11px] font-medium text-slate-400">Auditable zero-trust ledger</span>
          </div>

          <div className="flex-1 overflow-x-auto">
            {recentMovements.length === 0 ? (
              <div className="p-8 text-center text-slate-400 text-xs">
                No stock movement events logged for this shop yet.
              </div>
            ) : (
              <table className="w-full text-left border-collapse">
                <thead>
                  <tr className="bg-slate-50/70 border-b border-slate-100 text-[11px] font-semibold text-slate-500 uppercase tracking-wider">
                    <th className="py-2.5 px-4">Type</th>
                    <th className="py-2.5 px-4">Product</th>
                    <th className="py-2.5 px-4 text-right">Delta</th>
                    <th className="py-2.5 px-4 text-right">Balance</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-slate-100 text-xs">
                  {recentMovements.map((mov) => {
                    const isPositive = Number(mov.delta_quantity) > 0;
                    return (
                      <tr key={mov.id} className="hover:bg-slate-50/50 transition-colors">
                        <td className="py-3 px-4">
                          <span
                            className={`px-2 py-0.5 rounded text-[10px] font-bold tracking-wider ${
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
                        <td className="py-3 px-4 font-medium text-slate-800 truncate max-w-[140px]">
                          {mov.product?.name || 'Item'}
                        </td>
                        <td className="py-3 px-4 text-right font-mono font-semibold">
                          <span
                            className={`inline-flex items-center ${
                              isPositive ? 'text-emerald-600' : 'text-slate-700'
                            }`}
                          >
                            {isPositive ? (
                              <ArrowUpRight className="w-3 h-3 mr-0.5" />
                            ) : (
                              <ArrowDownRight className="w-3 h-3 mr-0.5 text-slate-400" />
                            )}
                            {isPositive ? `+${mov.delta_quantity}` : mov.delta_quantity}
                          </span>
                        </td>
                        <td className="py-3 px-4 text-right font-mono text-slate-500">
                          {Number(mov.quantity_after).toFixed(3)}
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            )}
          </div>
        </div>
      </div>
    </div>
  );
};
