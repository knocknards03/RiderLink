import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:get/get.dart';
import '../db/database_helper.dart';
import '../controllers/community_controller.dart';
import 'community_screen.dart';

class TripReplayScreen extends StatefulWidget {
  const TripReplayScreen({super.key});

  @override
  State<TripReplayScreen> createState() => _TripReplayScreenState();
}

class _TripReplayScreenState extends State<TripReplayScreen> {
  List<Map<String, dynamic>> _trips = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadTrips();
  }

  Future<void> _loadTrips() async {
    final db = await DatabaseHelper().database;
    final rows = await db.query(
      'trips',
      orderBy: 'start_time DESC',
    );
    setState(() {
      _trips = rows.map((r) => Map<String, dynamic>.from(r)).toList();
      _loading = false;
    });
  }

  String _formatDuration(int startMs, int endMs) {
    if (endMs == 0) return 'In progress';
    final dur = Duration(milliseconds: endMs - startMs);
    final h = dur.inHours;
    final m = dur.inMinutes.remainder(60);
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }

  String _formatDate(int ms) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    const months = ['Jan','Feb','Mar','Apr','May','Jun',
                    'Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}  '
           '${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF141414),
        foregroundColor: Colors.white,
        title: const Text('Trip History',
            style: TextStyle(fontWeight: FontWeight.w700)),
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Colors.redAccent))
          : _trips.isEmpty
              ? _emptyState()
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _trips.length,
                  itemBuilder: (_, i) => _TripCard(
                    trip: _trips[i],
                    formatDate: _formatDate,
                    formatDuration: _formatDuration,
                  ),
                ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.route, size: 72, color: Colors.white12),
          const SizedBox(height: 16),
          const Text('No trips yet',
              style: TextStyle(color: Colors.white38, fontSize: 18)),
          const SizedBox(height: 8),
          const Text('Your rides will appear here after your first trip.',
              style: TextStyle(color: Colors.white24, fontSize: 13),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

// ── Trip card ─────────────────────────────────────────────────────────────────

class _TripCard extends StatelessWidget {
  final Map<String, dynamic> trip;
  final String Function(int) formatDate;
  final String Function(int, int) formatDuration;

  const _TripCard({
    required this.trip,
    required this.formatDate,
    required this.formatDuration,
  });

  @override
  Widget build(BuildContext context) {
    final startMs  = trip['start_time'] as int? ?? 0;
    final endMs    = trip['end_time']   as int? ?? 0;
    final maxLean  = (trip['max_lean_angle'] as num?)?.toDouble() ?? 0.0;
    final distKm   = (trip['distance_km'] as num?)?.toDouble() ?? 0.0;
    final topSpeed = (trip['top_speed'] as num?)?.toDouble() ?? 0.0;
    final tripId   = trip['id'] as int;

    return GestureDetector(
      onTap: () => Get.to(() => _TripReplayMapScreen(tripId: tripId, trip: trip)),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.motorcycle, color: Colors.redAccent, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        formatDate(startMs),
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 14),
                      ),
                      const SizedBox(height: 4),
                      Wrap(spacing: 8, children: [
                        _pill(Icons.timer_outlined,
                            formatDuration(startMs, endMs), Colors.blueAccent),
                        _pill(Icons.rotate_90_degrees_ccw,
                            '${maxLean.toStringAsFixed(1)}°',
                            maxLean > 40 ? Colors.redAccent : Colors.greenAccent),
                        if (distKm > 0)
                          _pill(Icons.route,
                              '${distKm.toStringAsFixed(1)} km', Colors.orangeAccent),
                        if (topSpeed > 0)
                          _pill(Icons.speed,
                              '${topSpeed.toStringAsFixed(0)} km/h', Colors.purpleAccent),
                      ]),
                    ],
                  ),
                ),
                const Icon(Icons.play_circle_outline,
                    color: Colors.white38, size: 28),
              ],
            ),
            // Share to community button
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () => _shareToRide(context, trip),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.blueAccent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.blueAccent.withOpacity(0.3)),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.group_add, color: Colors.blueAccent, size: 15),
                    SizedBox(width: 6),
                    Text('Share as Community Ride',
                        style: TextStyle(color: Colors.blueAccent,
                            fontSize: 12, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _shareToRide(BuildContext context, Map<String, dynamic> trip) {
    try {
      final community = Get.find<CommunityController>();
      if (community.myGroups.isEmpty) {
        Get.snackbar('No Groups', 'Join or create a community group first.',
            backgroundColor: Colors.orange, colorText: Colors.white);
        return;
      }
      final startMs = trip['start_time'] as int? ?? 0;
      final dt = DateTime.fromMillisecondsSinceEpoch(startMs);
      const months = ['Jan','Feb','Mar','Apr','May','Jun',
                      'Jul','Aug','Sep','Oct','Nov','Dec'];
      final dateStr = '${dt.day} ${months[dt.month-1]} ${dt.year}';
      Get.bottomSheet(
        CreateRideSheet(
          community: community,
          prefillTitle: 'Ride on $dateStr',
          prefillDesc:
              'Distance: ${(trip['distance_km'] as num?)?.toStringAsFixed(1) ?? "?"} km  '
              '· Max lean: ${(trip['max_lean_angle'] as num?)?.toStringAsFixed(1) ?? "?"}°  '
              '· Top speed: ${(trip['top_speed'] as num?)?.toStringAsFixed(0) ?? "?"} km/h',
        ),
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
      );
    } catch (_) {
      Get.snackbar('Login Required', 'Sign in to share rides with your community.',
          backgroundColor: Colors.orange, colorText: Colors.white);
    }
  }

  Widget _pill(IconData icon, String label, Color color) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 12, color: color),
      const SizedBox(width: 3),
      Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
    ]);
  }
}

// ── Replay map screen ─────────────────────────────────────────────────────────

class _TripReplayMapScreen extends StatefulWidget {
  final int tripId;
  final Map<String, dynamic> trip;
  const _TripReplayMapScreen({required this.tripId, required this.trip});

  @override
  State<_TripReplayMapScreen> createState() => _TripReplayMapScreenState();
}

class _TripReplayMapScreenState extends State<_TripReplayMapScreen> {
  List<LatLng> _route = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadRoute();
  }

  Future<void> _loadRoute() async {
    final db = await DatabaseHelper().database;

    final pointRows = await db.query(
      'route_points',
      where: 'trip_id = ?',
      whereArgs: [widget.tripId],
      orderBy: 'timestamp ASC',
    );

    final points = pointRows
        .map((r) => LatLng(r['latitude'] as double, r['longitude'] as double))
        .toList();

    setState(() {
      _route = points;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF141414),
        foregroundColor: Colors.white,
        title: const Text('Trip Replay',
            style: TextStyle(fontWeight: FontWeight.w700)),
        elevation: 0,
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.redAccent))
          : Column(
              children: [
                // Stats bar — use trip data passed from list
                _StatsBar(trip: widget.trip),
                // Map
                Expanded(
                  child: _route.isEmpty
                      ? const Center(
                          child: Text('No GPS points recorded for this trip.',
                              style: TextStyle(color: Colors.white38)))
                      : FlutterMap(
                          options: MapOptions(
                            initialCenter: _route.first,
                            initialZoom: 14.0,
                          ),
                          children: [
                            TileLayer(
                              urlTemplate:
                                  'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                              userAgentPackageName: 'com.example.riderlink',
                            ),
                            // Route trail
                            PolylineLayer(polylines: [
                              Polyline(
                                points: _route,
                                color: Colors.black38,
                                strokeWidth: 8,
                              ),
                              Polyline(
                                points: _route,
                                color: Colors.redAccent,
                                strokeWidth: 4,
                              ),
                            ]),
                            // Start / end markers
                            MarkerLayer(markers: [
                              Marker(
                                point: _route.first,
                                width: 36, height: 36,
                                child: Container(
                                  decoration: const BoxDecoration(
                                    color: Colors.green,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.play_arrow,
                                      color: Colors.white, size: 20),
                                ),
                              ),
                              Marker(
                                point: _route.last,
                                width: 36, height: 36,
                                child: Container(
                                  decoration: const BoxDecoration(
                                    color: Colors.red,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.stop,
                                      color: Colors.white, size: 20),
                                ),
                              ),
                            ]),
                          ],
                        ),
                ),
              ],
            ),
    );
  }
}

class _StatsBar extends StatelessWidget {
  final Map<String, dynamic> trip;
  const _StatsBar({required this.trip});

  @override
  Widget build(BuildContext context) {
    final startMs  = trip['start_time'] as int? ?? 0;
    final endMs    = trip['end_time']   as int? ?? 0;
    final maxLean  = (trip['max_lean_angle'] as num?)?.toDouble() ?? 0.0;
    final distKm   = (trip['distance_km'] as num?)?.toDouble() ?? 0.0;
    final topSpeed = (trip['top_speed'] as num?)?.toDouble() ?? 0.0;

    final dur = endMs > 0
        ? Duration(milliseconds: endMs - startMs)
        : Duration.zero;
    final durStr = dur.inHours > 0
        ? '${dur.inHours}h ${dur.inMinutes.remainder(60)}m'
        : '${dur.inMinutes}m';

    return Container(
      color: const Color(0xFF141414),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _stat(Icons.timer_outlined, durStr, 'Duration', Colors.blueAccent),
          _stat(Icons.rotate_90_degrees_ccw,
              '${maxLean.toStringAsFixed(1)}°', 'Max Lean',
              maxLean > 40 ? Colors.redAccent : Colors.greenAccent),
          _stat(Icons.route,
              '${distKm.toStringAsFixed(1)} km', 'Distance', Colors.orangeAccent),
          _stat(Icons.speed,
              '${topSpeed.toStringAsFixed(0)} km/h', 'Top Speed', Colors.purpleAccent),
        ],
      ),
    );
  }

  Widget _stat(IconData icon, String value, String label, Color color) {
    return Column(children: [
      Icon(icon, color: color, size: 18),
      const SizedBox(height: 4),
      Text(value,
          style: TextStyle(
              color: color, fontWeight: FontWeight.bold, fontSize: 15)),
      Text(label,
          style: const TextStyle(color: Colors.white38, fontSize: 10)),
    ]);
  }
}

