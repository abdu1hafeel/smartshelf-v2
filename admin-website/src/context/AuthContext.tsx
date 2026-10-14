// ==============================================================================
// SmartShelf V2 - Authentication & Tenant Context
// ==============================================================================

import React, { createContext, useEffect, useState, useCallback } from 'react';
import type { User, Session } from '@supabase/supabase-js';
import { supabase, isSupabaseConfigured } from '../lib/supabase';
import type { Organization, Shop, Profile, OrganizationMembership, ShopMembership } from '../types/database';

interface AuthContextType {
  user: User | null;
  session: Session | null;
  profile: Profile | null;
  organizations: Organization[];
  activeOrg: Organization | null;
  setActiveOrg: (org: Organization | null) => void;
  shops: Shop[];
  activeShop: Shop | null;
  setActiveShop: (shop: Shop | null) => void;
  orgMembership: OrganizationMembership | null;
  shopMembership: ShopMembership | null;
  isOrgAdmin: boolean;
  isShopAdmin: boolean;
  loading: boolean;
  refreshTenantData: () => Promise<void>;
  signIn: (email: string, password: string) => Promise<{ error: Error | null }>;
  signUp: (email: string, password: string, fullName: string) => Promise<{ error: Error | null }>;
  signOut: () => Promise<void>;
}

export const AuthContext = createContext<AuthContextType | undefined>(undefined);

export const AuthProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const [user, setUser] = useState<User | null>(null);
  const [session, setSession] = useState<Session | null>(null);
  const [profile, setProfile] = useState<Profile | null>(null);
  const [organizations, setOrganizations] = useState<Organization[]>([]);
  const [activeOrg, setActiveOrg] = useState<Organization | null>(null);
  const [shops, setShops] = useState<Shop[]>([]);
  const [activeShop, setActiveShop] = useState<Shop | null>(null);
  const [orgMembership, setOrgMembership] = useState<OrganizationMembership | null>(null);
  const [shopMembership, setShopMembership] = useState<ShopMembership | null>(null);
  const [loading, setLoading] = useState(isSupabaseConfigured);

  const fetchTenantData = useCallback(async (currentUserId: string, preferredOrgId?: string, preferredShopId?: string) => {
    try {
      // 1. Fetch user profile
      const { data: prof } = await supabase
        .from('profiles')
        .select('*')
        .eq('id', currentUserId)
        .maybeSingle();

      if (prof) setProfile(prof as Profile);

      // 2. Fetch organizations accessible to this user
      const { data: orgs, error: orgsErr } = await supabase
        .from('organizations')
        .select('*')
        .order('name');

      if (orgsErr) {
        console.error('Error fetching organizations:', orgsErr);
        return;
      }

      const orgList: Organization[] = orgs || [];
      setOrganizations(orgList);

      const targetOrg = orgList.find((o) => o.id === preferredOrgId) || orgList[0] || null;
      setActiveOrg(targetOrg);

      if (targetOrg) {
        // Fetch membership for role resolution
        const { data: mem } = await supabase
          .from('organization_memberships')
          .select('*')
          .eq('organization_id', targetOrg.id)
          .eq('user_id', currentUserId)
          .maybeSingle();
        setOrgMembership(mem as OrganizationMembership | null);

        // Fetch shops in active org
        const { data: shopList } = await supabase
          .from('shops')
          .select('*')
          .eq('organization_id', targetOrg.id)
          .order('name');

        const loadedShops: Shop[] = shopList || [];
        setShops(loadedShops);

        const targetShop = loadedShops.find((s) => s.id === preferredShopId) || loadedShops[0] || null;
        setActiveShop(targetShop);

        if (targetShop) {
          const { data: sm } = await supabase
            .from('shop_memberships')
            .select('*')
            .eq('shop_id', targetShop.id)
            .eq('user_id', currentUserId)
            .maybeSingle();
          setShopMembership(sm as ShopMembership | null);
        } else {
          setShopMembership(null);
        }
      } else {
        setShops([]);
        setActiveShop(null);
        setOrgMembership(null);
        setShopMembership(null);
      }
    } catch (err) {
      console.error('Failed to load tenant data:', err);
    }
  }, []);

  const refreshTenantData = useCallback(async () => {
    if (user) {
      await fetchTenantData(user.id, activeOrg?.id, activeShop?.id);
    }
  }, [user, activeOrg?.id, activeShop?.id, fetchTenantData]);

  // Handle active organization switch
  const handleSetActiveOrg = useCallback((org: Organization | null) => {
    setActiveOrg(org);
    if (user && org) {
      fetchTenantData(user.id, org.id);
    } else {
      setShops([]);
      setActiveShop(null);
      setOrgMembership(null);
    }
  }, [user, fetchTenantData]);

  // Handle active shop switch
  const handleSetActiveShop = useCallback(async (shop: Shop | null) => {
    setActiveShop(shop);
    if (user && shop) {
      const { data: sm } = await supabase
        .from('shop_memberships')
        .select('*')
        .eq('shop_id', shop.id)
        .eq('user_id', user.id)
        .maybeSingle();
      setShopMembership(sm as ShopMembership | null);
    } else {
      setShopMembership(null);
    }
  }, [user]);

  useEffect(() => {
    if (!isSupabaseConfigured) {
      return;
    }

    // Check active session
    supabase.auth.getSession().then(({ data: { session: currentSession } }) => {
      setSession(currentSession);
      setUser(currentSession?.user ?? null);
      if (currentSession?.user) {
        fetchTenantData(currentSession.user.id).finally(() => setLoading(false));
      } else {
        setLoading(false);
      }
    });

    const { data: { subscription } } = supabase.auth.onAuthStateChange((_event, newSession) => {
      setSession(newSession);
      setUser(newSession?.user ?? null);
      if (newSession?.user) {
        fetchTenantData(newSession.user.id);
      } else {
        setProfile(null);
        setOrganizations([]);
        setActiveOrg(null);
        setShops([]);
        setActiveShop(null);
        setOrgMembership(null);
        setShopMembership(null);
      }
    });

    return () => {
      subscription.unsubscribe();
    };
  }, [fetchTenantData]);

  const signIn = async (email: string, password: string) => {
    const { error } = await supabase.auth.signInWithPassword({ email, password });
    return { error: error as Error | null };
  };

  const signUp = async (email: string, password: string, fullName: string) => {
    const { error } = await supabase.auth.signUp({
      email,
      password,
      options: {
        data: {
          full_name: fullName,
        },
      },
    });
    return { error: error as Error | null };
  };

  const signOut = async () => {
    await supabase.auth.signOut();
  };

  const isOrgAdmin = orgMembership?.role === 'ORG_ADMIN' && orgMembership.status === 'ACTIVE';
  const isShopAdmin = isOrgAdmin || (shopMembership?.role === 'SHOP_ADMIN' && shopMembership.status === 'ACTIVE');

  return (
    <AuthContext.Provider
      value={{
        user,
        session,
        profile,
        organizations,
        activeOrg,
        setActiveOrg: handleSetActiveOrg,
        shops,
        activeShop,
        setActiveShop: handleSetActiveShop,
        orgMembership,
        shopMembership,
        isOrgAdmin,
        isShopAdmin,
        loading,
        refreshTenantData,
        signIn,
        signUp,
        signOut,
      }}
    >
      {children}
    </AuthContext.Provider>
  );
};

export { useAuth } from './useAuth';
