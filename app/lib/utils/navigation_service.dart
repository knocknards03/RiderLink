import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class NavigationService {
  // Utilizing the completely free, open-source routing machine (OSRM) API!
  // This calculates the absolute fastest driving route connecting two points across the globe
  static const String _baseUrl = 'http://router.project-osrm.org/route/v1/driving';

  static Future<List<LatLng>> getRoute(LatLng start, LatLng end) async {
    // OSRM uniquely requires coordinate formatting as [Longitude, Latitude] strings
    final String url = '$_baseUrl/${start.longitude},${start.latitude};${end.longitude},${end.latitude}?geometries=geojson';
    
    try {
      final response = await http.get(Uri.parse(url));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List routes = data['routes'];
        
        // Extract the raw spatial geometry if a valid paved path was discovered
        if (routes.isNotEmpty) {
          final geometry = routes[0]['geometry'];
          final List coordinates = geometry['coordinates'];
          
          return coordinates.map((coord) {
            // Translate GeoJSON's [Lng, Lat] back into FlutterMap's standard [Lat, Lng] Object layout
            return LatLng(coord[1], coord[0]); 
          }).toList();
        }
      } else {
         print("OSRM API Error: Code ${response.statusCode}");
      }
    } catch (e) {
      print("Navigation Fetch Error: $e");
    }
    
    // Return empty route if network failed or road could not be traced
    return [];
  }
}
