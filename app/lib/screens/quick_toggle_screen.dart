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
import 'community_screen.dart';

/// Slide-up bottom sheet with rider info, live telemetry, quick toggles,
/// mesh chat and sign-out. Open it via [QuickTogglePanel.show()].
class QuickTogglePanel {
  static void show({
    required bool followMode,
    required VoidCallback onToggleFollow,
  }) {
    Get.bottomSheet(
      _QuickToggleSheet(
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

// ─────────────────────────────────────────────────────────────────────────────
// Root sheet widget — uses GetBuilder-style direct Get.find so every Obx
// wraps only the smallest reactive subtree.
// ─────────────────────────────────────────────────────────────────────────────

class _QuickToggleSheet extends StatelessWidget {
  final bool followMode;
  final VoidCallback onToggleFollow;

  const _QuickToggleSheet({
    required this.followMode,
    required this.onToggleFollow,
  });

  @override
  Widget build(BuildContext context) {
    // Resolve controllers once here — safe because we're in a StatelessWidget
    // build, not inside an Obx closure.
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
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Drag handle ───────────────────────────────────────────────
            Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // ── Rider card ────────────────────────────────────────────────
            _buildRiderCard(auth, ble),
            const SizedBox(height: 20),

            // ── Live telemetry ────────────────────────────────────────────
            _buildTelemetry(analytics, ble),
            const SizedBox(height: 20),

            // ── Toggle grid ───────────────────────────────────────────────
            _buildToggleGrid(settings),
            const SizedBox(height: 20),

            // ── Quick nav ─────────────────────────────────────────────────
            _buildQuickNav(),
            const SizedBox(height: 20),

            // ── Mesh chat ─────────────────────────────────────────────────
            _buildMeshChat(ble),
            const SizedBox(height: 20),

            // ── Sign out ──────────────────────────────────────────────────
            _buildSignOut(auth),
          ],
        ),
      ),
    );
  }

  // ── Rider card ─────────────────────────────────────────────────────────────

  Widget _buildRiderCard(AuthController auth, BleController ble) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          // Avatar — reactive to name/id changes
          Obx(() => CircleAvatar(
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
          )),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Name
                Obx(() => Text(
                  auth.userName.value.isNotEmpty ? auth.userName.value : 'Rider',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                )),
                const SizedBox(height: 2),
                // Email
                Obx(() => Text(
                  auth.userEmail.value,
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                )),
                const SizedBox(height: 4),
                Row(children: [
                  // Blood group badge
                  Obx(() {
                    if (auth.userBloodGroup.value.isEmpty) {
                      return const SizedBox.shrink();
                    }
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.red.shade900,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        auth.userBloodGroup.value,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    );
                  }),
                  const SizedBox(width: 8),
                  // BLE status dot
                  Obx(() => Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
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
                    ],
                  )),
                ]),
              ],
            ),
          ),
          // Edit profile
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

  // ── Telemetry row ──────────────────────────────────────────────────────────

  Widget _buildTelemetry(AnalyticsController analytics, BleController ble) {
    return Row(children: [
      // Speed
      Expanded(child: Obx(() => _telemetryTile(
        Icons.speed,
        '${ble.mySpeedKmh.value.toStringAsFixed(0)} km/h',
        'Speed',
        Colors.blueAccent,
      ))),
      const SizedBox(width: 10),
      // Lean
      Expanded(child: Obx(() {
        final lean = analytics.currentLeanAngle.value;
        final color = lean < 20
            ? Colors.greenAccent
            : lean < 40
                ? Colors.yellowAccent
                : Colors.redAccent;
        return _telemetryTile(
          Icons.rotate_90_degrees_ccw,
          '${lean.toStringAsFixed(1)}°',
          'Lean',
          color,
        );
      })),
      const SizedBox(width: 10),
      // G-Force
      Expanded(child: Obx(() => _telemetryTile(
        Icons.bolt,
        '${analytics.currentGForce.value.toStringAsFixed(2)}G',
        'G-Force',
        Colors.greenAccent,
      ))),
    ]);
  }

  Widget _telemetryTile(IconData icon, String value, String label, Color color) {
    return Container(
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
    );
  }

  // ── Toggle grid ────────────────────────────────────────────────────────────

  Widget _buildToggleGrid(SettingsController settings) {
    return GridView.count(
      crossAxisCount: 4,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 0.9,
      children: [
        // Follow mode — plain bool, no Obx needed
        _toggleTile(
          icon: Icons.navigation,
          label: 'Follow',
          active: followMode,
          activeColor: const Color(0xFF4285F4),
          onTap: () {
            onToggleFollow();
            Get.back();
          },
        ),
        // Glove mode
        Obx(() => _toggleTile(
          icon: Icons.pan_tool,
          label: 'Gloves',
          active: settings.isGloveMode.value,
          activeColor: Colors.orange,
          onTap: settings.toggleGloveMode,
        )),
        // Voice nav
        Obx(() => _toggleTile(
          icon: Icons.record_voice_over,
          label: 'Voice',
          active: settings.enableVoiceNav.value,
          activeColor: Colors.purple,
          onTap: settings.toggleVoiceNav,
        )),
        // Curvy routes
        Obx(() => _toggleTile(
          icon: Icons.route,
          label: 'Curvy',
          active: settings.preferCurvyRoutes.value,
          activeColor: Colors.teal,
          onTap: settings.toggleCurvyRoutes,
        )),
      ],
    );
  }

  Widget _toggleTile({
    required IconData icon,
    required String label,
    required bool active,
    required Color activeColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: active
              ? activeColor.withOpacity(0.18)
              : const Color(0xFF1E1E1E),
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

  // ── Quick nav ──────────────────────────────────────────────────────────────

  Widget _buildQuickNav() {
    return Row(children: [
      _navTile(Icons.history, 'Trips',
          () { Get.back(); Get.to(() => const TripReplayScreen()); }),
      const SizedBox(width: 10),
      _navTile(Icons.garage_outlined, 'Garage',
          () { Get.back(); Get.to(() => const GarageScreen()); }),
      const SizedBox(width: 10),
      _navTile(Icons.group, 'Community',
          () { Get.back(); Get.to(() => const CommunityScreen()); }),
      const SizedBox(width: 10),
      _navTile(Icons.person_outline, 'Profile',
          () { Get.back(); Get.to(() => const ProfileScreen()); }),
    ]);
  }

  Widget _navTile(IconData icon, String label, VoidCallback onTap) {
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

  // ── Mesh chat ──────────────────────────────────────────────────────────────

  Widget _buildMeshChat(BleController ble) {
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
          _chatChip(Icons.local_gas_station, 'Need Fuel', Colors.orange,
              () { Get.back(); ble.sendMeshMessage('I need fuel soon!'); }),
          const SizedBox(width: 8),
          _chatChip(Icons.back_hand, 'Wait Up', Colors.blueAccent,
              () { Get.back(); ble.sendMeshMessage('Wait for me!'); }),
          const SizedBox(width: 8),
          _chatChip(Icons.local_police, 'Cop Ahead', Colors.redAccent,
              () { Get.back(); ble.sendMeshMessage('Police checkpoint ahead!'); }),
          const SizedBox(width: 8),
          _chatChip(Icons.thumb_up, 'Clear', Colors.greenAccent,
              () { Get.back(); ble.sendMeshMessage('Road is clear!'); }),
        ]),
      ],
    );
  }

  Widget _chatChip(
      IconData icon, String label, Color color, VoidCallback onTap) {
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

  // ── Sign out ───────────────────────────────────────────────────────────────

  Widget _buildSignOut(AuthController auth) {
    return Obx(() {
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
    });
  }
}
