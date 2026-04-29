import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:get/get.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../utils/protocol_parser.dart';

class BleController extends GetxController {
  // Reactive states used to notify UI widgets that data has changed instantly
  final RxBool isConnected = false.obs;
  final RxList<String> logs = <String>[].obs;
  
  BluetoothDevice? targetDevice;
  BluetoothCharacteristic? txCharacteristic; // Notify stream from Firmware -> App
  BluetoothCharacteristic? rxCharacteristic; // Write stream from App -> Firmware

  // Securely caches live GPS feeds from other riders (Mapped via their Unique Sender ID)
  final RxMap<int, List<double>> riderLocations = <int, List<double>>{}.obs;

  // New State for Hazards (Waze-style reporting)
  final RxList<Map<String, dynamic>> reportedHazards = <Map<String, dynamic>>[].obs;

  // New Navigation States
  final Rx<LatLng?> myLocation = Rx<LatLng?>(null); // Tracks your own phone's GPS position
  final Rx<LatLng?> destinationPin = Rx<LatLng?>(null); // Tracks the final destination selected
  final RxList<LatLng> currentRoute = <LatLng>[].obs; // Contains the snaking geometry of the OSRM path

  // --- Heading & Speed (Google Maps-style live arrow) ---
  // GPS bearing in degrees (0–360, 0 = North). Updated from Geolocator position stream.
  // Valid only when speed > 1 m/s; below that, gyro-fused heading takes over.
  final RxDouble myHeading = 0.0.obs;
  // Speed in km/h from GPS
  final RxDouble mySpeedKmh = 0.0.obs;
  // Raw GPS position stream exposed so AnalyticsController can fuse gyro heading
  final Rx<Position?> lastGpsPosition = Rx<Position?>(null);

  // Custom Hardware UUIDs matching the ESP32 code inside Firmware/config.h
  final String SERVICE_UUID = "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"; 
  final String RX_UUID = "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"; // Where our app writes outgoing data
  final String TX_UUID = "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"; // Where our app listens for incoming data

  Timer? _proximityTimer;
  Timer? _retryTimer;
  // Track the ever() worker so we can cancel it and avoid leaking multiple listeners
  Worker? _locationWorker;

  @override
  void onInit() {
    super.onInit();
    startScan();
    _proximityTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      _checkGroupProximity();
    });
  }

  @override
  void onClose() {
    _proximityTimer?.cancel();
    _retryTimer?.cancel();
    _locationWorker?.dispose();
    super.onClose();
  }

  void _checkGroupProximity() {
    if (myLocation.value == null || riderLocations.isEmpty) return;
    
    const distanceHelper = Distance();
    for (var entry in riderLocations.entries) {
      final riderId = entry.key;
      final loc = entry.value;
      final riderLatLng = LatLng(loc[0], loc[1]);
      
      final meterDistance = distanceHelper.as(LengthUnit.Meter, myLocation.value!, riderLatLng);
      if (meterDistance > 1000) { // 1 kilometer threshold
        Get.snackbar("Rider Separated!", "Rider #${riderId.toRadixString(16)} is ${meterDistance.toInt()} meters away!",
            snackPosition: SnackPosition.TOP, backgroundColor: Colors.orange, colorText: Colors.white, duration: const Duration(seconds: 6));
      }
    }
  }

  void startScan() async {
    logs.add("Checking permissions...");
    
    // Explicitly invoke Android Security Permissions. This is highly mandatory on Android 12+!
    await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();

    // Lock onto the phone's native hardware GPS module
    logs.add("Acquiring GPS lock...");
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (serviceEnabled) {
        Position pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
        myLocation.value = LatLng(pos.latitude, pos.longitude);
        lastGpsPosition.value = pos;

        // Subscribe to a continuous GPS stream — distanceFilter 3m for smooth arrow movement
        Geolocator.getPositionStream(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.bestForNavigation,
              distanceFilter: 3, // update every 3 metres for smooth tracking
            )
        ).listen((Position position) {
            myLocation.value = LatLng(position.latitude, position.longitude);
            lastGpsPosition.value = position;
            mySpeedKmh.value = (position.speed * 3.6).clamp(0.0, 300.0); // m/s → km/h

            // Use GPS bearing only when moving fast enough for it to be reliable (>2 km/h)
            if (position.speed > 0.55 && position.headingAccuracy >= 0) {
              myHeading.value = position.heading;
            }
        });
      }
    } catch (e) {
      logs.add("GPS Error: $e");
    }

    logs.add("Scanning for RiderLink...");
    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));

    bool found = false;
    FlutterBluePlus.scanResults.listen((results) {
      for (ScanResult r in results) {
        if (r.device.platformName == "RiderLink" || r.device.name == "RiderLink") {
          found = true;
          connectToDevice(r.device);
          FlutterBluePlus.stopScan();
          break;
        }
      }
    });

    // If device not found after scan timeout, retry every 15 seconds
    // so the user doesn't have to restart the app when the hardware powers on late.
    _retryTimer = Timer.periodic(const Duration(seconds: 15), (timer) {
      if (!isConnected.value) {
        logs.add("RiderLink not found. Retrying scan...");
        FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));
      } else {
        timer.cancel(); // Stop retrying once connected
      }
    });
  }

  void connectToDevice(BluetoothDevice device) async {
    logs.add("Found ${device.platformName}. Connecting...");
    try {
      // Execute the low-energy connection protocol
      await device.connect();
      targetDevice = device;
      isConnected.value = true;
      logs.add("Connected to ${device.platformName}");
      
      // Probe the hardware to discover what "Channels/Endpoints" they offer us
      discoverServices(device);
      
      // Keep a background stream monitoring connection drops or resets
      device.connectionState.listen((state) {
          if (state == BluetoothConnectionState.disconnected) {
              isConnected.value = false;
              rxCharacteristic = null;
              txCharacteristic = null;
              targetDevice = null;
              logs.add("Disconnected! Will retry scan...");
              // Re-arm the retry timer so we reconnect automatically
              _retryTimer?.cancel();
              _retryTimer = Timer.periodic(const Duration(seconds: 15), (timer) {
                if (!isConnected.value) {
                  logs.add("Retrying scan after disconnect...");
                  FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));
                } else {
                  timer.cancel();
                }
              });
          }
      });
      
    } catch (e) {
      logs.add("Connection failed: $e");
    }
  }

  void discoverServices(BluetoothDevice device) async {
    List<BluetoothService> services = await device.discoverServices();
    for (var service in services) {
       // Only engage if the UUID perfectly matches our proprietary system string
       if (service.uuid.toString().toUpperCase() == SERVICE_UUID) {
           for (var characteristic in service.characteristics) {
               String uuid = characteristic.uuid.toString().toUpperCase();
               
               // TX = Listen and alert us anytime new LoRa data gets routed through
               if(uuid == TX_UUID) {
                   txCharacteristic = characteristic;
                   await characteristic.setNotifyValue(true);
                   characteristic.onValueReceived.listen((value) {
                       _handleData(value);
                   });
                   logs.add("Subscribed to TX (Notify)");
               }
               
               // RX = Allow us to inject arbitrary data into the ESP32 to transmit out
               if(uuid == RX_UUID) {
                   rxCharacteristic = characteristic;
                   logs.add("Found RX (Write)");
               }
           }
       }
    }
  }

  void _handleData(List<int> data) {
    try {
      // Unpack the raw byte-stream string into legible parameters 
      final packet = ProtocolParser.parse(data);
      logs.add("Rx Packet: Type=${packet.type}, ID=${packet.senderId.toRadixString(16)}");
      
      // Separate pure GPS data tracking locations versus general string payloads 
      if (packet.type == ProtocolParser.PACKET_TYPE_LOCATION) {
          final loc = ProtocolParser.parseLocation(packet.payload);
          if (loc.isNotEmpty) {
             riderLocations[packet.senderId] = [loc['lat']!, loc['lng']!];
             logs.add("Location Update: ID=${packet.senderId} -> ${loc['lat']}, ${loc['lng']}");
          }
      } else if (packet.type == ProtocolParser.PACKET_TYPE_MESSAGE) {
          
          final msg = ProtocolParser.parseMessage(packet.payload);
          logs.add("Message: $msg");
          
          // Identify our custom emergency SOS injection string
          if (msg.startsWith("[SOS]|")) {
             final parts = msg.split('|');
             if (parts.length >= 6) {
                 String name = parts[1];
                 String blood = parts[2];
                 String emergency = parts[3];
                 String latStr = parts[4];
                 String lngStr = parts[5];
                 
                 // Suspend the user layout and popup the extremely loud Alert Modal
                 Get.defaultDialog(
                     title: "EMERGENCY SOS",
                     titleStyle: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 22),
                     middleText: "Rider $name (Blood Group: $blood) initiated an SOS at Coordinates [$latStr, $lngStr]! Please assist immediately.",
                     backgroundColor: Colors.red[50],
                     barrierDismissible: false,
                     
                     confirm: Column(
                       children: [
                         ElevatedButton.icon(
                             style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 45)),
                             icon: const Icon(Icons.phone),
                             label: const Text("Call Emergency Contact"),
                             onPressed: () {
                                 if(emergency.isNotEmpty && emergency != 'None') {
                                     launchUrl(Uri.parse("tel:$emergency"));
                                 }
                             },
                         ),
                         const SizedBox(height: 8),
                         ElevatedButton.icon(
                             style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 45)),
                             icon: const Icon(Icons.navigation),
                             label: const Text("Navigate to Crash Site"),
                             onPressed: () {
                                 launchUrl(Uri.parse("https://www.google.com/maps/dir/?api=1&destination=$latStr,$lngStr"));
                                 Get.back();
                             },
                         ),
                         const SizedBox(height: 8),
                         TextButton(
                             onPressed: () => Get.back(),
                             child: const Text("Dismiss Warning"),
                         ),
                       ],
                     ),
                 );
             }
          } 
          // Detect arbitrary user notification drops (Tea Break, Lunch Break...)
          else if (msg.startsWith("[BREAK]|")) {
             final parts = msg.split('|');
             if (parts.length >= 3) {
                 String type = parts[1];
                 String name = parts[2];
                 
                 // Show a friendly top-bar slider for less critical interactions 
                 Get.snackbar("RiderLink Break Point", "$name has requested a stop for: $type!", 
                     snackPosition: SnackPosition.TOP, 
                     backgroundColor: Colors.orangeAccent,
                     colorText: Colors.black,
                     duration: const Duration(seconds: 10)
                 );
             }
          } else if (msg.startsWith("[HAZARD]|")) {
             final parts = msg.split('|');
             if (parts.length >= 5) {
                 String type = parts[1];
                 String name = parts[2];
                 double lat = double.tryParse(parts[3]) ?? 0.0;
                 double lng = double.tryParse(parts[4]) ?? 0.0;
                 
                 reportedHazards.add({
                   'type': type,
                   'name': name,
                   'lat': lat,
                   'lng': lng,
                   'time': DateTime.now()
                 });
                 
                 Get.snackbar("Hazard Ahead", "$name reported a $type!", 
                     snackPosition: SnackPosition.TOP, 
                     backgroundColor: Colors.redAccent,
                     colorText: Colors.white,
                     duration: const Duration(seconds: 8)
                 );
             }
          } else if (msg.startsWith("[MESH]|")) {
             final parts = msg.split('|');
             if (parts.length >= 3) {
                 int ttl = int.tryParse(parts[1]) ?? 0;
                 String content = parts.sublist(2).join('|');
                 
                 logs.add("Mesh Rx (TTL: $ttl): $content");
                 Get.snackbar("Mesh Message", content, 
                     snackPosition: SnackPosition.TOP, 
                     backgroundColor: Colors.purple,
                     colorText: Colors.white,
                     duration: const Duration(seconds: 5)
                 );
             }
          }
      }
      
    } catch (e) {
      logs.add("Parse Error: $e");
    }
  }

  void sendMessage(String message) async {
      // Send raw UTF8 byte bytes back into the RX Characteristic if it exists
      if (rxCharacteristic != null) {
          await rxCharacteristic!.write(utf8.encode(message));
          logs.add("Sent: $message");
      }
  }

  void sendSOS() async {
    final prefs = await SharedPreferences.getInstance();
    String name = prefs.getString('name') ?? 'Unknown Rider';
    String blood = prefs.getString('blood_group') ?? 'N/A';
    String emergency = prefs.getString('emergency_contact') ?? 'None';
    
    String latStr = myLocation.value != null ? myLocation.value!.latitude.toString() : "0.0";
    String lngStr = myLocation.value != null ? myLocation.value!.longitude.toString() : "0.0";
    
    String payload = "[SOS]|$name|$blood|$emergency|$latStr|$lngStr";

    // Guard: only show success if the message was actually written to hardware.
    // Previously this showed "SOS Sent" even when rxCharacteristic was null.
    if (rxCharacteristic != null) {
      await rxCharacteristic!.write(utf8.encode(payload));
      logs.add("Broadcasted SOS!");
      Get.snackbar("SOS Sent", "Emergency broadcast transmitted to all nearby riders.",
          backgroundColor: Colors.redAccent, colorText: Colors.white);
    } else {
      logs.add("SOS FAILED — BLE not connected");
      Get.snackbar(
        "SOS Failed — No Hardware",
        "BLE device is not connected. Your SOS was NOT broadcast. Call emergency services directly.",
        backgroundColor: Colors.red,
        colorText: Colors.white,
        duration: const Duration(seconds: 10),
        snackPosition: SnackPosition.TOP,
      );
    }
  }

  void sendBreak(String type) async {
    final prefs = await SharedPreferences.getInstance();
    String name = prefs.getString('name') ?? 'A Rider';
    
    String payload = "[BREAK]|$type|$name";
    sendMessage(payload);
    logs.add("Broadcasted Break: $type");
    Get.snackbar("Break Signal", "Notified other riders about $type.", backgroundColor: Colors.green, colorText: Colors.white);
  }

  void reportHazard(String type) async {
    final prefs = await SharedPreferences.getInstance();
    String name = prefs.getString('name') ?? 'Rider';
    
    if (myLocation.value != null) {
      // Add locally
      reportedHazards.add({
        'type': type,
        'name': name,
        'lat': myLocation.value!.latitude,
        'lng': myLocation.value!.longitude,
        'time': DateTime.now()
      });
      
      // Pack coordinates into payload
      String payload = "[HAZARD]|$type|$name|${myLocation.value!.latitude}|${myLocation.value!.longitude}";
      sendMessage(payload);
      Get.snackbar("Hazard Reported", "$type added to map.", backgroundColor: Colors.orange, colorText: Colors.white);
    } else {
      Get.snackbar("Error", "Awaiting GPS lock to report hazard.", backgroundColor: Colors.red, colorText: Colors.white);
    }
  }

  void sendMeshMessage(String message, {int ttl = 3}) async {
    final prefs = await SharedPreferences.getInstance();
    String name = prefs.getString('name') ?? 'Rider';
    
    // Basic TTL routing prefix for ESP32 mesh nodes to bounce
    String payload = "[MESH]|$ttl|[$name]: $message";
    sendMessage(payload);
    Get.snackbar("Transmitting", "Sent via LoRa Mesh", backgroundColor: Colors.blueAccent, colorText: Colors.white);
  }
}
