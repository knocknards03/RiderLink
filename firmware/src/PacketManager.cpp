#include "PacketManager.h"
#include "esp_mac.h" // Required to access the ESP32's hardware MAC address

std::vector<uint8_t> PacketManager::serialize(const RiderPacket& packet) {
    std::vector<uint8_t> buffer;
    
    // Byte 1: The designated packet type (e.g. MESSAGE or LOCATION)
    buffer.push_back(packet.type);
    
    // Bytes 2-5: The 32-bit Sender ID. We execute bit-shifting to break it into 4 individual bytes
    buffer.push_back((packet.senderId >> 24) & 0xFF); // Extract highest 8 bits
    buffer.push_back((packet.senderId >> 16) & 0xFF);
    buffer.push_back((packet.senderId >> 8) & 0xFF);
    buffer.push_back(packet.senderId & 0xFF);         // Extract lowest 8 bits

    // Byte 6: The length of the Payload (restricts packet length to a max of 255 bytes)
    uint8_t payloadLen = packet.payload.size();
    buffer.push_back(payloadLen);

    // Byte 7 to End: Insert the actual message data payload into the buffer
    buffer.insert(buffer.end(), packet.payload.begin(), packet.payload.end());

    return buffer;
}

RiderPacket PacketManager::deserialize(const std::vector<uint8_t>& data) {
    RiderPacket packet;
    
    // Reject packets smaller than the bare minimum size: Type(1) + ID(4) + Len(1) = 6 bytes
    if (data.size() < 6) return packet; 

    packet.type = data[0]; // Read packet type
    
    // Reconstruct the 32-bit integer ID by shifting the 4 chunks back into sequence.
    // Explicit casting to uint32_t prevents nasty C++ sign-extension bugs that create negative numbers.
    packet.senderId = ((uint32_t)data[1] << 24) | ((uint32_t)data[2] << 16) | ((uint32_t)data[3] << 8) | (uint32_t)data[4];
    
    uint8_t payloadLen = data[5];
    
    // Safeguard to prevent out-of-bounds memory reading
    if (data.size() >= 6 + payloadLen) {
        packet.payload.assign(data.begin() + 6, data.begin() + 6 + payloadLen);
    }

    return packet;
}

uint32_t PacketManager::getDeviceId() {
    // Acquire the factory-burned hardcoded MAC address of the ESP32 chip
    uint64_t mac = ESP.getEfuseMac(); 
    
    // Truncate it to the bottom 32-bits to use as a simple, universally unique ID for the MVP
    return (uint32_t)(mac & 0xFFFFFFFF); 
}
