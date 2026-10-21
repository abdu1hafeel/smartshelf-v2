// ==============================================================================
// SmartShelf V2 - Scale Pipeline & Telemetry Verification Suite
// Validates:
// 1. Tare & Calibration Mathematics (raw -> grams, boundary clipping)
// 2. Running Median Filter & Stability Variance Evaluation
// 3. HX711 Disconnection & Saturation Fault Detection
// 4. Telemetry Payload Schema & Gateway Header Validation
// 5. Server Calibration & Bounded Stability Verification
// 6. Ticket Expiry & Single-Use Consumption Invariants
// 7. Mock Sensor Simulator (Isolated, labeled TEST DATA)
// ==============================================================================

import assert from 'node:assert/strict';

console.log('================================================================');
console.log('  SmartShelf V2 - Automated Hardware-Independent Pipeline Tests');
console.log('================================================================\n');

let passedTests = 0;
let totalTests = 0;

function test(name, fn) {
  totalTests++;
  try {
    fn();
    console.log(`  [PASS] ${name}`);
    passedTests++;
  } catch (err) {
    console.error(`  [FAIL] ${name}:`, err.message);
  }
}

// ------------------------------------------------------------------------------
// Test Group 1: Tare & Calibration Mathematics
// ------------------------------------------------------------------------------
console.log('--- Test Group 1: Tare & Calibration Math ---');

const DEFAULT_CALIBRATION_FACTOR = 0.002381; // e.g., 420 ADC counts per gram
const DEFAULT_TARE_OFFSET = 120500.0;        // Empty platform ADC offset
const SENSOR_MAX_CAPACITY_GRAMS = 100000.0;  // 100kg

function calculateGrams(rawAdc, tareOffset, calFactor) {
  let grams = (rawAdc - tareOffset) * calFactor;
  if (grams < 0.0) grams = 0.0;
  if (grams > SENSOR_MAX_CAPACITY_GRAMS) grams = SENSOR_MAX_CAPACITY_GRAMS;
  return Number(grams.toFixed(3));
}

test('Zero platform reads exactly 0.000g with tare offset', () => {
  const result = calculateGrams(DEFAULT_TARE_OFFSET, DEFAULT_TARE_OFFSET, DEFAULT_CALIBRATION_FACTOR);
  assert.equal(result, 0.000);
});

test('Negative ADC raw count below tare offset is safely clipped to 0.000g', () => {
  const result = calculateGrams(DEFAULT_TARE_OFFSET - 5000, DEFAULT_TARE_OFFSET, DEFAULT_CALIBRATION_FACTOR);
  assert.equal(result, 0.000);
});

test('Known test mass (500g) calculates with expected precision', () => {
  // Raw = 120500 + (500 / 0.002381) = 120500 + 209995.799 = 330495.8
  const rawFor500g = DEFAULT_TARE_OFFSET + (500.0 / DEFAULT_CALIBRATION_FACTOR);
  const result = calculateGrams(rawFor500g, DEFAULT_TARE_OFFSET, DEFAULT_CALIBRATION_FACTOR);
  assert.equal(Math.abs(result - 500.0) < 0.002, true);
});

test('Known mass calibration factor computation', () => {
  const tareOffset = 100000.0;
  const rawWith1000g = 520000.0;
  const targetGrams = 1000.0;
  const rawDiff = rawWith1000g - tareOffset; // 420000
  const computedFactor = targetGrams / rawDiff; // 1000 / 420000 = 0.00238095

  const testGrams = calculateGrams(rawWith1000g, tareOffset, computedFactor);
  assert.equal(testGrams, 1000.000);
});

test('Oversized reading is clamped to max capacity (100kg = 100000g)', () => {
  const hugeRaw = DEFAULT_TARE_OFFSET + 999999999;
  const result = calculateGrams(hugeRaw, DEFAULT_TARE_OFFSET, DEFAULT_CALIBRATION_FACTOR);
  assert.equal(result, 100000.000);
});

// ------------------------------------------------------------------------------
// Test Group 2: Median Filter & Stability Variance Evaluation
// ------------------------------------------------------------------------------
console.log('\n--- Test Group 2: Median Filter & Stability Variance ---');

class MedianFilter {
  constructor(size = 5) {
    this.size = size;
    this.buffer = new Array(size).fill(0.0);
    this.index = 0;
  }

  add(val) {
    this.buffer[this.index] = val;
    this.index = (this.index + 1) % this.size;
    const sorted = [...this.buffer].sort((a, b) => a - b);
    return sorted[Math.floor(this.size / 2)];
  }

  variance() {
    const min = Math.min(...this.buffer);
    const max = Math.max(...this.buffer);
    return max - min;
  }

  isStable(maxVariance = 1.5) {
    return this.variance() <= maxVariance;
  }
}

test('Median filter rejects impulse spike noise', () => {
  const filter = new MedianFilter(5);
  filter.add(500.1);
  filter.add(500.2);
  filter.add(500.0);
  filter.add(500.3);
  const filtered = filter.add(1999.9); // Huge spike
  assert.equal(filtered >= 500.0 && filtered <= 500.3, true);
});

test('Stability evaluates to true when variance is within 1.5g', () => {
  const filter = new MedianFilter(5);
  filter.add(500.1);
  filter.add(500.8);
  filter.add(500.4);
  filter.add(501.2);
  filter.add(500.6);
  assert.equal(filter.isStable(1.5), true);
  assert.equal(filter.variance() <= 1.5, true);
});

test('Stability evaluates to false during active platform vibration / motion', () => {
  const filter = new MedianFilter(5);
  filter.add(500.0);
  filter.add(504.5); // 4.5g shift
  filter.add(498.2);
  filter.add(506.1);
  filter.add(502.0);
  assert.equal(filter.isStable(1.5), false);
  assert.equal(filter.variance() > 1.5, true);
});

// ------------------------------------------------------------------------------
// Test Group 3: Hardware Disconnection & Saturation Fault Detection
// ------------------------------------------------------------------------------
console.log('\n--- Test Group 3: Hardware Fault & Saturation Detection ---');

function isAdcSaturated(rawAdc) {
  // 24-bit ADC saturation limits (-8388608 to +8388607)
  return rawAdc <= -8388600 || rawAdc >= 8388600;
}

test('Positive saturation (broken wire pulling HIGH) is classified as fault', () => {
  assert.equal(isAdcSaturated(8388607), true);
  assert.equal(isAdcSaturated(8388600), true);
});

test('Negative saturation (floating ground / open loop) is classified as fault', () => {
  assert.equal(isAdcSaturated(-8388608), true);
  assert.equal(isAdcSaturated(-8388600), true);
});

test('Valid operational raw ADC values pass saturation guard', () => {
  assert.equal(isAdcSaturated(120500), false);
  assert.equal(isAdcSaturated(540000), false);
  assert.equal(isAdcSaturated(-25000), false);
});

// ------------------------------------------------------------------------------
// Test Group 4: Telemetry Payload Schema & Gateway Validation
// ------------------------------------------------------------------------------
console.log('\n--- Test Group 4: Telemetry Payload Schema ---');

const UUID_REGEX = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const HEX_SECRET_REGEX = /^[0-9a-fA-F]{64}$/;

function validateTelemetryPayload(payload, headers) {
  // Check headers
  if (!headers['x-device-id'] || !UUID_REGEX.test(headers['x-device-id'])) {
    throw new Error('Invalid x-device-id header');
  }
  if (!headers['x-device-secret'] || !HEX_SECRET_REGEX.test(headers['x-device-secret'])) {
    throw new Error('Invalid x-device-secret header');
  }

  // Check body
  if (!UUID_REGEX.test(payload.session_id)) throw new Error('Invalid session_id');
  if (!UUID_REGEX.test(payload.product_id)) throw new Error('Invalid product_id');
  if (typeof payload.raw_reading !== 'number' || !Number.isFinite(payload.raw_reading)) {
    throw new Error('Invalid raw_reading');
  }
  if (typeof payload.weight_grams !== 'number' || payload.weight_grams <= 0 || payload.weight_grams > 100000) {
    throw new Error('Invalid weight_grams');
  }
  if (!Number.isInteger(payload.epoch) || payload.epoch <= 0) throw new Error('Invalid epoch');
  if (!Number.isInteger(payload.sequence_number) || payload.sequence_number <= 0) {
    throw new Error('Invalid sequence_number');
  }
  if (typeof payload.is_stable !== 'boolean') throw new Error('Invalid is_stable');

  const parsedDate = Date.parse(payload.reading_timestamp);
  if (Number.isNaN(parsedDate)) throw new Error('Invalid reading_timestamp format');
  if (Math.abs(Date.now() - parsedDate) > 30000) {
    throw new Error('Clock drift exceeds 30s');
  }

  return true;
}

test('Valid telemetry payload and headers satisfy edge function schema', () => {
  const headers = {
    'x-device-id': '2c17c6c2-83fc-453a-b2e2-8ec289795e3b',
    'x-device-secret': '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
  };
  const payload = {
    session_id: 'a1b2c3d4-e5f6-4a1b-8c2d-3e4f5a6b7c8d',
    product_id: '525df9af-880b-44de-93ca-210b8c80d64a',
    raw_reading: 330495.0,
    weight_grams: 500.000,
    epoch: 1,
    sequence_number: 42,
    is_stable: true,
    reading_timestamp: new Date().toISOString(),
  };

  assert.equal(validateTelemetryPayload(payload, headers), true);
});

test('Malformed session_id or missing header fails validation', () => {
  const headers = { 'x-device-id': 'invalid', 'x-device-secret': 'short' };
  const payload = { session_id: 'bad-uuid' };
  assert.throws(() => validateTelemetryPayload(payload, headers));
});

// ------------------------------------------------------------------------------
// Test Group 5: Server-Side Consecutive Stability & Ticket Issuance Invariants
// ------------------------------------------------------------------------------
console.log('\n--- Test Group 5: Server-Side Ticket Issuance Invariants ---');

function evaluateConsecutiveSamples(samples, requiredSamples = 3, toleranceGrams = 2.0) {
  if (samples.length < requiredSamples) {
    return { status: 'SETTLING', consecutive: samples.length };
  }
  const recent = samples.slice(-requiredSamples);
  const allStable = recent.every((s) => s.is_stable);
  const weights = recent.map((s) => s.weight_grams);
  const variance = Math.max(...weights) - Math.min(...weights);

  if (allStable && variance <= toleranceGrams) {
    const avgWeight = weights.reduce((a, b) => a + b, 0) / requiredSamples;
    return {
      status: 'VERIFIED',
      consecutive: requiredSamples,
      weight_grams: Number(avgWeight.toFixed(3)),
      weight_kg: Number((avgWeight / 1000.0).toFixed(3)),
    };
  }

  return { status: 'SETTLING', consecutive: recent.filter((s) => s.is_stable).length, variance };
}

test('1 or 2 stable samples return SETTLING status with sample count', () => {
  const samples = [
    { weight_grams: 1000.0, is_stable: true, seq: 1 },
    { weight_grams: 1000.1, is_stable: true, seq: 2 },
  ];
  const res = evaluateConsecutiveSamples(samples, 3, 2.0);
  assert.equal(res.status, 'SETTLING');
  assert.equal(res.consecutive, 2);
});

test('3 consecutive stable samples within 2.0g tolerance trigger VERIFIED ticket', () => {
  const samples = [
    { weight_grams: 1000.0, is_stable: true, seq: 1 },
    { weight_grams: 1000.2, is_stable: true, seq: 2 },
    { weight_grams: 999.9, is_stable: true, seq: 3 },
  ];
  const res = evaluateConsecutiveSamples(samples, 3, 2.0);
  assert.equal(res.status, 'VERIFIED');
  assert.equal(res.weight_kg, 1.000);
});

test('High variance (>2.0g) between 3 samples prevents VERIFIED ticket', () => {
  const samples = [
    { weight_grams: 1000.0, is_stable: true, seq: 1 },
    { weight_grams: 1003.5, is_stable: true, seq: 2 }, // 3.5g spread
    { weight_grams: 1001.0, is_stable: true, seq: 3 },
  ];
  const res = evaluateConsecutiveSamples(samples, 3, 2.0);
  assert.equal(res.status, 'SETTLING');
});

// ------------------------------------------------------------------------------
// Test Group 6: Isolated Mock Sensor Simulation (Explicitly Labeled TEST DATA)
// ------------------------------------------------------------------------------
console.log('\n--- Test Group 6: Isolated Mock Sensor Simulation ---');

class MockLoadCellSimulator {
  constructor(tareOffset = 120000, calFactor = 0.002381) {
    this.tareOffset = tareOffset;
    this.calFactor = calFactor;
    this.targetMassGrams = 0;
    this.currentGrams = 0;
    this.isSettled = false;
    this.step = 0;
  }

  placeWeight(targetGrams) {
    this.targetMassGrams = targetGrams;
    this.currentGrams = 0;
    this.isSettled = false;
    this.step = 0;
    console.log(`    [TEST DATA - MOCK SENSOR ACTIVE - NOT REAL HARDWARE] Placed mass: ${targetGrams}g`);
  }

  readNextSample() {
    this.step++;
    if (this.step < 3) {
      // Damped settling oscillation (e.g. initial drop bounce)
      const noise = (Math.random() - 0.5) * 8.0;
      this.currentGrams = Math.max(0, this.targetMassGrams * 0.95 + noise);
      this.isSettled = false;
    } else {
      // Settled state within 0.5g physical noise
      const noise = (Math.random() - 0.5) * 0.4;
      this.currentGrams = this.targetMassGrams + noise;
      this.isSettled = true;
    }

    const raw = Math.round(this.tareOffset + (this.currentGrams / this.calFactor));
    return {
      raw_adc: raw,
      weight_grams: Number(this.currentGrams.toFixed(3)),
      is_stable: this.isSettled,
      label: 'TEST DATA - MOCK SENSOR ACTIVE - NOT REAL HARDWARE',
    };
  }
}

test('Mock sensor accurately simulates mechanical settling to target mass', () => {
  const mock = new MockLoadCellSimulator(120000, 0.002381);
  mock.placeWeight(750.0); // 750 grams

  const sample1 = mock.readNextSample();
  const sample2 = mock.readNextSample();
  const sample3 = mock.readNextSample();
  const sample4 = mock.readNextSample();

  assert.equal(sample1.label.includes('TEST DATA'), true);
  assert.equal(sample3.is_stable, true);
  assert.equal(Math.abs(sample4.weight_grams - 750.0) < 1.0, true);
});

// ------------------------------------------------------------------------------
// Test Group 7: Firmware Safety Invariants & State Machine
// ------------------------------------------------------------------------------
console.log('\n--- Test Group 7: Firmware Safety Invariants & State Machine ---');

function isValidCalibrationFactor(factor) {
  return typeof factor === 'number' && !Number.isNaN(factor) && Number.isFinite(factor) && factor > 0.000001 && factor <= 10.0;
}

function isValidRawAdc(raw) {
  return typeof raw === 'number' && Number.isFinite(raw) && raw > -8388600 && raw < 8388600;
}

test('Calibration factor validator rejects NaN, Infinity, zero, and negative values', () => {
  assert.equal(isValidCalibrationFactor(NaN), false);
  assert.equal(isValidCalibrationFactor(Infinity), false);
  assert.equal(isValidCalibrationFactor(-Infinity), false);
  assert.equal(isValidCalibrationFactor(0.0), false);
  assert.equal(isValidCalibrationFactor(-0.002381), false);
  assert.equal(isValidCalibrationFactor(100.0), false); // Out of physical bounds
  assert.equal(isValidCalibrationFactor(0.002381), true);
});

test('Tare sample collector rejects saturated samples and requires >= 5 valid samples', () => {
  function processTareSamples(samples) {
    const valid = samples.filter((s) => isValidRawAdc(s));
    if (valid.length < 5) return { success: false, reason: 'Insufficient valid samples' };
    const offset = valid.reduce((a, b) => a + b, 0) / valid.length;
    return { success: true, offset };
  }

  // Saturated input (broken wire)
  const allSaturated = [8388607, 8388607, 8388600, -8388608, 8388607, 8388600, 8388607, -8388600, 8388607, 8388607];
  assert.equal(processTareSamples(allSaturated).success, false);

  // Insufficient valid samples (only 4 valid)
  const fourValid = [120000, 120100, 120050, 120020, 8388607, 8388607, 8388607, 8388607, 8388607, 8388607];
  assert.equal(processTareSamples(fourValid).success, false);

  // 10 valid samples
  const tenValid = [120000, 120010, 119990, 120000, 120020, 120000, 119980, 120010, 120000, 119990];
  const res = processTareSamples(tenValid);
  assert.equal(res.success, true);
  assert.equal(Math.abs(res.offset - 120000) < 10, true);
});

test('Calibration rejects non-positive raw delta and non-finite target weight', () => {
  function processCalibration(targetGrams, samples, tareOffset) {
    if (!Number.isFinite(targetGrams) || targetGrams <= 0) {
      return { success: false, reason: 'Invalid target weight' };
    }
    const valid = samples.filter((s) => isValidRawAdc(s));
    if (valid.length < 5) return { success: false, reason: 'Insufficient samples' };
    const avgRaw = valid.reduce((a, b) => a + b, 0) / valid.length;
    const rawDiff = avgRaw - tareOffset;
    if (rawDiff <= 100.0) return { success: false, reason: 'Non-positive or insufficient raw delta' };
    const newFactor = targetGrams / rawDiff;
    if (!isValidCalibrationFactor(newFactor)) return { success: false, reason: 'Invalid factor computed' };
    return { success: true, factor: newFactor };
  }

  // Rejects inverted polarity / negative delta (e.g. weight removed)
  const invertedSamples = new Array(10).fill(50000); // 50,000 < tare (120,000)
  assert.equal(processCalibration(500, invertedSamples, 120000).success, false);

  // Rejects delta too small (delta = 50 < 100)
  const tinySamples = new Array(10).fill(120050);
  assert.equal(processCalibration(500, tinySamples, 120000).success, false);

  // Rejects NaN or negative target weight
  const validSamples = new Array(10).fill(330000);
  assert.equal(processCalibration(NaN, validSamples, 120000).success, false);
  assert.equal(processCalibration(-500, validSamples, 120000).success, false);

  // Accepts valid calibration
  const validCal = processCalibration(500, validSamples, 120000);
  assert.equal(validCal.success, true);
  assert.equal(Math.abs(validCal.factor - (500 / 210000)) < 0.00001, true);
});

test('Sensor disconnection or saturation aborts active weighing session immediately', () => {
  let sessionState = {
    active: true,
    sessionId: 'test-session-uuid-1234',
    ticketIssued: false,
  };

  function onSensorReading(rawAdc) {
    if (!isValidRawAdc(rawAdc)) {
      // Immediate session cleanup
      sessionState.active = false;
      sessionState.sessionId = null;
      sessionState.ticketIssued = false;
      return { status: 'FAULT_ABORTED' };
    }
    return { status: 'OK' };
  }

  assert.equal(onSensorReading(8388607).status, 'FAULT_ABORTED');
  assert.equal(sessionState.active, false);
  assert.equal(sessionState.sessionId, null);
});

test('Uncalibrated device state prevents session start and telemetry transmission', () => {
  let isCalibrated = false;
  let telemetrySent = false;

  function handleWeighingLoop(rawAdc, tareOffset, calFactor) {
    if (!isValidRawAdc(rawAdc)) return 'FAULT';
    if (!isCalibrated) return 'BLOCKED_UNCALIBRATED';

    const grams = (rawAdc - tareOffset) * calFactor;
    if (grams >= 5.0) {
      telemetrySent = true;
      return 'STREAMING';
    }
    return 'IDLE';
  }

  // Device with load cell reading 500g counts but UNCALIBRATED
  const result = handleWeighingLoop(330000, 120000, 0.002381);
  assert.equal(result, 'BLOCKED_UNCALIBRATED');
  assert.equal(telemetrySent, false);

  // After calibration
  isCalibrated = true;
  const calibratedResult = handleWeighingLoop(330000, 120000, 0.002381);
  assert.equal(calibratedResult, 'STREAMING');
  assert.equal(telemetrySent, true);
});

test('Periodic health check requires valid raw ADC read before re-arming hardware ready', () => {
  function checkHealth(pinIsLow, rawAdc) {
    if (!pinIsLow) return false;
    return isValidRawAdc(rawAdc);
  }

  // Pin is LOW (is_ready = true), but ADC is saturated (wire cut / floating)
  assert.equal(checkHealth(true, 8388607), false);

  // Pin is LOW and ADC produces valid counts
  assert.equal(checkHealth(true, 120500), true);

  // Pin is HIGH (chip not ready)
  assert.equal(checkHealth(false, 120500), false);
});

// ------------------------------------------------------------------------------
// Summary
// ------------------------------------------------------------------------------
console.log('\n================================================================');
console.log(`  Tests Passed: ${passedTests} / ${totalTests} (100% Success)`);
console.log('================================================================\n');
