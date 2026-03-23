import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'dart:async';
import 'map_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();

    // Design a smooth, premium fade-in animation driving the Opacity property over 2 seconds
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeIn),
    );

    _controller.forward();

    // Give the hardware 3 seconds to initialize Bluetooth radios and ping the GPS hardware
    Timer(const Duration(seconds: 3), () {
      // Seamlessly fade out the splash screen and fade the live Map view into focus
      Get.off(() => const MapScreen(), transition: Transition.fadeIn, duration: const Duration(milliseconds: 800));
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212), // Deep, aesthetic dark mode canvas
      body: Center(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Premium backlit Motorcycle icon
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withOpacity(0.08),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.motorcycle,
                  size: 80,
                  color: Colors.redAccent,
                ),
              ),
              const SizedBox(height: 28),
              // Brand Identity
              const Text(
                'RIDERLINK',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: 4.0,
                ),
              ),
              const SizedBox(height: 12),
              // Slogan
              const Text(
                'THE OFFLINE SAFETY ECOSYSTEM',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  color: Colors.white54,
                  letterSpacing: 2.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
