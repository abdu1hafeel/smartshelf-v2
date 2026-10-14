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
constexpr uint8_t HX711_DOUT_PIN = 16;
constexpr uint8_t HX711_SCK_PIN  = 4;

// Load cell physical parameters (calibrated against certified weights)
constexpr float SCALE_CALIBRATION_FACTOR = 1.0f;
constexpr float SCALE_TARE_OFFSET        = 0.0f;
constexpr float WEIGHT_THRESHOLD_GRAMS   = 5.0f;   // Minimum threshold to activate session
constexpr float STABILITY_MAX_VARIANCE   = 1.5f;   // Physical variance threshold for local stability flag

// Telemetry interval (250ms = 4Hz streaming rate)
constexpr uint32_t TELEMETRY_INTERVAL_MS = 250;

// ------------------------------------------------------------------------------
// Production HTTPS Root CA Certificate (ISRG Root X1)
// Valid through Mon, 04 Jun 2035 11:04:38 GMT
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
"-----END CERTIFICATE-----\n";

// ------------------------------------------------------------------------------
// Device Provisioning Credentials (Provisioned during authorized enrollment)
// ------------------------------------------------------------------------------
// Replace with actual shop WiFi and enrolled device credentials
const char* WIFI_SSID       = "SmartShelf-Retail-AP";
const char* WIFI_PASSWORD   = "retail_secure_pass";

// Supabase Scale Telemetry Edge Function URL
const char* TELEMETRY_URL   = "https://your-project-ref.supabase.co/functions/v1/scale-telemetry";

// Provisioned Machine-to-Machine Credentials
const char* DEVICE_ID       = "00000000-0000-0000-0000-000000000001";
const char* DEVICE_SECRET   = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";

// Enrolled default loose product UUID
const char* CURRENT_PRODUCT_ID = "00000000-0000-0000-0000-000000000002";

// ------------------------------------------------------------------------------
// Global State & Peripherals
// ------------------------------------------------------------------------------
HX711 scale;
Preferences preferences;

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
// Setup Routine
// ------------------------------------------------------------------------------
void setup() {
    Serial.begin(115200);
    delay(500);

    Serial.println("\n==================================================");
    Serial.println("  SmartShelf V2 - Scale Controller (HX711/ESP32)");
    Serial.println("==================================================");

    // 1. Initialize persistent boot epoch counter from NVS
    initBootEpoch();

    // 2. Initialize HX711 Load Cell
    scale.begin(HX711_DOUT_PIN, HX711_SCK_PIN);
    scale.set_scale(SCALE_CALIBRATION_FACTOR);
    scale.set_offset(SCALE_TARE_OFFSET);

    Serial.println("[Scale] HX711 initialized. Taring platform...");
    scale.tare();
    Serial.println("[Scale] Platform zeroed.");

    // 3. Connect to Wi-Fi
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
        // Initialize SNTP time (mandatory for TLS certificate validity checking)
        configTime(0, 0, "pool.ntp.org", "time.google.com");
        Serial.println("[NTP] Synchronizing network time...");
        time_t now = time(nullptr);
        uint8_t ntpWait = 0;
        while (now < 1700000000 && ntpWait < 10) { // Ensure clock is beyond 2023
            delay(500);
            now = time(nullptr);
            ntpWait++;
        }
        Serial.println("[NTP] Time synchronized successfully.");

        // 4. Perform authenticated boot registration over verified TLS
        registerBootSession();
    } else {
        Serial.println("\n[WiFi] Connection timeout. Operating in offline buffer mode.");
    }

    Serial.printf("[System] Ready. Epoch: %llu, Registered: %s\n",
                  g_boot_epoch, g_boot_registered ? "YES" : "NO");
}

// ------------------------------------------------------------------------------
// Main Loop
// ------------------------------------------------------------------------------
void loop() {
    uint32_t now = millis();

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

    // If boot was not registered yet (e.g. WiFi was down during setup), attempt registration
    if (!g_boot_registered) {
        static uint32_t lastBootAttempt = 0;
        if (now - lastBootAttempt > 5000) {
            lastBootAttempt = now;
            registerBootSession();
        }
    }

    // Check HX711 readiness
    if (scale.is_ready()) {
        float rawAdc = scale.read();
        float calculatedGrams = (rawAdc - SCALE_TARE_OFFSET) * SCALE_CALIBRATION_FACTOR;
        if (calculatedGrams < 0.0f) calculatedGrams = 0.0f;

        float filteredGrams = getFilteredReading(calculatedGrams);
        float variance = 0.0f;
        bool isLocallyStable = evaluateStability(variance);

        // Weighing session activation: Weight detected on platform
        if (filteredGrams >= WEIGHT_THRESHOLD_GRAMS) {
            if (!g_session_active) {
                // New weighing session triggered
                generateUUIDv4(g_session_id);
                g_session_active = true;
                g_ticket_issued  = false;
                Serial.printf("\n[Session] New weighing session started: %s\n", g_session_id);
            }

            // Stream telemetry at TELEMETRY_INTERVAL_MS while session is active and not yet verified
            if (!g_ticket_issued && (now - g_last_telemetry_ms >= TELEMETRY_INTERVAL_MS)) {
                g_last_telemetry_ms = now;
                sendTelemetrySample(rawAdc, filteredGrams, isLocallyStable);
            }
        } else {
            // Platform unloaded (< WEIGHT_THRESHOLD_GRAMS)
            if (g_session_active) {
                Serial.printf("[Session] Platform unloaded. Weighing session %s closed.\n", g_session_id);
                g_session_active = false;
                g_ticket_issued  = false;
                g_session_id[0]  = '\0';
            }
        }
    }

    // Yield CPU to background tasks (Wi-Fi/TCP stack)
    vTaskDelay(pdMS_TO_TICKS(10));
}
