// ==============================================================================
// SmartShelf V2 - ESP32 Scale Local Hardware Configuration (Template)
// ==============================================================================
// Copy this file to "scale_config.h" in the same directory (firmware/src/).
// "scale_config.h" is ignored by git to prevent committing secrets to version control.
// ==============================================================================

#pragma once

// 1. Wi-Fi Access Point Credentials
#define WIFI_SSID       "Your-Shop-WiFi-SSID"
#define WIFI_PASSWORD   "Your-Shop-WiFi-Password"

// 2. Supabase Scale Telemetry Edge Function URL
// Staging: "https://kmpkrszwonieetbtytao.supabase.co/functions/v1/scale-telemetry"
#define TELEMETRY_URL   "https://kmpkrszwonieetbtytao.supabase.co/functions/v1/scale-telemetry"

// 3. Machine-to-Machine Credentials (Obtained from Admin Website > Scale Devices > Enroll)
// Example: "00000000-0000-0000-0000-000000000001"
#define DEVICE_ID       "YOUR-ENROLLED-DEVICE-UUID"

// 64-character hexadecimal API secret (Displayed ONCE during device enrollment)
#define DEVICE_SECRET   "YOUR-64-HEX-DEVICE-SECRET"

// 4. Default Loose Produce Product UUID (Enrolled in active shop inventory)
#define CURRENT_PRODUCT_ID "YOUR-LOOSE-PRODUCT-UUID"
