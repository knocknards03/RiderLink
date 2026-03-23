import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'ble_controller.dart';

class SafetyController extends GetxController {
  final double crashThreshold = 40.0; // Adjust as needed depending on phone mount rigidity
  StreamSubscription? _accelSubscription;
  Timer? _sosTimer;
  final RxBool isCrashDetected = false.obs;
  final RxInt countdown = 15.obs;

  @override
  void onInit() {
    super.onInit();
    startMonitoring();
  }

  void startMonitoring() {
    _accelSubscription = userAccelerometerEventStream(samplingPeriod: const Duration(milliseconds: 100)).listen((UserAccelerometerEvent event) {
      // Calculate magnitude
      double magnitude = sqrt(pow(event.x, 2) + pow(event.y, 2) + pow(event.z, 2));
      
      if (magnitude > crashThreshold && !isCrashDetected.value) {
        _triggerCrashSequence();
      }
    });
  }

  void _triggerCrashSequence() {
    isCrashDetected.value = true;
    countdown.value = 15;
    
    // Show UI dialog
    Get.defaultDialog(
      title: "CRASH DETECTED",
      titleStyle: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 24),
      backgroundColor: Colors.black87,
      barrierDismissible: false,
      content: Obx(() => Column(
        children: [
          const Text("High impact detected! Sending SOS in:", style: TextStyle(color: Colors.white, fontSize: 16), textAlign: TextAlign.center,),
          const SizedBox(height: 20),
          Text("${countdown.value}s", style: const TextStyle(color: Colors.redAccent, fontSize: 48, fontWeight: FontWeight.bold)),
        ],
      )),
      confirm: ElevatedButton(
        style: ElevatedButton.styleFrom(backgroundColor: Colors.green, minimumSize: const Size(double.infinity, 50)),
        onPressed: _cancelCrashSequence,
        child: const Text("I'M OKAY - CANCEL", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
      ),
    );

    // Start countdown timer
    _sosTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (countdown.value > 1) {
        countdown.value--;
      } else {
        // Timer reached 0, send SOS
        _sosTimer?.cancel();
        if (Get.isDialogOpen == true) {
          Get.back(); // close dialog
        }
        _sendSosCommand();
      }
    });
  }

  void _cancelCrashSequence() {
    _sosTimer?.cancel();
    isCrashDetected.value = false;
    if (Get.isDialogOpen == true) {
      Get.back(); // close dialog
    }
    Get.snackbar("Cancelled", "SOS sequence aborted.", backgroundColor: Colors.orange, colorText: Colors.white);
  }

  void _sendSosCommand() {
    isCrashDetected.value = false;
    try {
      final bleController = Get.find<BleController>();
      bleController.sendSOS();
    } catch (e) {
      Get.snackbar("Error", "Could not connect to BLE hardware to send SOS.", backgroundColor: Colors.red, colorText: Colors.white);
    }
  }

  @override
  void onClose() {
    _accelSubscription?.cancel();
    _sosTimer?.cancel();
    super.onClose();
  }
}
