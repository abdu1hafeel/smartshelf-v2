// ==============================================================================
// SmartShelf V2 - Organization Onboarding & Shop Management
// ==============================================================================

import React, { useState, useEffect, useCallback } from 'react';
import { useAuth } from '../context/AuthContext';
import { supabase } from '../lib/supabase';
import type { OrganizationMembership } from '../types/database';
import {
  Building2,
  Store,
  Plus,
  Users,
  ShieldCheck,
  CheckCircle2,
  AlertCircle,
  MapPin,
  Calendar,
} from 'lucide-react';

export const OrganizationView: React.FC = () => {
  const {
    activeOrg,
    organizations,
    setActiveOrg,
    shops,
    isOrgAdmin,
    refreshTenantData,
  } = useAuth();

  const [members, setMembers] = useState<OrganizationMembership[]>([]);
  const [loadingMembers, setLoadingMembers] = useState(false);

  // Modals
  const [showOrgModal, setShowOrgModal] = useState(false);
  const [showShopModal, setShowShopModal] = useState(false);

  // Form States
  const [newOrgName, setNewOrgName] = useState('');
  const [newShopName, setNewShopName] = useState('');
  const [newShopLocation, setNewShopLocation] = useState('');
  const [newShopCurrency, setNewShopCurrency] = useState('INR');

  // Feedback State
  const [submitting, setSubmitting] = useState(false);
  const [errorMsg, setErrorMsg] = useState<string | null>(null);
  const [successMsg, setSuccessMsg] = useState<string | null>(null);

  const fetchMembers = useCallback(async () => {
    if (!activeOrg) return;
    setLoadingMembers(true);
    try {
      const { data: memData, error: memErr } = await supabase
        .from('organization_memberships')
        .select('*')
        .eq('organization_id', activeOrg.id)
        .order('created_at');

      if (memErr) {
        console.error('Error fetching members:', memErr);
        setMembers([]);
        return;
      }

      const memberships = (memData || []) as OrganizationMembership[];
      const userIds = memberships.map((m) => m.user_id).filter(Boolean);

      if (userIds.length > 0) {
        const { data: profData, error: profErr } = await supabase
          .from('profiles')
          .select('*')
          .in('id', userIds);

        if (profErr) {
          console.error('Error fetching member profiles:', profErr);
        }

        const profMap = new Map((profData || []).map((p) => [p.id, p]));
        const combined = memberships.map((m) => ({
          ...m,
          profile: profMap.get(m.user_id) || undefined,
        }));
        setMembers(combined);
      } else {
        setMembers(memberships);
      }
    } catch (err) {
      console.error('Failed to load team members:', err);
    } finally {
      setLoadingMembers(false);
    }
  }, [activeOrg]);

  useEffect(() => {
    fetchMembers();
  }, [fetchMembers]);

  // RPC: Create Organization Onboarding
  const handleCreateOrg = async (e: React.FormEvent) => {
    e.preventDefault();
    setErrorMsg(null);
    setSuccessMsg(null);
    setSubmitting(true);

    try {
      const { data, error } = await supabase.rpc('create_organization_onboarding', {
        p_org_name: newOrgName.trim(),
      });

      if (error) {
        setErrorMsg(error.message);
      } else if (data) {
        setSuccessMsg(`Organization "${data.organization_name}" onboarded successfully.`);
        setNewOrgName('');
        await refreshTenantData();
        setTimeout(() => setShowOrgModal(false), 800);
      }
    } catch (err: unknown) {
      setErrorMsg(err instanceof Error ? err.message : 'Organization onboarding failed');
    } finally {
      setSubmitting(false);
    }
  };

  // RPC: Create Shop
  const handleCreateShop = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!activeOrg) return;
    setErrorMsg(null);
    setSuccessMsg(null);
    setSubmitting(true);

    try {
      const { data, error } = await supabase.rpc('create_shop', {
        p_organization_id: activeOrg.id,
        p_name: newShopName.trim(),
        p_location: newShopLocation.trim() || null,
        p_currency: newShopCurrency.trim() || 'INR',
      });

      if (error) {
        setErrorMsg(error.message);
      } else if (data) {
        setSuccessMsg(`Shop location "${data.name}" provisioned successfully.`);
        setNewShopName('');
        setNewShopLocation('');
        await refreshTenantData();
        setTimeout(() => setShowShopModal(false), 800);
      }
    } catch (err: unknown) {
      setErrorMsg(err instanceof Error ? err.message : 'Shop creation failed');
    } finally {
      setSubmitting(false);
    }
  };

  // If user has zero organizations, show full onboarding hero card
  if (organizations.length === 0) {
    return (
      <div className="p-8 max-w-xl mx-auto mt-12">
        <div className="bg-white rounded-2xl border border-slate-200/90 shadow-xl p-8 text-center">
          <div className="w-14 h-14 bg-indigo-50 text-indigo-600 rounded-2xl flex items-center justify-center mx-auto mb-4">
            <Building2 className="w-7 h-7" />
          </div>
          <h2 className="text-xl font-bold text-slate-900">Welcome to SmartShelf V2</h2>
          <p className="text-xs text-slate-500 mt-2 mb-6 max-w-sm mx-auto">
            You are not currently enrolled in any organization. Initialize your retail tenant to begin stocking products and managing scale controllers.
          </p>

          {errorMsg && (
            <div className="mb-4 p-3 bg-rose-50 border border-rose-200 text-rose-700 rounded-xl text-xs flex items-start gap-2 text-left">
              <AlertCircle className="w-4 h-4 flex-shrink-0 mt-0.5" />
              <span>{errorMsg}</span>
            </div>
          )}

          {successMsg && (
            <div className="mb-4 p-3 bg-emerald-50 border border-emerald-200 text-emerald-700 rounded-xl text-xs flex items-start gap-2 text-left">
              <CheckCircle2 className="w-4 h-4 flex-shrink-0 mt-0.5" />
              <span>{successMsg}</span>
            </div>
          )}

          <form onSubmit={handleCreateOrg} className="space-y-4 text-left">
            <div>
              <label className="block text-xs font-semibold text-slate-700 mb-1">
                Organization / Company Legal Name *
              </label>
              <input
                type="text"
                required
                minLength={2}
                value={newOrgName}
                onChange={(e) => setNewOrgName(e.target.value)}
                placeholder="e.g. Acme Supermarkets Private Ltd"
                className="w-full px-3.5 py-2.5 bg-slate-50 border border-slate-300 rounded-xl text-xs text-slate-800 focus:outline-none focus:ring-2 focus:ring-indigo-500"
              />
            </div>

            <button
              type="submit"
              disabled={submitting}
              className="w-full py-3 bg-indigo-600 hover:bg-indigo-500 text-white font-semibold text-xs rounded-xl shadow-md shadow-indigo-600/30 transition-all disabled:opacity-50"
            >
              {submitting ? 'Initializing Tenant...' : 'Initialize Organization'}
            </button>
          </form>
        </div>
      </div>
    );
  }

  return (
    <div className="p-8 max-w-7xl mx-auto space-y-8">
      {/* Top Organization Header */}
      <div className="bg-white p-6 rounded-2xl border border-slate-200 shadow-xs flex flex-col md:flex-row md:items-center justify-between gap-4">
        <div>
          <div className="flex items-center gap-2 text-xs font-semibold text-indigo-600 uppercase tracking-wider mb-1">
            <Building2 className="w-4 h-4" />
            <span>Retail Organization</span>
          </div>
          <h2 className="text-xl font-bold text-slate-900">{activeOrg?.name}</h2>
          <div className="flex items-center gap-4 text-xs text-slate-400 mt-1">
            <span className="flex items-center gap-1 font-mono">
              ID: {activeOrg?.id}
            </span>
            <span>•</span>
            <span className="flex items-center gap-1">
              <Calendar className="w-3.5 h-3.5" />
              Since {activeOrg && new Date(activeOrg.created_at).toLocaleDateString()}
            </span>
          </div>
        </div>

        <div className="flex items-center gap-2 self-start md:self-auto">
          {organizations.length > 1 && (
            <select
              value={activeOrg?.id || ''}
              onChange={(e) => {
                const org = organizations.find((o) => o.id === e.target.value) || null;
                setActiveOrg(org);
              }}
              aria-label="Switch organization"
              className="px-3 py-2 bg-slate-50 border border-slate-200 rounded-xl text-xs font-semibold text-slate-700"
            >
              {organizations.map((org) => {
                const isDuplicate = organizations.filter((o) => o.name.toLowerCase() === org.name.toLowerCase()).length > 1;
                const label = isDuplicate ? `${org.name} (${org.id.slice(0, 8)})` : org.name;
                return (
                  <option key={org.id} value={org.id}>
                    {label}
                  </option>
                );
              })}
            </select>
          )}

          <button
            type="button"
            onClick={() => {
              setErrorMsg(null);
              setSuccessMsg(null);
              setShowOrgModal(true);
            }}
            className="px-3.5 py-2 text-xs font-semibold text-slate-700 bg-white border border-slate-200 hover:bg-slate-50 rounded-xl shadow-xs transition-all flex items-center gap-1.5"
          >
            <Plus className="w-3.5 h-3.5" /> New Org
          </button>
        </div>
      </div>

      {/* Grid: Shops & Members */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-8">
        {/* Shops Management */}
        <div className="bg-white rounded-xl border border-slate-200 shadow-xs overflow-hidden flex flex-col">
          <div className="p-5 border-b border-slate-100 flex items-center justify-between">
            <div className="flex items-center gap-2">
              <Store className="w-4 h-4 text-indigo-600" />
              <h3 className="text-sm font-bold text-slate-800">Retail Store Locations</h3>
            </div>
            {isOrgAdmin && (
              <button
                type="button"
                onClick={() => {
                  setErrorMsg(null);
                  setSuccessMsg(null);
                  setShowShopModal(true);
                }}
                className="px-3 py-1.5 text-xs font-semibold text-white bg-indigo-600 hover:bg-indigo-500 rounded-lg shadow-xs transition-all flex items-center gap-1"
              >
                <Plus className="w-3.5 h-3.5" /> Add Location
              </button>
            )}
          </div>

          <div className="p-5 divide-y divide-slate-100">
            {shops.length === 0 ? (
              <div className="text-center py-8 text-slate-400 text-xs">
                No store locations provisioned in this organization.
              </div>
            ) : (
              shops.map((shop) => (
                <div key={shop.id} className="py-3 first:pt-0 last:pb-0 flex items-center justify-between">
                  <div>
                    <h4 className="text-sm font-semibold text-slate-900">{shop.name}</h4>
                    {shop.location && (
                      <p className="text-xs text-slate-500 flex items-center gap-1 mt-0.5">
                        <MapPin className="w-3 h-3 text-slate-400" />
                        {shop.location}
                      </p>
                    )}
                  </div>
                  <span className="px-2 py-0.5 bg-slate-100 text-slate-700 rounded text-xs font-mono font-semibold">
                    {shop.currency}
                  </span>
                </div>
              ))
            )}
          </div>
        </div>

        {/* Team Members & RBAC Roles */}
        <div className="bg-white rounded-xl border border-slate-200 shadow-xs overflow-hidden flex flex-col">
          <div className="p-5 border-b border-slate-100 flex items-center justify-between">
            <div className="flex items-center gap-2">
              <Users className="w-4 h-4 text-indigo-600" />
              <h3 className="text-sm font-bold text-slate-800">Team & Governance</h3>
            </div>
            <span className="text-xs font-medium text-slate-400">
              {members.length} members
            </span>
          </div>

          <div className="p-5 divide-y divide-slate-100">
            {loadingMembers ? (
              <div className="text-center py-6 text-slate-400 text-xs">Loading team members...</div>
            ) : members.length === 0 ? (
              <div className="text-center py-6 text-slate-400 text-xs">No members found.</div>
            ) : (
              members.map((mem) => (
                <div key={mem.id} className="py-3 first:pt-0 last:pb-0 flex items-center justify-between">
                  <div>
                    <div className="text-xs font-semibold text-slate-900">
                      {mem.profile?.full_name || 'Member'}
                    </div>
                    <div className="text-[11px] text-slate-400 font-mono">{mem.user_id}</div>
                  </div>
                  <span
                    className={`inline-flex items-center gap-1 px-2.5 py-0.5 rounded-full text-[10px] font-bold ${
                      mem.role === 'ORG_ADMIN'
                        ? 'bg-purple-50 text-purple-700 border border-purple-200'
                        : 'bg-slate-100 text-slate-700 border border-slate-200'
                    }`}
                  >
                    <ShieldCheck className="w-3 h-3" />
                    {mem.role}
                  </span>
                </div>
              ))
            )}
          </div>

          <div className="p-4 bg-slate-50 border-t border-slate-100 text-[11px] text-slate-500">
            🔒 <strong>Protected Administrator Invariant:</strong> The database prevents demoting or deleting the final remaining active ORG_ADMIN.
          </div>
        </div>
      </div>

      {/* Modal: New Organization */}
      {showOrgModal && (
        <div className="fixed inset-0 z-50 bg-slate-900/60 backdrop-blur-xs flex items-center justify-center p-4">
          <div className="bg-white rounded-2xl max-w-md w-full p-6 shadow-2xl border border-slate-200">
            <h3 className="text-base font-bold text-slate-900 mb-1">Create New Organization</h3>
            <p className="text-xs text-slate-500 mb-4">
              Provisions a separate tenant with independent shops, products, and inventory.
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

            <form onSubmit={handleCreateOrg} className="space-y-3">
              <div>
                <label className="block text-xs font-semibold text-slate-700 mb-1">Organization Name *</label>
                <input
                  type="text"
                  required
                  minLength={2}
                  value={newOrgName}
                  onChange={(e) => setNewOrgName(e.target.value)}
                  placeholder="e.g. Metro Marts Ltd"
                  className="w-full px-3 py-2 bg-slate-50 border border-slate-300 rounded-xl text-xs text-slate-800 focus:outline-none focus:ring-2 focus:ring-indigo-500"
                />
              </div>

              <div className="flex items-center justify-end gap-2 pt-3 border-t border-slate-100">
                <button
                  type="button"
                  onClick={() => setShowOrgModal(false)}
                  className="px-4 py-2 text-xs font-medium text-slate-600 hover:bg-slate-100 rounded-xl"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  disabled={submitting}
                  className="px-4 py-2 text-xs font-semibold text-white bg-indigo-600 hover:bg-indigo-500 rounded-xl disabled:opacity-50"
                >
                  {submitting ? 'Creating...' : 'Create Organization'}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {/* Modal: New Shop */}
      {showShopModal && (
        <div className="fixed inset-0 z-50 bg-slate-900/60 backdrop-blur-xs flex items-center justify-center p-4">
          <div className="bg-white rounded-2xl max-w-md w-full p-6 shadow-2xl border border-slate-200">
            <h3 className="text-base font-bold text-slate-900 mb-1">Add Store Location</h3>
            <p className="text-xs text-slate-500 mb-4">
              Configures a new physical retail shop in {activeOrg?.name}.
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

            <form onSubmit={handleCreateShop} className="space-y-3">
              <div>
                <label className="block text-xs font-semibold text-slate-700 mb-1">Shop Name *</label>
                <input
                  type="text"
                  required
                  minLength={2}
                  value={newShopName}
                  onChange={(e) => setNewShopName(e.target.value)}
                  placeholder="e.g. Uptown Branch"
                  className="w-full px-3 py-2 bg-slate-50 border border-slate-300 rounded-xl text-xs text-slate-800 focus:outline-none focus:ring-2 focus:ring-indigo-500"
                />
              </div>

              <div>
                <label className="block text-xs font-semibold text-slate-700 mb-1">Location Address</label>
                <input
                  type="text"
                  value={newShopLocation}
                  onChange={(e) => setNewShopLocation(e.target.value)}
                  placeholder="e.g. 45 Commercial Street, Suite 10"
                  className="w-full px-3 py-2 bg-slate-50 border border-slate-300 rounded-xl text-xs text-slate-800 focus:outline-none focus:ring-2 focus:ring-indigo-500"
                />
              </div>

              <div>
                <label className="block text-xs font-semibold text-slate-700 mb-1">Currency *</label>
                <input
                  type="text"
                  required
                  value={newShopCurrency}
                  onChange={(e) => setNewShopCurrency(e.target.value.toUpperCase())}
                  placeholder="INR, USD, EUR, etc."
                  className="w-full px-3 py-2 bg-slate-50 border border-slate-300 rounded-xl text-xs text-slate-800 focus:outline-none focus:ring-2 focus:ring-indigo-500 font-mono uppercase"
                />
              </div>

              <div className="flex items-center justify-end gap-2 pt-3 border-t border-slate-100">
                <button
                  type="button"
                  onClick={() => setShowShopModal(false)}
                  className="px-4 py-2 text-xs font-medium text-slate-600 hover:bg-slate-100 rounded-xl"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  disabled={submitting}
                  className="px-4 py-2 text-xs font-semibold text-white bg-indigo-600 hover:bg-indigo-500 rounded-xl disabled:opacity-50"
                >
                  {submitting ? 'Provisioning...' : 'Provision Shop'}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
};
