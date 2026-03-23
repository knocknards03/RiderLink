import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class GarageScreen extends StatefulWidget {
  const GarageScreen({super.key});

  @override
  State<GarageScreen> createState() => _GarageScreenState();
}

class _GarageScreenState extends State<GarageScreen> {
  int _odometer = 0;
  int _lastChainLube = 0;
  int _lastOilChange = 0;
  int _fuelRangeAvg = 300; // Expected km from a full tank
  int _lastFuelFill = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _odometer = prefs.getInt('odometer') ?? 12000;
      _lastChainLube = prefs.getInt('last_chain_lube') ?? 11500;
      _lastOilChange = prefs.getInt('last_oil_change') ?? 10000;
      _fuelRangeAvg = prefs.getInt('fuel_range_avg') ?? 300;
      _lastFuelFill = prefs.getInt('last_fuel_fill') ?? 11800;
    });
  }

  _saveData(String key, int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(key, value);
    _loadData();
  }

  Widget _buildStatCard(String title, int lastDone, int interval, String key, IconData icon) {
    int distanceSince = _odometer - lastDone;
    int remaining = interval - distanceSince;
    double progress = distanceSince / interval;
    if (progress > 1.0) progress = 1.0;
    
    Color statusColor = Colors.green;
    if (remaining < 100) statusColor = Colors.orange;
    if (remaining < 0) statusColor = Colors.red;

    return Card(
      elevation: 4,
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              children: [
                Icon(icon, size: 30, color: statusColor),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      Text(remaining > 0 ? "Due in $remaining km" : "Overdue by ${remaining.abs()} km", 
                        style: TextStyle(color: statusColor, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white),
                  onPressed: () => _saveData(key, _odometer),
                  child: const Text("Just Did It!"),
                )
              ],
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(value: progress, color: statusColor, backgroundColor: Colors.grey[300], minHeight: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Digital Garage"), backgroundColor: Colors.indigo, foregroundColor: Colors.white),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: Colors.indigo[50], borderRadius: BorderRadius.circular(15)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Odometer", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                Row(
                  children: [
                    Text("$_odometer km", style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.indigo)),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.edit, color: Colors.indigo),
                      onPressed: () {
                         int temp = _odometer;
                         showDialog(context: context, builder: (ctx) => AlertDialog(
                           title: const Text("Update Odometer"),
                           content: TextField(
                             keyboardType: TextInputType.number,
                             decoration: const InputDecoration(hintText: "Enter current KM"),
                             onChanged: (val) => temp = int.tryParse(val) ?? temp,
                           ),
                           actions: [
                             TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
                             TextButton(onPressed: () { _saveData('odometer', temp); Navigator.pop(ctx); }, child: const Text("Save"))
                           ],
                         ));
                      },
                    )
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _buildStatCard("Chain Cleaning & Lube", _lastChainLube, 500, 'last_chain_lube', Icons.settings),
          _buildStatCard("Engine Oil Change", _lastOilChange, 5000, 'last_oil_change', Icons.water_drop),
          _buildStatCard("Fuel Stop Estimator", _lastFuelFill, _fuelRangeAvg, 'last_fuel_fill', Icons.local_gas_station),
        ],
      )
    );
  }
}
