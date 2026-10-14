// ==============================================================================
// SmartShelf V2 - Missing Configuration Notice
// ==============================================================================

import React from 'react';
import { AlertTriangle, Key } from 'lucide-react';

export const ConfigNotice: React.FC = () => {
  return (
    <div className="min-h-screen bg-slate-900 flex items-center justify-center p-4">
      <div className="max-w-lg w-full bg-slate-800 border border-amber-500/30 rounded-2xl p-8 shadow-2xl">
        <div className="w-12 h-12 rounded-xl bg-amber-500/10 text-amber-400 flex items-center justify-center mb-4 border border-amber-500/20">
          <AlertTriangle className="w-6 h-6" />
        </div>
        <h2 className="text-xl font-bold text-white mb-2">Supabase Configuration Required</h2>
        <p className="text-xs text-slate-400 mb-6 leading-relaxed">
          The SmartShelf V2 admin website needs your Supabase project credentials to connect to the database.
          Please create a <code className="text-indigo-400 bg-slate-900 px-1.5 py-0.5 rounded">.env.local</code> file in <code className="text-indigo-400 bg-slate-900 px-1.5 py-0.5 rounded">admin-website/</code> using the template below:
        </p>

        <div className="bg-slate-900 p-4 rounded-xl border border-slate-700/80 font-mono text-xs text-slate-300 space-y-2 mb-6">
          <div className="text-slate-500"># admin-website/.env.local</div>
          <div><span className="text-indigo-400">VITE_SUPABASE_URL</span>=http://127.0.0.1:54321</div>
          <div><span className="text-indigo-400">VITE_SUPABASE_ANON_KEY</span>=your-anon-key-here</div>
        </div>

        <div className="flex items-center gap-2 text-xs text-slate-400 border-t border-slate-700/60 pt-4">
          <Key className="w-4 h-4 text-amber-400 flex-shrink-0" />
          <span>
            <strong>Security Notice:</strong> Only provide the public anonymous key. NEVER supply the service-role key in browser code.
          </span>
        </div>
      </div>
    </div>
  );
};
