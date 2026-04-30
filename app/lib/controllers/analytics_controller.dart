import 'dart:async';
import 'dart:math';
import 'package:get/get.dart';
import 'package:latlong2/latlong.dart';
import 'package:sensors_plus/sensors_plus.dart';
import '../db/database_helper.dart';
import 'ble_controller.dart';

class AnalyticsController extends GetxController {
  final RxDouble currentLeanAngle = 0.0.obs;
  final RxDouble maxLeanAngle     = 0.0.obs;
  final RxDouble currentGForce    = 1.0.obs;
  final RxDouble fusedHeading     = 0.0.obs;

  // ── Trip distance & speed tracking ─────────────────────────────────────────
  final RxDouble tripDistanceKm   = 0.0.obs;
  final RxDouble topSpeedKmh      = 0.0.obs;

  StreamSubscription? _gyroSubscription;
  StreamSubscription? _accelSubscription;
  Timer? _dbTimer;

  DateTime _lastGyroTime = DateTime.now();
  LatLng? _lastGpsPoint;           // for haversine distance accumulation
  static const _distCalc = Distance();

  int? currentTripId;

  @override
  void onInit() {
    super.onInit();
    startAnalytics();
  }

  void startAnalytics() async {
    final db = DatabaseHelper();
    currentTripId = await db.insertTrip(DateTime.now().millisecondsSinceEpoch);

    // ── Gyroscope: lean angle + heading fusion ──────────────────────────────
    _gyroSubscription = gyroscopeEventStream(
      samplingPeriod: const Duration(milliseconds: 50),
    ).listen((event) {
      final now = DateTime.now();
      final dt  = now.difference(_lastGyroTime).inMicroseconds / 1e6;
      _lastGyroTime = now;

      // Lean angle (Y-axis, capped at 60°)
      double lean = (event.y * 57.2958).abs().clamp(0.0, 60.0);
      currentLeanAngle.value = lean;
      if (lean > maxLeanAngle.value) maxLeanAngle.value = lean;

      // Heading fusion
      final ble      = Get.find<BleController>();
      final speedKmh = ble.mySpeedKmh.value;

      if (speedKmh < 2.0) {
        // Pure gyro at low speed
        double yaw = (fusedHeading.value - event.z * 57.2958 * dt) % 360.0;
        fusedHeading.value = yaw < 0 ? yaw + 360.0 : yaw;
      } else {
        // Complementary filter: 95% GPS + 5% gyro
        double gyroYaw = (fusedHeading.value - event.z * 57.2958 * dt) % 360.0;
        if (gyroYaw < 0) gyroYaw += 360.0;
        double diff = ble.myHeading.value - gyroYaw;
        if (diff > 180) diff -= 360;
        if (diff < -180) diff += 360;
        double blended = gyroYaw + diff * 0.05;
        if (blended < 0) blended += 360.0;
        if (blended >= 360) blended -= 360.0;
        fusedHeading.value = blended;
      }
    });

    // ── Accelerometer: G-force ──────────────────────────────────────────────
    _accelSubscription = accelerometerEventStream().listen((event) {
      currentGForce.value =
          sqrt(pow(event.x, 2) + pow(event.y, 2) + pow(event.z, 2)) / 9.81;
    });

    // ── GPS logging + distance + speed tracking (every 5 s) ────────────────
    _dbTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      final ble = Get.find<BleController>();
      final loc = ble.myLocation.value;
      if (loc == null || currentTripId == null) return;

      // Accumulate distance
      if (_lastGpsPoint != null) {
        final metres = _distCalc.as(LengthUnit.Meter, _lastGpsPoint!, loc);
        // Ignore GPS jumps > 500 m in 5 s (likely a bad fix)
        if (metres < 500) {
          tripDistanceKm.value += metres / 1000.0;
        }
      }
      _lastGpsPoint = loc;

      // Track top speed
      final speed = ble.mySpeedKmh.value;
      if (speed > topSpeedKmh.value) topSpeedKmh.value = speed;

      // Persist route point every 10 s (every other tick)
      if (timer.tick % 2 == 0) {
        db.insertRoutePoint(currentTripId!, loc.latitude, loc.longitude);
      }
    });
  }

  @override
  void onClose() {
    _gyroSubscription?.cancel();
    _accelSubscription?.cancel();
    _dbTimer?.cancel();
    if (currentTripId != null) {
      DatabaseHelper().updateTripEnd(
        currentTripId!,
        DateTime.now().millisecondsSinceEpoch,
        maxLeanAngle.value,
        distanceKm: tripDistanceKm.value,
        topSpeedKmh: topSpeedKmh.value,
      );
    }
    super.onClose();
  }
}
