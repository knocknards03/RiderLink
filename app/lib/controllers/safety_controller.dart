import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'ble_controller.dart';

class SafetyController extends GetxController {
  // ── Thresholds ──────────────────────────────────────────────────────────────
  // 8G ≈ 78.5 m/s² — genuine high-impact crash threshold.
  // Normal road bumps rarely exceed 3–4G (29–39 m/s²).
  static const double _crashThresholdMs2 = 78.5;

  // 3 consecutive samples at 100 ms = 300 ms of sustained impact.
  // Filters single-spike false positives from potholes / phone drops.
  static const int _debounceCount = 3;

  // ── Reactive state (used by map screen for persistent indicator) ────────────
  final RxBool  isCrashDetected   = false.obs;
  final RxBool  isMonitoring      = true.obs;
  final RxInt   countdown         = 15.obs;
  final RxDouble peakImpactG      = 0.0.obs;  // highest G recorded this session
  final RxInt   crashesDetected   = 0.obs;    // total crashes this session

  StreamSubscription? _accelSubscription;
  Timer? _sosTimer;
  int _consecutiveHighImpactSamples = 0;

  @override
  void onInit() {
    super.onInit();
    startMonitoring();
  }

  // ── Monitoring ──────────────────────────────────────────────────────────────

  void startMonitoring() {
    isMonitoring.value = true;
    _accelSubscription = userAccelerometerEventStream(
      samplingPeriod: const Duration(milliseconds: 100),
    ).listen((UserAccelerometerEvent event) {
      final double magnitude =
          sqrt(pow(event.x, 2) + pow(event.y, 2) + pow(event.z, 2));

      // Track peak G for the telemetry HUD
      final gValue = magnitude / 9.81;
      if (gValue > peakImpactG.value) peakImpactG.value = gValue;

      if (magnitude > _crashThresholdMs2) {
        _consecutiveHighImpactSamples++;
        if (_consecutiveHighImpactSamples >= _debounceCount &&
            !isCrashDetected.value) {
          _triggerCrashSequence(magnitude);
        }
      } else {
        _consecutiveHighImpactSamples = 0;
      }
    });
  }

  void stopMonitoring() {
    isMonitoring.value = false;
    _accelSubscription?.cancel();
    _accelSubscription = null;
  }

  void toggleMonitoring() {
    if (isMonitoring.value) {
      stopMonitoring();
      Get.snackbar('Crash Detection Off', 'Tap again to re-enable.',
          backgroundColor: Colors.orange, colorText: Colors.white,
          duration: const Duration(seconds: 3));
    } else {
      startMonitoring();
      Get.snackbar('Crash Detection On', 'Monitoring for impacts.',
          backgroundColor: Colors.green, colorText: Colors.white,
          duration: const Duration(seconds: 2));
    }
  }

  // ── Crash sequence ──────────────────────────────────────────────────────────

  void _triggerCrashSequence(double impactMs2) {
    isCrashDetected.value = true;
    crashesDetected.value++;
    _consecutiveHighImpactSamples = 0;
    countdown.value = 15;

    Get.defaultDialog(
      title: "⚠ CRASH DETECTED",
      titleStyle: const TextStyle(
          color: Colors.red, fontWeight: FontWeight.bold, fontSize: 22),
      backgroundColor: Colors.black,
      barrierDismissible: false,
      content: Obx(() => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "High impact detected!\nSending SOS to your group in:",
                style: TextStyle(color: Colors.white70, fontSize: 15),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              // Countdown ring
              Stack(alignment: Alignment.center, children: [
                SizedBox(
                  width: 90, height: 90,
                  child: CircularProgressIndicator(
                    value: countdown.value / 15.0,
                    strokeWidth: 6,
                    backgroundColor: Colors.white12,
                    color: countdown.value > 5
                        ? Colors.orangeAccent
                        : Colors.redAccent,
                  ),
                ),
                Text(
                  '${countdown.value}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 36,
                      fontWeight: FontWeight.bold),
                ),
              ]),
              const SizedBox(height: 12),
              Text(
                'Impact: ${(impactMs2 / 9.81).toStringAsFixed(1)}G',
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ],
          )),
      confirm: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            minimumSize: const Size(double.infinity, 52),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12))),
        icon: const Icon(Icons.check_circle, color: Colors.white),
        label: const Text("I'M OKAY — CANCEL",
            style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.bold)),
        onPressed: _cancelCrashSequence,
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
    Get.snackbar(
      "SOS Cancelled",
      "Glad you're okay! Crash detection continues.",
      backgroundColor: Colors.orange,
      colorText: Colors.white,
      duration: const Duration(seconds: 4),
    );
  }

  void _sendSosCommand() {
    isCrashDetected.value = false;
    try {
      final ble = Get.find<BleController>();
      if (ble.isConnected.value) {
        ble.sendSOS();
      } else {
        // No BLE hardware — show prominent warning
        Get.defaultDialog(
          title: "SOS SENT — No Hardware",
          titleStyle: const TextStyle(
              color: Colors.red, fontWeight: FontWeight.bold),
          backgroundColor: Colors.black,
          barrierDismissible: false,
          middleText:
              "BLE device not connected.\nYour SOS could NOT be broadcast over LoRa.\n\nCall emergency services directly.",
          middleTextStyle:
              const TextStyle(color: Colors.white70, fontSize: 14),
          confirm: ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: Get.back,
            child: const Text("OK", style: TextStyle(color: Colors.white)),
          ),
        );
      }
    } catch (e) {
      Get.snackbar("Error", "Could not send SOS: $e",
          backgroundColor: Colors.red, colorText: Colors.white);
    }
  }

  /// Simulate a crash — useful for demos and testing without a real impact.
  void simulateCrash() {
    if (!isCrashDetected.value) {
      _triggerCrashSequence(78.5); // exactly at threshold
    }
  }

  @override
  void onClose() {
    _accelSubscription?.cancel();
    _sosTimer?.cancel();
    super.onClose();
  }
}
