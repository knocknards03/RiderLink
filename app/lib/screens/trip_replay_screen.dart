import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:get/get.dart';
import '../db/database_helper.dart';

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
    final tripId   = trip['id'] as int;

    return GestureDetector(
      onTap: () => Get.to(() => _TripReplayMapScreen(tripId: tripId)),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white10),
        ),
        child: Row(
          children: [
            // Icon
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(
                color: Colors.redAccent.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.motorcycle, color: Colors.redAccent, size: 24),
            ),
            const SizedBox(width: 14),
            // Info
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
                  Row(children: [
                    _pill(Icons.timer_outlined,
                        formatDuration(startMs, endMs), Colors.blueAccent),
                    const SizedBox(width: 8),
                    _pill(Icons.rotate_90_degrees_ccw,
                        '${maxLean.toStringAsFixed(1)}° lean',
                        maxLean > 40 ? Colors.redAccent : Colors.greenAccent),
                  ]),
                ],
              ),
            ),
            const Icon(Icons.play_circle_outline,
                color: Colors.white38, size: 28),
          ],
        ),
      ),
    );
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
  const _TripReplayMapScreen({required this.tripId});

  @override
  State<_TripReplayMapScreen> createState() => _TripReplayMapScreenState();
}

class _TripReplayMapScreenState extends State<_TripReplayMapScreen> {
  List<LatLng> _route = [];
  bool _loading = true;
  Map<String, dynamic>? _trip;

  @override
  void initState() {
    super.initState();
    _loadRoute();
  }

  Future<void> _loadRoute() async {
    final db = await DatabaseHelper().database;

    final tripRows = await db.query(
      'trips', where: 'id = ?', whereArgs: [widget.tripId]);
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
      _trip = tripRows.isNotEmpty
          ? Map<String, dynamic>.from(tripRows.first)
          : null;
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
                // Stats bar
                if (_trip != null) _StatsBar(trip: _trip!),
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
    final startMs = trip['start_time'] as int? ?? 0;
    final endMs   = trip['end_time']   as int? ?? 0;
    final maxLean = (trip['max_lean_angle'] as num?)?.toDouble() ?? 0.0;

    final dur = endMs > 0
        ? Duration(milliseconds: endMs - startMs)
        : Duration.zero;
    final durStr = dur.inHours > 0
        ? '${dur.inHours}h ${dur.inMinutes.remainder(60)}m'
        : '${dur.inMinutes}m';

    return Container(
      color: const Color(0xFF141414),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _stat(Icons.timer_outlined, durStr, 'Duration', Colors.blueAccent),
          _stat(Icons.rotate_90_degrees_ccw,
              '${maxLean.toStringAsFixed(1)}°', 'Max Lean',
              maxLean > 40 ? Colors.redAccent : Colors.greenAccent),
          _stat(Icons.location_on_outlined,
              '${(trip['distance_km'] as num?)?.toStringAsFixed(1) ?? '0.0'} km',
              'Distance', Colors.orangeAccent),
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
