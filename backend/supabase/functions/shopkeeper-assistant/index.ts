// ==============================================================================
// SmartShelf V2 - AI Shopkeeper Assistant Edge Function
// Endpoint: POST /functions/v1/shopkeeper-assistant
//
// ARCHITECTURE & SECURITY:
// 1. Zero-Trust Identity: Authenticates user via Supabase Auth JWT.
// 2. Multi-Tenant Authorization: Verifies caller access via `has_shop_access`.
// 3. Deterministic Analytics Engine: Calculates exact business figures directly
//    from PostgreSQL (sales, stock, velocity, thresholds) without LLM guessing.
// 4. AI Synthesis Provider Abstraction:
//    - Uses Gemini or OpenAI API when configured via environment secrets.
//    - Gracefully falls back to real-time deterministic natural-language synthesis
//      when no API key is set, guaranteeing zero downtime.
// ==============================================================================

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.48.1";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json",
};

const UUID_REGEX = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

interface AssistantRequest {
  shop_id: string;
  question: string;
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }

  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: CORS_HEADERS,
    });
  }

  const authHeader = req.headers.get("Authorization");
  if (!authHeader || !authHeader.startsWith("Bearer ")) {
    return new Response(
      JSON.stringify({ error: "Unauthorized: Missing Bearer token" }),
      { status: 401, headers: CORS_HEADERS },
    );
  }

  let body: AssistantRequest;
  try {
    body = await req.json();
  } catch (_) {
    return new Response(
      JSON.stringify({ error: "Invalid JSON body" }),
      { status: 400, headers: CORS_HEADERS },
    );
  }

  const { shop_id, question } = body;
  if (!shop_id || !UUID_REGEX.test(shop_id)) {
    return new Response(
      JSON.stringify({ error: "Invalid or missing shop_id" }),
      { status: 400, headers: CORS_HEADERS },
    );
  }

  if (!question || question.trim().length === 0) {
    return new Response(
      JSON.stringify({ error: "Question cannot be empty" }),
      { status: 400, headers: CORS_HEADERS },
    );
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "http://supabase_kong_backend:8000";
  const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";

  // Authenticated client bound to the caller's JWT
  const userClient = createClient(supabaseUrl, supabaseAnonKey, {
    global: { headers: { Authorization: authHeader } },
  });

  // 1. Verify User Session
  const { data: userData, error: userError } = await userClient.auth.getUser();
  if (userError || !userData?.user) {
    return new Response(
      JSON.stringify({ error: "Unauthorized: Invalid or expired session token" }),
      { status: 401, headers: CORS_HEADERS },
    );
  }

  // 2. Verify Shop Access Authorization
  const { data: hasAccess, error: accessError } = await userClient.rpc("has_shop_access", {
    p_shop_id: shop_id,
  });

  if (accessError || !hasAccess) {
    return new Response(
      JSON.stringify({ error: "Forbidden: You are not authorized to access this store's records." }),
      { status: 403, headers: CORS_HEADERS },
    );
  }

  // 3. Fetch Shop Metadata
  const { data: shopRecord } = await userClient
    .from("shops")
    .select("id, name, location, currency, organization_id")
    .eq("id", shop_id)
    .single();

  const shopName = shopRecord?.name ?? "Your Shop";
  const currency = shopRecord?.currency ?? "INR";
  const orgId = shopRecord?.organization_id;

  // 4. Intent Classification & Deterministic Analytics Engine
  const intent = classifyIntent(question);
  const analyticsData = await executeAnalyticsQuery(userClient, intent, shop_id, orgId);

  // 5. Narrative Synthesis (AI Provider or Structured Business Logic)
  const answer = await synthesizeResponse({
    question: question.trim(),
    intent,
    shopName,
    currency,
    data: analyticsData,
  });

  return new Response(
    JSON.stringify({
      success: true,
      intent,
      answer,
      metrics: analyticsData,
      timestamp: new Date().toISOString(),
    }),
    { status: 200, headers: CORS_HEADERS },
  );
});

// ==============================================================================
// Intent Classification
// ==============================================================================

type QueryIntent =
  | "TODAY_SALES"
  | "MONTH_SALES"
  | "TOP_SELLING"
  | "LOW_STOCK"
  | "RESTOCK"
  | "SLOW_MOVING"
  | "PERIOD_COMPARE"
  | "CROSS_SHOP"
  | "GENERAL_OVERVIEW";

function classifyIntent(query: string): QueryIntent {
  const q = query.toLowerCase();

  if (
    q.includes("today") ||
    q.includes("day's revenue") ||
    q.includes("todays sales") ||
    q.includes("how much did i make today") ||
    q.includes("revenue today")
  ) {
    return "TODAY_SALES";
  }

  if (
    q.includes("month") ||
    q.includes("monthly") ||
    q.includes("this month")
  ) {
    return "MONTH_SALES";
  }

  if (
    q.includes("compare") ||
    q.includes("comparison") ||
    q.includes("versus") ||
    q.includes("vs") ||
    q.includes("last week") ||
    q.includes("this week with")
  ) {
    return "PERIOD_COMPARE";
  }

  if (
    q.includes("top") ||
    q.includes("best selling") ||
    q.includes("most sold") ||
    q.includes("highest selling") ||
    q.includes("popular") ||
    q.includes("fast selling")
  ) {
    return "TOP_SELLING";
  }

  if (
    q.includes("restock") ||
    q.includes("reorder") ||
    q.includes("buy more") ||
    q.includes("what should i order")
  ) {
    return "RESTOCK";
  }

  if (
    q.includes("low stock") ||
    q.includes("out of stock") ||
    q.includes("running low") ||
    q.includes("depleted") ||
    q.includes("stock level") ||
    q.includes("shortage")
  ) {
    return "LOW_STOCK";
  }

  if (
    q.includes("slow") ||
    q.includes("not selling") ||
    q.includes("dead stock") ||
    q.includes("least sold") ||
    q.includes("slow-moving")
  ) {
    return "SLOW_MOVING";
  }

  if (
    q.includes("other shop") ||
    q.includes("other store") ||
    q.includes("network") ||
    q.includes("cross shop") ||
    q.includes("all branch")
  ) {
    return "CROSS_SHOP";
  }

  return "GENERAL_OVERVIEW";
}

// ==============================================================================
// Deterministic Analytics Query Execution
// ==============================================================================

async function executeAnalyticsQuery(
  client: any,
  intent: QueryIntent,
  shopId: string,
  orgId?: string,
): Promise<Record<string, unknown>> {
  const now = new Date();

  switch (intent) {
    case "TODAY_SALES": {
      const startOfToday = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate())).toISOString();
      const { data: sales } = await client
        .from("sales")
        .select("id, sale_number, total_amount, payment_method, payment_status, created_at")
        .eq("shop_id", shopId)
        .gte("created_at", startOfToday);

      const rows = sales ?? [];
      let totalRevenue = 0;
      const paymentBreakdown: Record<string, number> = {};

      for (const s of rows) {
        const amt = Number(s.total_amount) || 0;
        totalRevenue += amt;
        const method = s.payment_method || "CASH";
        paymentBreakdown[method] = (paymentBreakdown[method] || 0) + amt;
      }

      // Query today's top product sold
      const saleIds = rows.map((s: any) => s.id);
      let topItemName = null;
      let topItemQty = 0;

      if (saleIds.length > 0) {
        const { data: items } = await client
          .from("sale_items")
          .select("product_name, unit_type, quantity")
          .in("sale_id", saleIds);

        const itemMap: Record<string, { name: string; qty: number; unit: string }> = {};
        for (const item of items ?? []) {
          const key = item.product_name;
          if (!itemMap[key]) {
            itemMap[key] = { name: item.product_name, qty: 0, unit: item.unit_type === "LOOSE" ? "kg" : "pcs" };
          }
          itemMap[key].qty += Number(item.quantity) || 0;
        }

        const sorted = Object.values(itemMap).sort((a, b) => b.qty - a.qty);
        if (sorted.length > 0) {
          topItemName = `${sorted[0].name} (${sorted[0].qty} ${sorted[0].unit})`;
          topItemQty = sorted[0].qty;
        }
      }

      return {
        date: startOfToday.split("T")[0],
        transaction_count: rows.length,
        total_revenue: totalRevenue,
        average_order_value: rows.length > 0 ? (totalRevenue / rows.length).toFixed(2) : 0,
        payment_breakdown: paymentBreakdown,
        top_product_today: topItemName,
      };
    }

    case "MONTH_SALES": {
      const startOfMonth = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1)).toISOString();
      const { data: sales } = await client
        .from("sales")
        .select("total_amount, created_at")
        .eq("shop_id", shopId)
        .gte("created_at", startOfMonth);

      const rows = sales ?? [];
      let totalRevenue = 0;
      for (const s of rows) {
        totalRevenue += Number(s.total_amount) || 0;
      }

      const daysInMonth = now.getUTCDate();
      const dailyAverage = daysInMonth > 0 ? (totalRevenue / daysInMonth).toFixed(2) : 0;

      return {
        month: now.toLocaleString("default", { month: "long", year: "numeric" }),
        transaction_count: rows.length,
        total_revenue: totalRevenue,
        daily_average: dailyAverage,
        start_date: startOfMonth.split("T")[0],
      };
    }

    case "PERIOD_COMPARE": {
      const nowMs = now.getTime();
      const sevenDaysMs = 7 * 24 * 60 * 60 * 1000;
      const startOfThisWeek = new Date(nowMs - sevenDaysMs).toISOString();
      const startOfLastWeek = new Date(nowMs - 2 * sevenDaysMs).toISOString();

      const { data: thisWeekSales } = await client
        .from("sales")
        .select("total_amount")
        .eq("shop_id", shopId)
        .gte("created_at", startOfThisWeek);

      const { data: lastWeekSales } = await client
        .from("sales")
        .select("total_amount")
        .eq("shop_id", shopId)
        .gte("created_at", startOfLastWeek)
        .lt("created_at", startOfThisWeek);

      const thisWeekRev = (thisWeekSales ?? []).reduce((acc: number, s: any) => acc + (Number(s.total_amount) || 0), 0);
      const lastWeekRev = (lastWeekSales ?? []).reduce((acc: number, s: any) => acc + (Number(s.total_amount) || 0), 0);

      const diff = thisWeekRev - lastWeekRev;
      const percentageChange = lastWeekRev > 0 ? ((diff / lastWeekRev) * 100).toFixed(1) : (thisWeekRev > 0 ? "+100" : "0");

      return {
        this_week_revenue: thisWeekRev,
        this_week_orders: (thisWeekSales ?? []).length,
        last_week_revenue: lastWeekRev,
        last_week_orders: (lastWeekSales ?? []).length,
        revenue_difference: diff,
        percentage_change: percentageChange,
      };
    }

    case "TOP_SELLING": {
      const thirtyDaysAgo = new Date(now.getTime() - 30 * 24 * 60 * 60 * 1000).toISOString();
      const { data: sales } = await client
        .from("sales")
        .select("id")
        .eq("shop_id", shopId)
        .gte("created_at", thirtyDaysAgo);

      const saleIds = (sales ?? []).map((s: any) => s.id);
      if (saleIds.length === 0) {
        return { items: [], period: "last 30 days" };
      }

      const { data: items } = await client
        .from("sale_items")
        .select("product_name, unit_type, quantity, line_total")
        .in("sale_id", saleIds);

      const itemMap: Record<string, { name: string; unit_type: string; total_quantity: number; total_revenue: number }> = {};
      for (const item of items ?? []) {
        const key = item.product_name;
        if (!itemMap[key]) {
          itemMap[key] = {
            name: item.product_name,
            unit_type: item.unit_type,
            total_quantity: 0,
            total_revenue: 0,
          };
        }
        itemMap[key].total_quantity += Number(item.quantity) || 0;
        itemMap[key].total_revenue += Number(item.line_total) || 0;
      }

      const ranked = Object.values(itemMap).sort((a, b) => b.total_quantity - a.total_quantity);

      return {
        period: "last 30 days",
        top_by_quantity: ranked.slice(0, 5),
        top_by_revenue: [...ranked].sort((a, b) => b.total_revenue - a.total_revenue).slice(0, 5),
      };
    }

    case "LOW_STOCK": {
      const { data: inventory } = await client
        .from("shop_inventory")
        .select("quantity, low_stock_threshold, is_available, product:products(name, unit_type, barcode, sku)")
        .eq("shop_id", shopId);

      const outOfStock: any[] = [];
      const lowStock: any[] = [];
      const healthy: any[] = [];

      for (const item of inventory ?? []) {
        const qty = Number(item.quantity) || 0;
        const threshold = Number(item.low_stock_threshold) || 5;
        const unit = item.product?.unit_type === "LOOSE" ? "kg" : "pcs";
        const entry = {
          name: item.product?.name ?? "Unknown",
          quantity: qty,
          threshold,
          unit,
        };

        if (qty <= 0) {
          outOfStock.push(entry);
        } else if (qty <= threshold) {
          lowStock.push(entry);
        } else {
          healthy.push(entry);
        }
      }

      return {
        total_tracked_items: (inventory ?? []).length,
        out_of_stock_count: outOfStock.length,
        low_stock_count: lowStock.length,
        out_of_stock_items: outOfStock,
        low_stock_items: lowStock,
      };
    }

    case "RESTOCK": {
      // Products below or at threshold
      const { data: inventory } = await client
        .from("shop_inventory")
        .select("product_id, quantity, low_stock_threshold, product:products(name, unit_type)")
        .eq("shop_id", shopId);

      const candidates: any[] = [];
      const fourteenDaysAgo = new Date(now.getTime() - 14 * 24 * 60 * 60 * 1000).toISOString();

      for (const item of inventory ?? []) {
        const qty = Number(item.quantity) || 0;
        const threshold = Number(item.low_stock_threshold) || 5;
        if (qty <= threshold) {
          candidates.push({
            productId: item.product_id,
            name: item.product?.name ?? "Unknown",
            unit: item.product?.unit_type === "LOOSE" ? "kg" : "pcs",
            currentStock: qty,
            threshold,
          });
        }
      }

      // Check recent sales rate
      const recommendations: any[] = [];
      for (const c of candidates) {
        const { data: saleItems } = await client
          .from("sale_items")
          .select("quantity, created_at")
          .eq("product_id", c.productId)
          .gte("created_at", fourteenDaysAgo);

        const totalSold14d = (saleItems ?? []).reduce((acc: number, s: any) => acc + (Number(s.quantity) || 0), 0);
        const dailyRate = totalSold14d / 14;

        // Recommended restock: enough for 2 weeks buffer + deficit to threshold
        const suggestedOrder = Math.max(
          Math.ceil((c.threshold * 2) - c.currentStock),
          Math.ceil(dailyRate * 14) || c.threshold,
        );

        recommendations.push({
          name: c.name,
          currentStock: c.currentStock,
          unit: c.unit,
          threshold: c.threshold,
          recent14dSales: totalSold14d,
          dailyRunRate: dailyRate.toFixed(2),
          suggestedRestock: suggestedOrder,
          urgency: c.currentStock === 0 ? "CRITICAL (Out of stock)" : "HIGH (Below safety threshold)",
        });
      }

      return {
        recommendation_count: recommendations.length,
        items: recommendations,
      };
    }

    case "SLOW_MOVING": {
      const thirtyDaysAgo = new Date(now.getTime() - 30 * 24 * 60 * 60 * 1000).toISOString();
      const { data: inventory } = await client
        .from("shop_inventory")
        .select("product_id, quantity, created_at, product:products(name, unit_type)")
        .eq("shop_id", shopId);

      const slowItems: any[] = [];
      for (const item of inventory ?? []) {
        const { data: sales } = await client
          .from("sale_items")
          .select("quantity")
          .eq("product_id", item.product_id)
          .gte("created_at", thirtyDaysAgo);

        const totalSold = (sales ?? []).reduce((acc: number, s: any) => acc + (Number(s.quantity) || 0), 0);
        const itemAgeDays = Math.floor((now.getTime() - new Date(item.created_at).getTime()) / (24 * 60 * 60 * 1000));

        if (totalSold <= 1 && itemAgeDays >= 7) {
          slowItems.push({
            name: item.product?.name ?? "Unknown",
            currentStock: Number(item.quantity) || 0,
            unit: item.product?.unit_type === "LOOSE" ? "kg" : "pcs",
            unitsSoldLast30Days: totalSold,
            daysStocked: itemAgeDays,
          });
        }
      }

      return {
        period: "last 30 days",
        slow_moving_count: slowItems.length,
        items: slowItems,
      };
    }

    case "CROSS_SHOP": {
      // Verify if caller is ORG_ADMIN
      const { data: isOrgAdmin } = await client.rpc("is_org_admin", {
        p_organization_id: orgId,
      });

      if (!isOrgAdmin) {
        return {
          authorized: false,
          message: "Cross-store trends and comparative network analytics are restricted to organization administrators to protect individual branch data privacy.",
        };
      }

      // Aggregate anonymous performance across organization shops
      const { data: shops } = await client
        .from("shops")
        .select("id, name")
        .eq("organization_id", orgId);

      const shopCount = (shops ?? []).length;
      return {
        authorized: true,
        participating_branches: shopCount,
        note: "Organization multi-branch network analytics enabled.",
      };
    }

    case "GENERAL_OVERVIEW":
    default: {
      const startOfToday = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate())).toISOString();
      const { data: todaySales } = await client
        .from("sales")
        .select("total_amount")
        .eq("shop_id", shopId)
        .gte("created_at", startOfToday);

      const todayRev = (todaySales ?? []).reduce((acc: number, s: any) => acc + (Number(s.total_amount) || 0), 0);

      const { data: inventory } = await client
        .from("shop_inventory")
        .select("quantity, low_stock_threshold")
        .eq("shop_id", shopId);

      let lowCount = 0;
      let outCount = 0;
      for (const inv of inventory ?? []) {
        const q = Number(inv.quantity) || 0;
        const th = Number(inv.low_stock_threshold) || 5;
        if (q <= 0) outCount++;
        else if (q <= th) lowCount++;
      }

      return {
        today_revenue: todayRev,
        today_sales_count: (todaySales ?? []).length,
        total_products: (inventory ?? []).length,
        low_stock_count: lowCount,
        out_of_stock_count: outCount,
      };
    }
  }
}

// ==============================================================================
// Narrative Synthesis (AI Provider / Structured Synthesis)
// ==============================================================================

interface SynthesisContext {
  question: string;
  intent: QueryIntent;
  shopName: string;
  currency: string;
  data: Record<string, any>;
}

async function synthesizeResponse(ctx: SynthesisContext): Promise<string> {
  const geminiKey = Deno.env.get("GEMINI_API_KEY");
  const openAiKey = Deno.env.get("OPENAI_API_KEY");

  // If Gemini API key is available, generate response using Gemini
  if (geminiKey) {
    try {
      const prompt = `You are the SmartShelf AI Assistant for ${ctx.shopName}.
Answer the shopkeeper's question: "${ctx.question}"

Use ONLY these verified database facts:
${JSON.stringify(ctx.data, null, 2)}

Rules:
1. Always present money in ${ctx.currency} (₹).
2. Clearly format quantities with their correct units (pcs or kg).
3. Do NOT make up any numbers or trends not present in the data.
4. Keep the answer direct, practical, and helpful for a retail shopkeeper.`;

      const res = await fetch(
        `https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=${geminiKey}`,
        {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            contents: [{ parts: [{ text: prompt }] }],
            generationConfig: { maxOutputTokens: 250, temperature: 0.2 },
          }),
        },
      );

      if (res.ok) {
        const json = await res.json();
        const text = json.candidates?.[0]?.content?.parts?.[0]?.text;
        if (text && text.trim().length > 0) {
          return text.trim();
        }
      }
    } catch (_) {
      // Fallback gracefully to deterministic synthesis below
    }
  }

  // If OpenAI API key is available, generate response using OpenAI
  if (openAiKey) {
    try {
      const res = await fetch("https://api.openai.com/v1/chat/completions", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${openAiKey}`,
        },
        body: JSON.stringify({
          model: "gpt-4o-mini",
          messages: [
            {
              role: "system",
              content: `You are the SmartShelf AI Assistant for ${ctx.shopName}. Answer the shopkeeper's question using ONLY the provided verified database facts. Use ${ctx.currency} (₹) and proper units (pcs/kg). Never hallucinate numbers.`,
            },
            {
              role: "user",
              content: `Question: "${ctx.question}"\n\nVerified Data: ${JSON.stringify(ctx.data)}`,
            },
          ],
          max_tokens: 250,
          temperature: 0.2,
        }),
      });

      if (res.ok) {
        const json = await res.json();
        const text = json.choices?.[0]?.message?.content;
        if (text && text.trim().length > 0) {
          return text.trim();
        }
      }
    } catch (_) {
      // Fallback gracefully to deterministic synthesis below
    }
  }

  // Graceful, 100% Deterministic Verified Synthesis
  return generateDeterministicSynthesis(ctx);
}

function generateDeterministicSynthesis(ctx: SynthesisContext): string {
  const { intent, currency, data, shopName } = ctx;

  switch (intent) {
    case "TODAY_SALES": {
      const rev = Number(data.total_revenue || 0).toFixed(2);
      const count = data.transaction_count || 0;
      const aov = data.average_order_value || "0.00";
      const top = data.top_product_today ? ` The highest-selling item today was ${data.top_product_today}.` : "";

      if (count === 0) {
        return `Your store has not recorded any completed sales transactions yet today (${data.date}). All checkout receipts will automatically update this summary in real-time.`;
      }

      return `Today, ${shopName} recorded ₹${rev} in gross sales across ${count} transaction${count === 1 ? "" : "s"} with an average order value of ₹${aov}.${top}`;
    }

    case "MONTH_SALES": {
      const rev = Number(data.total_revenue || 0).toFixed(2);
      const count = data.transaction_count || 0;
      const avg = Number(data.daily_average || 0).toFixed(2);

      if (count === 0) {
        return `For ${data.month}, no sales transactions have been logged so far.`;
      }

      return `For ${data.month}, your shop has generated ₹${rev} in revenue across ${count} customer bills, averaging approximately ₹${avg} per day.`;
    }

    case "PERIOD_COMPARE": {
      const thisWeek = Number(data.this_week_revenue || 0).toFixed(2);
      const lastWeek = Number(data.last_week_revenue || 0).toFixed(2);
      const pct = data.percentage_change;
      const isUp = Number(pct) >= 0;

      return `This week your store made ₹${thisWeek} (${data.this_week_orders} bills) compared to ₹${lastWeek} (${data.last_week_orders} bills) during the previous 7 days. That represents a ${isUp ? "+" : ""}${pct}% ${isUp ? "growth" : "decrease"} in revenue.`;
    }

    case "TOP_SELLING": {
      const topItems = (data.top_by_quantity as any[]) || [];
      if (topItems.length === 0) {
        return "There are no recorded sales over the past 30 days to determine top-selling products.";
      }

      const list = topItems
        .map((item, idx) => `${idx + 1}. ${item.name}: ${item.total_quantity} ${item.unit_type === "LOOSE" ? "kg" : "pcs"} (₹${Number(item.total_revenue).toFixed(2)})`)
        .join("\n");

      return `Here are your top-selling products over the last 30 days by quantity sold:\n\n${list}`;
    }

    case "LOW_STOCK": {
      const outList = (data.out_of_stock_items as any[]) || [];
      const lowList = (data.low_stock_items as any[]) || [];

      if (outList.length === 0 && lowList.length === 0) {
        return `Great news! All ${data.total_tracked_items} stocked products in ${shopName} are currently above their configured safety thresholds.`;
      }

      let response = "";
      if (outList.length > 0) {
        const outNames = outList.map((i) => `• ${i.name} (0 ${i.unit})`).join("\n");
        response += `⚠️ Out of Stock (${outList.length}):\n${outNames}\n\n`;
      }

      if (lowList.length > 0) {
        const lowNames = lowList.map((i) => `• ${i.name}: ${i.quantity} ${i.unit} (Alert threshold: ${i.threshold} ${i.unit})`).join("\n");
        response += `⚡ Running Low (${lowList.length}):\n${lowNames}`;
      }

      return response.trim();
    }

    case "RESTOCK": {
      const items = (data.items as any[]) || [];
      if (items.length === 0) {
        return "No products currently require restocking. All items are maintained above their safety thresholds.";
      }

      const details = items
        .map(
          (i, idx) =>
            `${idx + 1}. ${i.name} [${i.urgency}]\n   Current stock: ${i.currentStock} ${i.unit} (Safety: ${i.threshold} ${i.unit})\n   Suggested restock: +${i.suggestedRestock} ${i.unit} (14-day sales: ${i.recent14dSales} ${i.unit})`,
        )
        .join("\n\n");

      return `Based on current stock levels and 14-day sales velocity, here are your prioritized restock recommendations:\n\n${details}\n\n(Tip: Tap '+ Stock' on the inventory screen to log incoming stock shipments.)`;
    }

    case "SLOW_MOVING": {
      const items = (data.items as any[]) || [];
      if (items.length === 0) {
        return "No slow-moving products were detected over the past 30 days. All active products have steady sales velocity.";
      }

      const lines = items
        .map(
          (i, idx) =>
            `${idx + 1}. ${i.name}: Only ${i.unitsSoldLast30Days} ${i.unit} sold in the last 30 days (Stock: ${i.currentStock} ${i.unit}, stocked for ${i.daysStocked} days)`,
        )
        .join("\n");

      return `These items have had minimal or zero customer purchases over the past 30 days:\n\n${lines}\n\nConsider reviewing their placement or running a promotional discount.`;
    }

    case "CROSS_SHOP": {
      if (!data.authorized) {
        return data.message || "Cross-shop insights are restricted to organization administrators to protect store data privacy.";
      }
      return `Your organization oversees ${data.participating_branches} active branch locations. Comparative network reports are enabled.`;
    }

    case "GENERAL_OVERVIEW":
    default: {
      const rev = Number(data.today_revenue || 0).toFixed(2);
      const orders = data.today_sales_count || 0;
      const low = data.low_stock_count || 0;
      const out = data.out_of_stock_count || 0;

      return `Hello! ${shopName} has recorded ₹${rev} across ${orders} sale${orders === 1 ? "" : "s"} today. You have ${data.total_products} tracked products, with ${low} low-stock alert${low === 1 ? "" : "s"} and ${out} out-of-stock item${out === 1 ? "" : "s"}. What would you like to check next?`;
    }
  }
}
