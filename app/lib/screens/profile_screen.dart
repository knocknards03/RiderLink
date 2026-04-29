import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:get/get.dart';
import '../controllers/auth_controller.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _nameCtrl      = TextEditingController();
  final _primaryCtrl   = TextEditingController();
  final _emergencyCtrl = TextEditingController();
  final _bloodCtrl     = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _nameCtrl.text      = prefs.getString('name') ?? '';
      _primaryCtrl.text   = prefs.getString('primary_contact') ?? '';
      _emergencyCtrl.text = prefs.getString('emergency_contact') ?? '';
      _bloodCtrl.text     = prefs.getString('blood_group') ?? '';
    });
  }

  Future<void> _saveProfile() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('name', _nameCtrl.text);
    await prefs.setString('primary_contact', _primaryCtrl.text);
    await prefs.setString('emergency_contact', _emergencyCtrl.text);
    await prefs.setString('blood_group', _bloodCtrl.text);

    // Keep AuthController reactive state in sync so the quick-toggle
    // panel shows the updated name/blood group immediately
    try {
      final auth = Get.find<AuthController>();
      auth.userName.value       = _nameCtrl.text;
      auth.userBloodGroup.value = _bloodCtrl.text;
      auth.userEmergency.value  = _emergencyCtrl.text;
      auth.userPhone.value      = _primaryCtrl.text;
    } catch (_) {
      // AuthController may not be registered in all test contexts
    }

    Get.snackbar(
      "Saved",
      "Profile updated.",
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: Colors.green,
      colorText: Colors.white,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF141414),
        foregroundColor: Colors.white,
        title: const Text('Rider Profile',
            style: TextStyle(fontWeight: FontWeight.w700)),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Avatar
          Center(
            child: Obx(() {
              try {
                final auth = Get.find<AuthController>();
                return CircleAvatar(
                  radius: 44,
                  backgroundColor: auth.avatarColor,
                  child: Text(
                    auth.initials,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 28),
                  ),
                );
              } catch (_) {
                return const CircleAvatar(
                  radius: 44,
                  backgroundColor: Colors.grey,
                  child: Icon(Icons.person, size: 44, color: Colors.white),
                );
              }
            }),
          ),
          const SizedBox(height: 28),
          _darkField(_nameCtrl,      'Full Name',             Icons.person_outline),
          const SizedBox(height: 14),
          _darkField(_bloodCtrl,     'Blood Group (e.g. O+)', Icons.bloodtype_outlined),
          const SizedBox(height: 14),
          _darkField(_primaryCtrl,   'Primary Contact No.',   Icons.phone_outlined,
              type: TextInputType.phone),
          const SizedBox(height: 14),
          _darkField(_emergencyCtrl, 'Emergency Contact No.', Icons.emergency_outlined,
              type: TextInputType.phone),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _saveProfile,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text('Save Profile',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _darkField(
    TextEditingController ctrl,
    String label,
    IconData icon, {
    TextInputType type = TextInputType.text,
  }) {
    return TextField(
      controller: ctrl,
      keyboardType: type,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white38),
        prefixIcon: Icon(icon, color: Colors.white38, size: 20),
        filled: true,
        fillColor: const Color(0xFF1E1E1E),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
        ),
      ),
    );
  }
}
