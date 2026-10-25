import 'dart:async';
import 'package:flutter/material.dart';
import '../services/catalog_service.dart';
import 'home_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _glowAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();

    // Smooth breathing glow animation
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _glowAnimation = Tween<double>(begin: 8.0, end: 28.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _scaleAnimation = Tween<double>(begin: 0.94, end: 1.04).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _initializeAppData();
  }

  Future<void> _initializeAppData() async {
    // 1. Load catalog in the background
    final stopwatch = Stopwatch()..start();
    await CatalogService.loadCatalog();
    stopwatch.stop();

    // 2. Ensure minimum display time so the animation feels smooth and intentional
    final remainingMs = 1200 - stopwatch.elapsedMilliseconds;
    if (remainingMs > 0) {
      await Future.delayed(Duration(milliseconds: remainingMs));
    }

    if (!mounted) return;

    // 3. Smooth fade transition to HomeScreen
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => const HomeScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 500),
      ),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF101419),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Glowing Logo with Breathing Animation
            AnimatedBuilder(
              animation: _pulseController,
              builder: (context, child) {
                return Transform.scale(
                  scale: _scaleAnimation.value,
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF22BFA2).withOpacity(0.4),
                          blurRadius: _glowAnimation.value,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: ClipOval(
                      child: Image.asset(
                        'assets/icons/app_icon.png',
                        width: 110,
                        height: 110,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Container(
                          width: 110,
                          height: 110,
                          decoration: const BoxDecoration(
                            color: Color(0xFF1C252C),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.bolt, color: Color(0xFF22BFA2), size: 54),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),

            const SizedBox(height: 28),

            // App Name
            const Text(
              'VoltMatch',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Know Before You Connect',
              style: TextStyle(
                fontSize: 13,
                color: Color(0xFFA7B0B9),
                letterSpacing: 0.3,
              ),
            ),

            const SizedBox(height: 48),

            // Subtle Mint Loading Indicator
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                color: Color(0xFF22BFA2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}