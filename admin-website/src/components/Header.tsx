// ==============================================================================
// SmartShelf V2 - Top Application Header & Shop Selector
// ==============================================================================

import React from 'react';
import { useAuth } from '../context/AuthContext';
import { Store, Building2, ChevronDown, RefreshCw, Circle } from 'lucide-react';

interface HeaderProps {
  title: string;
  subtitle: string;
  onRefresh?: () => void;
  isRefreshing?: boolean;
}

export const Header: React.FC<HeaderProps> = ({ title, subtitle, onRefresh, isRefreshing }) => {
  const { organizations, activeOrg, setActiveOrg, shops, activeShop, setActiveShop } = useAuth();

  return (
    <header className="h-16 bg-white border-b border-slate-200 px-6 flex items-center justify-between flex-shrink-0">
      <div>
        <h1 className="text-lg font-bold text-slate-900 leading-tight">{title}</h1>
        <p className="text-xs text-slate-500">{subtitle}</p>
      </div>

      <div className="flex items-center gap-4">
        {/* Active Organization Selector */}
        <div className="flex items-center gap-2">
          <span className="text-xs font-medium text-slate-500">Org:</span>
          {organizations.length > 0 ? (
            <div className="relative">
              <select
                value={activeOrg?.id || ''}
                onChange={(e) => {
                  const selected = organizations.find((o) => o.id === e.target.value) || null;
                  setActiveOrg(selected);
                }}
                aria-label="Active Organization"
                className="appearance-none bg-slate-50 border border-slate-300 hover:border-slate-400 text-slate-800 text-xs font-semibold rounded-lg pl-8 pr-8 py-2 focus:outline-none focus:ring-2 focus:ring-indigo-500 cursor-pointer transition-all"
              >
                {organizations.map((org) => {
                  const isDuplicate =
                    organizations.filter((o) => o.name.toLowerCase() === org.name.toLowerCase()).length > 1;
                  const label = isDuplicate ? `${org.name} (${org.id.slice(0, 8)})` : org.name;
                  return (
                    <option key={org.id} value={org.id}>
                      {label}
                    </option>
                  );
                })}
              </select>
              <Building2 className="w-3.5 h-3.5 text-slate-500 absolute left-2.5 top-1/2 -translate-y-1/2 pointer-events-none" />
              <ChevronDown className="w-3.5 h-3.5 text-slate-500 absolute right-2.5 top-1/2 -translate-y-1/2 pointer-events-none" />
            </div>
          ) : (
            <span className="text-xs text-amber-600 bg-amber-50 px-2.5 py-1 rounded-md border border-amber-200 font-medium">
              No Organizations
            </span>
          )}
        </div>

        {/* Active Shop Selector */}
        {activeOrg && (
          <div className="flex items-center gap-2">
            <span className="text-xs font-medium text-slate-500">Shop:</span>
            {shops.length > 0 ? (
              <div className="relative">
                <select
                  value={activeShop?.id || ''}
                  onChange={(e) => {
                    const selected = shops.find((s) => s.id === e.target.value) || null;
                    setActiveShop(selected);
                  }}
                  aria-label="Active Shop Location"
                  className="appearance-none bg-slate-50 border border-slate-300 hover:border-slate-400 text-slate-800 text-xs font-semibold rounded-lg pl-8 pr-8 py-2 focus:outline-none focus:ring-2 focus:ring-indigo-500 cursor-pointer transition-all"
                >
                  {shops.map((s) => (
                    <option key={s.id} value={s.id}>
                      {s.name} ({s.currency})
                    </option>
                  ))}
                </select>
                <Store className="w-3.5 h-3.5 text-slate-500 absolute left-2.5 top-1/2 -translate-y-1/2 pointer-events-none" />
                <ChevronDown className="w-3.5 h-3.5 text-slate-500 absolute right-2.5 top-1/2 -translate-y-1/2 pointer-events-none" />
              </div>
            ) : (
              <span className="text-xs text-amber-600 bg-amber-50 px-2.5 py-1 rounded-md border border-amber-200 font-medium">
                No Shops Configured
              </span>
            )}
          </div>
        )}

        {/* Database Status indicator */}
        <div className="hidden sm:flex items-center gap-1.5 px-2.5 py-1 bg-slate-100 rounded-full text-[11px] font-medium text-slate-600">
          <Circle className="w-2 h-2 fill-emerald-500 text-emerald-500" />
          <span>Connected</span>
        </div>

        {/* Refresh Button */}
        {onRefresh && (
          <button
            type="button"
            onClick={onRefresh}
            disabled={isRefreshing}
            title="Refresh database records"
            aria-label="Refresh database records"
            className="p-2 text-slate-500 hover:text-slate-800 hover:bg-slate-100 rounded-lg transition-colors border border-slate-200 disabled:opacity-50"
          >
            <RefreshCw className={`w-4 h-4 ${isRefreshing ? 'animate-spin text-indigo-600' : ''}`} />
          </button>
        )}
      </div>
    </header>
  );
};
