import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import '../controllers/auth_controller.dart';
import 'map_screen.dart';

/// OTP verification screen — shown after login/register credentials are accepted.
/// User enters the 6-digit code sent to their email.
class OtpScreen extends StatefulWidget {
  const OtpScreen({super.key});

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final AuthController _auth = Get.find<AuthController>();

  // 6 individual digit controllers
  final List<TextEditingController> _digitCtrl =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes =
      List.generate(6, (_) => FocusNode());

  // Resend cooldown
  int _resendCountdown = 60;
  Timer? _resendTimer;

  @override
  void initState() {
    super.initState();
    _startResendTimer();
  }

  @override
  void dispose() {
    for (final c in _digitCtrl) c.dispose();
    for (final f in _focusNodes) f.dispose();
    _resendTimer?.cancel();
    super.dispose();
  }

  void _startResendTimer() {
    _resendCountdown = 60;
    _resendTimer?.cancel();
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_resendCountdown > 0) {
        setState(() => _resendCountdown--);
      } else {
        t.cancel();
      }
    });
  }

  String get _otp => _digitCtrl.map((c) => c.text).join();

  Future<void> _verify() async {
    if (_otp.length < 6) {
      Get.snackbar('Incomplete', 'Enter all 6 digits.',
          backgroundColor: Colors.orange, colorText: Colors.white);
      return;
    }
    final ok = await _auth.verifyOtp(_otp);
    if (ok) {
      Get.offAll(() => const MapScreen(), transition: Transition.fadeIn);
    }
  }

  Future<void> _resend() async {
    if (_resendCountdown > 0) return;
    // Clear all boxes
    for (final c in _digitCtrl) c.clear();
    _focusNodes[0].requestFocus();
    _auth.errorMsg.value = '';

    final ok = await _auth.sendOtp(
      email: _auth.pendingEmail.value,
      purpose: _auth.pendingPurpose.value,
    );
    if (ok) {
      _startResendTimer();
      Get.snackbar('Code Resent', 'A new OTP was sent to ${_auth.pendingEmail.value}',
          backgroundColor: Colors.green, colorText: Colors.white);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 60),

              // Icon
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.mark_email_read_outlined,
                    size: 52, color: Colors.redAccent),
              ),
              const SizedBox(height: 24),

              const Text(
                'Check your email',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),

              Obx(() => Text(
                'We sent a 6-digit code to\n${_auth.pendingEmail.value}',
                style: const TextStyle(
                    color: Colors.white54, fontSize: 14, height: 1.5),
                textAlign: TextAlign.center,
              )),

              // Dev mode hint
              Obx(() {
                if (!_auth.devMode.value) return const SizedBox.shrink();
                return Container(
                  margin: const EdgeInsets.only(top: 12),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.orange.withOpacity(0.4)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.developer_mode,
                          color: Colors.orange, size: 16),
                      SizedBox(width: 6),
                      Text(
                        'Dev mode: OTP printed in backend terminal',
                        style: TextStyle(color: Colors.orange, fontSize: 12),
                      ),
                    ],
                  ),
                );
              }),

              const SizedBox(height: 40),

              // ── 6-digit OTP boxes ──────────────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(6, (i) => _digitBox(i)),
              ),

              const SizedBox(height: 16),

              // Error message
              Obx(() {
                final err = _auth.errorMsg.value;
                if (err.isEmpty) return const SizedBox.shrink();
                return Container(
                  margin: const EdgeInsets.only(top: 4, bottom: 8),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.red.shade900.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(children: [
                    const Icon(Icons.error_outline,
                        color: Colors.redAccent, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(err,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 13)),
                    ),
                  ]),
                );
              }),

              const SizedBox(height: 28),

              // Verify button
              Obx(() => SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _auth.isLoading.value ? null : _verify,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    disabledBackgroundColor:
                        Colors.redAccent.withOpacity(0.4),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _auth.isLoading.value
                      ? const SizedBox(
                          width: 22, height: 22,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2.5))
                      : const Text(
                          'Verify & Continue',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              )),

              const SizedBox(height: 20),

              // Resend
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text("Didn't receive it? ",
                      style: TextStyle(color: Colors.white38, fontSize: 13)),
                  GestureDetector(
                    onTap: _resendCountdown == 0 ? _resend : null,
                    child: Obx(() => Text(
                      _resendCountdown > 0
                          ? 'Resend in ${_resendCountdown}s'
                          : 'Resend code',
                      style: TextStyle(
                        color: _resendCountdown > 0
                            ? Colors.white24
                            : Colors.redAccent,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    )),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Back to login
              TextButton(
                onPressed: () {
                  _auth.otpSent.value  = false;
                  _auth.errorMsg.value = '';
                  Get.back();
                },
                child: const Text(
                  '← Back to Sign In',
                  style: TextStyle(color: Colors.white38, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _digitBox(int index) {
    return SizedBox(
      width: 46,
      height: 56,
      child: TextFormField(
        controller: _digitCtrl[index],
        focusNode: _focusNodes[index],
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        maxLength: 1,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 22,
          fontWeight: FontWeight.bold,
        ),
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(
          counterText: '',
          filled: true,
          fillColor: const Color(0xFF1E1E1E),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide:
                const BorderSide(color: Colors.redAccent, width: 2),
          ),
        ),
        onChanged: (val) {
          if (val.isNotEmpty) {
            // Move to next box
            if (index < 5) {
              _focusNodes[index + 1].requestFocus();
            } else {
              // Last digit entered — auto-submit
              _focusNodes[index].unfocus();
              _verify();
            }
          } else {
            // Backspace — move to previous box
            if (index > 0) {
              _focusNodes[index - 1].requestFocus();
            }
          }
        },
      ),
    );
  }
}
