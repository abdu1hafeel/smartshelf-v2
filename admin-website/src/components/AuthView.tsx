// ==============================================================================
// SmartShelf V2 - Authentication Screen
// ==============================================================================

import React, { useState } from 'react';
import { useAuth } from '../context/AuthContext';
import { LogIn, UserPlus, AlertCircle, Shield, CheckCircle2 } from 'lucide-react';

export const AuthView: React.FC = () => {
  const { signIn, signUp } = useAuth();
  const [isSignUp, setIsSignUp] = useState(false);
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [fullName, setFullName] = useState('');
  const [loading, setLoading] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [successMessage, setSuccessMessage] = useState<string | null>(null);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setErrorMessage(null);
    setSuccessMessage(null);
    setLoading(true);

    try {
      if (isSignUp) {
        if (!fullName.trim()) {
          setErrorMessage('Please enter your full name');
          setLoading(false);
          return;
        }
        const { error } = await signUp(email, password, fullName);
        if (error) {
          setErrorMessage(error.message);
        } else {
          setSuccessMessage('Account created successfully! Check your email if verification is required, or sign in.');
          setIsSignUp(false);
        }
      } else {
        const { error } = await signIn(email, password);
        if (error) {
          setErrorMessage(error.message);
        }
      }
    } catch (err: unknown) {
      setErrorMessage(err instanceof Error ? err.message : 'Authentication failed');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="min-h-screen bg-slate-900 flex flex-col justify-center items-center p-4">
      {/* Brand Header */}
      <div className="mb-8 text-center">
        <div className="inline-flex items-center justify-center w-14 h-14 rounded-2xl bg-indigo-600 text-white shadow-xl shadow-indigo-600/30 mb-4">
          <Shield className="w-8 h-8" />
        </div>
        <h1 className="text-3xl font-bold text-white tracking-tight">SmartShelf V2</h1>
        <p className="text-slate-400 text-sm mt-1">Retail Inventory & IoT Scale Control Portal</p>
      </div>

      {/* Card */}
      <div className="w-full max-w-md bg-slate-800 border border-slate-700/80 rounded-2xl shadow-2xl p-8">
        <div className="flex border-b border-slate-700 mb-6">
          <button
            type="button"
            onClick={() => { setIsSignUp(false); setErrorMessage(null); }}
            className={`flex-1 pb-3 text-sm font-semibold transition-colors flex items-center justify-center gap-2 ${
              !isSignUp ? 'text-indigo-400 border-b-2 border-indigo-500' : 'text-slate-400 hover:text-slate-200'
            }`}
          >
            <LogIn className="w-4 h-4" /> Sign In
          </button>
          <button
            type="button"
            onClick={() => { setIsSignUp(true); setErrorMessage(null); }}
            className={`flex-1 pb-3 text-sm font-semibold transition-colors flex items-center justify-center gap-2 ${
              isSignUp ? 'text-indigo-400 border-b-2 border-indigo-500' : 'text-slate-400 hover:text-slate-200'
            }`}
          >
            <UserPlus className="w-4 h-4" /> Register
          </button>
        </div>

        {errorMessage && (
          <div className="mb-5 p-3.5 bg-rose-500/10 border border-rose-500/20 rounded-xl flex items-start gap-3 text-rose-400 text-sm">
            <AlertCircle className="w-5 h-5 flex-shrink-0 mt-0.5" />
            <span>{errorMessage}</span>
          </div>
        )}

        {successMessage && (
          <div className="mb-5 p-3.5 bg-emerald-500/10 border border-emerald-500/20 rounded-xl flex items-start gap-3 text-emerald-400 text-sm">
            <CheckCircle2 className="w-5 h-5 flex-shrink-0 mt-0.5" />
            <span>{successMessage}</span>
          </div>
        )}

        <form onSubmit={handleSubmit} className="space-y-4">
          {isSignUp && (
            <div>
              <label className="block text-xs font-medium text-slate-300 mb-1">Full Name</label>
              <input
                type="text"
                required
                value={fullName}
                onChange={(e) => setFullName(e.target.value)}
                placeholder="Jane Doe"
                className="w-full px-3.5 py-2.5 bg-slate-900 border border-slate-700 rounded-xl text-white placeholder-slate-500 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:border-transparent transition-all"
              />
            </div>
          )}

          <div>
            <label className="block text-xs font-medium text-slate-300 mb-1">Email Address</label>
            <input
              type="email"
              required
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              placeholder="admin@smartshelf.retail"
              className="w-full px-3.5 py-2.5 bg-slate-900 border border-slate-700 rounded-xl text-white placeholder-slate-500 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:border-transparent transition-all"
            />
          </div>

          <div>
            <label className="block text-xs font-medium text-slate-300 mb-1">Password</label>
            <input
              type="password"
              required
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              placeholder="••••••••••••"
              minLength={6}
              className="w-full px-3.5 py-2.5 bg-slate-900 border border-slate-700 rounded-xl text-white placeholder-slate-500 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:border-transparent transition-all"
            />
          </div>

          <button
            type="submit"
            disabled={loading}
            className="w-full mt-2 py-3 px-4 bg-indigo-600 hover:bg-indigo-500 text-white font-medium text-sm rounded-xl shadow-lg shadow-indigo-600/30 transition-all disabled:opacity-50 disabled:cursor-not-allowed flex items-center justify-center gap-2"
          >
            {loading ? (
              <span className="w-5 h-5 border-2 border-white/20 border-t-white rounded-full animate-spin"></span>
            ) : isSignUp ? (
              <>Create Administrator Account</>
            ) : (
              <>Sign In to Dashboard</>
            )}
          </button>
        </form>

        <div className="mt-6 pt-5 border-t border-slate-700/60 text-center">
          <p className="text-xs text-slate-400">
            Protected by Row Level Security (RLS) & Zero-Trust engine permissions.
          </p>
        </div>
      </div>
    </div>
  );
};
