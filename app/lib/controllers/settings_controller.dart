import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsController extends GetxController {
  final RxBool isGloveMode = false.obs;
  final RxBool preferCurvyRoutes = false.obs;
  final RxBool enableVoiceNav = true.obs;

  @override
  void onInit() {
    super.onInit();
    _loadSettings();
  }

  void _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    isGloveMode.value = prefs.getBool('glove_mode') ?? false;
    preferCurvyRoutes.value = prefs.getBool('curvy_routes') ?? false;
    enableVoiceNav.value = prefs.getBool('voice_nav') ?? true;
  }

  void toggleGloveMode() async {
    isGloveMode.value = !isGloveMode.value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('glove_mode', isGloveMode.value);
  }

  void toggleCurvyRoutes() async {
    preferCurvyRoutes.value = !preferCurvyRoutes.value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('curvy_routes', preferCurvyRoutes.value);
  }

  void toggleVoiceNav() async {
    enableVoiceNav.value = !enableVoiceNav.value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('voice_nav', enableVoiceNav.value);
  }
  
  // Placeholder for voice Turn-by-Turn engine
  void speakInstruction(String text) {
     if (!enableVoiceNav.value) return;
     // In a real app, use flutter_tts here
     // print("TTS: $text");
  }
}
