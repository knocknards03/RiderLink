import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controllers/auth_controller.dart';
import '../controllers/ble_controller.dart';
import '../controllers/analytics_controller.dart';
import '../controllers/settings_controller.dart';
import 'login_screen.dart';
import 'profile_screen.dart';
import 'trip_replay_screen.dart';
import 'garage_screen.dart';

/// QuickTogglePanel — a bottom-sheet style overlay that slides up from the map.
/// Shows:
///   • Rider avatar + name + online status
///   • One-tap toggles for Glove Mode, Voice Nav, Curvy Routes, Follow Mode
///   • Live telemetry snapshot (speed, lean, G-force)
///   • Quick navigation links
///   • Logout button
///
/// Call [QuickTogglePanel.show()] to display it.
class QuickTogglePanel {
  static void show({required bool followMode, required VoidCallback onToggleFollow}) {
    Get.bottomSheet(
      _QuickToggleContent(
        followMode: followMode,
        onToggleFollow: onToggleFollow,
      ),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      enterBottomSheetDuration: const Duration(milliseconds: 280),
      exitBottomSheetDuration: const Duration(milliseconds: 220),
    );
  }
}

class _QuickToggleContent extends StatelessWidget {
  final bool followMode;
  final VoidCallback onToggleFollow;

  const _QuickToggleContent({
    required this.followMode,
    required this.onToggleFollow,
  });

  @override
  Widget build(BuildContext context) {
    final auth     = Get.find<AuthController>();
    final ble      = Get.find<BleController>();
    final analytics = Get.find<AnalyticsController>();
    final settings = Get.find<SettingsController>();

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF141414),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: 40, height: 4,
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // ── Rider card ────────────────────────────────────────────────────
          Obx(() => _RiderCard(auth: auth, ble: ble)),

          const SizedBox(height: 20),

          // ── Live telemetry row ────────────────────────────────────────────
          Obx(() => _TelemetryRow(analytics: analytics, ble: ble)),

          const SizedBox(height: 20),

          // ── Toggle grid ───────────────────────────────────────────────────
          Obx(() => _ToggleGrid(
            settings: settings,
            followMode: followMode,
            onToggleFollow: () {
              onToggleFollow();
              Get.back(); // close panel after toggling follow
            },
          )),

          const SizedBox(height: 20),

          // ── Quick nav row ─────────────────────────────────────────────────
          _QuickNavRow(),

          const SizedBox(height: 20),

          // ── LoRa Mesh quick chat ──────────────────────────────────────────
          _MeshChatRow(ble: ble),

          const SizedBox(height: 20),

          // ── Logout ────────────────────────────────────────────────────────
          Obx(() {
            if (!auth.isLoggedIn.value) return const SizedBox.shrink();
            return SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.redAccent,
                  side: const BorderSide(color: Colors.redAccent),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.logout, size: 18),
                label: const Text('Sign Out',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                onPressed: () async {
                  Get.back();
                  await auth.logout();
                  Get.offAll(() => const LoginScreen(),
                      transition: Transition.fadeIn);
                },
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ── Rider card ────────────────────────────────────────────────────────────────

class _RiderCard extends StatelessWidget {
  final AuthController auth;
  final BleController ble;

  const _RiderCard({required this.auth, required this.ble});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          // Avatar circle with initials
          CircleAvatar(
            radius: 28,
            backgroundColor: auth.avatarColor,
            child: Text(
              auth.initials,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  auth.userName.value.isNotEmpty
                      ? auth.userName.value
                      : 'Rider',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  auth.userEmail.value,
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(children: [
                  // Blood group badge
                  if (auth.userBloodGroup.value.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.red.shade900,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        auth.userBloodGroup.value,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  const SizedBox(width: 8),
                  // BLE status dot
                  Container(
                    width: 8, height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: ble.isConnected.value
                          ? Colors.greenAccent
                          : Colors.redAccent,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    ble.isConnected.value ? 'Hardware On' : 'No Hardware',
                    style: TextStyle(
                      color: ble.isConnected.value
                          ? Colors.greenAccent
                          : Colors.redAccent,
                      fontSize: 11,
                    ),
                  ),
                ]),
              ],
            ),
          ),
          // Edit profile button
          IconButton(
            icon: const Icon(Icons.edit_outlined, color: Colors.white38),
            onPressed: () {
              Get.back();
              Get.to(() => const ProfileScreen());
            },
          ),
        ],
      ),
    );
  }
}

// ── Telemetry row ─────────────────────────────────────────────────────────────

class _TelemetryRow extends StatelessWidget {
  final AnalyticsController analytics;
  final BleController ble;

  const _TelemetryRow({required this.analytics, required this.ble});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      _TelemetryTile(
        icon: Icons.speed,
        label: 'Speed',
        value: '${ble.mySpeedKmh.value.toStringAsFixed(0)} km/h',
        color: Colors.blueAccent,
      ),
      const SizedBox(width: 10),
      _TelemetryTile(
        icon: Icons.rotate_90_degrees_ccw,
        label: 'Lean',
        value: '${analytics.currentLeanAngle.value.toStringAsFixed(1)}°',
        color: _leanColor(analytics.currentLeanAngle.value),
      ),
      const SizedBox(width: 10),
      _TelemetryTile(
        icon: Icons.bolt,
        label: 'G-Force',
        value: '${analytics.currentGForce.value.toStringAsFixed(2)}G',
        color: Colors.greenAccent,
      ),
    ]);
  }

  Color _leanColor(double lean) {
    if (lean < 20) return Colors.greenAccent;
    if (lean < 40) return Colors.yellowAccent;
    return Colors.redAccent;
  }
}

class _TelemetryTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _TelemetryTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 6),
          Text(value,
              style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  fontFamily: 'monospace')),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(color: Colors.white38, fontSize: 10)),
        ]),
      ),
    );
  }
}

// ── Toggle grid ───────────────────────────────────────────────────────────────

class _ToggleGrid extends StatelessWidget {
  final SettingsController settings;
  final bool followMode;
  final VoidCallback onToggleFollow;

  const _ToggleGrid({
    required this.settings,
    required this.followMode,
    required this.onToggleFollow,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 4,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 0.9,
      children: [
        _ToggleTile(
          icon: Icons.navigation,
          label: 'Follow',
          active: followMode,
          activeColor: const Color(0xFF4285F4),
          onTap: onToggleFollow,
        ),
        _ToggleTile(
          icon: Icons.pan_tool,
          label: 'Gloves',
          active: settings.isGloveMode.value,
          activeColor: Colors.orange,
          onTap: settings.toggleGloveMode,
        ),
        _ToggleTile(
          icon: Icons.record_voice_over,
          label: 'Voice',
          active: settings.enableVoiceNav.value,
          activeColor: Colors.purple,
          onTap: settings.toggleVoiceNav,
        ),
        _ToggleTile(
          icon: Icons.route,
          label: 'Curvy',
          active: settings.preferCurvyRoutes.value,
          activeColor: Colors.teal,
          onTap: settings.toggleCurvyRoutes,
        ),
      ],
    );
  }
}

class _ToggleTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final Color activeColor;
  final VoidCallback onTap;

  const _ToggleTile({
    required this.icon,
    required this.label,
    required this.active,
    required this.activeColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: active ? activeColor.withOpacity(0.18) : const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: active ? activeColor : Colors.white12,
            width: 1.5,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                color: active ? activeColor : Colors.white38,
                size: 24),
            const SizedBox(height: 6),
            Text(label,
                style: TextStyle(
                  color: active ? activeColor : Colors.white38,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                )),
          ],
        ),
      ),
    );
  }
}

// ── Quick nav row ─────────────────────────────────────────────────────────────

class _QuickNavRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(children: [
      _NavTile(
        icon: Icons.history,
        label: 'Trips',
        onTap: () { Get.back(); Get.to(() => const TripReplayScreen()); },
      ),
      const SizedBox(width: 10),
      _NavTile(
        icon: Icons.garage_outlined,
        label: 'Garage',
        onTap: () { Get.back(); Get.to(() => const GarageScreen()); },
      ),
      const SizedBox(width: 10),
      _NavTile(
        icon: Icons.person_outline,
        label: 'Profile',
        onTap: () { Get.back(); Get.to(() => const ProfileScreen()); },
      ),
    ]);
  }
}

class _NavTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _NavTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(children: [
            Icon(icon, color: Colors.white60, size: 22),
            const SizedBox(height: 6),
            Text(label,
                style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 11,
                    fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
    );
  }
}

// ── LoRa Mesh quick chat row ──────────────────────────────────────────────────

class _MeshChatRow extends StatelessWidget {
  final BleController ble;
  const _MeshChatRow({required this.ble});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 10),
          child: Text(
            'QUICK CHAT  ·  LoRa Mesh',
            style: TextStyle(
              color: Colors.white38,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
        ),
        Row(children: [
          _ChatChip(
            icon: Icons.local_gas_station,
            label: 'Need Fuel',
            color: Colors.orange,
            onTap: () { Get.back(); ble.sendMeshMessage('I need fuel soon!'); },
          ),
          const SizedBox(width: 8),
          _ChatChip(
            icon: Icons.back_hand,
            label: 'Wait Up',
            color: Colors.blueAccent,
            onTap: () { Get.back(); ble.sendMeshMessage('Wait for me!'); },
          ),
          const SizedBox(width: 8),
          _ChatChip(
            icon: Icons.local_police,
            label: 'Cop Ahead',
            color: Colors.redAccent,
            onTap: () { Get.back(); ble.sendMeshMessage('Police checkpoint ahead!'); },
          ),
          const SizedBox(width: 8),
          _ChatChip(
            icon: Icons.thumb_up,
            label: 'Clear',
            color: Colors.greenAccent,
            onTap: () { Get.back(); ble.sendMeshMessage('Road is clear!'); },
          ),
        ]),
      ],
    );
  }
}

class _ChatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ChatChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Column(children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 9,
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
          ]),
        ),
      ),
    );
  }
}
