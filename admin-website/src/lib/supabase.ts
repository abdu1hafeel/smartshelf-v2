// ==============================================================================
// SmartShelf V2 - Supabase Browser Client
// ==============================================================================

import { createClient } from '@supabase/supabase-js';

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL || '';
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY || '';

export const isSupabaseConfigured = Boolean(
  supabaseUrl &&
  supabaseAnonKey &&
  supabaseUrl !== 'https://your-project-ref.supabase.co' &&
  supabaseAnonKey !== 'your-anon-key-here'
);

// Fallback to dummy values if not configured so the app can mount and present the config screen
const effectiveUrl = isSupabaseConfigured ? supabaseUrl : 'https://placeholder.supabase.co';
const effectiveAnonKey = isSupabaseConfigured ? supabaseAnonKey : 'placeholder-anon-key';

export const supabase = createClient(effectiveUrl, effectiveAnonKey, {
  auth: {
    persistSession: true,
    autoRefreshToken: true,
    detectSessionInUrl: true,
  },
});
