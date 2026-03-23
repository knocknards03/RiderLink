#ifndef PACKET_MANAGER_H
#define PACKET_MANAGER_H

#include <Arduino.h>
#include <vector>

struct RiderPacket {
    uint8_t type;
    uint32_t senderId;
    std::vector<uint8_t> payload;
};

class PacketManager {
public:
    static std::vector<uint8_t> serialize(const RiderPacket& packet);
    static RiderPacket deserialize(const std::vector<uint8_t>& data);
    static uint32_t getDeviceId();
};

#endif
