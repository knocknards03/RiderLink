#include <Arduino.h>
#include <RadioLib.h>
#include <TinyGPS++.h>
#include <NimBLEDevice.h>
#include "config.h"
#include "PacketManager.h"

// --- Globals ---
SX1262 radio = new Module(LORA_NSS, LORA_DIO1, LORA_NRST, LORA_BUSY);
TinyGPSPlus gps;
HardwareSerial gpsSerial(1);
NimBLEServer *pServer;
NimBLECharacteristic *pTxCharacteristic;
NimBLECharacteristic *pRxCharacteristic;

bool deviceConnected = false;
bool oldDeviceConnected = false;
unsigned long lastGpsReadTime = 0;
const unsigned long gpsInterval = 10000; // 10 seconds for testing

// --- Interrupt Flag ---
volatile bool receivedFlag = false;
void IRAM_ATTR setFlag() {
  receivedFlag = true;
}

// --- BLE Callbacks ---
class MyServerCallbacks : public NimBLEServerCallbacks {
    void onConnect(NimBLEServer* pServer) {
        deviceConnected = true;
        Serial.println("Device connected");
    };
    void onDisconnect(NimBLEServer* pServer) {
        deviceConnected = false;
        Serial.println("Device disconnected");
    }
};

class MyCallbacks : public NimBLECharacteristicCallbacks {
    void onWrite(NimBLECharacteristic *pCharacteristic) {
        std::string rxValue = pCharacteristic->getValue();
        if (rxValue.length() > 0) {
            Serial.printf("Received Value: %s\n", rxValue.c_str());

            // Create Packet for text message
            RiderPacket packet;
            packet.type = PACKET_TYPE_MESSAGE;
            packet.senderId = PacketManager::getDeviceId();
            packet.payload.assign(rxValue.begin(), rxValue.end());

            std::vector<uint8_t> data = PacketManager::serialize(packet);
            
            // Transmit
            int state = radio.startTransmit(data.data(), data.size());
             if (state == RADIOLIB_ERR_NONE) {
                Serial.println(F("[SX1262] Transmission started!"));
            } else {
                Serial.print(F("[SX1262] Transmission failed, code "));
                Serial.println(state);
            }
        }
    }
};

void setup() {
  Serial.begin(115200);
  delay(1000); // Allow hardware serial port to stabilize
  
  // 1. Initialize Long Range (LoRa) Radio
  Serial.print(F("[SX1262] Initializing ... "));
  // Configure explicit pinout matching the Heltec V3 schematic
  int state = radio.begin(LORA_FREQ, 125.0, 9, 7, 10, 22);
  if (state == RADIOLIB_ERR_NONE) {
    Serial.println(F("success!"));
  } else {
    Serial.print(F("failed, code "));
    Serial.println(state);
    while (true); // Hard halt if antenna initialization fails
  }

  // Bind an Interrupt Service Routine (ISR) to trigger the moment a packet hits the antenna
  radio.setPacketReceivedAction(setFlag);
  
  // Activate continuous background listening
  state = radio.startReceive();
  if (state == RADIOLIB_ERR_NONE) {
    Serial.println(F("[SX1262] Listening..."));
  } else {
    Serial.print(F("[SX1262] Failed to start receive, code "));
    Serial.println(state);
  }

  // 2. Initialize GPS module 
  // HardwareSerial(1) is rerouted through software multiplexing to map to specific GPIO pins
  gpsSerial.begin(GPS_BAUD, SERIAL_8N1, GPS_RX_PIN, GPS_TX_PIN);

  // 3. Initialize Bluetooth Low Energy (BLE)
  NimBLEDevice::init(BLE_DEVICE_NAME);
  pServer = NimBLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());
  NimBLEService *pService = pServer->createService(BLE_SERVICE_UUID);
  
  // Establish TX Endpoint (Hardware broadcasting TO the mobile phone)
  pTxCharacteristic = pService->createCharacteristic(
                                         BLE_TX_UUID,
                                         NIMBLE_PROPERTY::NOTIFY
                                       );
                                       
  // Establish RX Endpoint (Hardware listening FROM the mobile phone)
  pRxCharacteristic = pService->createCharacteristic(
                                               BLE_RX_UUID,
                                               NIMBLE_PROPERTY::WRITE
                                             );
  pRxCharacteristic->setCallbacks(new MyCallbacks());
  
  // Start broadcasting the bluetooth pairing signal so the Flutter app can find it
  pService->start();
  NimBLEAdvertising *pAdvertising = NimBLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(BLE_SERVICE_UUID);
  pAdvertising->setScanResponse(true);
  pAdvertising->start();
  Serial.println("BLE Started");
}

void loop() {
  // --- Check for Incoming RF Data ---
  if(receivedFlag) {
    // A packet triggered the ISR. Clear the flag immediately so we don't miss the next one.
    receivedFlag = false;
    
    // Dump the radio buffer out of the SPI module into ESP32 memory
    int len = radio.getPacketLength();
    std::vector<uint8_t> data(len);
    int state = radio.readData(data.data(), len);
    
    if (state == RADIOLIB_ERR_NONE) {
        Serial.println(F("[SX1262] Packet received!"));
        
        // Print diagnostics to serial
        RiderPacket packet = PacketManager::deserialize(data);
        Serial.printf("Type: %d, Sender: %X\n", packet.type, packet.senderId);

        // If the mobile app is actively connected, seamlessly stream the raw bytes over Bluetooth
        if (deviceConnected) {
            pTxCharacteristic->setValue(data.data(), data.size());
            pTxCharacteristic->notify(); // Triggers a Notify Characteristic in Flutter
        }

    } else {
        Serial.print(F("[SX1262] Read failed, code "));
        Serial.println(state);
    }
    
    // Reset the LoRa chip receiver logic
    radio.startReceive();
  }

  // --- Poll the GPS Feed ---
  while (gpsSerial.available() > 0) {
    gps.encode(gpsSerial.read());
  }

  if (millis() - lastGpsReadTime > gpsInterval) {
    if (gps.location.isValid()) {
        float lat = gps.location.lat();
        float lng = gps.location.lng();
        
        Serial.printf("GPS: %f, %f\n", lat, lng);

        // Prepare packet
        RiderPacket packet;
        packet.type = PACKET_TYPE_LOCATION;
        packet.senderId = PacketManager::getDeviceId();
        
        // Payload: [Lat(4)][Long(4)]
        uint8_t payload[8];
        memcpy(&payload[0], &lat, 4);
        memcpy(&payload[4], &lng, 4);
        packet.payload.assign(payload, payload + 8);

        std::vector<uint8_t> data = PacketManager::serialize(packet);

        // Transmit via LoRa
        radio.startTransmit(data.data(), data.size());
        
        // Also stream the hardware GPS to the connected phone via BLE.
        // The phone's own GPS may be less accurate when mounted inside a fairing.
        // Sending a self-location packet lets the app use the hardware GPS instead.
        if (deviceConnected) {
            std::vector<uint8_t> bleData = PacketManager::serialize(packet);
            pTxCharacteristic->setValue(bleData.data(), bleData.size());
            pTxCharacteristic->notify();
        }
        
    } else {
       // Serial.println("GPS Searching...");
    }
    lastGpsReadTime = millis();
  }

  // --- BLE Connection Management ---
  if (!deviceConnected && oldDeviceConnected) {
      delay(500); 
      pServer->startAdvertising(); 
      oldDeviceConnected = deviceConnected;
      Serial.println("Restarting advertising...");
  }
  if (deviceConnected && !oldDeviceConnected) {
      oldDeviceConnected = deviceConnected;
  }
  
  // vTaskDelay(1) yields to the FreeRTOS scheduler for 1 tick (~1ms).
  // This prevents TWDT resets without blocking ISR flag processing for 10ms
  // the way delay(10) did — important for not missing back-to-back LoRa packets.
  vTaskDelay(1);
}
