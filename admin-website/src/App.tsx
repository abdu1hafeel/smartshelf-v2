// ==============================================================================
// SmartShelf V2 - Main Retail Admin Dashboard Application
// ==============================================================================

import React, { useState } from 'react';
import { AuthProvider, useAuth } from './context/AuthContext';
import { isSupabaseConfigured } from './lib/supabase';
import { ConfigNotice } from './components/ConfigNotice';
import { AuthView } from './components/AuthView';
import { Sidebar, type NavTab } from './components/Sidebar';
import { Header } from './components/Header';
import { DashboardView } from './components/DashboardView';
import { InventoryView } from './components/InventoryView';
import { ProductsView } from './components/ProductsView';
import { DevicesView } from './components/DevicesView';
import { OrganizationView } from './components/OrganizationView';

const TAB_METADATA: Record<NavTab, { title: string; subtitle: string }> = {
  dashboard: {
    title: 'Dashboard Overview',
    subtitle: 'Real-time retail operational KPIs and sales activity',
  },
  inventory: {
    title: 'Shop Inventory & Stock Movements',
    subtitle: 'Manage shelf stock levels, pricing, and view auditable inventory movements',
  },
  products: {
    title: 'Master Product Catalog',
    subtitle: 'Define packaged and loose weighed products across the organization',
  },
  devices: {
    title: 'Scale Device Management',
    subtitle: 'Enroll, calibrate, and monitor IoT load-cell scale controllers',
  },
  organization: {
    title: 'Shops & Organization Governance',
    subtitle: 'Manage multi-tenant organization structure, locations, and access',
  },
};

const MainLayout: React.FC = () => {
  const { user, loading, refreshTenantData } = useAuth();
  const [currentTab, setCurrentTab] = useState<NavTab>('dashboard');
  const [isRefreshing, setIsRefreshing] = useState(false);

  const handleRefresh = async () => {
    setIsRefreshing(true);
    try {
      await refreshTenantData();
    } finally {
      setIsRefreshing(false);
    }
  };

  if (loading) {
    return (
      <div className="min-h-screen bg-slate-900 flex flex-col items-center justify-center p-4">
        <div className="w-10 h-10 border-3 border-indigo-500/20 border-t-indigo-500 rounded-full animate-spin mb-3"></div>
        <p className="text-xs font-semibold text-slate-400">Loading SmartShelf V2 Admin...</p>
      </div>
    );
  }

  if (!user) {
    return <AuthView />;
  }

  const { title, subtitle } = TAB_METADATA[currentTab];

  return (
    <div className="flex h-screen w-screen overflow-hidden bg-slate-50">
      {/* Sidebar Navigation */}
      <Sidebar currentTab={currentTab} onSelectTab={setCurrentTab} />

      {/* Main Content Area */}
      <div className="flex-1 flex flex-col min-w-0 h-screen overflow-hidden">
        <Header
          title={title}
          subtitle={subtitle}
          onRefresh={handleRefresh}
          isRefreshing={isRefreshing}
        />

        <main className="flex-1 overflow-y-auto">
          {currentTab === 'dashboard' && <DashboardView />}
          {currentTab === 'inventory' && <InventoryView />}
          {currentTab === 'products' && <ProductsView />}
          {currentTab === 'devices' && <DevicesView />}
          {currentTab === 'organization' && <OrganizationView />}
        </main>
      </div>
    </div>
  );
};

export default function App() {
  if (!isSupabaseConfigured) {
    return <ConfigNotice />;
  }

  return (
    <AuthProvider>
      <MainLayout />
    </AuthProvider>
  );
}
