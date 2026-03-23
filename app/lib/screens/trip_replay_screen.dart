import 'package:flutter/material.dart';

class TripReplayScreen extends StatelessWidget {
  const TripReplayScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Trip History & Replays'),
        backgroundColor: Colors.pink,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.map, size: 80, color: Colors.grey),
            const SizedBox(height: 20),
            const Text("Trip Replay UI", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Text("Previous rides will appear here.", style: TextStyle(color: Colors.grey[600])),
          ],
        ),
      ),
    );
  }
}
