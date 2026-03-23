#ifndef CONFIG_H
#define CONFIG_H

#include <Arduino.h>

// --- LoRa Configuration (Heltec V3) ---
#define LORA_NSS    8
#define LORA_DIO1   14
#define LORA_NRST   12
#define LORA_BUSY   13
#define LORA_FREQ   865.0 // Frequency (MHz) 

// --- GPS Configuration ---
// Make sure to cross reference with your specific wiring!
// Common pins on Heltec V3 headers: 
// RX Pin (Connect to GPS TX): 48
// TX Pin (Connect to GPS RX): 47
#define GPS_RX_PIN  48 
#define GPS_TX_PIN  47 
#define GPS_BAUD    9600

// --- BLE Configuration ---
#define BLE_DEVICE_NAME "RiderLink"
#define BLE_SERVICE_UUID "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
#define BLE_RX_UUID "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"
#define BLE_TX_UUID "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"

// --- Protocol Configuration ---
#define PACKET_TYPE_LOCATION 0x01
#define PACKET_TYPE_MESSAGE  0x02
#define PACKET_TYPE_ALERT    0x03

#endif
