// ==============================================================================
// SmartShelf V2 - Scale Telemetry Edge Function
// Endpoint: POST /scale-telemetry
//
// PHYSICAL HARDWARE & SERVER PROTOCOL SPECIFICATION:
// 1. ESP32 Scale Controller Architecture:
//    - Sensor: HX711 24-bit ADC coupled to a four-wire strain-gauge load cell (e.g. 50kg/100kg).
//    - Sampling Rate: 10Hz physical ADC rate, filtered via a running median-of-5 window.
//    - Telemetry Interval: 250ms (4Hz transmission rate) while weight is detected on platform.
// 2. Weighing Session Lifecycle:
//    - A weighing session begins when weight on the platform crosses the tare deadband threshold (> 5.0g).
//    - The ESP32 (or POS cashier tablet) generates a cryptographically random UUID for `session_id`.
//    - The scale streams periodic telemetry readings carrying the constant `session_id` and strictly
//      incrementing `sequence_number`.
//    - When the server responds with {"status": "SETTLING", "samples_accumulated": N, ...}:
//      The ESP32 displays a "Settling... (N/3)" indicator on the local LCD/OLED display and continues
//      streaming at the 250ms interval.
//    - When the server responds with {"status": "VERIFIED", "ticket": {...}}:
//      The ESP32 beeps an audible confirmation, freezes the display on the stable weight, caches the
//      issued `ticket_id`, broadcasts the ticket via BLE/Realtime to the shopkeeper POS app, and halts
//      telemetry transmission until the platform returns to zero (unloaded).
// 3. Machine-to-Machine Authentication & Gateway Security:
//    - ESP32 connects directly over TLS (HTTPS).
//    - Headers:
//        `x-device-id`: UUID matching an active record in public.devices.
//        `x-device-secret`: 64-char hex secret provisioned during authorized enrollment or rotation.
//    - Supabase Gateway JWT verification is disabled ([functions.scale-telemetry] verify_jwt = false)
//      in config.toml because the scale hardware cannot hold or refresh Supabase Auth user JWTs.
//    - The function verifies the device secret against public.device_credentials (stored as SHA-256).
//    - Browser access is strictly disallowed (no wildcard CORS; browser clients never access scale telemetry).
// 4. Zero-Trust Verification Guarantees:
//    - Never trust client-supplied boolean stability alone.
//    - Telemetry readings persist into public.sensor_readings while the scale settles.
//    - A single-use verified_weight_ticket is issued only after 3 consecutive strictly increasing
//      readings within a 4-second bounded time window verify within 2.0g tolerance and match server calibration.
// ==============================================================================

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.48.1";

const UUID_REGEX = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const HEX_SECRET_REGEX = /^[0-9a-fA-F]{64}$/;
const MAX_REQUEST_BYTES = 4096;
const MAX_SCALE_WEIGHT_GRAMS = 100000; // 100 kg physical capacity limit

async function sha256Hex(data: string): Promise<string> {
  const encoder = new TextEncoder();
  const hashBuffer = await crypto.subtle.digest("SHA-256", encoder.encode(data));
  const hashArray = Array.from(new Uint8Array(hashBuffer));
  return hashArray.map((b) => b.toString(16).padStart(2, "0")).join("");
}

function jsonResponse(data: unknown, status: number): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      "Content-Type": "application/json",
      "X-Content-Type-Options": "nosniff",
      "Cache-Control": "no-store",
    },
  });
}

serve(async (req: Request) => {
  // 1. Strict method validation (no CORS preflight needed for machine-to-machine HTTPS)
  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed. Machine telemetry requires POST." }, 405);
  }

  // 2. Body size guard to prevent memory exhaustion
  const contentLength = req.headers.get("content-length");
  if (contentLength && parseInt(contentLength, 10) > MAX_REQUEST_BYTES) {
    return jsonResponse({ error: "Payload too large. Maximum 4KB allowed." }, 413);
  }

  // 3. Header validation & extraction
  const deviceId = req.headers.get("x-device-id");
  const deviceSecret = req.headers.get("x-device-secret");

  if (!deviceId || !deviceSecret) {
    return jsonResponse({ error: "Unauthorized: Missing device credentials (x-device-id, x-device-secret)" }, 401);
  }

  if (!UUID_REGEX.test(deviceId)) {
    return jsonResponse({ error: "Unauthorized: Malformed device identifier" }, 401);
  }

  if (!HEX_SECRET_REGEX.test(deviceSecret)) {
    return jsonResponse({ error: "Unauthorized: Malformed device secret" }, 401);
  }

  // 4. Parse JSON body
  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ error: "Bad request: Malformed JSON payload" }, 400);
  }

  // 5. Supabase service-role client initialization
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

  if (!supabaseUrl || !supabaseServiceKey) {
    return jsonResponse({ error: "Internal server error: Backend configuration missing" }, 500);
  }

  const supabaseAdmin = createClient(supabaseUrl, supabaseServiceKey, {
    auth: { persistSession: false },
  });

  try {
    // 6. Verify machine credential against quarantined public.device_credentials table
    const secretHash = await sha256Hex(deviceSecret);

    const { data: creds, error: credError } = await supabaseAdmin
      .from("device_credentials")
      .select("device_id")
      .eq("device_id", deviceId)
      .eq("api_key_hash", secretHash)
      .maybeSingle();

    if (credError || !creds) {
      return jsonResponse({ error: "Unauthorized: Invalid or revoked device credentials" }, 401);
    }

    // 7. Handle Dedicated Boot-Session Registration
    if (body.action === "register_boot") {
      const rawEpoch = body.epoch;
      if (typeof rawEpoch !== "number" || !Number.isInteger(rawEpoch) || rawEpoch <= 0) {
        return jsonResponse({ error: "Invalid epoch: Boot registration requires positive integer epoch" }, 400);
      }

      const firmwareVersion = typeof body.firmware_version === "string" ? body.firmware_version : "2.0.0";
      const bootReason = typeof body.boot_reason === "string" ? body.boot_reason : "POWERON";

      const { data: bootResult, error: bootError } = await supabaseAdmin.rpc(
        "register_device_boot",
        {
          p_device_id: deviceId,
          p_boot_epoch: rawEpoch,
          p_firmware_version: firmwareVersion,
          p_boot_reason: bootReason,
        }
      );

      if (bootError) {
        let bootMsg = "Boot registration rejected";
        if (bootError.message.includes("BOOT_RATE_LIMITED")) {
          bootMsg = "Boot rate limited: Consecutive boot registrations must be separated by at least 5 seconds";
        } else if (bootError.message.includes("BOOT_FLAPPING_DETECTED")) {
          bootMsg = "Boot flapping detected: Excessive reboot transitions in rolling window. Administrative inspection required.";
        } else if (bootError.message.includes("INVALID_EPOCH_TRANSITION")) {
          bootMsg = "Invalid epoch transition: Boot epoch must increment by exactly 1. Use admin recovery if device lost NVS or was replaced.";
        } else if (bootError.message.includes("REPLAY_DETECTED")) {
          bootMsg = "Replay detected: Stale boot epoch has already expired";
        } else if (bootError.message.includes("deactivated")) {
          bootMsg = "Device deactivated or unauthorized";
        }
        return jsonResponse({ error: bootMsg }, 400);
      }

      return jsonResponse(bootResult, 200);
    }

    // 8. Strict schema & type validations for telemetry streaming
    const {
      session_id: sessionId,
      product_id: productId,
      raw_reading: rawReading,
      weight_grams: weightGrams,
      epoch: rawEpoch,
      sequence_number: sequenceNumber,
      is_stable: isStable,
      reading_timestamp: readingTimestamp,
    } = body;

    if (typeof sessionId !== "string" || !UUID_REGEX.test(sessionId)) {
      return jsonResponse({ error: "Invalid session_id: Expected valid UUID" }, 400);
    }

    if (typeof productId !== "string" || !UUID_REGEX.test(productId)) {
      return jsonResponse({ error: "Invalid product_id: Expected valid UUID" }, 400);
    }

    if (typeof rawReading !== "number" || !Number.isFinite(rawReading)) {
      return jsonResponse({ error: "Invalid raw_reading: Expected finite numeric ADC value" }, 400);
    }

    if (
      typeof weightGrams !== "number" ||
      !Number.isFinite(weightGrams) ||
      weightGrams <= 0 ||
      weightGrams > MAX_SCALE_WEIGHT_GRAMS
    ) {
      return jsonResponse(
        { error: "Invalid weight_grams: Must be a positive number within scale capacity" },
        400
      );
    }

    const epoch = rawEpoch !== undefined ? rawEpoch : 1;
    if (
      typeof epoch !== "number" ||
      !Number.isInteger(epoch) ||
      epoch <= 0 ||
      epoch > Number.MAX_SAFE_INTEGER
    ) {
      return jsonResponse({ error: "Invalid epoch: Expected positive integer" }, 400);
    }

    if (
      typeof sequenceNumber !== "number" ||
      !Number.isInteger(sequenceNumber) ||
      sequenceNumber <= 0 ||
      sequenceNumber > Number.MAX_SAFE_INTEGER
    ) {
      return jsonResponse({ error: "Invalid sequence_number: Expected positive integer" }, 400);
    }

    if (typeof isStable !== "boolean") {
      return jsonResponse({ error: "Invalid is_stable: Expected boolean" }, 400);
    }

    if (typeof readingTimestamp !== "string") {
      return jsonResponse({ error: "Invalid reading_timestamp: Expected ISO 8601 string" }, 400);
    }

    const parsedDate = Date.parse(readingTimestamp);
    if (Number.isNaN(parsedDate)) {
      return jsonResponse({ error: "Invalid reading_timestamp: Malformed timestamp format" }, 400);
    }

    // Clock drift assertion (+- 30 seconds max allowable drift)
    const now = Date.now();
    if (Math.abs(now - parsedDate) > 30000) {
      return jsonResponse({ error: "Invalid timestamp: Hardware clock drift exceeds +-30s tolerance" }, 400);
    }

    // 9. Invoke trusted procedure public.record_scale_telemetry()
    const { data: result, error: rpcError } = await supabaseAdmin.rpc(
      "record_scale_telemetry",
      {
        p_device_id: deviceId,
        p_session_id: sessionId,
        p_product_id: productId,
        p_raw_reading: rawReading,
        p_weight_grams: weightGrams,
        p_sequence_number: sequenceNumber,
        p_is_stable: isStable,
        p_reading_timestamp: new Date(parsedDate).toISOString(),
        p_epoch: epoch,
      }
    );

    if (rpcError) {
      // Sanitize database error messages to prevent internal schema leaks
      let clientMessage = "Telemetry verification rejected";
      if (rpcError.message.includes("REPLAY_DETECTED")) {
        clientMessage = "Sequence or epoch replay detected: boot epoch and sequence number must be monotonic";
      } else if (rpcError.message.includes("UNREGISTERED_EPOCH")) {
        clientMessage = "Unregistered epoch: device must register boot session before streaming telemetry";
      } else if (rpcError.message.includes("SESSION_CONSUMED")) {
        clientMessage = "Session ticket already consumed: cannot re-issue ticket for a finalized sale";
      } else if (rpcError.message.includes("SESSION_EXPIRED")) {
        clientMessage = "Session ticket expired: new weighing session required";
      } else if (rpcError.message.includes("CALIBRATION_MISMATCH")) {
        clientMessage = "Calibration check failed: reported weight deviates from load-cell ADC expectation";
      } else if (rpcError.message.includes("Stale or future")) {
        clientMessage = "Telemetry timestamp outside validity window";
      } else if (rpcError.message.includes("deactivated")) {
        clientMessage = "Device deactivated or unauthorized";
      } else if (rpcError.message.includes("Tenant integrity")) {
        clientMessage = "Tenant integrity violation: device and product shop mismatch";
      } else if (rpcError.message.includes("Weight precision")) {
        clientMessage = "Weight precision violation: maximum 3 decimal places allowed";
      } else if (rpcError.message.includes("packaged")) {
        clientMessage = "Product is packaged and does not accept scale weight tickets";
      }

      return jsonResponse({ error: clientMessage }, 400);
    }

    // 9. Structured response handling:
    // When scale is settling, readings are persisted and settling progress is returned.
    // When stability criteria are satisfied, the verified single-use weight ticket is returned.
    if (result && result.status === "SETTLING") {
      return jsonResponse(
        {
          success: true,
          status: "SETTLING",
          session_id: result.session_id,
          epoch: result.epoch,
          sequence_number: result.sequence_number,
          weight_grams: result.weight_grams,
          samples_accumulated: result.consecutive_samples,
          samples_required: result.required_samples,
          variance_grams: result.variance_grams,
          tolerance_grams: result.tolerance_grams,
          message: result.message,
        },
        200
      );
    }

    if (result && result.status === "VERIFIED") {
      return jsonResponse(
        {
          success: true,
          status: "VERIFIED",
          consecutive_samples: result.consecutive_samples,
          ticket: result.ticket,
        },
        200
      );
    }

    return jsonResponse({ success: true, result }, 200);
  } catch {
    return jsonResponse({ error: "Internal server error processing scale telemetry" }, 500);
  }
});
