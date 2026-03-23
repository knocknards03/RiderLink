import 'dart:typed_data';

class RiderPacket {
  final int type;
  final int senderId;
  final Uint8List payload;

  RiderPacket({
    required this.type,
    required this.senderId,
    required this.payload,
  });

  @override
  String toString() {
    return 'Packet(type: $type, senderId: ${senderId.toRadixString(16)}, payloadLen: ${payload.length})';
  }
}

class ProtocolParser {
  static const int PACKET_TYPE_LOCATION = 0x01;
  static const int PACKET_TYPE_MESSAGE = 0x02;
  static const int PACKET_TYPE_ALERT = 0x03;

  /// Parses a byte array into a RiderPacket object.
  /// Packet Structure: [Type(1)][SenderID(4)][PayloadLength(1)][Payload(N)]
  static RiderPacket parse(List<int> data) {
    if (data.length < 6) {
      throw Exception("Invalid packet length: ${data.length} (min 6)");
    }

    final byteData = ByteData.sublistView(Uint8List.fromList(data));
    
    // 1. Type
    int type = byteData.getUint8(0);

    // 2. Sender ID (4 bytes, Big Endian as per C++ implementation bit shifting)
    // C++: (packet.senderId >> 24) & 0xFF ...
    // This implies Big Endian transmission.
    int senderId = byteData.getUint32(1, Endian.big);

    // 3. Payload Length
    int payloadLen = byteData.getUint8(5);

    // 4. Payload
    if (data.length < 6 + payloadLen) {
         throw Exception("Incomplete payload. Expected $payloadLen, got ${data.length - 6}");
    }
    
    Uint8List payload = Uint8List(payloadLen);
    for(int i=0; i<payloadLen; i++) {
        payload[i] = byteData.getUint8(6+i);
    }

    return RiderPacket(
      type: type,
      senderId: senderId,
      payload: payload,
    );
  }

  /// Helper to parse Location Payload [Lat(4)][Long(4)]
  static Map<String, double> parseLocation(Uint8List payload) {
      if (payload.length < 8) return {};
      final bd = ByteData.sublistView(payload);
      double lat = bd.getFloat32(0, Endian.little); // C++ memcpy is usually Little Endian on ESP32
      double lng = bd.getFloat32(4, Endian.little);
      return {'lat': lat, 'lng': lng};
  }

  /// Helper to parse String Payload
  static String parseMessage(Uint8List payload) {
      return String.fromCharCodes(payload);
  }
}
