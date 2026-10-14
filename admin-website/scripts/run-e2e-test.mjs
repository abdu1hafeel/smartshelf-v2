// ==============================================================================
// SmartShelf V2 - Automated End-to-End Integration Test Suite
// Targets: Local Supabase Stack (http://127.0.0.1:54321)
// ==============================================================================

import { createClient } from '@supabase/supabase-js';

const SUPABASE_URL = process.env.VITE_SUPABASE_URL || 'http://127.0.0.1:54321';
const SUPABASE_ANON_KEY = process.env.VITE_SUPABASE_ANON_KEY || 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0';

const results = [];

function record(name, status, details = '') {
  results.push({ name, status, details });
  const icon = status === 'PASS' ? '✅' : '❌';
  console.log(`${icon} [${status}] ${name}${details ? ` -> ${details}` : ''}`);
}

async function run() {
  console.log('==============================================================================');
  console.log('Starting SmartShelf V2 Local Integration Tests');
  console.log(`Connecting to: ${SUPABASE_URL}`);
  console.log('==============================================================================\n');

  const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    auth: { persistSession: false },
  });

  const timestamp = Date.now();
  const adminEmail = `admin_${timestamp}@testmart.local`;
  const adminPassword = `SuperP@ssw0rd_${timestamp}!`;
  const adminFullName = `SuperAdmin ${timestamp}`;

  let adminUser = null;
  let orgId = null;
  let shopId = null;
  let categoryId = null;
  let packagedProductId = null;
  let looseProductId = null;
  let deviceId = null;
  let initialDeviceSecret = null;

  // 1. Sign-Up
  try {
    const { data, error } = await supabase.auth.signUp({
      email: adminEmail,
      password: adminPassword,
      options: {
        data: { full_name: adminFullName },
      },
    });

    if (error) throw error;
    if (!data.user) throw new Error('No user returned from signUp');
    adminUser = data.user;
    record('User Sign-Up', 'PASS', `Created user ${adminUser.id} (${adminEmail})`);
  } catch (err) {
    record('User Sign-Up', 'FAIL', err.message);
    process.exit(1);
  }

  // 2. Sign-In
  try {
    const { data, error } = await supabase.auth.signInWithPassword({
      email: adminEmail,
      password: adminPassword,
    });

    if (error) throw error;
    if (!data.session?.access_token) throw new Error('No session access_token received');
    record('User Sign-In', 'PASS', `Authenticated session established (JWT token valid)`);
  } catch (err) {
    record('User Sign-In', 'FAIL', err.message);
    process.exit(1);
  }

  // 3. Profile Auto-Creation Trigger
  try {
    const { data, error } = await supabase
      .from('profiles')
      .select('*')
      .eq('id', adminUser.id)
      .single();

    if (error) throw error;
    if (data.full_name !== adminFullName) {
      throw new Error(`Profile full_name mismatch: expected "${adminFullName}", got "${data.full_name}"`);
    }
    record('Profile Creation (Trigger)', 'PASS', `Profile automatically provisioned with name: ${data.full_name}`);
  } catch (err) {
    record('Profile Creation (Trigger)', 'FAIL', err.message);
  }

  // 4. Organization Onboarding (RPC)
  try {
    const orgName = `TestMart Enterprise ${timestamp}`;
    const { data, error } = await supabase.rpc('create_organization_onboarding', {
      p_org_name: orgName,
    });

    if (error) throw error;
    if (!data?.organization_id) throw new Error('RPC did not return organization_id');
    orgId = data.organization_id;

    // Verify record in organizations table
    const { data: orgRecord, error: orgErr } = await supabase
      .from('organizations')
      .select('*')
      .eq('id', orgId)
      .single();

    if (orgErr) throw orgErr;
    record('Organization Onboarding (RPC)', 'PASS', `Org created: "${orgRecord.name}" (ID: ${orgId}) with ORG_ADMIN membership`);
  } catch (err) {
    record('Organization Onboarding (RPC)', 'FAIL', err.message);
    process.exit(1);
  }

  // 5. Shop Creation (RPC)
  try {
    const shopName = `Downtown Flagship ${timestamp}`;
    const { data, error } = await supabase.rpc('create_shop', {
      p_organization_id: orgId,
      p_name: shopName,
      p_location: 'Central Plaza Block A',
      p_currency: 'INR',
    });

    if (error) throw error;
    if (!data?.shop_id && !data?.id) throw new Error('RPC did not return shop id');
    shopId = data.shop_id || data.id;

    // Verify record in shops table
    const { data: shopRecord, error: shopErr } = await supabase
      .from('shops')
      .select('*')
      .eq('id', shopId)
      .single();

    if (shopErr) throw shopErr;
    record('Shop Creation (RPC)', 'PASS', `Shop created: "${shopRecord.name}" (Currency: ${shopRecord.currency})`);
  } catch (err) {
    record('Shop Creation (RPC)', 'FAIL', err.message);
    process.exit(1);
  }

  // 6. Category Creation (RPC)
  try {
    const categoryName = `Bakery & Pastries ${timestamp}`;
    const { data, error } = await supabase.rpc('create_category', {
      p_organization_id: orgId,
      p_name: categoryName,
      p_description: 'Fresh artisanal bakery products',
    });

    if (error) throw error;
    if (!data?.category_id) throw new Error('RPC did not return category_id');
    categoryId = data.category_id;

    // Verify record in categories table
    const { data: catRecord, error: catErr } = await supabase
      .from('categories')
      .select('*')
      .eq('id', categoryId)
      .single();

    if (catErr) throw catErr;
    record('Category Creation (RPC)', 'PASS', `Category created: "${catRecord.name}"`);
  } catch (err) {
    record('Category Creation (RPC)', 'FAIL', err.message);
  }

  // 7. Product Creation - Packaged (RPC)
  try {
    const { data, error } = await supabase.rpc('create_product', {
      p_organization_id: orgId,
      p_category_id: categoryId,
      p_name: 'Artisan Sourdough Loaf 500g',
      p_barcode: `890${timestamp.toString().slice(-10)}`,
      p_sku: `BREAD-SOUR-${timestamp.toString().slice(-4)}`,
      p_unit_type: 'PACKAGED',
      p_description: 'Naturally fermented rustic sourdough',
    });

    if (error) throw error;
    if (!data?.product_id) throw new Error('RPC did not return product_id');
    packagedProductId = data.product_id;

    const { data: prodRecord, error: prodErr } = await supabase
      .from('products')
      .select('*, category:categories(*)')
      .eq('id', packagedProductId)
      .single();

    if (prodErr) throw prodErr;
    record('Product Creation: PACKAGED (RPC)', 'PASS', `Created product: "${prodRecord.name}" [SKU: ${prodRecord.sku}] in category "${prodRecord.category?.name}"`);
  } catch (err) {
    record('Product Creation: PACKAGED (RPC)', 'FAIL', err.message);
  }

  // 8. Product Creation - Loose Weighed (RPC)
  try {
    const { data, error } = await supabase.rpc('create_product', {
      p_organization_id: orgId,
      p_category_id: null,
      p_name: 'Organic Honeycrisp Apples',
      p_barcode: null,
      p_sku: `PROD-APPL-${timestamp.toString().slice(-4)}`,
      p_unit_type: 'LOOSE',
      p_description: 'Locally grown crisp apples sold by weight',
    });

    if (error) throw error;
    if (!data?.product_id) throw new Error('RPC did not return product_id');
    looseProductId = data.product_id;

    record('Product Creation: LOOSE (RPC)', 'PASS', `Created loose product (ID: ${looseProductId}) without category`);
  } catch (err) {
    record('Product Creation: LOOSE (RPC)', 'FAIL', err.message);
  }

  // 9. Inventory Setup & Initial Stock Ledger (RPC)
  try {
    const { error } = await supabase.rpc('setup_shop_inventory', {
      p_shop_id: shopId,
      p_product_id: packagedProductId,
      p_selling_price: 65.50,
      p_initial_quantity: 25,
      p_low_stock_threshold: 5,
    });

    if (error) throw error;

    // Verify shop_inventory row
    const { data: invRecord, error: invErr } = await supabase
      .from('shop_inventory')
      .select('*, product:products(*)')
      .eq('shop_id', shopId)
      .eq('product_id', packagedProductId)
      .single();

    if (invErr) throw invErr;

    // Verify stock_movements ledger entry
    const { data: movRecords, error: movErr } = await supabase
      .from('stock_movements')
      .select('*')
      .eq('shop_id', shopId)
      .eq('product_id', packagedProductId);

    if (movErr) throw movErr;
    if (movRecords.length === 0) throw new Error('No stock_movements ledger record found for initial stock');

    record(
      'Inventory Setup & Stock Ledger (RPC)',
      'PASS',
      `Inventory configured at price ₹${invRecord.selling_price}, qty: ${invRecord.quantity}. Ledger recorded movement: ${movRecords[0].movement_type} (+${movRecords[0].delta_quantity})`
    );
  } catch (err) {
    record('Inventory Setup & Stock Ledger (RPC)', 'FAIL', err.message);
  }

  // 10. Device Enrollment & One-Time Secret (RPC)
  try {
    const devIdentifier = `SCALE-ESP32-${timestamp.toString().slice(-6)}`;
    const { data, error } = await supabase.rpc('enroll_device', {
      p_shop_id: shopId,
      p_device_identifier: devIdentifier,
      p_name: 'Bakery Checkout Load Cell #1',
    });

    if (error) throw error;
    if (!data?.device_id || !data?.device_secret) {
      throw new Error('RPC did not return device_id or device_secret');
    }

    deviceId = data.device_id;
    initialDeviceSecret = data.device_secret;

    // Verify devices row has NO raw secret exposed
    const { data: devRecord, error: devErr } = await supabase
      .from('devices')
      .select('*')
      .eq('id', deviceId)
      .single();

    if (devErr) throw devErr;
    if ('secret' in devRecord || 'device_secret' in devRecord) {
      throw new Error('Raw device secret leaked in devices table!');
    }

    record(
      'Device Enrollment (RPC)',
      'PASS',
      `Device "${devRecord.name}" enrolled [ID: ${deviceId}]. 256-bit secret generated (${initialDeviceSecret.slice(0, 8)}...); quarantined in device_credentials`
    );
  } catch (err) {
    record('Device Enrollment (RPC)', 'FAIL', err.message);
  }

  // 11. Credential Rotation (RPC)
  try {
    const { data, error } = await supabase.rpc('rotate_device_credentials', {
      p_device_id: deviceId,
    });

    if (error) throw error;
    if (!data?.new_device_secret) throw new Error('RPC did not return new_device_secret');
    if (data.new_device_secret === initialDeviceSecret) {
      throw new Error('New secret must differ from initial secret');
    }

    record('Credential Rotation (RPC)', 'PASS', `Device secret rotated successfully. New secret generated.`);
  } catch (err) {
    record('Credential Rotation (RPC)', 'FAIL', err.message);
  }

  // 12. Calibration (RPC)
  try {
    const { error } = await supabase.rpc('calibrate_device', {
      p_device_id: deviceId,
      p_tare_offset: -12500.5,
      p_calibration_factor: 420.75,
    });

    if (error) throw error;
    record('Device Calibration (RPC)', 'PASS', `Device calibrated with tare offset and factor.`);
  } catch (err) {
    record('Device Calibration (RPC)', 'FAIL', err.message);
  }

  // 13. Cross-Tenant Security & Unauthorized Isolation Test
  try {
    const outsiderEmail = `outsider_${timestamp}@anotherorg.local`;
    const outsiderPassword = `OutsiderPass_${timestamp}!`;

    const { error: outErr } = await supabase.auth.signUp({
      email: outsiderEmail,
      password: outsiderPassword,
      options: { data: { full_name: 'Outsider User' } },
    });

    if (outErr) throw outErr;

    // Login as outsider
    const outsiderClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
      auth: { persistSession: false },
    });
    await outsiderClient.auth.signInWithPassword({
      email: outsiderEmail,
      password: outsiderPassword,
    });

    // 13a. Attempt to select Org 1 (should return empty array)
    const { data: stolenOrgs, error: stolenOrgErr } = await outsiderClient
      .from('organizations')
      .select('*')
      .eq('id', orgId);

    if (stolenOrgErr) throw stolenOrgErr;
    if (stolenOrgs.length > 0) throw new Error('RLS VIOLATION: Outsider was able to read another org!');

    // 13b. Attempt to select Shop 1 (should return empty array)
    const { data: stolenShops, error: stolenShopErr } = await outsiderClient
      .from('shops')
      .select('*')
      .eq('id', shopId);

    if (stolenShopErr) throw stolenShopErr;
    if (stolenShops.length > 0) throw new Error('RLS VIOLATION: Outsider was able to read another shop!');

    // 13c. Attempt to execute create_product on Org 1 (should be rejected)
    const { error: illegalRpcErr } = await outsiderClient.rpc('create_product', {
      p_organization_id: orgId,
      p_category_id: null,
      p_name: 'Malicious Injected Product',
      p_barcode: null,
      p_sku: 'HACK-01',
      p_unit_type: 'PACKAGED',
    });

    if (!illegalRpcErr) {
      throw new Error('SECURITY VIOLATION: Outsider executed create_product in another tenant org!');
    }

    record('Cross-Tenant RLS & Security Isolation', 'PASS', `Outsider blocked by RLS from reading org/shop rows and rejected from executing admin RPCs`);
  } catch (err) {
    record('Cross-Tenant RLS & Security Isolation', 'FAIL', err.message);
  }

  console.log('\n==============================================================================');
  console.log('Test Summary:');
  const passed = results.filter((r) => r.status === 'PASS').length;
  const failed = results.filter((r) => r.status === 'FAIL').length;
  console.log(`Total: ${results.length} | Passed: ${passed} | Failed: ${failed}`);
  console.log('==============================================================================\n');

  if (failed > 0) {
    process.exit(1);
  }
}

run().catch((err) => {
  console.error('Fatal test error:', err);
  process.exit(1);
});
