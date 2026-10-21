// ==============================================================================
// SmartShelf V2 - Navigation Sidebar
// ==============================================================================

import React from 'react';
import { useAuth } from '../context/AuthContext';
import {
  LayoutDashboard,
  Boxes,
  Tag,
  Scale,
  Building2,
  LogOut,
  ShieldCheck,
  Store,
} from 'lucide-react';

export type NavTab = 'dashboard' | 'inventory' | 'products' | 'devices' | 'organization';

interface SidebarProps {
  currentTab: NavTab;
  onSelectTab: (tab: NavTab) => void;
}

export const Sidebar: React.FC<SidebarProps> = ({ currentTab, onSelectTab }) => {
  const { activeOrg, organizations, isOrgAdmin, isShopAdmin, signOut, profile, user } = useAuth();

  const navItems: { id: NavTab; label: string; icon: React.ComponentType<{ className?: string }> }[] = [
    { id: 'dashboard', label: 'Overview', icon: LayoutDashboard },
    { id: 'inventory', label: 'Shop Inventory', icon: Boxes },
    { id: 'products', label: 'Product Catalog', icon: Tag },
    { id: 'devices', label: 'Scale Devices', icon: Scale },
    { id: 'organization', label: 'Shops & Organization', icon: Building2 },
  ];

  const roleLabel = isOrgAdmin
    ? 'Organization Admin'
    : isShopAdmin
    ? 'Shop Administrator'
    : 'Shopkeeper / Cashier';

  return (
    <aside className="w-64 bg-slate-900 border-r border-slate-800 flex flex-col h-screen select-none flex-shrink-0">
      {/* Brand Header */}
      <div className="p-5 border-b border-slate-800/80 flex items-center gap-3">
        <div className="w-9 h-9 rounded-xl bg-indigo-600 flex items-center justify-center text-white shadow-md shadow-indigo-600/30">
          <Scale className="w-5 h-5" />
        </div>
        <div>
          <h2 className="text-sm font-bold text-white tracking-tight leading-none">SmartShelf V2</h2>
          <span className="text-[11px] text-slate-400 font-medium">Retail Platform</span>
        </div>
      </div>

      {/* Organization Badge */}
      <div className="px-4 py-3 mx-3 my-3 bg-slate-800/60 rounded-xl border border-slate-700/50">
        <div className="flex items-center gap-2 text-slate-400 text-xs mb-1">
          <Store className="w-3.5 h-3.5 text-indigo-400" />
          <span className="font-medium uppercase tracking-wider text-[10px]">Active Tenant</span>
        </div>
        <p
          className="text-sm font-semibold text-white truncate"
          title={activeOrg ? `${activeOrg.name} (${activeOrg.id})` : undefined}
        >
          {activeOrg
            ? organizations.filter((o) => o.name.toLowerCase() === activeOrg.name.toLowerCase()).length > 1
              ? `${activeOrg.name} (${activeOrg.id.slice(0, 8)})`
              : activeOrg.name
            : 'No Organization Selected'}
        </p>
      </div>

      {/* Navigation Links */}
      <nav className="flex-1 px-3 space-y-1 overflow-y-auto">
        {navItems.map((item) => {
          const Icon = item.icon;
          const isActive = currentTab === item.id;
          return (
            <button
              key={item.id}
              type="button"
              onClick={() => onSelectTab(item.id)}
              className={`w-full flex items-center gap-3 px-3.5 py-2.5 rounded-xl text-sm font-medium transition-all ${
                isActive
                  ? 'bg-indigo-600 text-white shadow-md shadow-indigo-600/20'
                  : 'text-slate-400 hover:text-slate-200 hover:bg-slate-800/60'
              }`}
            >
              <Icon className={`w-4 h-4 ${isActive ? 'text-white' : 'text-slate-400'}`} />
              {item.label}
            </button>
          );
        })}
      </nav>

      {/* User & Role Section */}
      <div className="p-4 border-t border-slate-800/80 bg-slate-900/50">
        <div className="flex items-center gap-3 mb-3">
          <div className="w-9 h-9 rounded-full bg-slate-800 border border-slate-700 flex items-center justify-center text-slate-300 font-semibold text-xs">
            {(profile?.full_name || user?.email || 'U')[0].toUpperCase()}
          </div>
          <div className="flex-1 min-w-0">
            <p className="text-xs font-semibold text-white truncate">
              {profile?.full_name || user?.email}
            </p>
            <div className="flex items-center gap-1 text-[11px] text-emerald-400 font-medium">
              <ShieldCheck className="w-3 h-3" />
              <span className="truncate">{roleLabel}</span>
            </div>
          </div>
        </div>

        <button
          type="button"
          onClick={signOut}
          className="w-full flex items-center justify-center gap-2 py-2 px-3 text-xs font-medium text-slate-400 hover:text-rose-400 hover:bg-rose-500/10 rounded-lg transition-colors border border-transparent hover:border-rose-500/20"
        >
          <LogOut className="w-3.5 h-3.5" /> Sign Out
        </button>
      </div>
    </aside>
  );
};
