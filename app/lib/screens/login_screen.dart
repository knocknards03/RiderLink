import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controllers/auth_controller.dart';
import 'map_screen.dart';
import 'otp_screen.dart';

/// Full-screen login / register UI shown on first launch (or after logout).
/// Two tabs: Sign In and Create Account.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  final AuthController _auth = Get.find<AuthController>();

  // ── Sign-in fields ──────────────────────────────────────────────────────────
  final _loginEmailCtrl    = TextEditingController();
  final _loginPasswordCtrl = TextEditingController();
  bool _loginObscure = true;

  // ── Register fields ─────────────────────────────────────────────────────────
  final _regNameCtrl      = TextEditingController();
  final _regEmailCtrl     = TextEditingController();
  final _regPasswordCtrl  = TextEditingController();
  final _regPhoneCtrl     = TextEditingController();
  final _regBloodCtrl     = TextEditingController();
  final _regEmergencyCtrl = TextEditingController();
  bool _regObscure = true;

  final _loginFormKey = GlobalKey<FormState>();
  final _regFormKey   = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    _loginEmailCtrl.dispose();
    _loginPasswordCtrl.dispose();
    _regNameCtrl.dispose();
    _regEmailCtrl.dispose();
    _regPasswordCtrl.dispose();
    _regPhoneCtrl.dispose();
    _regBloodCtrl.dispose();
    _regEmergencyCtrl.dispose();
    super.dispose();
  }

  // ── Actions ─────────────────────────────────────────────────────────────────

  Future<void> _doLogin() async {
    if (!_loginFormKey.currentState!.validate()) return;
    final ok = await _auth.login(
      email: _loginEmailCtrl.text.trim(),
      password: _loginPasswordCtrl.text,
    );
    if (ok) {
      // Credentials valid + OTP sent → go to OTP screen
      Get.to(() => const OtpScreen(), transition: Transition.rightToLeft);
    }
  }

  Future<void> _doRegister() async {
    if (!_regFormKey.currentState!.validate()) return;
    final ok = await _auth.register(
      name: _regNameCtrl.text.trim(),
      email: _regEmailCtrl.text.trim(),
      password: _regPasswordCtrl.text,
      phone: _regPhoneCtrl.text.trim(),
      bloodGroup: _regBloodCtrl.text.trim(),
      emergencyContact: _regEmergencyCtrl.text.trim(),
    );
    if (ok) {
      // Account created + OTP sent → go to OTP screen
      Get.to(() => const OtpScreen(), transition: Transition.rightToLeft);
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ──────────────────────────────────────────────────────
            const SizedBox(height: 40),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.motorcycle, size: 56, color: Colors.redAccent),
            ),
            const SizedBox(height: 16),
            const Text(
              'RIDERLINK',
              style: TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.w800,
                letterSpacing: 4,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Your offline safety ecosystem',
              style: TextStyle(color: Colors.white38, fontSize: 12, letterSpacing: 1),
            ),
            const SizedBox(height: 32),

            // ── Tab bar ──────────────────────────────────────────────────────
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 32),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(30),
              ),
              child: TabBar(
                controller: _tabs,
                indicator: BoxDecoration(
                  color: Colors.redAccent,
                  borderRadius: BorderRadius.circular(30),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white38,
                labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                tabs: const [
                  Tab(text: 'Sign In'),
                  Tab(text: 'Create Account'),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // ── Error banner ─────────────────────────────────────────────────
            Obx(() {
              final err = _auth.errorMsg.value;
              if (err.isEmpty) return const SizedBox.shrink();
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.red.shade900.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(children: [
                  const Icon(Icons.error_outline, color: Colors.redAccent, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(err,
                        style: const TextStyle(color: Colors.white70, fontSize: 13)),
                  ),
                ]),
              );
            }),

            // ── Tab views ────────────────────────────────────────────────────
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [
                  _buildLoginTab(),
                  _buildRegisterTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Login tab ────────────────────────────────────────────────────────────────

  Widget _buildLoginTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: Form(
        key: _loginFormKey,
        child: Column(children: [
          _field(
            controller: _loginEmailCtrl,
            label: 'Email',
            icon: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
            validator: _emailValidator,
          ),
          const SizedBox(height: 14),
          _field(
            controller: _loginPasswordCtrl,
            label: 'Password',
            icon: Icons.lock_outline,
            obscure: _loginObscure,
            suffixIcon: IconButton(
              icon: Icon(
                _loginObscure ? Icons.visibility_off : Icons.visibility,
                color: Colors.white38,
              ),
              onPressed: () => setState(() => _loginObscure = !_loginObscure),
            ),
            validator: (v) => (v == null || v.isEmpty) ? 'Enter password' : null,
          ),
          const SizedBox(height: 28),
          Obx(() => _authButton(
            label: 'Sign In',
            loading: _auth.isLoading.value,
            onTap: _doLogin,
          )),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () => _tabs.animateTo(1),
            child: const Text(
              "Don't have an account? Create one →",
              style: TextStyle(color: Colors.white38, fontSize: 13),
            ),
          ),
        ]),
      ),
    );
  }

  // ── Register tab ─────────────────────────────────────────────────────────────

  Widget _buildRegisterTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: Form(
        key: _regFormKey,
        child: Column(children: [
          _field(
            controller: _regNameCtrl,
            label: 'Full Name',
            icon: Icons.person_outline,
            validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter your name' : null,
          ),
          const SizedBox(height: 14),
          _field(
            controller: _regEmailCtrl,
            label: 'Email',
            icon: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
            validator: _emailValidator,
          ),
          const SizedBox(height: 14),
          _field(
            controller: _regPasswordCtrl,
            label: 'Password (min 8 chars)',
            icon: Icons.lock_outline,
            obscure: _regObscure,
            suffixIcon: IconButton(
              icon: Icon(
                _regObscure ? Icons.visibility_off : Icons.visibility,
                color: Colors.white38,
              ),
              onPressed: () => setState(() => _regObscure = !_regObscure),
            ),
            validator: (v) {
              if (v == null || v.isEmpty) return 'Enter a password';
              if (v.length < 8) return 'Minimum 8 characters';
              return null;
            },
          ),
          const SizedBox(height: 14),
          _field(
            controller: _regPhoneCtrl,
            label: 'Phone Number',
            icon: Icons.phone_outlined,
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 14),
          _field(
            controller: _regBloodCtrl,
            label: 'Blood Group (e.g. O+)',
            icon: Icons.bloodtype_outlined,
          ),
          const SizedBox(height: 14),
          _field(
            controller: _regEmergencyCtrl,
            label: 'Emergency Contact No.',
            icon: Icons.emergency_outlined,
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 28),
          Obx(() => _authButton(
            label: 'Create Account',
            loading: _auth.isLoading.value,
            onTap: _doRegister,
          )),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () => _tabs.animateTo(0),
            child: const Text(
              'Already have an account? Sign in →',
              style: TextStyle(color: Colors.white38, fontSize: 13),
            ),
          ),
        ]),
      ),
    );
  }

  // ── Shared widgets ────────────────────────────────────────────────────────────

  Widget _field({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    bool obscure = false,
    Widget? suffixIcon,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      style: const TextStyle(color: Colors.white),
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white38),
        prefixIcon: Icon(icon, color: Colors.white38, size: 20),
        suffixIcon: suffixIcon,
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
        errorStyle: const TextStyle(color: Colors.redAccent),
      ),
    );
  }

  Widget _authButton({
    required String label,
    required bool loading,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: loading ? null : onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.redAccent,
          disabledBackgroundColor: Colors.redAccent.withOpacity(0.4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: loading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2.5,
                ),
              )
            : Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
      ),
    );
  }

  String? _emailValidator(String? v) {
    if (v == null || v.trim().isEmpty) return 'Enter your email';
    if (!RegExp(r'^[\w.+-]+@[\w-]+\.[a-z]{2,}$').hasMatch(v.trim())) {
      return 'Enter a valid email';
    }
    return null;
  }
}
