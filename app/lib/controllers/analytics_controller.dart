import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:sensors_plus/sensors_plus.dart';
import '../db/database_helper.dart';
import 'ble_controller.dart';

class AnalyticsController extends GetxController {
  final RxDouble currentLeanAngle = 0.0.obs;
  final RxDouble maxLeanAngle = 0.0.obs;
  final RxDouble currentGForce = 1.0.obs;
  
  StreamSubscription? _gyroSubscription;
  StreamSubscription? _accelSubscription;
  Timer? _dbTimer;
  
  int? currentTripId;

  @override
  void onInit() {
    super.onInit();
    startAnalytics();
  }

  void startAnalytics() async {
    // Start a new trip in offline database
    final db = DatabaseHelper();
    currentTripId = await db.insertTrip(
      DateTime.now().millisecondsSinceEpoch,
    );

    // Monitor Gyroscope for Lean Angle (Simplified visualization)
    _gyroSubscription = gyroscopeEventStream().listen((GyroscopeEvent event) {
      double lean = (event.y * 57.2958).abs(); 
      if (lean > 60) lean = 60; // Cap visual to reasonable number
      currentLeanAngle.value = lean;
      if (lean > maxLeanAngle.value) {
        maxLeanAngle.value = lean;
      }
    });

    // Monitor G-Force
    _accelSubscription = userAccelerometerEventStream().listen((UserAccelerometerEvent event) {
      double gForce = sqrt(pow(event.x, 2) + pow(event.y, 2) + pow(event.z, 2)) / 9.81;
      currentGForce.value = gForce;
    });

    // Log GPS Route Points every 10 seconds for breadcrumb tracking
    _dbTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      final bleController = Get.find<BleController>();
      if (bleController.myLocation.value != null && currentTripId != null) {
        db.insertRoutePoint(
          currentTripId!, 
          bleController.myLocation.value!.latitude, 
          bleController.myLocation.value!.longitude
        );
      }
    });
  }

  @override
  void onClose() {
    _gyroSubscription?.cancel();
    _accelSubscription?.cancel();
    _dbTimer?.cancel();
    
    // Finalize trip
    if (currentTripId != null) {
      DatabaseHelper().updateTripEnd(currentTripId!, DateTime.now().millisecondsSinceEpoch, maxLeanAngle.value);
    }
    super.onClose();
  }
}
