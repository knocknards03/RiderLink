import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_tts/flutter_tts.dart';

class SettingsController extends GetxController {
  final FlutterTts flutterTts = FlutterTts();
  
  final RxBool isGloveMode = false.obs;
  final RxBool preferCurvyRoutes = false.obs;
  final RxBool enableVoiceNav = true.obs;

  @override
  void onInit() {
    super.onInit();
    _loadSettings();
    flutterTts.setLanguage("en-US");
    flutterTts.setSpeechRate(0.5);
    flutterTts.setVolume(1.0);
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
    speakInstruction(isGloveMode.value ? "Glove Mode Enabled" : "Glove Mode Disabled");
  }

  void toggleCurvyRoutes() async {
    preferCurvyRoutes.value = !preferCurvyRoutes.value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('curvy_routes', preferCurvyRoutes.value);
    speakInstruction(preferCurvyRoutes.value ? "Scenic Routes Enabled" : "Scenic Routes Disabled");
  }

  void toggleVoiceNav() async {
    enableVoiceNav.value = !enableVoiceNav.value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('voice_nav', enableVoiceNav.value);
    
    // Explicitly speak this one regardless of the flag so the user knows it turned back on!
    if (enableVoiceNav.value) {
       flutterTts.speak("Voice Navigation Activated");
    }
  }
  
  // Triggers the device's native TTS engine to speak aloud
  void speakInstruction(String text) {
     if (!enableVoiceNav.value) return;
     flutterTts.speak(text);
  }
}
