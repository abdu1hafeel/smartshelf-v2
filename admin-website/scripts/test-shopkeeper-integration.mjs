// ==============================================================================
// SmartShelf V2 - Shopkeeper & POS Integration Test Suite
// ==============================================================================

import { createClient } from '@supabase/supabase-js';
import crypto from 'crypto';

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
  console.log('Starting Shopkeeper Integration & process_sale_tx Test Suite');
  console.log(`Connecting to: ${SUPABASE_URL}`);
  console.log('==============================================================================\n');

  const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    auth: { persistSession: false },
  });

  const timestamp = Date.now();
  const orgAdminEmail = `shopkeeper_admin_${timestamp}@testmart.local`;
  const orgAdminPass = `P@ssword_${timestamp}!`;

  let orgId = null;
  let shopId = null;
  let packagedProdId = null;
  let looseProdId = null;
  let cashierUser = null;
  let initialStock = 20;
  let itemPrice = 49.50;

  // 1. Setup Admin, Org, Shop, and Catalog
  try {
    const { data: authData, error: authErr } = await supabase.auth.signUp({
      email: orgAdminEmail,
      password: orgAdminPass,
      options: { data: { full_name: 'Shop Admin' } },
    });
    if (authErr) throw authErr;

    await supabase.auth.signInWithPassword({
      email: orgAdminEmail,
      password: orgAdminPass,
    });

    // Create Org
    const { data: orgData, error: orgErr } = await supabase.rpc('create_organization_onboarding', {
      p_org_name: `Shopkeeper Org ${timestamp}`,
    });
    if (orgErr) throw orgErr;
    orgId = orgData.organization_id;

    // Create Shop
    const { data: sData, error: sErr } = await supabase.rpc('create_shop', {
      p_organization_id: orgId,
      p_name: `Express Branch ${timestamp}`,
      p_location: 'Station Road',
      p_currency: 'INR',
    });
    if (sErr) throw sErr;
    shopId = sData.shop_id || sData.id;

    // Create Packaged Product
    const { data: pData, error: pErr } = await supabase.rpc('create_product', {
      p_organization_id: orgId,
      p_category_id: null,
      p_name: 'Packaged Biscuits 200g',
      p_barcode: `890${timestamp.toString().slice(-10)}`,
      p_sku: `BISC-${timestamp.toString().slice(-4)}`,
      p_unit_type: 'PACKAGED',
      p_description: 'Crispy cookies',
    });
    if (pErr) throw pErr;
    packagedProdId = pData.product_id;

    // Create Loose Product
    const { data: lData, error: lErr } = await supabase.rpc('create_product', {
      p_organization_id: orgId,
      p_category_id: null,
      p_name: 'Loose Tomatoes',
      p_barcode: null,
      p_sku: `TOM-${timestamp.toString().slice(-4)}`,
      p_unit_type: 'LOOSE',
      p_description: 'Farm fresh tomatoes',
    });
    if (lErr) throw lErr;
    looseProdId = lData.product_id;

    // Setup Shop Inventory for Packaged Item
    const { error: invErr } = await supabase.rpc('setup_shop_inventory', {
      p_shop_id: shopId,
      p_product_id: packagedProdId,
      p_selling_price: itemPrice,
      p_initial_quantity: initialStock,
      p_low_stock_threshold: 5,
    });
    if (invErr) throw invErr;

    // Setup Shop Inventory for Loose Item
    const { error: looseInvErr } = await supabase.rpc('setup_shop_inventory', {
      p_shop_id: shopId,
      p_product_id: looseProdId,
      p_selling_price: 35.00,
      p_initial_quantity: 50.0,
      p_low_stock_threshold: 5.0,
    });
    if (looseInvErr) throw looseInvErr;

    record('Shop & Inventory Provisioning', 'PASS', `Shop ${shopId} ready with packaged & loose items`);
  } catch (err) {
    record('Shop & Inventory Provisioning', 'FAIL', err.message);
    process.exit(1);
  }

  // 2. Create Cashier User & Add to Shop Membership
  const cashierEmail = `cashier_${timestamp}@testmart.local`;
  const cashierPass = `CashierP@ss_${timestamp}!`;
  let cashierClient = null;

  try {
    const signupClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
      auth: { persistSession: false },
    });

    const { data: cAuth, error: cErr } = await signupClient.auth.signUp({
      email: cashierEmail,
      password: cashierPass,
      options: { data: { full_name: 'Test Cashier' } },
    });
    if (cErr) throw cErr;
    cashierUser = cAuth.user;

    // Admin assigns cashier to shop using assign_shop_membership RPC
    const { error: memErr } = await supabase.rpc('assign_shop_membership', {
      p_shop_id: shopId,
      p_user_id: cashierUser.id,
      p_role: 'SHOPKEEPER',
    });
    if (memErr) throw memErr;

    cashierClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
      auth: { persistSession: false },
    });

    const { error: signInErr } = await cashierClient.auth.signInWithPassword({
      email: cashierEmail,
      password: cashierPass,
    });
    if (signInErr) throw signInErr;

    record('Cashier Account & Shop Membership', 'PASS', `Cashier ${cashierEmail} authenticated & authorized for shop ${shopId}`);
  } catch (err) {
    record('Cashier Account & Shop Membership', 'FAIL', err.message);
    process.exit(1);
  }

  // 3. Shopkeeper reads authorized shop and inventory
  try {
    const { data: shops, error: sErr } = await cashierClient
      .from('shops')
      .select('*')
      .eq('id', shopId);
    if (sErr) throw sErr;
    if (shops.length !== 1) throw new Error('Cashier could not view authorized shop');

    const { data: inv, error: iErr } = await cashierClient
      .from('shop_inventory')
      .select('*, product:products(*)')
      .eq('shop_id', shopId);
    if (iErr) throw iErr;
    if (inv.length < 2) throw new Error('Cashier could not read shop inventory');

    record('Shopkeeper Inventory Lookup', 'PASS', `Retrieved ${inv.length} stocked products for shop`);
  } catch (err) {
    record('Shopkeeper Inventory Lookup', 'FAIL', err.message);
  }

  // 4. Test Packaged Product Checkout via process_sale_tx
  const checkoutId = crypto.randomUUID();
  const buyQty = 3;
  let saleId = null;
  let saleNumber = null;

  try {
    const itemsPayload = [
      {
        product_id: packagedProdId,
        quantity: buyQty,
      },
    ];

    const { data, error } = await cashierClient.rpc('process_sale_tx', {
      p_shop_id: shopId,
      p_checkout_id: checkoutId,
      p_payment_method: 'CASH',
      p_items: itemsPayload,
      p_notes: 'Integration test checkout',
    });

    if (error) throw error;
    if (!data?.sale_id || !data?.sale_number) {
      throw new Error(`Invalid RPC response: ${JSON.stringify(data)}`);
    }

    saleId = data.sale_id;
    saleNumber = data.sale_number;
    const expectedTotal = buyQty * itemPrice;

    if (Math.abs(data.total_amount - expectedTotal) > 0.01) {
      throw new Error(`Total amount mismatch: expected ₹${expectedTotal}, got ₹${data.total_amount}`);
    }

    record('Packaged Item Checkout (process_sale_tx)', 'PASS', `Sale #${saleNumber} confirmed, Total: ₹${data.total_amount}`);
  } catch (err) {
    record('Packaged Item Checkout (process_sale_tx)', 'FAIL', err.message);
  }

  // 5. Verify Database State Post-Checkout
  try {
    // 5a. Check sale record
    const { data: saleRecord, error: sErr } = await cashierClient
      .from('sales')
      .select('*')
      .eq('id', saleId)
      .single();
    if (sErr) throw sErr;
    if (saleRecord.payment_status !== 'COMPLETED') throw new Error(`Sale status is ${saleRecord.payment_status}`);

    // 5b. Check sale_items
    const { data: saleItems, error: siErr } = await cashierClient
      .from('sale_items')
      .select('*')
      .eq('sale_id', saleId);
    if (siErr) throw siErr;
    if (saleItems.length !== 1) throw new Error(`Expected 1 sale item, got ${saleItems.length}`);
    if (saleItems[0].quantity !== buyQty) throw new Error(`Item quantity mismatch: ${saleItems[0].quantity}`);

    // 5c. Check inventory decrement
    const { data: invPost, error: invErr } = await cashierClient
      .from('shop_inventory')
      .select('*')
      .eq('shop_id', shopId)
      .eq('product_id', packagedProdId)
      .single();
    if (invErr) throw invErr;
    const expectedStock = initialStock - buyQty;
    if (invPost.quantity !== expectedStock) {
      throw new Error(`Inventory stock not properly decremented: expected ${expectedStock}, got ${invPost.quantity}`);
    }

    // 5d. Check stock_movements ledger entry
    const { data: movements, error: movErr } = await cashierClient
      .from('stock_movements')
      .select('*')
      .eq('reference_id', saleId);
    if (movErr) throw movErr;
    if (movements.length !== 1) throw new Error(`Expected 1 stock movement for sale, got ${movements.length}`);
    if (movements[0].movement_type !== 'SALE' || movements[0].delta_quantity !== -buyQty) {
      throw new Error(`Stock movement ledger mismatch: delta=${movements[0].delta_quantity}`);
    }

    record('Database State & Stock Ledger Verification', 'PASS', `Stock decremented from ${initialStock} to ${expectedStock}, stock_movements ledger created atomically`);
  } catch (err) {
    record('Database State & Stock Ledger Verification', 'FAIL', err.message);
  }

  // 6. Idempotent Retry Test with Same Checkout ID
  try {
    const itemsPayload = [
      {
        product_id: packagedProdId,
        quantity: buyQty,
      },
    ];

    // Resend exact same checkout_id
    const { data: retryData, error: retryErr } = await cashierClient.rpc('process_sale_tx', {
      p_shop_id: shopId,
      p_checkout_id: checkoutId,
      p_payment_method: 'CASH',
      p_items: itemsPayload,
      p_notes: 'Integration test checkout',
    });

    if (retryErr) throw retryErr;
    if (!retryData.is_idempotent_retry) {
      throw new Error('Expected is_idempotent_retry to be true on duplicate submission');
    }
    if (retryData.sale_id !== saleId) {
      throw new Error('Idempotent retry returned a different sale_id');
    }

    // Verify stock was NOT deducted again
    const { data: invCheck, error: invErr } = await cashierClient
      .from('shop_inventory')
      .select('*')
      .eq('shop_id', shopId)
      .eq('product_id', packagedProdId)
      .single();
    if (invErr) throw invErr;
    if (invCheck.quantity !== (initialStock - buyQty)) {
      throw new Error(`Double deduction detected! Quantity is ${invCheck.quantity}`);
    }

    record('Idempotent Retry Safety', 'PASS', `Identical checkout UUID returned is_idempotent_retry=true without double stock deduction`);
  } catch (err) {
    record('Idempotent Retry Safety', 'FAIL', err.message);
  }

  // 7. Idempotency Conflict Test (Same Checkout ID with Modified Payload)
  try {
    const conflictingPayload = [
      {
        product_id: packagedProdId,
        quantity: 1, // Modified from 3 to 1
      },
    ];

    const { error: confErr } = await cashierClient.rpc('process_sale_tx', {
      p_shop_id: shopId,
      p_checkout_id: checkoutId,
      p_payment_method: 'CASH',
      p_items: conflictingPayload,
    });

    if (!confErr) {
      throw new Error('Database should have rejected altered payload with IDEMPOTENCY_CONFLICT');
    }

    if (!confErr.message.includes('IDEMPOTENCY_CONFLICT')) {
      throw new Error(`Unexpected error message: ${confErr.message}`);
    }

    record('Idempotency Conflict Rejection', 'PASS', `Rejected modified payload reusing checkout_id: ${confErr.message}`);
  } catch (err) {
    record('Idempotency Conflict Rejection', 'FAIL', err.message);
  }

  // 8. Insufficient Stock Rejection
  try {
    const excessiveCheckoutId = crypto.randomUUID();
    const excessivePayload = [
      {
        product_id: packagedProdId,
        quantity: 9999, // Way exceeds available stock
      },
    ];

    const { error: oosErr } = await cashierClient.rpc('process_sale_tx', {
      p_shop_id: shopId,
      p_checkout_id: excessiveCheckoutId,
      p_payment_method: 'CASH',
      p_items: excessivePayload,
    });

    if (!oosErr) {
      throw new Error('Database should have rejected excessive quantity with Insufficient stock');
    }

    if (!oosErr.message.toLowerCase().includes('insufficient stock')) {
      throw new Error(`Unexpected error message: ${oosErr.message}`);
    }

    record('Insufficient Stock Rejection', 'PASS', `Correctly aborted checkout due to: ${oosErr.message}`);
  } catch (err) {
    record('Insufficient Stock Rejection', 'FAIL', err.message);
  }

  // 9. Cross-Shop Isolation: Cashier Cannot Access Another Shop
  try {
    // Create another shop under the same org
    await supabase.auth.signInWithPassword({
      email: orgAdminEmail,
      password: orgAdminPass,
    });

    const { data: s2Data, error: s2Err } = await supabase.rpc('create_shop', {
      p_organization_id: orgId,
      p_name: `Secret Shop 2 ${timestamp}`,
      p_location: 'Uptown',
      p_currency: 'INR',
    });
    if (s2Err) throw s2Err;
    const shop2Id = s2Data.shop_id || s2Data.id;

    // Login back as cashier
    await cashierClient.auth.signInWithPassword({
      email: cashierEmail,
      password: cashierPass,
    });

    // 9a. Try to select shop2
    const { data: s2Rows, error: rlsErr } = await cashierClient
      .from('shops')
      .select('*')
      .eq('id', shop2Id);
    if (rlsErr) throw rlsErr;
    if (s2Rows.length > 0) throw new Error('RLS VIOLATION: Cashier can read unauthorized shop!');

    // 9b. Try to call process_sale_tx on shop2
    const unauthorizedCheckoutId = crypto.randomUUID();
    const { error: unauthErr } = await cashierClient.rpc('process_sale_tx', {
      p_shop_id: shop2Id,
      p_checkout_id: unauthorizedCheckoutId,
      p_payment_method: 'CASH',
      p_items: [{ product_id: packagedProdId, quantity: 1 }],
    });

    if (!unauthErr) {
      throw new Error('Unauthorized process_sale_tx call was not blocked!');
    }

    if (!unauthErr.message.includes('Unauthorized')) {
      throw new Error(`Expected Unauthorized error, got: ${unauthErr.message}`);
    }

    record('Cross-Shop Authorization & RLS Enforcement', 'PASS', `Cashier blocked from accessing unauthorized shop: ${unauthErr.message}`);
  } catch (err) {
    record('Cross-Shop Authorization & RLS Enforcement', 'FAIL', err.message);
  }

  // Summary
  console.log('\n==============================================================================');
  console.log(`SUMMARY: ${results.filter(r => r.status === 'PASS').length} of ${results.length} integration tests passed.`);
  console.log('==============================================================================');

  const failed = results.filter(r => r.status === 'FAIL');
  if (failed.length > 0) {
    process.exit(1);
  }
}

run().catch((err) => {
  console.error('Unhandled test failure:', err);
  process.exit(1);
});
