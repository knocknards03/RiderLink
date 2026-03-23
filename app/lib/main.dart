import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'screens/splash_screen.dart'; // Changed from map_screen.dart
import 'controllers/ble_controller.dart';
import 'controllers/safety_controller.dart';
import 'controllers/analytics_controller.dart';
import 'controllers/settings_controller.dart';
import 'db/database_helper.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Database
  await DatabaseHelper().database;

  // Initialize BLE Controller (Global Singleton)
  Get.put(BleController());
  
  // Initialize Safety Controller (Crash Detection)
  Get.put(SafetyController());

  // Initialize Analytics Controller (Telemetry & GPX log)
  Get.put(AnalyticsController());

  // Initialize Settings Controller (Glove Mode, UI scale)
  Get.put(SettingsController());

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'RiderLink',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFE91E63)), // Premium color
        useMaterial3: true,
      ),
      home: const SplashScreen(),
    );
  }
}
