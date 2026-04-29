import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jwt_decoder/jwt_decoder.dart';

/// AuthController manages the full authentication lifecycle:
///   - Register / Login via the RiderLink backend REST API
///   - Persist the JWT in SharedPreferences so the session survives app restarts
///   - Expose reactive user state so any widget can react to login/logout
///   - Sync rider profile fields (name, blood group, emergency contact) from
///     the server response into SharedPreferences so BleController.sendSOS()
///     always has fresh data without a separate profile fetch
class AuthController extends GetxController {
  // ── Backend base URL ────────────────────────────────────────────────────────
  // Physical device: use your Mac's local WiFi IP (not 10.0.2.2 which is emulator-only)
  static const String _baseUrl = 'http://10.102.77.9:8080';

  // ── Reactive state ──────────────────────────────────────────────────────────
  final RxBool isLoggedIn   = false.obs;
  final RxBool isLoading    = false.obs;
  final RxString errorMsg   = ''.obs;

  // Rider profile fields exposed reactively so the UI can bind to them
  final RxString userName          = ''.obs;
  final RxString userEmail         = ''.obs;
  final RxString userBloodGroup    = ''.obs;
  final RxString userPhone         = ''.obs;
  final RxString userEmergency     = ''.obs;
  final RxInt    userId            = 0.obs;

  // Raw JWT — kept private; exposed only via isLoggedIn / userId
  String? _token;

  // SharedPreferences keys
  static const _kToken     = '_auth_token';
  static const _kUserId    = '_auth_user_id';
  static const _kUserName  = '_auth_user_name';
  static const _kUserEmail = '_auth_user_email';

  @override
  void onInit() {
    super.onInit();
    _restoreSession();
  }

  // ── Session persistence ─────────────────────────────────────────────────────

  /// Called at startup — restores a previously saved JWT if it hasn't expired.
  Future<void> _restoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_kToken);
    if (saved == null) return;

    // Validate expiry locally without a network round-trip
    if (JwtDecoder.isExpired(saved)) {
      await _clearSession(prefs);
      return;
    }

    _token = saved;
    final payload = JwtDecoder.decode(saved);
    userId.value    = int.tryParse(payload['sub'] ?? '0') ?? 0;
    userEmail.value = payload['email'] ?? '';
    userName.value  = prefs.getString(_kUserName) ?? '';
    isLoggedIn.value = true;

    // Refresh profile from server in the background (non-blocking)
    _refreshProfile();
  }

  Future<void> _persistSession(
    SharedPreferences prefs,
    String token,
    Map<String, dynamic> user,
  ) async {
    await prefs.setString(_kToken, token);
    await prefs.setInt(_kUserId, user['id'] as int);
    await prefs.setString(_kUserName, user['name'] as String? ?? '');
    await prefs.setString(_kUserEmail, user['email'] as String? ?? '');

    // Also write into the keys BleController.sendSOS() reads
    await prefs.setString('name', user['name'] as String? ?? '');
    await prefs.setString('blood_group', user['blood_group'] as String? ?? '');
    await prefs.setString('emergency_contact', user['emergency_contact'] as String? ?? '');
  }

  Future<void> _clearSession([SharedPreferences? prefs]) async {
    prefs ??= await SharedPreferences.getInstance();
    await prefs.remove(_kToken);
    await prefs.remove(_kUserId);
    await prefs.remove(_kUserName);
    await prefs.remove(_kUserEmail);
    _token = null;
    isLoggedIn.value = false;
    userId.value = 0;
    userName.value = '';
    userEmail.value = '';
    userBloodGroup.value = '';
    userPhone.value = '';
    userEmergency.value = '';
  }

  // ── API calls ───────────────────────────────────────────────────────────────

  Future<bool> register({
    required String name,
    required String email,
    required String password,
    String? phone,
    String? bloodGroup,
    String? emergencyContact,
  }) async {
    isLoading.value = true;
    errorMsg.value  = '';
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/auth/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'name': name,
          'email': email,
          'password': password,
          if (phone != null && phone.isNotEmpty) 'phone': phone,
          if (bloodGroup != null && bloodGroup.isNotEmpty) 'blood_group': bloodGroup,
          if (emergencyContact != null && emergencyContact.isNotEmpty)
            'emergency_contact': emergencyContact,
        }),
      ).timeout(const Duration(seconds: 15));

      if (res.statusCode == 201) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        await _applyAuthResponse(body);
        return true;
      } else {
        final detail = (jsonDecode(res.body) as Map)['detail'] ?? 'Registration failed';
        errorMsg.value = detail.toString();
        return false;
      }
    } catch (e) {
      errorMsg.value = 'Network error — is the backend running?';
      return false;
    } finally {
      isLoading.value = false;
    }
  }

  Future<bool> login({
    required String email,
    required String password,
  }) async {
    isLoading.value = true;
    errorMsg.value  = '';
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': password}),
      ).timeout(const Duration(seconds: 15));

      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        await _applyAuthResponse(body);
        return true;
      } else {
        final detail = (jsonDecode(res.body) as Map)['detail'] ?? 'Login failed';
        errorMsg.value = detail.toString();
        return false;
      }
    } catch (e) {
      errorMsg.value = 'Network error — is the backend running?';
      return false;
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> logout() async {
    // Best-effort server-side revocation (fire and forget)
    if (_token != null) {
      try {
        await http.post(
          Uri.parse('$_baseUrl/auth/logout'),
          headers: {'Authorization': 'Bearer $_token'},
        ).timeout(const Duration(seconds: 5));
      } catch (_) {
        // Ignore network errors on logout — local session is cleared regardless
      }
    }
    await _clearSession();
  }

  Future<void> _applyAuthResponse(Map<String, dynamic> body) async {
    final token = body['token'] as String;
    final user  = body['user']  as Map<String, dynamic>;

    _token = token;
    userId.value        = user['id'] as int;
    userName.value      = user['name'] as String? ?? '';
    userEmail.value     = user['email'] as String? ?? '';
    userBloodGroup.value = user['blood_group'] as String? ?? '';
    userPhone.value     = user['phone'] as String? ?? '';
    userEmergency.value = user['emergency_contact'] as String? ?? '';
    isLoggedIn.value    = true;

    final prefs = await SharedPreferences.getInstance();
    await _persistSession(prefs, token, user);
  }

  Future<void> _refreshProfile() async {
    if (_token == null) return;
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/auth/me'),
        headers: {'Authorization': 'Bearer $_token'},
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final user = jsonDecode(res.body) as Map<String, dynamic>;
        userName.value       = user['name'] as String? ?? userName.value;
        userBloodGroup.value = user['blood_group'] as String? ?? '';
        userPhone.value      = user['phone'] as String? ?? '';
        userEmergency.value  = user['emergency_contact'] as String? ?? '';

        // Keep SharedPreferences in sync
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('name', userName.value);
        await prefs.setString('blood_group', userBloodGroup.value);
        await prefs.setString('emergency_contact', userEmergency.value);
      }
    } catch (_) {
      // Silent — profile refresh is best-effort
    }
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  /// Returns the initials for the avatar (e.g. "Ashwin K P" → "AK")
  String get initials {
    final parts = userName.value.trim().split(' ');
    if (parts.isEmpty || parts[0].isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  Color get avatarColor {
    // Deterministic colour from user id so it's consistent across sessions
    final colors = [
      Colors.deepPurple, Colors.indigo, Colors.blue,
      Colors.teal, Colors.green, Colors.orange, Colors.pink,
    ];
    return colors[userId.value % colors.length];
  }
}
