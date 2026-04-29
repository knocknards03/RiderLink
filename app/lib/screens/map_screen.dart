import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:get/get.dart';
import '../controllers/ble_controller.dart';
import '../controllers/analytics_controller.dart';
import '../controllers/settings_controller.dart';
import '../utils/navigation_service.dart';
import 'quick_toggle_screen.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with TickerProviderStateMixin {
  final MapController _mapController = MapController();

  // Auto-follow: when true the map camera tracks the rider and rotates to heading
  bool _followMode = true;
  bool _hasCenteredOnLocation = false;

  // Workers stored for clean disposal
  Worker? _locationWorker;
  Worker? _headingWorker;

  // Animation controllers for smooth marker pulse
  late AnimationController _markerPulseController;

  @override
  void initState() {
    super.initState();

    _markerPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ble = Get.find<BleController>();
      final analytics = Get.find<AnalyticsController>();

      // First-center on GPS lock
      if (ble.myLocation.value != null && !_hasCenteredOnLocation) {
        _hasCenteredOnLocation = true;
        _mapController.move(ble.myLocation.value!, 17.0);
      }

      // Follow location updates
      _locationWorker = ever(ble.myLocation, (LatLng? loc) {
        if (loc == null) return;
        if (!_hasCenteredOnLocation) {
          _hasCenteredOnLocation = true;
        }
        if (_followMode) {
          _mapController.move(loc, _mapController.camera.zoom);
        }
      });

      // Rotate map to match heading in follow mode
      _headingWorker = ever(analytics.fusedHeading, (double heading) {
        if (_followMode) {
          // flutter_map rotation: negative heading so map rotates under the arrow
          _mapController.rotate(-heading);
        }
      });
    });
  }

  @override
  void dispose() {
    _locationWorker?.dispose();
    _headingWorker?.dispose();
    _markerPulseController.dispose();
    super.dispose();
  }

  void _toggleFollowMode() {
    setState(() => _followMode = !_followMode);
    if (_followMode) {
      final ble = Get.find<BleController>();
      if (ble.myLocation.value != null) {
        _mapController.move(ble.myLocation.value!, 17.0);
        final analytics = Get.find<AnalyticsController>();
        _mapController.rotate(-analytics.fusedHeading.value);
      }
    } else {
      // Reset map rotation when leaving follow mode
      _mapController.rotate(0);
    }
  }

  // Build the animated directional arrow marker for the current rider
  Widget _buildMyLocationMarker(double headingDeg) {
    return AnimatedBuilder(
      animation: _markerPulseController,
      builder: (context, child) {
        final pulse = 0.85 + 0.15 * _markerPulseController.value;
        return Stack(
          alignment: Alignment.center,
          children: [
            // Accuracy halo
            Container(
              width: 56 * pulse,
              height: 56 * pulse,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.blueAccent.withOpacity(0.18 * pulse),
                border: Border.all(
                  color: Colors.blueAccent.withOpacity(0.35),
                  width: 1.5,
                ),
              ),
            ),
            // Directional arrow — rotated to heading
            // In follow mode the map itself rotates, so the arrow always points up.
            // In free mode we rotate the arrow widget to show true heading.
            Transform.rotate(
              angle: _followMode ? 0 : headingDeg * math.pi / 180.0,
              child: CustomPaint(
                size: const Size(36, 36),
                painter: _ArrowMarkerPainter(),
              ),
            ),
          ],
        );
      },
    );
  }

  // Pit-stop button helper
  Widget _buildBreakBtn(BleController ble, String type, IconData icon) {
    return Obx(() {
      final settings = Get.find<SettingsController>();
      final glove = settings.isGloveMode.value;
      return SizedBox(
        height: glove ? 56 : 44,
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFF8C00),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
            padding: EdgeInsets.symmetric(horizontal: glove ? 16 : 12),
          ),
          icon: Icon(icon, size: glove ? 22 : 18),
          label: Text(type, style: TextStyle(fontSize: glove ? 15 : 12, fontWeight: FontWeight.w600)),
          onPressed: () => ble.sendBreak(type),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final ble = Get.find<BleController>();
    final analytics = Get.find<AnalyticsController>();
    final settings = Get.find<SettingsController>();

    return Scaffold(
      backgroundColor: Colors.black,
      // No AppBar — full-screen map like Google Maps
      body: Stack(
        children: [
          // ── MAP ──────────────────────────────────────────────────────────
          Obx(() {
            final heading = analytics.fusedHeading.value;
            return FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: ble.myLocation.value ?? const LatLng(20.5937, 78.9629),
                initialZoom: ble.myLocation.value != null ? 17.0 : 5.0,
                minZoom: 3,
                maxZoom: 19,
                // Disable map rotation gesture in follow mode to avoid fighting the auto-rotate
                interactionOptions: InteractionOptions(
                  flags: _followMode
                      ? InteractiveFlag.pinchZoom | InteractiveFlag.doubleTapZoom
                      : InteractiveFlag.all,
                ),
                onPositionChanged: (MapPosition position, bool hasGesture) {
                  // User dragged the map — exit follow mode
                  if (hasGesture && _followMode) {
                    setState(() => _followMode = false);
                    _mapController.rotate(0);
                  }
                },
                onLongPress: (tapPosition, point) async {
                  ble.destinationPin.value = point;
                  if (ble.myLocation.value != null) {
                    final route = await NavigationService.getRoute(ble.myLocation.value!, point);
                    ble.currentRoute.assignAll(route);
                    settings.speakInstruction("Route calculated. Follow the blue line.");
                  }
                },
              ),
              children: [
                // OSM tile layer
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.riderlink',
                  tileBuilder: (context, tileWidget, tile) => tileWidget,
                ),

                // Route polyline
                Obx(() {
                  if (ble.currentRoute.isEmpty) return const SizedBox.shrink();
                  return PolylineLayer(polylines: [
                    // Route shadow
                    Polyline(
                      points: ble.currentRoute.toList(),
                      color: Colors.black38,
                      strokeWidth: 10.0,
                    ),
                    // Route fill
                    Polyline(
                      points: ble.currentRoute.toList(),
                      color: const Color(0xFF4285F4),
                      strokeWidth: 7.0,
                    ),
                  ]);
                }),

                // All markers
                Obx(() {
                  final List<Marker> markers = [];

                  // Other riders — red motorcycle icons
                  for (final entry in ble.riderLocations.entries) {
                    final loc = entry.value;
                    markers.add(Marker(
                      point: LatLng(loc[0], loc[1]),
                      width: 48,
                      height: 48,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.red.shade700,
                          shape: BoxShape.circle,
                          boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 6)],
                        ),
                        child: const Icon(Icons.motorcycle, color: Colors.white, size: 26),
                      ),
                    ));
                  }

                  // Destination pin
                  if (ble.destinationPin.value != null) {
                    markers.add(Marker(
                      point: ble.destinationPin.value!,
                      width: 44,
                      height: 56,
                      child: const Icon(Icons.location_on, color: Color(0xFF34A853), size: 52),
                    ));
                  }

                  // Hazard markers
                  for (final hazard in ble.reportedHazards) {
                    markers.add(Marker(
                      point: LatLng(hazard['lat'] as double, hazard['lng'] as double),
                      width: 40,
                      height: 40,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.orange.shade800,
                          shape: BoxShape.circle,
                          boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 4)],
                        ),
                        child: const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 22),
                      ),
                    ));
                  }

                  // My location — animated directional arrow
                  if (ble.myLocation.value != null) {
                    markers.add(Marker(
                      point: ble.myLocation.value!,
                      width: 60,
                      height: 60,
                      child: _buildMyLocationMarker(heading),
                    ));
                  }

                  return MarkerLayer(markers: markers);
                }),
              ],
            );
          }),

          // ── TOP BAR ──────────────────────────────────────────────────────
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  // Quick-toggle panel button (replaces drawer)
                  GestureDetector(
                    onTap: () => QuickTogglePanel.show(
                      followMode: _followMode,
                      onToggleFollow: _toggleFollowMode,
                    ),
                    child: Container(
                      width: 44, height: 44,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8)],
                      ),
                      child: const Icon(Icons.menu, color: Colors.black87),
                    ),
                  ),
                  const SizedBox(width: 10),

                  // Speed + BLE status pill
                  Expanded(
                    child: Obx(() {
                      final speed = ble.mySpeedKmh.value;
                      final connected = ble.isConnected.value;
                      return Container(
                        height: 44,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(22),
                          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8)],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(children: [
                              const Icon(Icons.speed, size: 18, color: Color(0xFF4285F4)),
                              const SizedBox(width: 6),
                              Text(
                                "${speed.toStringAsFixed(0)} km/h",
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                              ),
                            ]),
                            Row(children: [
                              Icon(
                                connected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                                size: 16,
                                color: connected ? Colors.green : Colors.red,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                connected ? "LoRa" : "No HW",
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: connected ? Colors.green : Colors.red,
                                ),
                              ),
                            ]),
                          ],
                        ),
                      );
                    }),
                  ),
                  const SizedBox(width: 10),

                  // SOS button
                  Obx(() {
                    final glove = settings.isGloveMode.value;
                    return GestureDetector(
                      onTap: () => ble.sendSOS(),
                      child: Container(
                        width: glove ? 64 : 52,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: const [BoxShadow(color: Colors.red, blurRadius: 8, spreadRadius: 1)],
                        ),
                        child: Center(
                          child: Text(
                            "SOS",
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: glove ? 16 : 13,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),

          // ── TELEMETRY HUD (top-right) ─────────────────────────────────────
          Positioned(
            top: 80,
            right: 12,
            child: SafeArea(
              child: Obx(() {
                final lean = analytics.currentLeanAngle.value;
                final maxLean = analytics.maxLeanAngle.value;
                final gForce = analytics.currentGForce.value;
                final heading = analytics.fusedHeading.value;

                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.78),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white12),
                    boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 10)],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _hudRow(Icons.rotate_90_degrees_ccw, "Lean",
                          "${lean.toStringAsFixed(1)}°", _leanColor(lean)),
                      const SizedBox(height: 4),
                      _hudRow(Icons.arrow_upward, "Max",
                          "${maxLean.toStringAsFixed(1)}°", Colors.redAccent),
                      const SizedBox(height: 4),
                      _hudRow(Icons.bolt, "G",
                          "${gForce.toStringAsFixed(2)}G", Colors.greenAccent),
                      const SizedBox(height: 4),
                      _hudRow(Icons.explore, "HDG",
                          "${heading.toStringAsFixed(0)}°", Colors.cyanAccent),
                    ],
                  ),
                );
              }),
            ),
          ),

          // ── RIGHT SIDE BUTTONS ────────────────────────────────────────────
          Positioned(
            right: 12,
            bottom: 120,
            child: Column(
              children: [
                // Follow / free mode toggle
                _mapBtn(
                  icon: _followMode ? Icons.navigation : Icons.navigation_outlined,
                  color: _followMode ? const Color(0xFF4285F4) : Colors.white,
                  iconColor: _followMode ? Colors.white : Colors.black87,
                  onTap: _toggleFollowMode,
                  tooltip: _followMode ? "Following" : "Free View",
                ),
                const SizedBox(height: 10),
                // Zoom in
                _mapBtn(
                  icon: Icons.add,
                  onTap: () => _mapController.move(
                    _mapController.camera.center,
                    (_mapController.camera.zoom + 1).clamp(3, 19),
                  ),
                ),
                const SizedBox(height: 6),
                // Zoom out
                _mapBtn(
                  icon: Icons.remove,
                  onTap: () => _mapController.move(
                    _mapController.camera.center,
                    (_mapController.camera.zoom - 1).clamp(3, 19),
                  ),
                ),
                const SizedBox(height: 10),
                // Hazard report
                _mapBtn(
                  icon: Icons.report_problem,
                  color: Colors.orange.shade700,
                  iconColor: Colors.white,
                  onTap: _showHazardSheet,
                  tooltip: "Report Hazard",
                ),
                const SizedBox(height: 10),
                // Logs
                _mapBtn(
                  icon: Icons.terminal,
                  onTap: _showLogsDialog,
                  tooltip: "Logs",
                ),
              ],
            ),
          ),

          // ── BOTTOM CONTROLS ───────────────────────────────────────────────
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 16, offset: Offset(0, -4))],
              ),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Drag handle
                  Container(
                    width: 40, height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  // Pit stop row
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(children: [
                      _buildBreakBtn(ble, "Tea", Icons.local_cafe),
                      const SizedBox(width: 8),
                      _buildBreakBtn(ble, "Breakfast", Icons.restaurant),
                      const SizedBox(width: 8),
                      _buildBreakBtn(ble, "Lunch", Icons.lunch_dining),
                      const SizedBox(width: 8),
                      _buildBreakBtn(ble, "Dinner", Icons.dinner_dining),
                    ]),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),

      // No drawer — quick-toggle panel is opened via the menu button in the top bar
    );
  }

  // ── HELPERS ───────────────────────────────────────────────────────────────

  Widget _hudRow(IconData icon, String label, String value, Color valueColor) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: Colors.white54),
        const SizedBox(width: 4),
        Text("$label ", style: const TextStyle(color: Colors.white54, fontSize: 11)),
        Text(value, style: TextStyle(color: valueColor, fontSize: 13, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
      ],
    );
  }

  Color _leanColor(double lean) {
    if (lean < 20) return Colors.greenAccent;
    if (lean < 40) return Colors.yellowAccent;
    return Colors.redAccent;
  }

  Widget _mapBtn({
    required IconData icon,
    Color color = Colors.white,
    Color iconColor = Colors.black87,
    required VoidCallback onTap,
    String? tooltip,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Tooltip(
        message: tooltip ?? '',
        child: Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6)],
          ),
          child: Icon(icon, color: iconColor, size: 22),
        ),
      ),
    );
  }

  void _showHazardSheet() {
    final ble = Get.find<BleController>();
    Get.bottomSheet(
      Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Report Hazard Ahead",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Wrap(spacing: 10, runSpacing: 10, children: [
              _hazardChip(ble, "Pothole", Icons.warning, Colors.orange),
              _hazardChip(ble, "Gravel", Icons.scatter_plot, Colors.brown),
              _hazardChip(ble, "Oil Spill", Icons.water_drop, Colors.deepPurple),
              _hazardChip(ble, "Animal", Icons.pets, Colors.red),
            ]),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _hazardChip(BleController ble, String type, IconData icon, Color color) {
    return ActionChip(
      avatar: Icon(icon, color: Colors.white, size: 16),
      label: Text(type, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      backgroundColor: color,
      onPressed: () { Get.back(); ble.reportHazard(type); },
    );
  }

  void _showLogsDialog() {
    final ble = Get.find<BleController>();
    Get.dialog(AlertDialog(
      title: const Text('Hardware Logs'),
      content: SizedBox(
        height: 360, width: 300,
        child: Obx(() => ListView.builder(
          reverse: true,
          itemCount: ble.logs.length,
          itemBuilder: (_, i) {
            final idx = ble.logs.length - 1 - i;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(ble.logs[idx],
                  style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
            );
          },
        )),
      ),
      actions: [TextButton(onPressed: Get.back, child: const Text('Close'))],
    ));
  }
}

// ── Custom painter for the Google Maps-style directional arrow ────────────────
class _ArrowMarkerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width / 2;

    // Outer white circle
    canvas.drawCircle(
      Offset(cx, cy),
      r,
      Paint()..color = Colors.white,
    );

    // Blue filled circle
    canvas.drawCircle(
      Offset(cx, cy),
      r - 3,
      Paint()..color = const Color(0xFF4285F4),
    );

    // White directional chevron pointing up (north = 0°)
    // Use ui.Path explicitly — latlong2 also exports a Path<LatLng> class
    // which would shadow dart:ui's Path without the prefix.
    final arrowPath = ui.Path();
    arrowPath.moveTo(cx, cy - r * 0.55);          // tip
    arrowPath.lineTo(cx - r * 0.38, cy + r * 0.35); // bottom-left
    arrowPath.lineTo(cx, cy + r * 0.10);           // inner bottom
    arrowPath.lineTo(cx + r * 0.38, cy + r * 0.35); // bottom-right
    arrowPath.close();

    canvas.drawPath(
      arrowPath,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
