import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'screens/splash_screen.dart';
import 'controllers/auth_controller.dart';
import 'controllers/ble_controller.dart';
import 'controllers/safety_controller.dart';
import 'controllers/analytics_controller.dart';
import 'controllers/settings_controller.dart';
import 'db/database_helper.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize encrypted local database
  await DatabaseHelper().database;

  // Auth controller must be first — splash screen reads isLoggedIn to decide routing
  Get.put(AuthController());

  // Core ride controllers
  Get.put(BleController());
  Get.put(SafetyController());
  Get.put(AnalyticsController());
  Get.put(SettingsController());

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'RiderLink',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFE91E63)),
        useMaterial3: true,
      ),
      // SplashScreen checks auth state and routes to Login or Map
      home: const SplashScreen(),
    );
  }
}
