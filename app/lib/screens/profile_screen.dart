import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:get/get.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  // Controllers bind inputs to the text fields so we can extract their values out smoothly
  final _nameCtrl = TextEditingController();
  final _primaryCtrl = TextEditingController();
  final _emergencyCtrl = TextEditingController();
  final _bloodCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Fetch previously saved data as soon as the screen attempts to load
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    // Connect to the device's secure local cache memory
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      // Auto-populate the text files. If no data exists, fall back to an empty string ''
      _nameCtrl.text = prefs.getString('name') ?? '';
      _primaryCtrl.text = prefs.getString('primary_contact') ?? '';
      _emergencyCtrl.text = prefs.getString('emergency_contact') ?? '';
      _bloodCtrl.text = prefs.getString('blood_group') ?? '';
    });
  }

  Future<void> _saveProfile() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Save the contents of every text box into internal device memory
    await prefs.setString('name', _nameCtrl.text);
    await prefs.setString('primary_contact', _primaryCtrl.text);
    await prefs.setString('emergency_contact', _emergencyCtrl.text);
    await prefs.setString('blood_group', _bloodCtrl.text);
    
    // Use the GetX UI library to render a slick pop-up confirmation at the bottom screen
    Get.snackbar("Success", "Profile details saved securely.",
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.green,
        colorText: Colors.white);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Rider Profile')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
            const Icon(Icons.account_circle, size: 100, color: Colors.grey),
            const SizedBox(height: 20),
            
            // Re-usable input boxes tailored exactly for gathering Text and Numbers securely
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: 'Full Name', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _bloodCtrl,
              decoration: const InputDecoration(labelText: 'Blood Group (e.g. O+)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _primaryCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Primary Contact No.', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _emergencyCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Emergency Contact No.', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 32),
            
            // Prominent save button triggering our Async save functions 
            ElevatedButton(
              onPressed: _saveProfile,
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.pink,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16)
              ),
              child: const Text('Save Profile', style: TextStyle(fontSize: 18)),
            )
          ],
        ),
      ),
    );
  }
}
