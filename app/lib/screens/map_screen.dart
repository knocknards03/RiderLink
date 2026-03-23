import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:get/get.dart';
import '../controllers/ble_controller.dart';
import '../utils/navigation_service.dart';
import '../controllers/analytics_controller.dart';
import '../controllers/settings_controller.dart';
import 'profile_screen.dart';
import 'trip_replay_screen.dart';
import 'garage_screen.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();
  bool _hasCenteredOnLocation = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final bleController = Get.find<BleController>();
      
      // Auto-center immediately if we already have a lock from splash screen
      if (bleController.myLocation.value != null) {
        _hasCenteredOnLocation = true;
      }
      
      // Keep a listening hook strictly for the very first time GPS acquires a lock
      ever(bleController.myLocation, (LatLng? loc) {
        if (loc != null && !_hasCenteredOnLocation) {
          _hasCenteredOnLocation = true;
          _mapController.move(loc, 16.0);
        }
      });
    });
  }

  // Reusable helper method to quickly stamp out identical Pit Stop Notification buttons
  Widget _buildBreakBtn(BleController controller, String type, IconData icon) {
    return Obx(() {
      final settings = Get.find<SettingsController>();
      double height = settings.isGloveMode.value ? 60 : 40;
      double fontSize = settings.isGloveMode.value ? 16 : 12;
      double iconSize = settings.isGloveMode.value ? 24 : 18;

      return SizedBox(
        height: height,
        child: FloatingActionButton.extended(
          heroTag: 'btn_$type',
          backgroundColor: Colors.orangeAccent,
          icon: Icon(icon, size: iconSize),
          label: Text(type, style: TextStyle(fontSize: fontSize)),
          onPressed: () => controller.sendBreak(type), 
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    // Inject the global Bluetooth controller so this UI screen can react to live hardware changes
    final BleController bleController = Get.find<BleController>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('RiderLink Navigation'),
        actions: [
          // The Obx widget forces this isolated row to selectively re-render whenever the Bluetooth connection connects or drops
          Obx(() => Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: Row(
              children: [
                Icon(
                  bleController.isConnected.value ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                  color: bleController.isConnected.value ? Colors.greenAccent : Colors.redAccent,
                ),
                const SizedBox(width: 8),
                Text(
                  bleController.isConnected.value ? "Connected" : "Disconnected",
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ))
        ],
      ),
      // A slide-out Navigation Drawer granting access to the offline personal settings
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            const DrawerHeader(
              decoration: BoxDecoration(color: Colors.pink),
              child: Text('RiderLink Menu', style: TextStyle(color: Colors.white, fontSize: 24)),
            ),
            ListTile(
              leading: const Icon(Icons.person),
              title: const Text('My Profile'),
              onTap: () {
                Navigator.pop(context); // Smoothly collapse the drawer
                Get.to(() => const ProfileScreen()); // Push the user to their profile view
              },
            ),
            ListTile(
              leading: const Icon(Icons.history),
              title: const Text('Trip History & Replays'),
              onTap: () {
                Navigator.pop(context);
                Get.to(() => const TripReplayScreen());
              },
            ),
            ListTile(
              leading: const Icon(Icons.garage),
              title: const Text('Digital Garage'),
              onTap: () {
                Navigator.pop(context);
                Get.to(() => const GarageScreen());
              },
            ),
            ListTile(
              leading: const Icon(Icons.settings),
              title: const Text('Rider Settings'),
              onTap: () {
                Navigator.pop(context);
                final settings = Get.find<SettingsController>();
                showDialog(context: context, builder: (ctx) => AlertDialog(
                  title: const Text("Preferences"),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Obx(() => SwitchListTile(
                        title: const Text("Glove-Friendly UI (Extra Large)"),
                        value: settings.isGloveMode.value,
                        onChanged: (val) => settings.toggleGloveMode(),
                      )),
                      Obx(() => SwitchListTile(
                        title: const Text("Curvy Routes (Scenic)"),
                        value: settings.preferCurvyRoutes.value,
                        onChanged: (val) => settings.toggleCurvyRoutes(),
                      )),
                      Obx(() => SwitchListTile(
                        title: const Text("Voice Navigation TTS"),
                        value: settings.enableVoiceNav.value,
                        onChanged: (val) => settings.toggleVoiceNav(),
                      )),
                    ],
                  ),
                  actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Close"))],
                ));
              },
            ),
            const Divider(),
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text("Quick Chat (LoRa Mesh)", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
            ),
            Wrap(
              alignment: WrapAlignment.spaceEvenly,
              runSpacing: 10,
              children: [
                ActionChip(
                  avatar: const Icon(Icons.local_gas_station, size: 16),
                  label: const Text("Need Fuel"), 
                  onPressed: () { bleController.sendMeshMessage("I need fuel soon!"); Navigator.pop(context); }
                ),
                ActionChip(
                  avatar: const Icon(Icons.back_hand, size: 16),
                  label: const Text("Wait Up"), 
                  onPressed: () { bleController.sendMeshMessage("Wait for me!"); Navigator.pop(context); }
                ),
                ActionChip(
                  avatar: const Icon(Icons.local_police, size: 16),
                  label: const Text("Cop Ahead"), 
                  onPressed: () { bleController.sendMeshMessage("Police checkpoint ahead!"); Navigator.pop(context); }
                ),
                ActionChip(
                  avatar: const Icon(Icons.thumb_up, size: 16),
                  label: const Text("Clear"), 
                  onPressed: () { bleController.sendMeshMessage("Road is clear!"); Navigator.pop(context); }
                ),
              ],
            ),
          ],
        ),
      ),
      // A Stack visually overlays UI elements directly on top of the interactive background map
      body: SafeArea(
        child: Stack(
          children: [
            FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: bleController.myLocation.value ?? const LatLng(20.5937, 78.9629),
              initialZoom: bleController.myLocation.value != null ? 16.0 : 5.0,
              // Calculate a route seamlessly whenever the user holds on the map
              onLongPress: (tapPosition, point) async {
                  bleController.destinationPin.value = point;
                  if (bleController.myLocation.value != null) {
                      final route = await NavigationService.getRoute(bleController.myLocation.value!, point);
                      bleController.currentRoute.assignAll(route);
                      final settings = Get.find<SettingsController>();
                      settings.speakInstruction("Route recalculated. Turn left in 200 meters.");
                  } else {
                      Get.snackbar("Location Unknown", "Waiting for GPS lock before navigating.", snackPosition: SnackPosition.BOTTOM);
                  }
              }
            ),
            children: [
              // Pulls mapping grid terrain online using public OpenStreetMap APIs
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.riderlink',
              ),
              // Draws the thick blue navigation path if a route exists
              Obx(() {
                  if (bleController.currentRoute.isEmpty) return const SizedBox.shrink();
                  return PolylineLayer(
                      polylines: [
                          Polyline(
                              points: bleController.currentRoute.toList(),
                              color: Colors.blueAccent,
                              strokeWidth: 6.0,
                          )
                      ]
                  );
              }),
              // Reactive Marker Layer plotting the live GPS coordinates of your friends and yourself
              Obx(() {
                List<Marker> markers = [];
                // Plot other riders
                for(var entry in bleController.riderLocations.entries) {
                    List<double> loc = entry.value;
                    markers.add(Marker(
                      point: LatLng(loc[0], loc[1]),
                      width: 40, height: 40,
                      child: const Icon(Icons.motorcycle, color: Colors.red, size: 40),
                    ));
                }
                // Plot my own live location
                if (bleController.myLocation.value != null) {
                    markers.add(Marker(
                       point: bleController.myLocation.value!,
                       width: 40, height: 40,
                       child: const Icon(Icons.navigation, color: Colors.blue, size: 40),
                    ));
                }
                // Plot the destination pin
                if (bleController.destinationPin.value != null) {
                    markers.add(Marker(
                       point: bleController.destinationPin.value!,
                       width: 40, height: 40,
                       child: const Icon(Icons.location_on, color: Colors.green, size: 50),
                    ));
                }
                // Plot hazards on the route
                for(var hazard in bleController.reportedHazards) {
                    markers.add(Marker(
                      point: LatLng(hazard['lat'], hazard['lng']),
                      width: 40, height: 40,
                      child: const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 40),
                    ));
                }
                return MarkerLayer(markers: markers);
              }),
            ],
          ),
          
          // An extremely visible Emergency SOS button pinned forcefully to the top left margin
          Positioned(
            top: 20,
            left: 10,
            child: Obx(() {
              final settings = Get.find<SettingsController>();
              return FloatingActionButton.extended(
                heroTag: 'sos_btn',
                backgroundColor: Colors.red,
                icon: Icon(Icons.warning, color: Colors.white, size: settings.isGloveMode.value ? 32 : 24),
                label: Text("SOS", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: settings.isGloveMode.value ? 20 : 14)),
                onPressed: () => bleController.sendSOS(),
              );
            }),
          ),
          
          // Mocked Weather Alerts Banner (Size-reduced compact pill)
          Positioned(
            top: 20,
            right: 16, // Right-aligned, freeing up the center and left of the map
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.blueGrey.withOpacity(0.95),
                borderRadius: BorderRadius.circular(15),
                boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.cloud_outlined, color: Colors.white, size: 16),
                  SizedBox(width: 6),
                  Text("Clear: 24°C", 
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                  ),
                ],
              ),
            ),
          ),

          // Live Telemetry Overlay
          Positioned(
            top: 80,
            right: 10,
            child: Obx(() {
               final analytics = Get.find<AnalyticsController>();
               return Container(
                 padding: const EdgeInsets.all(8),
                 decoration: BoxDecoration(
                   color: Colors.black87.withOpacity(0.75),
                   borderRadius: BorderRadius.circular(10),
                   border: Border.all(color: Colors.pinkAccent, width: 1),
                 ),
                 child: Column(
                   crossAxisAlignment: CrossAxisAlignment.end,
                   children: [
                     Text("Lean: ${analytics.currentLeanAngle.value.toStringAsFixed(1)}°", style: const TextStyle(color: Colors.white, fontFamily: 'monospace')),
                     Text("Max Lean: ${analytics.maxLeanAngle.value.toStringAsFixed(1)}°", style: const TextStyle(color: Colors.redAccent, fontFamily: 'monospace', fontSize: 10)),
                     const SizedBox(height: 4),
                     Text("G-Force: ${analytics.currentGForce.value.toStringAsFixed(2)}G", style: const TextStyle(color: Colors.greenAccent, fontFamily: 'monospace')),
                   ],
                 ),
               );
            }),
          ),
          
          // Horizontal Pit Stop controls arrayed along the bottom edge like a navigation bar
          Positioned(
            bottom: 20,
            left: 10,
            right: 80, // Prevent overlap with the floating action buttons on the right
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildBreakBtn(bleController, "Tea", Icons.local_cafe),
                  const SizedBox(width: 8),
                  _buildBreakBtn(bleController, "Breakfast", Icons.restaurant),
                  const SizedBox(width: 8),
                  _buildBreakBtn(bleController, "Lunch", Icons.lunch_dining),
                  const SizedBox(width: 8),
                  _buildBreakBtn(bleController, "Dinner", Icons.dinner_dining),
                ],
              ),
            ),
          ),

          // Hazard Reporting Button ("Waze for bikes")
          Positioned(
            bottom: 90, // Above the log floating button
            right: 16,
            child: FloatingActionButton(
              heroTag: 'hazard_btn',
              backgroundColor: Colors.orange,
              onPressed: () {
                Get.bottomSheet(
                  Container(
                    color: Colors.white,
                    padding: const EdgeInsets.all(20),
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        const SizedBox(
                          width: double.infinity,
                          child: Text("Report Hazard Ahead", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87)),
                        ),
                        const Divider(),
                        ActionChip(
                          avatar: const Icon(Icons.warning, color: Colors.white, size: 16),
                          label: const Text("Pothole", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          backgroundColor: Colors.orange,
                          onPressed: () { Get.back(); bleController.reportHazard("Pothole"); }
                        ),
                        ActionChip(
                          avatar: const Icon(Icons.scatter_plot, color: Colors.white, size: 16),
                          label: const Text("Gravel", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          backgroundColor: Colors.orange,
                          onPressed: () { Get.back(); bleController.reportHazard("Gravel"); }
                        ),
                        ActionChip(
                          avatar: const Icon(Icons.water_drop, color: Colors.white, size: 16),
                          label: const Text("Oil Spill", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          backgroundColor: Colors.orange,
                          onPressed: () { Get.back(); bleController.reportHazard("Oil Spill"); }
                        ),
                        ActionChip(
                          avatar: const Icon(Icons.pets, color: Colors.white, size: 16),
                          label: const Text("Animal", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          backgroundColor: Colors.redAccent,
                          onPressed: () { Get.back(); bleController.reportHazard("Animal"); }
                        ),
                      ],
                    ),
                  ),
                );
              },
              child: const Icon(Icons.report_problem, color: Colors.white, size: 28),
            ),
          ),
          
          // Center on Live Location Button
          Positioned(
            bottom: 160, 
            right: 16,
            child: FloatingActionButton(
              heroTag: 'center_loc_btn',
              backgroundColor: Colors.white,
              onPressed: () {
                if (bleController.myLocation.value != null) {
                  _mapController.move(bleController.myLocation.value!, 16.0);
                  Get.snackbar("GPS Lock", "Centered on your live location.", backgroundColor: Colors.green, colorText: Colors.white);
                } else {
                  Get.snackbar("Searching", "Awaiting GPS satellite lock...", snackPosition: SnackPosition.BOTTOM, backgroundColor: Colors.orange, colorText: Colors.white);
                }
              },
              child: const Icon(Icons.my_location, color: Colors.blueAccent),
            ),
          )
        ],
      )),
      
      // Secondary action dial to manually pop open the live bluetooth diagnostic viewer 
      floatingActionButton: FloatingActionButton(
        heroTag: 'log_btn',
        onPressed: () {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Hardware Logs'),
              content: SizedBox(
                height: 400,
                width: 300,
                child: Obx(() => ListView.builder(
                  itemCount: bleController.logs.length,
                  itemBuilder: (context, index) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4.0),
                    child: Text(
                      bleController.logs[index],
                      style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                    ),
                  ),
                )),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                )
              ],
            ),
          );
        },
        tooltip: "View Logs",
        child: const Icon(Icons.list_alt),
      ),
    );
  }
}
