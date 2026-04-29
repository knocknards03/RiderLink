import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'ble_controller.dart';

class SafetyController extends GetxController {
  // Threshold in m/s² — 8G ≈ 78.5 m/s².
  // userAccelerometerEventStream removes gravity, so 78.5 m/s² represents a
  // genuine high-impact event. Normal road bumps rarely exceed 3–4G (29–39 m/s²).
  static const double _crashThresholdMs2 = 78.5;

  // Require this many consecutive above-threshold samples before triggering.
  // At 100ms sampling, 3 samples = 300ms of sustained impact — filters out
  // single-spike false positives from potholes or phone drops.
  static const int _debounceCount = 3;

  StreamSubscription? _accelSubscription;
  Timer? _sosTimer;
  final RxBool isCrashDetected = false.obs;
  final RxInt countdown = 15.obs;

  int _consecutiveHighImpactSamples = 0;

  @override
  void onInit() {
    super.onInit();
    startMonitoring();
  }

  void startMonitoring() {
    _accelSubscription = userAccelerometerEventStream(
      samplingPeriod: const Duration(milliseconds: 100),
    ).listen((UserAccelerometerEvent event) {
      final double magnitude =
          sqrt(pow(event.x, 2) + pow(event.y, 2) + pow(event.z, 2));

      if (magnitude > _crashThresholdMs2) {
        _consecutiveHighImpactSamples++;
        if (_consecutiveHighImpactSamples >= _debounceCount &&
            !isCrashDetected.value) {
          _triggerCrashSequence();
        }
      } else {
        // Reset debounce counter on any below-threshold reading
        _consecutiveHighImpactSamples = 0;
      }
    });
  }

  void _triggerCrashSequence() {
    isCrashDetected.value = true;
    _consecutiveHighImpactSamples = 0;
    countdown.value = 15;

    Get.defaultDialog(
      title: "CRASH DETECTED",
      titleStyle: const TextStyle(
          color: Colors.red, fontWeight: FontWeight.bold, fontSize: 24),
      backgroundColor: Colors.black87,
      barrierDismissible: false,
      content: Obx(() => Column(
            children: [
              const Text(
                "High impact detected! Sending SOS in:",
                style: TextStyle(color: Colors.white, fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              Text(
                "${countdown.value}s",
                style: const TextStyle(
                    color: Colors.redAccent,
                    fontSize: 48,
                    fontWeight: FontWeight.bold),
              ),
            ],
          )),
      confirm: ElevatedButton(
        style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            minimumSize: const Size(double.infinity, 50)),
        onPressed: _cancelCrashSequence,
        child: const Text("I'M OKAY - CANCEL",
            style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold)),
      ),
    );

    _sosTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (countdown.value > 1) {
        countdown.value--;
      } else {
        _sosTimer?.cancel();
        if (Get.isDialogOpen == true) Get.back();
        _sendSosCommand();
      }
    });
  }

  void _cancelCrashSequence() {
    _sosTimer?.cancel();
    isCrashDetected.value = false;
    _consecutiveHighImpactSamples = 0;
    if (Get.isDialogOpen == true) Get.back();
    Get.snackbar("Cancelled", "SOS sequence aborted.",
        backgroundColor: Colors.orange, colorText: Colors.white);
  }

  void _sendSosCommand() {
    isCrashDetected.value = false;
    try {
      final bleController = Get.find<BleController>();
      // Guard: only attempt SOS if BLE hardware is actually connected.
      // If disconnected, warn the user so they know the broadcast didn't go out.
      if (bleController.isConnected.value) {
        bleController.sendSOS();
      } else {
        Get.snackbar(
          "SOS — No Hardware",
          "BLE device not connected. SOS could not be broadcast to other riders.",
          backgroundColor: Colors.red,
          colorText: Colors.white,
          duration: const Duration(seconds: 8),
        );
      }
    } catch (e) {
      Get.snackbar("Error", "Could not send SOS: $e",
          backgroundColor: Colors.red, colorText: Colors.white);
    }
  }

  @override
  void onClose() {
    _accelSubscription?.cancel();
    _sosTimer?.cancel();
    super.onClose();
  }
}
