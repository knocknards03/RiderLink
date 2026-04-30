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
import 'package:http/http.dart' as http;
import '../utils/protocol_parser.dart';
import 'auth_controller.dart';

class BleController extends GetxController {
  // ── Reactive state ──────────────────────────────────────────────────────────
  final RxBool isConnected   = false.obs;
  final RxBool isSimMode     = false.obs; // true = WiFi bridge, no ESP32
  final RxList<String> logs  = <String>[].obs;

  BluetoothDevice? targetDevice;
  BluetoothCharacteristic? txCharacteristic;
  BluetoothCharacteristic? rxCharacteristic;

  final RxMap<int, List<double>> riderLocations  = <int, List<double>>{}.obs;
  final RxList<Map<String, dynamic>> reportedHazards = <Map<String, dynamic>>[].obs;
  final Rx<LatLng?> myLocation    = Rx<LatLng?>(null);
  final Rx<LatLng?> destinationPin = Rx<LatLng?>(null);
  final RxList<LatLng> currentRoute = <LatLng>[].obs;
  final RxDouble myHeading  = 0.0.obs;
  final RxDouble mySpeedKmh = 0.0.obs;
  final Rx<Position?> lastGpsPosition = Rx<Position?>(null);

  // BLE UUIDs
  final String SERVICE_UUID = "6E400001-B5A3-F393-E0A9-E50E24DCCA9E";
  final String RX_UUID      = "6E400002-B5A3-F393-E0A9-E50E24DCCA9E";
  final String TX_UUID      = "6E400003-B5A3-F393-E0A9-E50E24DCCA9E";

  Timer? _proximityTimer;
  Timer? _retryTimer;
  Timer? _simPushTimer;   // pushes our location to backend every 3 s
  Timer? _simPullTimer;   // polls other riders from backend every 3 s
  Worker? _locationWorker;

  int _simLastPull = 0;   // Unix timestamp of last successful pull

  @override
  void onInit() {
    super.onInit();
    _startGps();
    _startBleScan();
    _proximityTimer = Timer.periodic(
        const Duration(seconds: 30), (_) => _checkGroupProximity());
  }

  @override
  void onClose() {
    _proximityTimer?.cancel();
    _retryTimer?.cancel();
    _simPushTimer?.cancel();
    _simPullTimer?.cancel();
    _locationWorker?.dispose();
    super.onClose();
  }

  // ── GPS (always on, regardless of BLE/sim mode) ─────────────────────────────

  Future<void> _startGps() async {
    await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();

    logs.add("Acquiring GPS lock...");
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      myLocation.value      = LatLng(pos.latitude, pos.longitude);
      lastGpsPosition.value = pos;

      // If sim mode is already active, push location immediately on GPS lock
      if (isSimMode.value) _simPushLocation();

      Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 3,
        ),
      ).listen((p) {
        myLocation.value      = LatLng(p.latitude, p.longitude);
        lastGpsPosition.value = p;
        mySpeedKmh.value      = (p.speed * 3.6).clamp(0.0, 300.0);
        if (p.speed > 0.55 && p.headingAccuracy >= 0) {
          myHeading.value = p.heading;
        }
      });
    } catch (e) {
      logs.add("GPS Error: $e");
    }
  }

  // ── BLE scan ────────────────────────────────────────────────────────────────

  void _startBleScan() {
    logs.add("Scanning for RiderLink hardware...");
    FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));

    FlutterBluePlus.scanResults.listen((results) {
      for (final r in results) {
        if (r.device.platformName == "RiderLink" ||
            r.device.name == "RiderLink") {
          _connectToDevice(r.device);
          FlutterBluePlus.stopScan();
          return;
        }
      }
    });

    // After 12 s with no hardware found → switch to WiFi simulation mode
    _retryTimer = Timer(const Duration(seconds: 12), () {
      if (!isConnected.value) {
        logs.add("No ESP32 found — enabling WiFi simulation mode.");
        _enableSimMode();
      }
    });
  }

  // ── WiFi simulation mode ────────────────────────────────────────────────────

  void _enableSimMode() {
    isSimMode.value    = true;
    isConnected.value  = true;

    // Initialize pull timestamp to NOW so we only receive NEW events,
    // not stale events from previous sessions stored in the backend.
    _simLastPull = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    Get.snackbar(
      "📡 WiFi Simulation Mode",
      "No ESP32 found. Using backend WiFi bridge to connect with other riders.",
      backgroundColor: Colors.blueAccent,
      colorText: Colors.white,
      duration: const Duration(seconds: 5),
      snackPosition: SnackPosition.TOP,
    );

    // Push location immediately, then every 3 s
    _simPushLocation();
    _simPushTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _simPushLocation();
    });

    // Pull immediately, then every 3 s
    _simPullEvents();
    _simPullTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _simPullEvents();
    });
  }

  Future<void> _simPushLocation() async {
    if (myLocation.value == null) return;
    try {
      final auth = Get.find<AuthController>();
      if (!auth.isLoggedIn.value) return;

      await http.post(
        Uri.parse('${AuthController.baseUrl}/sim/push'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${auth.token}',
        },
        body: jsonEncode({
          'user_id': auth.userId.value,
          'event_type': 'location',
          'payload': {
            'lat': myLocation.value!.latitude,
            'lng': myLocation.value!.longitude,
            'name': auth.userName.value,
          },
        }),
      ).timeout(const Duration(seconds: 5));
    } catch (_) {}
  }

  Future<void> _simPushEvent(String eventType, Map<String, dynamic> payload) async {
    try {
      final auth = Get.find<AuthController>();
      if (!auth.isLoggedIn.value) return;

      await http.post(
        Uri.parse('${AuthController.baseUrl}/sim/push'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${auth.token}',
        },
        body: jsonEncode({
          'user_id': auth.userId.value,
          'event_type': eventType,
          'payload': payload,
        }),
      ).timeout(const Duration(seconds: 5));
    } catch (_) {}
  }

  Future<void> _simPullEvents() async {
    try {
      final auth = Get.find<AuthController>();
      if (!auth.isLoggedIn.value) return;

      final res = await http.get(
        Uri.parse('${AuthController.baseUrl}/sim/pull?since=$_simLastPull'),
        headers: {'Authorization': 'Bearer ${auth.token}'},
      ).timeout(const Duration(seconds: 5));

      if (res.statusCode != 200) {
        logs.add("Sim pull error: ${res.statusCode}");
        return;
      }

      final events = jsonDecode(res.body) as List;

      // Always advance the timestamp to now so we never re-process old events
      final nowTs = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      if (events.isNotEmpty) {
        _simLastPull = (events.last['ts'] as int? ?? nowTs);
      } else {
        // No events — advance to now so next pull only gets truly new events
        _simLastPull = nowTs;
      }

      for (final e in events) {
        final type    = e['event_type'] as String;
        final payload = e['payload']    as Map<String, dynamic>;
        final userId  = e['user_id']    as int;

        switch (type) {
          case 'location':
            final lat  = (payload['lat'] as num).toDouble();
            final lng  = (payload['lng'] as num).toDouble();
            final name = payload['name'] as String? ?? 'Rider';
            riderLocations[userId] = [lat, lng];
            logs.add("📍 Rider $name ($userId) @ ${lat.toStringAsFixed(4)},${lng.toStringAsFixed(4)}");
            break;

          case 'message':
            final msg = payload['msg'] as String? ?? '';
            logs.add("💬 Sim Msg: $msg");
            _handleMessage(msg);
            break;

          case 'sos':
            final name      = payload['name']      as String? ?? 'Rider';
            final blood     = payload['blood']     as String? ?? 'N/A';
            final emergency = payload['emergency'] as String? ?? '';
            final lat       = payload['lat']       as String? ?? '0';
            final lng       = payload['lng']       as String? ?? '0';
            logs.add("🚨 SOS from $name");
            _showSosDialog(name, blood, emergency, lat, lng);
            break;

          case 'hazard':
            final hType = payload['type'] as String? ?? 'Hazard';
            final name  = payload['name'] as String? ?? 'Rider';
            final lat   = (payload['lat'] as num?)?.toDouble() ?? 0.0;
            final lng   = (payload['lng'] as num?)?.toDouble() ?? 0.0;
            reportedHazards.add({
              'type': hType, 'name': name,
              'lat': lat, 'lng': lng, 'time': DateTime.now(),
            });
            Get.snackbar("⚠ Hazard Ahead", "$name reported a $hType!",
                backgroundColor: Colors.redAccent, colorText: Colors.white,
                snackPosition: SnackPosition.TOP);
            break;
        }
      }
    } catch (e) {
      logs.add("Sim pull exception: $e");
    }
  }

  // ── BLE hardware path ───────────────────────────────────────────────────────

  void _connectToDevice(BluetoothDevice device) async {
    logs.add("Found ${device.platformName}. Connecting...");
    try {
      await device.connect();
      targetDevice      = device;
      isConnected.value = true;
      isSimMode.value   = false;
      _retryTimer?.cancel();
      logs.add("Connected to ${device.platformName}");
      _discoverServices(device);

      device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          isConnected.value  = false;
          rxCharacteristic   = null;
          txCharacteristic   = null;
          targetDevice       = null;
          logs.add("Disconnected — falling back to sim mode.");
          _enableSimMode();
        }
      });
    } catch (e) {
      logs.add("Connection failed: $e");
    }
  }

  void _discoverServices(BluetoothDevice device) async {
    final services = await device.discoverServices();
    for (final service in services) {
      if (service.uuid.toString().toUpperCase() == SERVICE_UUID) {
        for (final c in service.characteristics) {
          final uuid = c.uuid.toString().toUpperCase();
          if (uuid == TX_UUID) {
            txCharacteristic = c;
            await c.setNotifyValue(true);
            c.onValueReceived.listen(_handleData);
            logs.add("Subscribed to TX (Notify)");
          }
          if (uuid == RX_UUID) {
            rxCharacteristic = c;
            logs.add("Found RX (Write)");
          }
        }
      }
    }
  }

  void _handleData(List<int> data) {
    try {
      final packet = ProtocolParser.parse(data);
      if (packet.type == ProtocolParser.PACKET_TYPE_LOCATION) {
        final loc = ProtocolParser.parseLocation(packet.payload);
        if (loc.isNotEmpty) {
          riderLocations[packet.senderId] = [loc['lat']!, loc['lng']!];
        }
      } else if (packet.type == ProtocolParser.PACKET_TYPE_MESSAGE) {
        _handleMessage(ProtocolParser.parseMessage(packet.payload));
      }
    } catch (e) {
      logs.add("Parse Error: $e");
    }
  }

  // ── Message routing (shared by BLE and sim mode) ────────────────────────────

  void _handleMessage(String msg) {
    logs.add("Message: $msg");

    if (msg.startsWith("[SOS]|")) {
      final p = msg.split('|');
      if (p.length >= 6) {
        _showSosDialog(p[1], p[2], p[3], p[4], p[5]);
      }
    } else if (msg.startsWith("[BREAK]|")) {
      final p = msg.split('|');
      if (p.length >= 3) {
        Get.snackbar("Break Point", "${p[2]} requested a stop for: ${p[1]}!",
            backgroundColor: Colors.orangeAccent, colorText: Colors.black,
            snackPosition: SnackPosition.TOP,
            duration: const Duration(seconds: 10));
      }
    } else if (msg.startsWith("[HAZARD]|")) {
      final p = msg.split('|');
      if (p.length >= 5) {
        reportedHazards.add({
          'type': p[1], 'name': p[2],
          'lat': double.tryParse(p[3]) ?? 0.0,
          'lng': double.tryParse(p[4]) ?? 0.0,
          'time': DateTime.now(),
        });
        Get.snackbar("Hazard Ahead", "${p[2]} reported a ${p[1]}!",
            backgroundColor: Colors.redAccent, colorText: Colors.white,
            snackPosition: SnackPosition.TOP);
      }
    } else if (msg.startsWith("[MESH]|")) {
      final p = msg.split('|');
      if (p.length >= 3) {
        final content = p.sublist(2).join('|');
        Get.snackbar("Mesh Message", content,
            backgroundColor: Colors.purple, colorText: Colors.white,
            snackPosition: SnackPosition.TOP);
      }
    }
  }

  void _showSosDialog(String name, String blood, String emergency,
      String latStr, String lngStr) {
    Get.defaultDialog(
      title: "EMERGENCY SOS",
      titleStyle: const TextStyle(
          color: Colors.red, fontWeight: FontWeight.bold, fontSize: 22),
      middleText:
          "Rider $name (Blood: $blood) sent SOS at [$latStr, $lngStr]!",
      backgroundColor: Colors.red[50],
      barrierDismissible: false,
      confirm: Column(children: [
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 45)),
          icon: const Icon(Icons.phone),
          label: const Text("Call Emergency Contact"),
          onPressed: () {
            if (emergency.isNotEmpty && emergency != 'None') {
              launchUrl(Uri.parse("tel:$emergency"));
            }
          },
        ),
        const SizedBox(height: 8),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blueAccent,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 45)),
          icon: const Icon(Icons.navigation),
          label: const Text("Navigate to Crash Site"),
          onPressed: () {
            launchUrl(Uri.parse(
                "https://www.google.com/maps/dir/?api=1&destination=$latStr,$lngStr"));
            Get.back();
          },
        ),
        const SizedBox(height: 8),
        TextButton(onPressed: Get.back, child: const Text("Dismiss")),
      ]),
    );
  }

  // ── Proximity check ─────────────────────────────────────────────────────────

  void _checkGroupProximity() {
    if (myLocation.value == null || riderLocations.isEmpty) return;
    const d = Distance();
    for (final entry in riderLocations.entries) {
      final metres = d.as(LengthUnit.Meter,
          myLocation.value!, LatLng(entry.value[0], entry.value[1]));
      if (metres > 1000) {
        Get.snackbar(
          "Rider Separated!",
          "Rider #${entry.key.toRadixString(16)} is ${metres.toInt()} m away!",
          backgroundColor: Colors.orange,
          colorText: Colors.white,
          snackPosition: SnackPosition.TOP,
        );
      }
    }
  }

  // ── Public send methods ─────────────────────────────────────────────────────

  void _sendRaw(String message) async {
    if (isSimMode.value) {
      await _simPushEvent('message', {'msg': message});
    } else if (rxCharacteristic != null) {
      await rxCharacteristic!.write(utf8.encode(message));
    }
    logs.add("Sent: $message");
  }

  void sendSOS() async {
    final prefs = await SharedPreferences.getInstance();
    final name      = prefs.getString('name')              ?? 'Unknown Rider';
    final blood     = prefs.getString('blood_group')       ?? 'N/A';
    final emergency = prefs.getString('emergency_contact') ?? 'None';
    final latStr    = myLocation.value?.latitude.toString()  ?? '0.0';
    final lngStr    = myLocation.value?.longitude.toString() ?? '0.0';

    if (isSimMode.value) {
      await _simPushEvent('sos', {
        'name': name, 'blood': blood,
        'emergency': emergency, 'lat': latStr, 'lng': lngStr,
      });
      Get.snackbar("SOS Sent (WiFi)",
          "Emergency broadcast sent to all riders via backend.",
          backgroundColor: Colors.redAccent, colorText: Colors.white);
    } else if (rxCharacteristic != null) {
      final payload = "[SOS]|$name|$blood|$emergency|$latStr|$lngStr";
      await rxCharacteristic!.write(utf8.encode(payload));
      Get.snackbar("SOS Sent", "Emergency broadcast transmitted.",
          backgroundColor: Colors.redAccent, colorText: Colors.white);
    } else {
      Get.snackbar(
        "SOS Failed — Not Connected",
        "Neither BLE nor WiFi bridge is active.",
        backgroundColor: Colors.red,
        colorText: Colors.white,
        duration: const Duration(seconds: 10),
        snackPosition: SnackPosition.TOP,
      );
    }
  }

  void sendBreak(String type) async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString('name') ?? 'A Rider';
    _sendRaw("[BREAK]|$type|$name");
    Get.snackbar("Break Signal", "Notified other riders about $type.",
        backgroundColor: Colors.green, colorText: Colors.white);
  }

  void reportHazard(String type) async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString('name') ?? 'Rider';
    if (myLocation.value == null) {
      Get.snackbar("Error", "Awaiting GPS lock.",
          backgroundColor: Colors.red, colorText: Colors.white);
      return;
    }
    final lat = myLocation.value!.latitude;
    final lng = myLocation.value!.longitude;

    reportedHazards.add({
      'type': type, 'name': name,
      'lat': lat, 'lng': lng, 'time': DateTime.now(),
    });

    if (isSimMode.value) {
      await _simPushEvent('hazard',
          {'type': type, 'name': name, 'lat': lat, 'lng': lng});
    } else {
      _sendRaw("[HAZARD]|$type|$name|$lat|$lng");
    }
    Get.snackbar("Hazard Reported", "$type added to map.",
        backgroundColor: Colors.orange, colorText: Colors.white);
  }

  void sendMeshMessage(String message, {int ttl = 3}) async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString('name') ?? 'Rider';
    _sendRaw("[MESH]|$ttl|[$name]: $message");
    Get.snackbar("Transmitting", "Sent via ${isSimMode.value ? 'WiFi Bridge' : 'LoRa Mesh'}",
        backgroundColor: Colors.blueAccent, colorText: Colors.white);
  }

  // Legacy alias kept for compatibility
  void startScan() => _startBleScan();
  void sendMessage(String message) => _sendRaw(message);
}
