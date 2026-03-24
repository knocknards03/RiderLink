# RiderLink: Project Review 1 - Core Presentation Topics

If you are asked by your evaluating panel about the technical concepts, algorithms, and software engineering principles used to build **RiderLink**, these are the 8 core pillars you should summarize during your presentation:

### 1. Flutter Cross-Platform UI Development
* **Language:** Dart
* **Concepts:** Declarative UI programming, Reactive State Management (GetX framework), and Widget Tree optimization.
* **Why we used it:** Allows compiling beautifully native-feeling mobile applications that run smoothly on modern smartphone hardware with custom Map rendering engines.

### 2. LoRa (Long Range) Mesh Networking
* **Hardware:** Semtech SX1278 at 433MHz standard.
* **Concepts:** LPWAN (Low Power Wide Area Networks), Peer-to-Peer broadcasting, and custom packet creation.
* **Why we used it:** Solves the core problem statement—allowing communication (SOS, telemetry, messaging) in areas entirely lacking cellular or WiFi coverage.

### 3. Bluetooth Low Energy (BLE) Bridging
* **Concepts:** GATT Services, Characteristics, UUID definitions, and asynchronous characteristic subscriptions.
* **Why we used it:** The heavy lifting of the map UI must be mathematically calculated on a smartphone, but the smartphone does not possess a LoRa antenna. We use a custom, ultra-low power BLE connection bridging the Flutter app directly to the ESP32 hardware to safely ferry byte-packets back and forth.

### 4. Vehicle Telemetry & Sensor Fusion
* **Sensors:** Accelerometers, Gyroscopes (Smartphone native IMU / ESP32 MPU6050).
* **Concepts:** Mathematics of 3D-space vector measurements, instantaneous G-force collision calculations, and Live Lean Angles.
* **Why we used it:** Forms our proactive safety net. Constantly evaluating the IMU data stream allows the app to automatically detect catastrophic motorcycle crashes without relying on the rider's manually submitted SOS.

### 5. Geographic Information Systems (GIS) & Offline Maps
* **Concepts:** Coordinate tracking (Latitude/Longitude standardizations), Map-Tile caching algorithms for offline terrain rendering, and distance bounding.
* **Why we used it:** Enables the rich map interface that actively visually plots the blue route curves, other riders on the LoRa mesh network, and reported Waze-style path hazards.

### 6. Edge Database Design
* **Engine:** Local SQLite using the `sqflite` plugin.
* **Concepts:** Persistent local schema creation, querying, insertion triggers.
* **Why we used it:** Necessary for the "Digital Garage" tracking (service interval odometers) and GPX black-box location history without relying on an internet-based cloud logic like Firebase.

### 7. Vehicle-to-Vehicle (V2V) Math Modeling
* **Concepts:** Geodesic Distance calculations (Haversine formula).
* **Why we used it:** Used by our Group Proximity Alerts logic. The software calculates in real-time the Earth-curvature distance between your live GPS data and the LoRa-received GPS pings of external riders to issue a warning if someone gets dropped.

### 8. Embedded Firmware Execution
* **Language:** C++
* **Concepts:** Microcontroller programming, FreeRTOS tasks (running dual-core processes concurrently), and UART Serial Debugging.
* **Why we used it:** Managing the ESP32 "Brain" of the physical module bolted to the motorcycle requires extremely resilient code capable of executing hardware-level interrupts gracefully.
