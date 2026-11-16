import 'dart:async';

import 'package:flutter/material.dart';

/// Five-second animated entry screen used by the passenger and driver apps.
class BakeTaxiSplash extends StatefulWidget {
  const BakeTaxiSplash({
    super.key,
    required this.gifAsset,
    required this.subtitle,
    required this.child,
  });

  final String gifAsset;
  final String subtitle;
  final Widget child;

  @override
  State<BakeTaxiSplash> createState() => _BakeTaxiSplashState();
}

class _BakeTaxiSplashState extends State<BakeTaxiSplash> {
  Timer? _timer;
  bool _showHome = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _showHome = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
        duration: const Duration(milliseconds: 350),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        transitionBuilder: (child, animation) =>
            FadeTransition(opacity: animation, child: child),
        child: _showHome
            ? KeyedSubtree(
                key: const ValueKey('home'),
                child: widget.child,
              )
            : Scaffold(
                key: const ValueKey('splash'),
                backgroundColor: const Color(0xFF0B132B),
                body: SafeArea(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 373),
                            child: AspectRatio(
                              aspectRatio: 373 / 246,
                              child: Image.asset(
                                widget.gifAsset,
                                fit: BoxFit.contain,
                                gaplessPlayback: true,
                                errorBuilder: (_, __, ___) => const Center(
                                  child: Icon(
                                    Icons.local_taxi_rounded,
                                    size: 72,
                                    color: Color(0xFFFFD36A),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 22),
                          const Text(
                            'BAKE TAXI',
                            style: TextStyle(
                              color: Color(0xFFFFD36A),
                              fontSize: 25,
                              letterSpacing: 4,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            widget.subtitle,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Color(0xFFE5EAF5),
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
      );
}
