import 'dart:async';
import 'dart:math';
import 'package:get/get.dart';
import 'package:sensors_plus/sensors_plus.dart';
import '../db/database_helper.dart';
import 'ble_controller.dart';

class AnalyticsController extends GetxController {
  final RxDouble currentLeanAngle = 0.0.obs;
  final RxDouble maxLeanAngle = 0.0.obs;

  // G-force at rest should read ~1.0 (gravity). We use accelerometerEventStream
  // which includes gravity, then divide by 9.81 to convert m/s² → G.
  // userAccelerometerEventStream removes gravity, giving ~0.0 at rest — wrong for display.
  final RxDouble currentGForce = 1.0.obs;

  // --- Gyro-fused heading ---
  // When the bike is moving slowly (< 2 km/h) GPS bearing is noisy/invalid.
  // We integrate the gyroscope Z-axis (yaw rate) to keep the arrow pointing correctly.
  // When GPS bearing is valid (speed > 2 km/h) we snap back to GPS truth.
  final RxDouble fusedHeading = 0.0.obs;

  StreamSubscription? _gyroSubscription;
  StreamSubscription? _accelSubscription;
  Timer? _dbTimer;

  // Timestamp of the last gyro sample for delta-time integration
  DateTime _lastGyroTime = DateTime.now();

  int? currentTripId;

  @override
  void onInit() {
    super.onInit();
    startAnalytics();
  }

  void startAnalytics() async {
    final db = DatabaseHelper();
    currentTripId = await db.insertTrip(
      DateTime.now().millisecondsSinceEpoch,
    );

    // --- Gyroscope: lean angle + heading fusion ---
    _gyroSubscription = gyroscopeEventStream(
      samplingPeriod: const Duration(milliseconds: 50), // 20 Hz for smooth arrow
    ).listen((GyroscopeEvent event) {
      final now = DateTime.now();
      final dt = now.difference(_lastGyroTime).inMicroseconds / 1e6; // seconds
      _lastGyroTime = now;

      // Lean angle from Y-axis rotation rate (rad/s → degrees, capped at 60°)
      double lean = (event.y * 57.2958).abs();
      if (lean > 60) lean = 60;
      currentLeanAngle.value = lean;
      if (lean > maxLeanAngle.value) {
        maxLeanAngle.value = lean;
      }

      // Heading fusion: integrate Z-axis (yaw) when GPS bearing is unreliable.
      // event.z is in rad/s. Negative because phone Z-axis is inverted vs compass.
      // Only integrate when speed is low — at speed, GPS heading takes over.
      final bleController = Get.find<BleController>();
      final speedKmh = bleController.mySpeedKmh.value;

      if (speedKmh < 2.0) {
        // Pure gyro integration at low speed
        double yawDeg = event.z * 57.2958 * dt;
        double newHeading = (fusedHeading.value - yawDeg) % 360.0;
        if (newHeading < 0) newHeading += 360.0;
        fusedHeading.value = newHeading;
      } else {
        // Complementary filter: 95% GPS bearing + 5% gyro integration
        // This smooths out GPS bearing jitter while staying accurate
        double yawDeg = event.z * 57.2958 * dt;
        double gpsHeading = bleController.myHeading.value;
        double gyroHeading = (fusedHeading.value - yawDeg) % 360.0;
        if (gyroHeading < 0) gyroHeading += 360.0;

        // Shortest-path blend to avoid 359° → 1° wrap-around glitch
        double diff = gpsHeading - gyroHeading;
        if (diff > 180) diff -= 360;
        if (diff < -180) diff += 360;
        double blended = gyroHeading + diff * 0.05;
        if (blended < 0) blended += 360.0;
        if (blended >= 360) blended -= 360.0;
        fusedHeading.value = blended;
      }
    });

    // --- Accelerometer: G-force (includes gravity → ~1.0G at rest) ---
    _accelSubscription = accelerometerEventStream().listen((AccelerometerEvent event) {
      double gForce = sqrt(pow(event.x, 2) + pow(event.y, 2) + pow(event.z, 2)) / 9.81;
      currentGForce.value = gForce;
    });

    // Log GPS route points every 10 seconds
    _dbTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      final bleController = Get.find<BleController>();
      if (bleController.myLocation.value != null && currentTripId != null) {
        db.insertRoutePoint(
          currentTripId!,
          bleController.myLocation.value!.latitude,
          bleController.myLocation.value!.longitude,
        );
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
          currentTripId!, DateTime.now().millisecondsSinceEpoch, maxLeanAngle.value);
    }
    super.onClose();
  }
}
