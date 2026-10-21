// ==============================================================================
// SmartShelf V2 - ESP32 Scale Controller Firmware
// Board: ESP32 Dev Module (WROOM-32)
//
// Core Responsibilities:
// 1. Hardware load-cell interfacing via HX711 24-bit ADC with running median filtering.
// 2. Persistent Boot Epoch tracking in ESP32 Non-Volatile Storage (NVS / Preferences).
//    - Incremented EXACTLY ONCE on boot/reset in setup().
//    - Monotonic sequence numbers in RAM starting at 1 per boot (prevents flash burn-out).
// 3. Authenticated TLS Boot-Session Registration:
//    - Connects via verified TLS with trusted root CA (ISRG Root X1).
//    - Performs authenticated boot registration handshake before streaming telemetry.
//    - Safely detects NVS loss / epoch desynchronization and pauses for admin recovery.
// 4. Autonomous weighing session lifecycle:
//    - Weight threshold (> 5.0g) triggers session generation with unique session_id UUID.
//    - Streams telemetry every 250ms (4Hz) over HTTPS to Supabase Edge Function.
//    - Tracks server response (SETTLING vs VERIFIED).
//    - Halts transmission when ticket is issued; resets session when platform unloads (< 5.0g).
// 5. Replay and gap resilience:
//    - Sequence progression is monotonic.
//    - Network retries and TLS handshake failures abort cleanly without credential leak.
// ==============================================================================

#include <Arduino.h>
#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <HTTPClient.h>
#include <Preferences.h>
#include <HX711.h>
#include <ArduinoJson.h>
#include <time.h>

// ------------------------------------------------------------------------------
// Hardware Pin Definitions & Calibration Constants
// ------------------------------------------------------------------------------
constexpr uint8_t HX711_DOUT_PIN = 19; // DT  -> GPIO 19 (Safe, no strapping hazard)
constexpr uint8_t HX711_SCK_PIN  = 23; // SCK -> GPIO 23 (Safe, no strapping hazard)

// Default load cell physical parameters
constexpr float DEFAULT_CALIBRATION_FACTOR = 1.0f;
constexpr float DEFAULT_TARE_OFFSET        = 0.0f;
constexpr float WEIGHT_THRESHOLD_GRAMS     = 5.0f;     // Minimum threshold to activate session
constexpr float STABILITY_MAX_VARIANCE     = 1.5f;     // Physical variance threshold for local stability flag
constexpr float SENSOR_MAX_CAPACITY_GRAMS  = 100000.0f;// 100kg load cell max rating

// Telemetry interval (250ms = 4Hz streaming rate)
constexpr uint32_t TELEMETRY_INTERVAL_MS = 250;

// ------------------------------------------------------------------------------
// ------------------------------------------------------------------------------
// Production HTTPS Root CA Certificates:
// 1. ISRG Root X1 (Internet Security Research Group / Let's Encrypt)
//    Valid through Mon, 04 Jun 2035 11:04:38 GMT
// 2. GTS Root R4 (Google Trust Services LLC)
//    Valid through Mon, 22 Jun 2036 00:00:00 GMT
// Secures Supabase Cloud endpoints; prevents MITM attacks on device credentials.
// ------------------------------------------------------------------------------
const char* SUPABASE_ROOT_CA =
"-----BEGIN CERTIFICATE-----\n"
"MIIFazCCA1OgAwIBAgIRAIIQz7DSQONZRGPgu2OCiwAwDQYJKoZIhvcNAQELBQAw\n"
"TzELMAkGA1UEBhMCVVMxKTAnBgNVBAoTIEludGVybmV0IFNlY3VyaXR5IFJlc2Vh\n"
"cmNoIEdyb3VwMRUwEwYDVQQDEwxJU1JHIFJvb3QgWDEwHhcNMTUwNjA0MTEwNDM4\n"
"WhcNMzUwNjA0MTEwNDM4WjBPMQswCQYDVQQGEwJVUzEpMCcGA1UEChMgSW50ZXJu\n"
"ZXQgU2VjdXJpdHkgUmVzZWFyY2ggR3JvdXAxFTATBgNVBAMTDElTUkcgUm9vdCBY\n"
"MTCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBAK3oJHP0FDfzm54rVygc\n"
"h77ct984kIxuPOZXoHj3dcKi/vVqbvYATyjb3miGbESTtrFj/RQSa78f0uoxmyF+\n"
"0TM8ukj13Xnfs7j/EvEhmkvBioZxaUpmZmyPfjxwv60pIgbz5MDmgK7iS4+3mX6U\n"
"A5/TR5d8mUgjU+g4rk8Kb4Mu0UlXjIB0ttov0DiNewNwIRt18jA8+o+u3dpjq+sW\n"
"T8KOEUt+zwvo/7V3LvSye0rgTBIlDHCNAymg4VMk7BPZ7hm/ELNKjD+Jo2FR3qyH\n"
"B5T0Y3HsLuJvW5iB4YlcNHlsdu87kGJ55tukmi8mxdAQ4Q7e2RCOFvu396j3x+UC\n"
"B5iPNgiV5+I3lg02dZ77DnKxHZu8A/lJBdiB3QW0KtZB6awBdpUKD9jf1b0SHzUv\n"
"KBds0pjBqAlkd25HN7rOrFleaJ1/ctaJxQZBKT5ZPt0m9STJEadao0xAH0ahmbWn\n"
"OlFuhjuefXKnEgV4We0+UXgVCwOPjdAvBbI+e0ocS3MFEvzG6uBQE3xDk3SzynTn\n"
"jh8BCNAw1FtxNrQHusEwMFxIt4I7mKZ9YIqioymCzLq9gwQbooMDQaHWBfEbwrbw\n"
"qHyGO0aoSCqI3Haadr8faqU9GY/rOPNk3sgrDQoo//fb4hVC1CLQJ13hef4Y53CI\n"
"rU7m2Ys6xt0nUW7/vGT1M0NPAgMBAAGjQjBAMA4GA1UdDwEB/wQEAwIBBjAPBgNV\n"
"HRMBAf8EBTADAQH/MB0GA1UdDgQWBBR5tFnme7bl5AFzgAiIyBpY9umbbjANBgkq\n"
"hkiG9w0BAQsFAAOCAgEAVR9YqbyyqFDQDLHYGmkgJykIrGF1XIpu+ILlaS/V9lZL\n"
"ubhzEFnTIZd+50xx+7LSYK05qAvqFyFWhfFQDlnrzuBZ6brJFe+GnY+EgPbk6ZGQ\n"
"3BebYhtF8GaV0nxvwuo77x/Py9auJ/GpsMiu/X1+mvoiBOv/2X/qkSsisRcOj/KK\n"
"NFtY2PwByVS5uCbMiogziUwthDyC3+6WVwW6LLv3xLfHTjuCvjHIInNzktHCgKQ5\n"
"ORAzI4JMPJ+GslWYHb4phowim57iaztXOoJwTdwJx4nLCgdNbOhdjsnvzqvHu7Ur\n"
"TkXWStAmzOVyyghqpZXjFaH3pO3JLF+l+/+sKAIuvtd7u+Nxe5AW0wdeRlN8NwdC\n"
"jNPElpzVmbUq4JUagEiuTDkHzsxHpFKVK7q4+63SM1N95R1NbdWhscdCb+ZAJzVc\n"
"oyi3B43njTOQ5yOf+1CceWxG1bQVs5ZufpsMljq4Ui0/1lvh+wjChP4kqKOJ2qxq\n"
"4RgqsahDYVvTH9w7jXbyLeiNdd8XM2w9U/t7y0Ff/9yi0GE44Za4rF2LN9d11TPA\n"
"mRGunUHBcnWEvgJBQl9nJEiU0Zsnvgc/ubhPgXRR4Xq37Z0j4r7g1SgEEzwxA57d\n"
"emyPxgcYxn/eR44/KJ4EBs+lVDR3veyJm+kXQ99b21/+jh5Xos1AnX5iItreGCc=\n"
"-----END CERTIFICATE-----\n"
"-----BEGIN CERTIFICATE-----\n"
"MIICCTCCAY6gAwIBAgINAgPlwGjvYxqccpBQUjAKBggqhkjOPQQDAzBHMQswCQYD\n"
"VQQGEwJVUzEiMCAGA1UEChMZR29vZ2xlIFRydXN0IFNlcnZpY2VzIExMQzEUMBIG\n"
"A1UEAxMLR1RTIFJvb3QgUjQwHhcNMTYwNjIyMDAwMDAwWhcNMzYwNjIyMDAwMDAw\n"
"WjBHMQswCQYDVQQGEwJVUzEiMCAGA1UEChMZR29vZ2xlIFRydXN0IFNlcnZpY2Vz\n"
"IExMQzEUMBIGA1UEAxMLR1RTIFJvb3QgUjQwdjAQBgcqhkjOPQIBBgUrgQQAIgNi\n"
"AATzdHOnaItgrkO4NcWBMHtLSZ37wWHO5t5GvWvVYRg1rkDdc/eJkTBa6zzuhXyi\n"
"QHY7qca4R9gq55KRanPpsXI5nymfopjTX15YhmUPoYRlBtHci8nHc8iMai/lxKvR\n"
"HYqjQjBAMA4GA1UdDwEB/wQEAwIBhjAPBgNVHRMBAf8EBTADAQH/MB0GA1UdDgQW\n"
"BBSATNbrdP9JNqPV2Py1PsVq8JQdjDAKBggqhkjOPQQDAwNpADBmAjEA6ED/g94D\n"
"9J+uHXqnLrmvT/aDHQ4thQEd0dlq7A/Cr8deVl5c1RxYIigL9zC2L7F8AjEA8GE8\n"
"p/SgguMh1YQdc4acLa/KNJvxn7kjNuK8YAOdgLOaVsjh4rsUecrNIdSUtUlD\n"
"-----END CERTIFICATE-----\n";

// ------------------------------------------------------------------------------
// Device Provisioning Credentials (Provisioned during authorized enrollment)
// ------------------------------------------------------------------------------
// Optional local configuration override:
// Create "scale_config.h" in firmware/src/ (ignored by Git) to supply local Wi-Fi
// and provisioned device credentials securely without modifying tracked source.
#if __has_include("scale_config.h")
#include "scale_config.h"
#endif

#ifndef WIFI_SSID
#define WIFI_SSID "SmartShelf-Retail-AP"
#endif

#ifndef WIFI_PASSWORD
#define WIFI_PASSWORD "retail_secure_pass"
#endif

// Supabase Scale Telemetry Edge Function URL (Staging Endpoint)
#ifndef TELEMETRY_URL
#define TELEMETRY_URL "https://kmpkrszwonieetbtytao.supabase.co/functions/v1/scale-telemetry"
#endif

// Provisioned Machine-to-Machine Credentials
#ifndef DEVICE_ID
#define DEVICE_ID "00000000-0000-0000-0000-000000000001"
#endif

#ifndef DEVICE_SECRET
#define DEVICE_SECRET "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
#endif

// Enrolled default loose product UUID
#ifndef CURRENT_PRODUCT_ID
#define CURRENT_PRODUCT_ID "00000000-0000-0000-0000-000000000002"
#endif

// ------------------------------------------------------------------------------
// Global State & Peripherals
// ------------------------------------------------------------------------------
HX711 scale;
Preferences preferences;

// Dynamic calibration state (loaded from NVS)
float g_scale_tare_offset        = DEFAULT_TARE_OFFSET;
float g_scale_calibration_factor = DEFAULT_CALIBRATION_FACTOR;
bool  g_scale_hardware_ready     = false;
bool  g_is_calibrated            = false; // Explicit calibration validity flag

uint64_t g_boot_epoch      = 1;
uint64_t g_sequence_number = 1;
bool g_boot_registered     = false;

char g_session_id[37]      = {0};
bool g_session_active      = false;
bool g_ticket_issued       = false;

uint32_t g_last_telemetry_ms = 0;

// Circular buffer for running median filter
constexpr uint8_t FILTER_WINDOW_SIZE = 5;
float g_recent_readings[FILTER_WINDOW_SIZE] = {0.0f};
uint8_t g_filter_index = 0;

// ------------------------------------------------------------------------------
// Calibration & Sensor Validation Helpers
// ------------------------------------------------------------------------------
inline bool isValidCalibrationFactor(float factor) {
    return !isnan(factor) && !isinf(factor) && factor > 0.000001f && factor <= 10.0f;
}

inline bool isValidRawAdc(long raw) {
    return raw > -8388600 && raw < 8388600;
}

void abortActiveWeighingSession(const char* reason) {
    if (g_session_active) {
        Serial.printf("[Session] ABORT: Active session %s terminated (%s).\n", g_session_id, reason);
        g_session_active = false;
        g_ticket_issued  = false;
        g_session_id[0]  = '\0';
    }
}

// ------------------------------------------------------------------------------
// Helper: Cryptographically secure UUID v4 Generator
// ------------------------------------------------------------------------------
void generateUUIDv4(char* output) {
    uint8_t bytes[16];
    for (size_t i = 0; i < 16; i += 4) {
        uint32_t randVal = esp_random();
        memcpy(bytes + i, &randVal, 4);
    }
    // Set UUID v4 variant & version bits
    bytes[6] = (bytes[6] & 0x0F) | 0x40;
    bytes[8] = (bytes[8] & 0x3F) | 0x80;

    snprintf(output, 37,
        "%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x",
        bytes[0], bytes[1], bytes[2], bytes[3],
        bytes[4], bytes[5], bytes[6], bytes[7],
        bytes[8], bytes[9], bytes[10], bytes[11],
        bytes[12], bytes[13], bytes[14], bytes[15]
    );
}

// ------------------------------------------------------------------------------
// Helper: ISO 8601 UTC Timestamp Generator
// ------------------------------------------------------------------------------
void getISOTimestamp(char* buffer, size_t maxLen) {
    time_t now = time(nullptr);
    struct tm timeinfo;
    gmtime_r(&now, &timeinfo);
    strftime(buffer, maxLen, "%Y-%m-%dT%H:%M:%SZ", &timeinfo);
}

// ------------------------------------------------------------------------------
// NVS Calibration Storage Management
// ------------------------------------------------------------------------------
void loadCalibrationFromNVS() {
    if (!preferences.begin("smartshelf", true)) {
        Serial.println("[NVS] Calibration namespace not initialized; device remains UNCALIBRATED.");
        g_is_calibrated = false;
        return;
    }

    // Only treat as calibrated if keys explicitly exist and factor is strictly valid
    if (preferences.isKey("cal_factor") && preferences.isKey("tare_offset")) {
        float offset = preferences.getFloat("tare_offset", 0.0f);
        float factor = preferences.getFloat("cal_factor", 0.0f);
        if (isValidCalibrationFactor(factor) && isValidRawAdc((long)offset)) {
            g_scale_tare_offset = offset;
            g_scale_calibration_factor = factor;
            g_is_calibrated = true;
            Serial.printf("[NVS] Loaded Calibration: Tare Offset = %.1f, Scale Factor = %.6f [CALIBRATED]\n",
                          g_scale_tare_offset, g_scale_calibration_factor);
        } else {
            Serial.printf("[NVS] WARNING: Stored calibration invalid (Offset: %.1f, Factor: %.6f). Device UNCALIBRATED.\n",
                          offset, factor);
            g_is_calibrated = false;
        }
    } else {
        Serial.println("[NVS] NOTICE: No saved calibration in NVS. Device UNCALIBRATED (run TARE and CAL).");
        g_is_calibrated = false;
    }
    preferences.end();
}

bool saveTareOffsetToNVS(float offset) {
    if (!isValidRawAdc((long)offset)) {
        Serial.println("[NVS] ERROR: Cannot save saturated/invalid tare offset to NVS.");
        return false;
    }
    if (!preferences.begin("smartshelf", false)) {
        Serial.println("[NVS] ERROR: Failed to open NVS for writing tare offset.");
        return false;
    }
    preferences.putFloat("tare_offset", offset);
    preferences.end();
    g_scale_tare_offset = offset;
    Serial.printf("[NVS] Tare Offset SAVED to NVS: %.1f\n", offset);
    return true;
}

bool saveCalibrationFactorToNVS(float factor) {
    if (!isValidCalibrationFactor(factor)) {
        Serial.println("[NVS] ERROR: Cannot save invalid calibration factor to NVS.");
        return false;
    }
    if (!preferences.begin("smartshelf", false)) {
        Serial.println("[NVS] ERROR: Failed to open NVS for writing calibration factor.");
        return false;
    }
    preferences.putFloat("cal_factor", factor);
    preferences.end();
    g_scale_calibration_factor = factor;
    Serial.printf("[NVS] Calibration Factor SAVED to NVS: %.6f\n", factor);
    return true;
}

// ------------------------------------------------------------------------------
// Helper: NVS Boot Epoch Initialization (Runs Strictly ONCE in setup)
// ------------------------------------------------------------------------------
void initBootEpoch() {
    // Open NVS namespace "smartshelf" in read-write mode
    if (!preferences.begin("smartshelf", false)) {
        Serial.println("[NVS] CRITICAL: Failed to open NVS storage namespace.");
        g_boot_epoch = 0; // 0 indicates uninitialized / error state
        return;
    }

    // Retrieve previous boot counter; defaults to 0 on brand-new device
    uint64_t previous_epoch = preferences.getULong64("boot_epoch", 0);
    uint64_t next_epoch = previous_epoch + 1;

    size_t written = preferences.putULong64("boot_epoch", next_epoch);
    if (written != sizeof(uint64_t)) {
        Serial.println("[NVS] CRITICAL: Failed to write boot_epoch to NVS! Flash hardware fault.");
        g_boot_epoch = 0;
        preferences.end();
        return;
    }

    // Readback verification to guarantee non-volatile retention
    uint64_t verified = preferences.getULong64("boot_epoch", 0);
    preferences.end();

    if (verified != next_epoch) {
        Serial.println("[NVS] CRITICAL: NVS readback mismatch! Flash corruption detected.");
        g_boot_epoch = 0;
        return;
    }

    g_boot_epoch = next_epoch;
    Serial.printf("[NVS] Boot Epoch initialized and verified: %llu (Persistent in NVS)\n", g_boot_epoch);
}

// ------------------------------------------------------------------------------
// Authenticated Boot-Session Registration Handshake (TLS Verified)
// ------------------------------------------------------------------------------
bool registerBootSession() {
    if (g_boot_epoch == 0) {
        Serial.println("[Boot] HALTED: NVS write failed or unverified. Scale halted to prevent replay desynchronization.");
        return false;
    }

    if (WiFi.status() != WL_CONNECTED) {
        Serial.println("[Boot] Cannot register boot: WiFi not connected.");
        return false;
    }

    // Require valid system clock before initiating TLS handshake
    time_t currentClock = time(nullptr);
    if (currentClock < 1700000000) {
        Serial.printf("[Boot] Deferring registration: clock not synchronized (%ld < 1700000000).\n", (long)currentClock);
        return false;
    }

    WiFiClientSecure secureClient;
    // Strict TLS certificate verification against trusted root CA
    secureClient.setCACert(SUPABASE_ROOT_CA);

    HTTPClient https;
    if (!https.begin(secureClient, TELEMETRY_URL)) {
        Serial.println("[Boot] HTTPS setup failed. Connection aborted.");
        return false;
    }

    https.addHeader("Content-Type", "application/json");
    https.addHeader("x-device-id", DEVICE_ID);
    https.addHeader("x-device-secret", DEVICE_SECRET);

    JsonDocument doc;
    doc["action"]           = "register_boot";
    doc["epoch"]            = g_boot_epoch;
    doc["firmware_version"] = "2.0.0";
    doc["boot_reason"]      = "POWERON";

    String requestBody;
    serializeJson(doc, requestBody);

    Serial.printf("[Boot] Registering boot epoch %llu with server over verified TLS...\n", g_boot_epoch);
    int httpResponseCode = https.POST(requestBody);

    if (httpResponseCode == 200) {
        String resp = https.getString();
        JsonDocument respDoc;
        DeserializationError err = deserializeJson(respDoc, resp);
        if (!err) {
            const char* status = respDoc["status"] | "";
            if (strcmp(status, "BOOT_REGISTERED") == 0) {
                Serial.printf("[Boot] Registration confirmed! Active epoch: %llu\n", g_boot_epoch);
                g_boot_registered = true;
                g_sequence_number = 1;
                https.end();
                return true;
            }
        }
    }

    String errorBody = https.getString();
    Serial.printf("[Boot] Registration rejected (HTTP %d): %s\n", httpResponseCode, errorBody.c_str());

    if (errorBody.indexOf("INVALID_EPOCH_TRANSITION") >= 0 || errorBody.indexOf("REPLAY_DETECTED") >= 0) {
        Serial.println("[Boot] CRITICAL: Epoch desynchronization detected (NVS wipe or replacement).");
        Serial.println("[Boot] Perform administrative recovery on dashboard to assign new valid epoch.");
    }

    https.end();
    return false;
}

// ------------------------------------------------------------------------------
// Median Filter & Stability Computation
// ------------------------------------------------------------------------------
float getFilteredReading(float newReading) {
    g_recent_readings[g_filter_index] = newReading;
    g_filter_index = (g_filter_index + 1) % FILTER_WINDOW_SIZE;

    // Copy and sort to find median
    float sorted[FILTER_WINDOW_SIZE];
    memcpy(sorted, g_recent_readings, sizeof(sorted));
    for (uint8_t i = 0; i < FILTER_WINDOW_SIZE - 1; ++i) {
        for (uint8_t j = i + 1; j < FILTER_WINDOW_SIZE; ++j) {
            if (sorted[i] > sorted[j]) {
                float tmp = sorted[i];
                sorted[i] = sorted[j];
                sorted[j] = tmp;
            }
        }
    }
    return sorted[FILTER_WINDOW_SIZE / 2];
}

bool evaluateStability(float& outVariance) {
    float minVal = g_recent_readings[0];
    float maxVal = g_recent_readings[0];
    for (uint8_t i = 1; i < FILTER_WINDOW_SIZE; ++i) {
        if (g_recent_readings[i] < minVal) minVal = g_recent_readings[i];
        if (g_recent_readings[i] > maxVal) maxVal = g_recent_readings[i];
    }
    outVariance = maxVal - minVal;
    return (outVariance <= STABILITY_MAX_VARIANCE);
}

// ------------------------------------------------------------------------------
// Telemetry Transmission to Supabase Edge Function (Strict Verified TLS)
// ------------------------------------------------------------------------------
void sendTelemetrySample(float rawAdc, float weightGrams, bool isStable) {
    if (g_boot_epoch == 0 || !g_boot_registered) {
        Serial.println("[Telemetry] Blocked: Invalid boot epoch or unregistered boot session.");
        return;
    }

    if (WiFi.status() != WL_CONNECTED) {
        Serial.println("[WiFi] Telemetry skipped: No network connection.");
        return;
    }

    // Require valid system clock before streaming telemetry over TLS
    time_t currentClock = time(nullptr);
    if (currentClock < 1700000000) {
        Serial.printf("[Telemetry] Skipped: clock not synchronized (%ld < 1700000000).\n", (long)currentClock);
        return;
    }

    WiFiClientSecure secureClient;
    // Proper HTTPS certificate verification:
    // Never transmit device credentials over an unverified connection.
    secureClient.setCACert(SUPABASE_ROOT_CA);

    HTTPClient https;
    if (!https.begin(secureClient, TELEMETRY_URL)) {
        Serial.println("[HTTPS] TLS setup failed. Connection aborted.");
        return;
    }

    https.addHeader("Content-Type", "application/json");
    https.addHeader("x-device-id", DEVICE_ID);
    https.addHeader("x-device-secret", DEVICE_SECRET);

    // Format ISO timestamp
    char timestampBuf[30];
    getISOTimestamp(timestampBuf, sizeof(timestampBuf));

    // Construct telemetry JSON payload
    JsonDocument doc;
    doc["session_id"]        = g_session_id;
    doc["product_id"]        = CURRENT_PRODUCT_ID;
    doc["raw_reading"]       = rawAdc;
    doc["weight_grams"]      = serialized(String(weightGrams, 3)); // Round to 3 decimal places
    doc["epoch"]             = g_boot_epoch;
    doc["sequence_number"]   = g_sequence_number;
    doc["is_stable"]         = isStable;
    doc["reading_timestamp"] = timestampBuf;

    String requestBody;
    serializeJson(doc, requestBody);

    // Advance sequence number in RAM for next reading
    uint64_t currentSeq = g_sequence_number++;

    Serial.printf("[Telemetry] POST Epoch:%llu Seq:%llu Weight:%.3fg Stable:%s\n",
                  g_boot_epoch, currentSeq, weightGrams, isStable ? "true" : "false");

    int httpResponseCode = https.POST(requestBody);

    if (httpResponseCode > 0) {
        String responseText = https.getString();
        JsonDocument respDoc;
        DeserializationError error = deserializeJson(respDoc, responseText);

        if (!error) {
            const char* status = respDoc["status"] | "";
            if (strcmp(status, "SETTLING") == 0) {
                int samples = respDoc["samples_accumulated"] | 0;
                int required = respDoc["samples_required"] | 3;
                Serial.printf("[Scale] Settling... (%d/%d samples accumulated)\n", samples, required);
            } else if (strcmp(status, "VERIFIED") == 0) {
                const char* ticketId = respDoc["ticket"]["ticket_id"] | "N/A";
                float weightKg = respDoc["ticket"]["weight_kg"] | 0.0f;
                Serial.printf("\n==================================================\n");
                Serial.printf("[Scale] *** WEIGHT VERIFIED ***\n");
                Serial.printf("  Ticket ID : %s\n", ticketId);
                Serial.printf("  Weight    : %.3f kg\n", weightKg);
                Serial.printf("==================================================\n\n");
                g_ticket_issued = true; // Halt streaming until scale is unloaded
            }
        } else {
            Serial.printf("[HTTP] JSON parse error: %s\n", error.c_str());
        }
    } else {
        Serial.printf("[HTTPS] TLS/HTTP failed, error code: %d (%s)\n",
                      httpResponseCode, https.errorToString(httpResponseCode).c_str());
    }

    https.end();
}

// ------------------------------------------------------------------------------
// Interactive Serial Monitor Commands (Tare, Calibrate, Diagnostics)
// ------------------------------------------------------------------------------
void handleSerialCommands() {
    if (!Serial.available()) return;
    String cmd = Serial.readStringUntil('\n');
    cmd.trim();
    if (cmd.length() == 0) return;

    if (cmd.equalsIgnoreCase("TARE") || cmd.equalsIgnoreCase("t")) {
        Serial.println("\n[Command] Initiating Zero-Platform Tare...");
        if (!scale.wait_ready_timeout(1000)) {
            Serial.println("[Command] ERROR: Load cell not responding! Cannot tare disconnected sensor.");
            return;
        }
        long sum = 0;
        int validCount = 0;
        for (int i = 0; i < 10; i++) {
            if (scale.wait_ready_timeout(200)) {
                long raw = scale.read();
                if (isValidRawAdc(raw)) {
                    sum += raw;
                    validCount++;
                } else {
                    Serial.printf("[Command] WARNING: Discarding saturated/invalid sample (%ld) during tare.\n", raw);
                }
            }
            delay(50);
        }
        if (validCount >= 5) {
            float newOffset = (float)sum / validCount;
            if (saveTareOffsetToNVS(newOffset)) {
                scale.set_offset(newOffset);
                Serial.printf("[Command] SUCCESS: Tare complete. Zero Offset = %.1f (saved to NVS)\n", newOffset);
                if (isValidCalibrationFactor(g_scale_calibration_factor)) {
                    g_is_calibrated = true;
                }
            }
        } else {
            Serial.printf("[Command] ERROR: Insufficient valid samples for tare (%d/10). Platform unstable or sensor faulty.\n",
                          validCount);
        }
    } else if (cmd.startsWith("CAL") || cmd.startsWith("cal") || cmd.startsWith("c ") || cmd.startsWith("C ")) {
        int spaceIdx = cmd.indexOf(' ');
        if (spaceIdx < 0) {
            Serial.println("[Command] Usage: CAL <known_weight_in_grams> (e.g. CAL 500 or CAL 1000)");
            return;
        }
        float targetGrams = cmd.substring(spaceIdx + 1).toFloat();
        if (isnan(targetGrams) || isinf(targetGrams) || targetGrams <= 0.0f) {
            Serial.println("[Command] ERROR: Calibration weight must be a positive finite number.");
            return;
        }
        Serial.printf("\n[Command] Calibrating with certified mass: %.2fg...\n", targetGrams);
        if (!scale.wait_ready_timeout(1000)) {
            Serial.println("[Command] ERROR: Load cell not responding! Cannot calibrate disconnected sensor.");
            return;
        }
        long sum = 0;
        int validCount = 0;
        for (int i = 0; i < 10; i++) {
            if (scale.wait_ready_timeout(200)) {
                long raw = scale.read();
                if (isValidRawAdc(raw)) {
                    sum += raw;
                    validCount++;
                } else {
                    Serial.printf("[Command] WARNING: Discarding saturated/invalid sample (%ld) during cal.\n", raw);
                }
            }
            delay(50);
        }
        if (validCount >= 5) {
            float avgRaw = (float)sum / validCount;
            float rawDiff = avgRaw - g_scale_tare_offset;
            if (rawDiff <= 100.0f) {
                Serial.printf("[Command] ERROR: Insufficient or non-positive raw delta (rawDiff = %.1f, min required > 100.0). Check weight placement and polarity.\n",
                              rawDiff);
                return;
            }
            float newFactor = targetGrams / rawDiff;
            if (!isValidCalibrationFactor(newFactor)) {
                Serial.printf("[Command] ERROR: Computed calibration factor (%.6f) is out of realistic physical bounds (0.000001 to 10.0).\n",
                              newFactor);
                return;
            }
            if (saveCalibrationFactorToNVS(newFactor)) {
                scale.set_scale(newFactor);
                g_is_calibrated = true;
                Serial.printf("[Command] SUCCESS: Calibration complete! Scale Factor = %.6f [CALIBRATED]\n", newFactor);
            }
        } else {
            Serial.printf("[Command] ERROR: Insufficient valid samples for calibration (%d/10). Calibration aborted.\n",
                          validCount);
        }
    } else if (cmd.equalsIgnoreCase("RAW") || cmd.equalsIgnoreCase("r")) {
        Serial.println("\n[Command] Reading 10 instantaneous raw ADC values:");
        for (int i = 0; i < 10; i++) {
            if (scale.wait_ready_timeout(200)) {
                long r = scale.read();
                if (isValidRawAdc(r)) {
                    float g = (r - g_scale_tare_offset) * g_scale_calibration_factor;
                    Serial.printf("  Sample %02d: Raw ADC = %ld | Calculated = %.2fg (%s)\n",
                                  i + 1, r, g, g_is_calibrated ? "calibrated" : "UNCALIBRATED");
                } else {
                    Serial.printf("  Sample %02d: SATURATED / FAULT (%ld)\n", i + 1, r);
                }
            } else {
                Serial.printf("  Sample %02d: TIMEOUT (HX711 not responding)\n", i + 1);
            }
            delay(150);
        }
    } else if (cmd.equalsIgnoreCase("STATUS") || cmd.equalsIgnoreCase("s")) {
        Serial.println("\n========== SmartShelf V2 Scale Status ==========");
        Serial.printf("  GPIO DOUT (DT)   : GPIO %d\n", HX711_DOUT_PIN);
        Serial.printf("  GPIO SCK (CLK)   : GPIO %d\n", HX711_SCK_PIN);
        Serial.printf("  Hardware State   : %s\n", g_scale_hardware_ready ? "ONLINE (Responding)" : "FAULT / DISCONNECTED");
        Serial.printf("  Calibration      : %s\n", g_is_calibrated ? "CALIBRATED (Valid)" : "UNCALIBRATED (Calibration Required)");
        Serial.printf("  Tare Offset      : %.1f\n", g_scale_tare_offset);
        Serial.printf("  Scale Factor     : %.6f\n", g_scale_calibration_factor);
        Serial.printf("  Boot Epoch       : %llu (Registered: %s)\n", g_boot_epoch, g_boot_registered ? "YES" : "NO");
        Serial.printf("  Wi-Fi Status     : %s\n", WiFi.status() == WL_CONNECTED ? "CONNECTED" : "DISCONNECTED");
        if (WiFi.status() == WL_CONNECTED) {
            Serial.printf("  IP Address       : %s\n", WiFi.localIP().toString().c_str());
        }
        Serial.printf("  Telemetry Target : %s\n", TELEMETRY_URL);
        Serial.printf("  Enrolled Device  : %s\n", DEVICE_ID);
        Serial.println("=================================================\n");
    } else if (cmd.equalsIgnoreCase("RESET_EPOCH CONFIRM")) {
        Serial.println("\n[Command] Processing targeted NVS boot_epoch reset...");
        if (!preferences.begin("smartshelf", false)) {
            Serial.println("[Command] ERROR: Failed to open 'smartshelf' NVS namespace.");
            return;
        }
        size_t written = preferences.putULong64("boot_epoch", 0);
        uint64_t verified = preferences.getULong64("boot_epoch", 999);
        preferences.end();
        if (written == sizeof(uint64_t) && verified == 0) {
            Serial.println("[Command] SUCCESS: NVS boot_epoch reset to 0 (verified: 0). Next reboot will start at epoch 1.");
        } else {
            Serial.printf("[Command] ERROR: Failed to reset boot_epoch (written: %u, readback: %llu).\n", (unsigned int)written, verified);
        }
    } else if (cmd.equalsIgnoreCase("RESET_EPOCH")) {
        Serial.println("\n[Command] WARNING: RESET_EPOCH requires explicit confirmation. Send 'RESET_EPOCH CONFIRM' to proceed.");
    } else if (cmd.equalsIgnoreCase("REBOOT")) {
        Serial.println("\n[Command] Rebooting ESP32...");
        delay(200);
        ESP.restart();
    } else if (cmd.equalsIgnoreCase("HELP") || cmd.equalsIgnoreCase("h") || cmd.equalsIgnoreCase("?")) {
        Serial.println("\nAvailable Serial Commands:");
        Serial.println("  TARE, t        - Zero empty platform and save offset to NVS");
        Serial.println("  CAL <g>, c <g> - Calibrate with known weight in grams (e.g. CAL 500)");
        Serial.println("  RAW, r         - Stream 10 raw ADC samples for wiring verification");
        Serial.println("  STATUS, s      - Print current scale configuration and health");
        Serial.println("  RESET_EPOCH CONFIRM - Reset NVS boot_epoch to 0 for initial registration");
        Serial.println("  REBOOT         - Reboot the ESP32 controller");
        Serial.println("  HELP, h        - Print this command menu");
    }
}

// ------------------------------------------------------------------------------
// Setup Routine
// ------------------------------------------------------------------------------
void setup() {
    Serial.begin(115200);
    delay(500);

    Serial.println("\n==================================================");
    Serial.println("  SmartShelf V2 - Scale Controller (HX711/ESP32)");
    Serial.println("  Hardware Wiring: DT -> GPIO 19, SCK -> GPIO 23");
    Serial.println("==================================================");

    // Startup configuration checks
    if (strcmp(DEVICE_ID, "00000000-0000-0000-0000-000000000001") == 0) {
        Serial.println("[Config] NOTICE: Using placeholder DEVICE_ID. Update after device enrollment.");
    }
    if (strcmp(WIFI_SSID, "SmartShelf-Retail-AP") == 0) {
        Serial.println("[Config] NOTICE: Using placeholder WIFI_SSID.");
    }

    // 1. Initialize persistent boot epoch counter from NVS
    initBootEpoch();

    // 2. Load stored calibration parameters from NVS
    loadCalibrationFromNVS();

    // 3. Initialize HX711 Load Cell on safe GPIO pins 19 & 23
    scale.begin(HX711_DOUT_PIN, HX711_SCK_PIN);
    scale.set_scale(g_scale_calibration_factor);
    scale.set_offset(g_scale_tare_offset);

    Serial.printf("[Scale] Probing HX711 on DOUT:%d, SCK:%d...\n", HX711_DOUT_PIN, HX711_SCK_PIN);
    if (scale.wait_ready_timeout(1000)) {
        long raw = scale.read();
        // Check for saturation (indicates broken wire or disconnected amplifier)
        if (!isValidRawAdc(raw)) {
            Serial.printf("[Scale] FAULT: ADC Saturated (%ld). Load cell is disconnected or damaged.\n", raw);
            g_scale_hardware_ready = false;
        } else {
            Serial.printf("[Scale] SUCCESS: HX711 responding! Raw ADC reading: %ld\n", raw);
            g_scale_hardware_ready = true;
        }
    } else {
        Serial.printf("[Scale] WARNING: HX711 not ready on DT:%d, SCK:%d (timeout). Connect load cell to proceed.\n",
                      HX711_DOUT_PIN, HX711_SCK_PIN);
        g_scale_hardware_ready = false;
    }

    // 4. Connect to Wi-Fi
    Serial.printf("[WiFi] Connecting to %s", WIFI_SSID);
    WiFi.mode(WIFI_STA);
    WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
    uint32_t startAttempt = millis();
    while (WiFi.status() != WL_CONNECTED && millis() - startAttempt < 15000) {
        delay(500);
        Serial.print(".");
    }

    if (WiFi.status() == WL_CONNECTED) {
        Serial.printf("\n[WiFi] Connected! IP: %s\n", WiFi.localIP().toString().c_str());
        configTime(0, 0, "pool.ntp.org", "time.google.com");
        Serial.println("[NTP] Synchronizing network time...");
        time_t now = time(nullptr);
        uint8_t ntpWait = 0;
        while (now < 1700000000 && ntpWait < 10) {
            delay(500);
            now = time(nullptr);
            ntpWait++;
        }
        if (now >= 1700000000) {
            Serial.printf("[NTP] Time synchronized successfully: %ld (UTC)\n", (long)now);
            // 5. Perform authenticated boot registration over verified TLS
            registerBootSession();
        } else {
            Serial.printf("[NTP] Synchronization in progress (current epoch: %ld < 1700000000). Deferring registration.\n", (long)now);
        }
    } else {
        Serial.println("\n[WiFi] Connection timeout. Operating in offline buffer mode.");
    }

    Serial.printf("[System] Ready. Epoch: %llu, Registered: %s, Sensor Ready: %s, Calibrated: %s\n",
                  g_boot_epoch, g_boot_registered ? "YES" : "NO",
                  g_scale_hardware_ready ? "YES" : "NO (Awaiting hardware connection)",
                  g_is_calibrated ? "YES" : "NO (Calibration required before weighing)");
}

// ------------------------------------------------------------------------------
// Main Loop
// ------------------------------------------------------------------------------
void loop() {
    uint32_t now = millis();

    // Process interactive serial commands (tare, cal, status, raw)
    handleSerialCommands();

    // Maintain Wi-Fi connection
    if (WiFi.status() != WL_CONNECTED) {
        static uint32_t lastReconnectAttempt = 0;
        if (now - lastReconnectAttempt > 10000) {
            lastReconnectAttempt = now;
            Serial.println("[WiFi] Reconnecting...");
            WiFi.reconnect();
        }
        vTaskDelay(pdMS_TO_TICKS(50));
        return;
    }

    // Ensure NTP service is active if Wi-Fi connected or reconnected
    static bool s_ntp_active = false;
    if (!s_ntp_active) {
        configTime(0, 0, "pool.ntp.org", "time.google.com");
        s_ntp_active = true;
    }

    // Defer TLS operations until clock is synchronized
    time_t current_time = time(nullptr);
    if (current_time < 1700000000) {
        static uint32_t lastNtpPendingLog = 0;
        if (now - lastNtpPendingLog > 10000) {
            lastNtpPendingLog = now;
            Serial.printf("[NTP] Awaiting valid network time (current: %ld, required >= 1700000000)...\n", (long)current_time);
        }
        vTaskDelay(pdMS_TO_TICKS(50));
        return;
    } else {
        static bool s_ntp_valid_logged = false;
        if (!s_ntp_valid_logged) {
            s_ntp_valid_logged = true;
            Serial.printf("[NTP] Clock verified: %ld (UTC). Ready for secure TLS.\n", (long)current_time);
        }
    }

    // Attempt boot registration if pending
    if (!g_boot_registered) {
        static uint32_t lastBootAttempt = 0;
        if (now - lastBootAttempt > 5000) {
            lastBootAttempt = now;
            registerBootSession();
        }
    }

    // Periodic sensor connection check (every 2 seconds)
    // Requirement 8: Require fresh valid raw ADC reading before re-enabling sensor
    static uint32_t lastHealthCheck = 0;
    if (now - lastHealthCheck > 2000) {
        lastHealthCheck = now;
        if (scale.is_ready()) {
            long testRaw = scale.read();
            if (isValidRawAdc(testRaw)) {
                if (!g_scale_hardware_ready) {
                    g_scale_hardware_ready = true;
                    Serial.printf("[Scale] Load cell ADC connection restored (Raw: %ld).\n", testRaw);
                }
            } else {
                if (g_scale_hardware_ready) {
                    g_scale_hardware_ready = false;
                    abortActiveWeighingSession("ADC saturation during periodic health check");
                    Serial.printf("[Scale] FAULT: ADC Saturated (%ld) during health check. Weighing suspended.\n", testRaw);
                }
            }
        } else {
            if (g_scale_hardware_ready) {
                g_scale_hardware_ready = false;
                abortActiveWeighingSession("Sensor disconnected / unresponsive");
                Serial.println("[Scale] FAULT: Load cell disconnected or unresponsive. Weighing suspended.");
            }
        }
    }

    // Only process weighing session if load cell hardware is responding
    if (g_scale_hardware_ready && scale.is_ready()) {
        long raw = scale.read();

        // Requirement 6 & 7: Check sensor readings BEFORE converting to grams; abort immediately on fault
        if (!isValidRawAdc(raw)) {
            static uint32_t lastSatAlert = 0;
            if (now - lastSatAlert > 3000) {
                lastSatAlert = now;
                Serial.printf("[Scale] FAULT: ADC Saturated (%ld). Check load cell wiring.\n", raw);
            }
            g_scale_hardware_ready = false;
            abortActiveWeighingSession("ADC saturation detected during weighing");
        } else if (!g_is_calibrated) {
            // Requirement 2: Do NOT start weighing sessions or transmit telemetry if uncalibrated
            static uint32_t lastUncalAlert = 0;
            if (now - lastUncalAlert > 10000) {
                lastUncalAlert = now;
                Serial.println("[Scale] NOTICE: Device is UNCALIBRATED. Weighing & telemetry blocked. Run TARE and CAL in Serial Monitor.");
            }
        } else {
            float rawAdc = (float)raw;
            float calculatedGrams = (rawAdc - g_scale_tare_offset) * g_scale_calibration_factor;
            if (calculatedGrams < 0.0f) calculatedGrams = 0.0f;
            if (calculatedGrams > SENSOR_MAX_CAPACITY_GRAMS) calculatedGrams = SENSOR_MAX_CAPACITY_GRAMS;

            float filteredGrams = getFilteredReading(calculatedGrams);
            float variance = 0.0f;
            bool isLocallyStable = evaluateStability(variance);

            // Weighing session activation: Weight detected on platform
            if (filteredGrams >= WEIGHT_THRESHOLD_GRAMS) {
                if (!g_session_active) {
                    generateUUIDv4(g_session_id);
                    g_session_active = true;
                    g_ticket_issued  = false;
                    Serial.printf("\n[Session] New weighing session started: %s\n", g_session_id);
                }

                if (!g_ticket_issued && (now - g_last_telemetry_ms >= TELEMETRY_INTERVAL_MS)) {
                    g_last_telemetry_ms = now;
                    sendTelemetrySample(rawAdc, filteredGrams, isLocallyStable);
                }
            } else {
                if (g_session_active) {
                    Serial.printf("[Session] Platform unloaded (< %.1fg). Weighing session %s closed.\n",
                                  WEIGHT_THRESHOLD_GRAMS, g_session_id);
                    g_session_active = false;
                    g_ticket_issued  = false;
                    g_session_id[0]  = '\0';
                }
            }
        }
    }

    vTaskDelay(pdMS_TO_TICKS(10));
}
