// ==============================================================================
// SmartShelf V2 - Scale Device Management & Hardware Lifecycle
// ==============================================================================

import React, { useState, useEffect, useCallback } from 'react';
import { useAuth } from '../context/AuthContext';
import { supabase } from '../lib/supabase';
import type { Device } from '../types/database';
import {
  Scale,
  Plus,
  Key,
  RotateCw,
  PowerOff,
  Copy,
  Check,
  CheckCircle2,
  AlertCircle,
  Cpu,
  Clock,
  ShieldAlert,
} from 'lucide-react';

export const DevicesView: React.FC = () => {
  const { activeShop, isShopAdmin } = useAuth();
  const [devices, setDevices] = useState<Device[]>([]);
  const [loading, setLoading] = useState(true);

  // Modals
  const [showEnrollModal, setShowEnrollModal] = useState(false);
  const [showRotateModal, setShowRotateModal] = useState(false);
  const [showRecoverModal, setShowRecoverModal] = useState(false);
  const [showCalibrateModal, setShowCalibrateModal] = useState(false);
  const [selectedDevice, setSelectedDevice] = useState<Device | null>(null);

  // Form: Enroll
  const [enrollIdentifier, setEnrollIdentifier] = useState('');
  const [enrollName, setEnrollName] = useState('');

  // Form: Recover
  const [recoverOffset, setRecoverOffset] = useState('10');

  // Form: Calibrate
  const [tareOffset, setTareOffset] = useState('0.0000');
  const [calibrationFactor, setCalibrationFactor] = useState('1.0000');

  // Generated Secret Reveal Modal
  const [revealedSecret, setRevealedSecret] = useState<{
    deviceId: string;
    secret: string;
    title: string;
    instructions?: string;
  } | null>(null);
  const [copied, setCopied] = useState(false);

  // Action feedback
  const [actionLoading, setActionLoading] = useState(false);
  const [errorMsg, setErrorMsg] = useState<string | null>(null);
  const [successMsg, setSuccessMsg] = useState<string | null>(null);

  const fetchDevices = useCallback(async () => {
    if (!activeShop) {
      setLoading(false);
      return;
    }
    setLoading(true);

    try {
      const { data, error } = await supabase
        .from('devices')
        .select('*')
        .eq('shop_id', activeShop.id)
        .order('created_at', { ascending: false });

      if (error) console.error('Error fetching devices:', error);
      setDevices((data as Device[]) || []);
    } catch (err) {
      console.error('Failed to load scale devices:', err);
    } finally {
      setLoading(false);
    }
  }, [activeShop]);

  useEffect(() => {
    fetchDevices();
  }, [fetchDevices]);

  // Copy helper
  const copyToClipboard = (text: string) => {
    navigator.clipboard.writeText(text);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  // RPC: Enroll Device
  const handleEnrollDevice = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!activeShop) return;
    setErrorMsg(null);
    setSuccessMsg(null);
    setActionLoading(true);

    try {
      const { data, error } = await supabase.rpc('enroll_device', {
        p_shop_id: activeShop.id,
        p_device_identifier: enrollIdentifier.trim(),
        p_name: enrollName.trim(),
      });

      if (error) {
        setErrorMsg(error.message);
      } else if (data) {
        setShowEnrollModal(false);
        setEnrollIdentifier('');
        setEnrollName('');
        setRevealedSecret({
          deviceId: data.device_id,
          secret: data.device_secret,
          title: `New Device Credentials: ${data.device_identifier}`,
          instructions:
            'Store this 256-bit secret token securely. Flash it into the ESP32 firmware DEVICE_SECRET definition. It will NEVER be shown again.',
        });
        await fetchDevices();
      }
    } catch (err: unknown) {
      setErrorMsg(err instanceof Error ? err.message : 'Device enrollment failed');
    } finally {
      setActionLoading(false);
    }
  };

  // RPC: Rotate Credentials
  const handleRotateCredentials = async () => {
    if (!selectedDevice) return;
    setErrorMsg(null);
    setActionLoading(true);

    try {
      const { data, error } = await supabase.rpc('rotate_device_credentials', {
        p_device_id: selectedDevice.id,
      });

      if (error) {
        setErrorMsg(error.message);
      } else if (data) {
        setShowRotateModal(false);
        setRevealedSecret({
          deviceId: selectedDevice.id,
          secret: data.new_device_secret,
          title: `Rotated Secret: ${selectedDevice.device_identifier}`,
          instructions:
            'Credentials rotated. Update the ESP32 DEVICE_SECRET. Sequence numbers and boot epoch are preserved.',
        });
        await fetchDevices();
      }
    } catch (err: unknown) {
      setErrorMsg(err instanceof Error ? err.message : 'Rotation failed');
    } finally {
      setActionLoading(false);
    }
  };

  // RPC: Recover Device After Reset
  const handleRecover = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!selectedDevice) return;
    setErrorMsg(null);
    setActionLoading(true);

    try {
      const offset = parseInt(recoverOffset, 10) || 10;
      const { data, error } = await supabase.rpc('recover_device_after_reset', {
        p_device_id: selectedDevice.id,
        p_epoch_offset: offset,
      });

      if (error) {
        setErrorMsg(error.message);
      } else if (data) {
        setShowRecoverModal(false);
        setRevealedSecret({
          deviceId: selectedDevice.id,
          secret: data.new_device_secret,
          title: `Recovery Epoch Assigned: ${data.assigned_starting_epoch}`,
          instructions: `${data.instructions} (Previous server epoch was ${data.previous_epoch}).`,
        });
        await fetchDevices();
      }
    } catch (err: unknown) {
      setErrorMsg(err instanceof Error ? err.message : 'Recovery failed');
    } finally {
      setActionLoading(false);
    }
  };

  // RPC: Calibrate Device
  const handleCalibrate = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!selectedDevice) return;
    setErrorMsg(null);
    setActionLoading(true);

    try {
      const tare = parseFloat(tareOffset);
      const factor = parseFloat(calibrationFactor);

      const { error } = await supabase.rpc('calibrate_device', {
        p_device_id: selectedDevice.id,
        p_tare_offset: tare,
        p_calibration_factor: factor,
      });

      if (error) {
        setErrorMsg(error.message);
      } else {
        setSuccessMsg('Scale calibration saved to database.');
        await fetchDevices();
        setTimeout(() => setShowCalibrateModal(false), 800);
      }
    } catch (err: unknown) {
      setErrorMsg(err instanceof Error ? err.message : 'Calibration failed');
    } finally {
      setActionLoading(false);
    }
  };

  // RPC: Revoke Device
  const handleRevoke = async (device: Device) => {
    if (!window.confirm(`Revoke and deactivate scale "${device.name}" (${device.device_identifier})?`)) {
      return;
    }

    try {
      const { error } = await supabase.rpc('revoke_device', {
        p_device_id: device.id,
      });

      if (error) {
        alert(`Error revoking device: ${error.message}`);
      } else {
        await fetchDevices();
      }
    } catch (err: unknown) {
      alert(`Revocation error: ${err instanceof Error ? err.message : 'Unknown'}`);
    }
  };

  if (!activeShop) {
    return (
      <div className="p-8 max-w-md mx-auto text-center mt-12 bg-white rounded-2xl border border-slate-200 p-8">
        <Scale className="w-10 h-10 text-slate-300 mx-auto mb-3" />
        <h3 className="text-sm font-bold text-slate-800">No Active Shop Selected</h3>
        <p className="text-xs text-slate-500 mt-1">
          Select or configure a shop location to manage IoT scale devices.
        </p>
      </div>
    );
  }

  return (
    <div className="p-8 max-w-7xl mx-auto space-y-6">
      {/* Header Bar */}
      <div className="flex flex-col sm:flex-row items-stretch sm:items-center justify-between gap-4">
        <div>
          <h2 className="text-base font-bold text-slate-900 leading-tight">Scale IoT Controllers</h2>
          <p className="text-xs text-slate-500">
            Hardware load-cell telemetry controllers enrolled in {activeShop.name}.
          </p>
        </div>

        {isShopAdmin && (
          <button
            type="button"
            onClick={() => {
              setErrorMsg(null);
              setSuccessMsg(null);
              setShowEnrollModal(true);
            }}
            className="px-4 py-2 text-xs font-semibold text-white bg-indigo-600 hover:bg-indigo-500 rounded-xl shadow-xs shadow-indigo-600/30 transition-all flex items-center gap-1.5 self-start sm:self-auto"
          >
            <Plus className="w-4 h-4" />
            Enroll Scale Device
          </button>
        )}
      </div>

      {/* Devices List Table */}
      <div className="bg-white rounded-xl border border-slate-200 shadow-xs overflow-hidden">
        <div className="p-4 border-b border-slate-100 flex items-center justify-between">
          <div className="flex items-center gap-2">
            <Cpu className="w-4 h-4 text-indigo-600" />
            <h3 className="text-sm font-bold text-slate-800">Enrolled Devices</h3>
          </div>
          <span className="text-xs font-medium text-slate-400">
            {devices.length} hardware units
          </span>
        </div>

        {loading ? (
          <div className="p-12 text-center text-slate-400 text-xs">
            <div className="w-6 h-6 border-2 border-indigo-600/20 border-t-indigo-600 rounded-full animate-spin mx-auto mb-2"></div>
            Loading scale telemetry devices...
          </div>
        ) : devices.length === 0 ? (
          <div className="p-12 text-center">
            <Scale className="w-10 h-10 text-slate-300 mx-auto mb-3" />
            <p className="text-sm font-semibold text-slate-700">No scale devices enrolled</p>
            <p className="text-xs text-slate-400 mt-1 max-w-sm mx-auto">
              Provision and enroll an ESP32 scale device to start receiving verified weight tickets.
            </p>
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-left border-collapse text-xs">
              <thead>
                <tr className="bg-slate-50/70 border-b border-slate-100 text-[11px] font-semibold text-slate-500 uppercase tracking-wider">
                  <th className="py-3 px-5">Device</th>
                  <th className="py-3 px-4">Identifier</th>
                  <th className="py-3 px-4 text-center">Active Epoch</th>
                  <th className="py-3 px-4 text-right">Calibration</th>
                  <th className="py-3 px-4">Status & Heartbeat</th>
                  {isShopAdmin && <th className="py-3 px-4 text-right">Lifecycle Actions</th>}
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-100">
                {devices.map((device) => (
                  <tr key={device.id} className="hover:bg-slate-50/60 transition-colors">
                    <td className="py-3.5 px-5">
                      <div className="font-semibold text-slate-900">{device.name}</div>
                      <div className="text-[11px] text-slate-400 font-mono">
                        ID: {device.id}
                      </div>
                    </td>
                    <td className="py-3.5 px-4 font-mono font-semibold text-indigo-700">
                      {device.device_identifier}
                    </td>
                    <td className="py-3.5 px-4 text-center font-mono">
                      <span className="px-2 py-0.5 bg-slate-100 rounded text-slate-800 font-bold">
                        Ep: {device.current_epoch}
                      </span>
                      <div className="text-[10px] text-slate-400 mt-0.5">
                        Seq: {device.last_sequence_number}
                      </div>
                    </td>
                    <td className="py-3.5 px-4 text-right font-mono text-slate-600">
                      <div>Factor: {Number(device.calibration_factor).toFixed(4)}</div>
                      <div className="text-[10px] text-slate-400">Tare: {device.tare_offset}</div>
                    </td>
                    <td className="py-3.5 px-4">
                      {device.is_active ? (
                        <div className="space-y-0.5">
                          <span className="inline-flex items-center gap-1 text-[11px] font-semibold text-emerald-600">
                            <span className="w-1.5 h-1.5 rounded-full bg-emerald-500"></span> Active
                          </span>
                          {device.last_seen_at && (
                            <div className="text-[10px] text-slate-400 flex items-center gap-1">
                              <Clock className="w-2.5 h-2.5" />
                              {new Date(device.last_seen_at).toLocaleTimeString()}
                            </div>
                          )}
                        </div>
                      ) : (
                        <span className="inline-flex items-center gap-1 px-2 py-0.5 rounded text-[10px] font-bold bg-rose-50 text-rose-700 border border-rose-200">
                          Revoked
                        </span>
                      )}
                    </td>
                    {isShopAdmin && (
                      <td className="py-3.5 px-4 text-right space-x-1">
                        {device.is_active ? (
                          <>
                            <button
                              type="button"
                              onClick={() => {
                                setSelectedDevice(device);
                                setTareOffset(device.tare_offset.toString());
                                setCalibrationFactor(device.calibration_factor.toString());
                                setErrorMsg(null);
                                setSuccessMsg(null);
                                setShowCalibrateModal(true);
                              }}
                              className="px-2 py-1 text-[11px] font-semibold text-slate-700 bg-slate-100 hover:bg-slate-200 rounded-lg transition-colors"
                            >
                              Calibrate
                            </button>
                            <button
                              type="button"
                              onClick={() => {
                                setSelectedDevice(device);
                                setErrorMsg(null);
                                setShowRotateModal(true);
                              }}
                              title="Rotate secret key"
                              aria-label="Rotate device secret key"
                              className="p-1 text-slate-500 hover:text-indigo-600 rounded-lg transition-colors"
                            >
                              <Key className="w-3.5 h-3.5" />
                            </button>
                            <button
                              type="button"
                              onClick={() => {
                                setSelectedDevice(device);
                                setRecoverOffset('10');
                                setErrorMsg(null);
                                setShowRecoverModal(true);
                              }}
                              title="Recover after NVS loss"
                              aria-label="Recover device after NVS loss"
                              className="p-1 text-slate-500 hover:text-amber-600 rounded-lg transition-colors"
                            >
                              <RotateCw className="w-3.5 h-3.5" />
                            </button>
                            <button
                              type="button"
                              onClick={() => handleRevoke(device)}
                              title="Revoke device"
                              aria-label="Revoke device"
                              className="p-1 text-slate-400 hover:text-rose-600 rounded-lg transition-colors"
                            >
                              <PowerOff className="w-3.5 h-3.5" />
                            </button>
                          </>
                        ) : (
                          <span className="text-slate-400 text-[11px] italic">Deactivated</span>
                        )}
                      </td>
                    )}
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>

      {/* One-Time Secret Reveal Modal */}
      {revealedSecret && (
        <div className="fixed inset-0 z-50 bg-slate-900/70 backdrop-blur-xs flex items-center justify-center p-4">
          <div className="bg-white rounded-2xl max-w-lg w-full p-6 shadow-2xl border border-amber-300 animate-in fade-in zoom-in-95">
            <div className="flex items-center gap-2 text-amber-600 mb-2">
              <ShieldAlert className="w-5 h-5 flex-shrink-0" />
              <h3 className="text-base font-bold text-slate-900">{revealedSecret.title}</h3>
            </div>
            <p className="text-xs text-slate-600 mb-4">{revealedSecret.instructions}</p>

            <div className="bg-slate-900 text-slate-100 p-4 rounded-xl font-mono text-xs break-all relative mb-4 border border-slate-800">
              {revealedSecret.secret}
              <button
                type="button"
                onClick={() => copyToClipboard(revealedSecret.secret)}
                className="absolute right-2 top-2 p-1.5 bg-slate-800 hover:bg-slate-700 text-slate-300 rounded-lg transition-all"
                title="Copy secret"
              >
                {copied ? <Check className="w-4 h-4 text-emerald-400" /> : <Copy className="w-4 h-4" />}
              </button>
            </div>

            <div className="flex items-center justify-between">
              <span className="text-[11px] text-amber-700 font-medium">
                ⚠️ Store now. This secret will never be shown again.
              </span>
              <button
                type="button"
                onClick={() => setRevealedSecret(null)}
                className="px-4 py-2 text-xs font-semibold text-white bg-indigo-600 hover:bg-indigo-500 rounded-xl"
              >
                I Have Stored the Secret
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Modal: Enroll Device */}
      {showEnrollModal && (
        <div className="fixed inset-0 z-50 bg-slate-900/60 backdrop-blur-xs flex items-center justify-center p-4">
          <div className="bg-white rounded-2xl max-w-md w-full p-6 shadow-2xl border border-slate-200">
            <h3 className="text-base font-bold text-slate-900 mb-1">Enroll New Scale Controller</h3>
            <p className="text-xs text-slate-500 mb-4">
              Server generates a 256-bit cryptographic secret for authenticated HTTPS telemetry.
            </p>

            {errorMsg && (
              <div className="mb-4 p-3 bg-rose-50 border border-rose-200 text-rose-700 rounded-xl text-xs flex items-start gap-2">
                <AlertCircle className="w-4 h-4 flex-shrink-0 mt-0.5" />
                <span>{errorMsg}</span>
              </div>
            )}

            <form onSubmit={handleEnrollDevice} className="space-y-3">
              <div>
                <label className="block text-xs font-semibold text-slate-700 mb-1">
                  Device Hardware Identifier *
                </label>
                <input
                  type="text"
                  required
                  value={enrollIdentifier}
                  onChange={(e) => setEnrollIdentifier(e.target.value)}
                  placeholder="e.g. SCALE-ESP32-001"
                  className="w-full px-3 py-2 bg-slate-50 border border-slate-300 rounded-xl text-xs text-slate-800 focus:outline-none focus:ring-2 focus:ring-indigo-500 font-mono"
                />
              </div>

              <div>
                <label className="block text-xs font-semibold text-slate-700 mb-1">
                  Device Friendly Name *
                </label>
                <input
                  type="text"
                  required
                  value={enrollName}
                  onChange={(e) => setEnrollName(e.target.value)}
                  placeholder="e.g. Produce Section Scale #1"
                  className="w-full px-3 py-2 bg-slate-50 border border-slate-300 rounded-xl text-xs text-slate-800 focus:outline-none focus:ring-2 focus:ring-indigo-500"
                />
              </div>

              <div className="flex items-center justify-end gap-2 pt-3 border-t border-slate-100">
                <button
                  type="button"
                  onClick={() => setShowEnrollModal(false)}
                  className="px-4 py-2 text-xs font-medium text-slate-600 hover:bg-slate-100 rounded-xl"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  disabled={actionLoading}
                  className="px-4 py-2 text-xs font-semibold text-white bg-indigo-600 hover:bg-indigo-500 rounded-xl disabled:opacity-50"
                >
                  {actionLoading ? 'Enrolling...' : 'Generate Credentials'}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {/* Modal: Calibrate Scale */}
      {showCalibrateModal && selectedDevice && (
        <div className="fixed inset-0 z-50 bg-slate-900/60 backdrop-blur-xs flex items-center justify-center p-4">
          <div className="bg-white rounded-2xl max-w-sm w-full p-6 shadow-2xl border border-slate-200">
            <h3 className="text-base font-bold text-slate-900 mb-1">
              Calibrate: {selectedDevice.device_identifier}
            </h3>
            <p className="text-xs text-slate-500 mb-4">
              Calibrates the server-side expectation for raw ADC-to-gram conversion.
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

            <form onSubmit={handleCalibrate} className="space-y-3">
              <div>
                <label className="block text-xs font-semibold text-slate-700 mb-1">Tare Offset</label>
                <input
                  type="number"
                  step="any"
                  required
                  value={tareOffset}
                  onChange={(e) => setTareOffset(e.target.value)}
                  className="w-full px-3 py-2 bg-slate-50 border border-slate-300 rounded-xl text-xs text-slate-800 focus:outline-none focus:ring-2 focus:ring-indigo-500 font-mono"
                />
              </div>

              <div>
                <label className="block text-xs font-semibold text-slate-700 mb-1">
                  Calibration Factor (&gt; 0) *
                </label>
                <input
                  type="number"
                  step="any"
                  min="0.0001"
                  required
                  value={calibrationFactor}
                  onChange={(e) => setCalibrationFactor(e.target.value)}
                  className="w-full px-3 py-2 bg-slate-50 border border-slate-300 rounded-xl text-xs text-slate-800 focus:outline-none focus:ring-2 focus:ring-indigo-500 font-mono"
                />
              </div>

              <div className="flex items-center justify-end gap-2 pt-3 border-t border-slate-100">
                <button
                  type="button"
                  onClick={() => setShowCalibrateModal(false)}
                  className="px-4 py-2 text-xs font-medium text-slate-600 hover:bg-slate-100 rounded-xl"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  disabled={actionLoading}
                  className="px-4 py-2 text-xs font-semibold text-white bg-indigo-600 hover:bg-indigo-500 rounded-xl disabled:opacity-50"
                >
                  {actionLoading ? 'Saving...' : 'Save Calibration'}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {/* Modal: Rotate Confirmation */}
      {showRotateModal && selectedDevice && (
        <div className="fixed inset-0 z-50 bg-slate-900/60 backdrop-blur-xs flex items-center justify-center p-4">
          <div className="bg-white rounded-2xl max-w-sm w-full p-6 shadow-2xl border border-slate-200">
            <h3 className="text-base font-bold text-slate-900 mb-1">Rotate Secret Key</h3>
            <p className="text-xs text-slate-500 mb-4">
              Rotating key for "{selectedDevice.name}". The old secret will be permanently invalidated.
            </p>

            <div className="flex items-center justify-end gap-2 pt-3 border-t border-slate-100">
              <button
                type="button"
                onClick={() => setShowRotateModal(false)}
                className="px-4 py-2 text-xs font-medium text-slate-600 hover:bg-slate-100 rounded-xl"
              >
                Cancel
              </button>
              <button
                type="button"
                onClick={handleRotateCredentials}
                disabled={actionLoading}
                className="px-4 py-2 text-xs font-semibold text-white bg-indigo-600 hover:bg-indigo-500 rounded-xl disabled:opacity-50"
              >
                {actionLoading ? 'Rotating...' : 'Confirm Key Rotation'}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Modal: Recovery After Reset */}
      {showRecoverModal && selectedDevice && (
        <div className="fixed inset-0 z-50 bg-slate-900/60 backdrop-blur-xs flex items-center justify-center p-4">
          <div className="bg-white rounded-2xl max-w-sm w-full p-6 shadow-2xl border border-slate-200">
            <h3 className="text-base font-bold text-slate-900 mb-1">Device Recovery</h3>
            <p className="text-xs text-slate-500 mb-4">
              Use when the ESP32 board lost NVS or was replaced. Advances epoch strictly forward.
            </p>

            <form onSubmit={handleRecover} className="space-y-3">
              <div>
                <label className="block text-xs font-semibold text-slate-700 mb-1">
                  Epoch Advance Offset
                </label>
                <input
                  type="number"
                  min="1"
                  required
                  value={recoverOffset}
                  onChange={(e) => setRecoverOffset(e.target.value)}
                  className="w-full px-3 py-2 bg-slate-50 border border-slate-300 rounded-xl text-xs text-slate-800 focus:outline-none focus:ring-2 focus:ring-indigo-500 font-mono"
                />
                <span className="text-[10px] text-slate-400">
                  New epoch will be: {selectedDevice.current_epoch + (parseInt(recoverOffset, 10) || 10)}
                </span>
              </div>

              <div className="flex items-center justify-end gap-2 pt-3 border-t border-slate-100">
                <button
                  type="button"
                  onClick={() => setShowRecoverModal(false)}
                  className="px-4 py-2 text-xs font-medium text-slate-600 hover:bg-slate-100 rounded-xl"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  disabled={actionLoading}
                  className="px-4 py-2 text-xs font-semibold text-white bg-amber-600 hover:bg-amber-500 rounded-xl disabled:opacity-50"
                >
                  {actionLoading ? 'Recovering...' : 'Perform Recovery'}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
};
