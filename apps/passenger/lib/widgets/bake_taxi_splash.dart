import 'package:flutter/material.dart';

/// Premium animated entry screen shared by the passenger and driver apps.
class BakeTaxiSplash extends StatefulWidget {
  const BakeTaxiSplash({
    super.key,
    required this.logoAsset,
    required this.subtitle,
    required this.child,
  });

  final String logoAsset;
  final String subtitle;
  final Widget child;

  @override
  State<BakeTaxiSplash> createState() => _BakeTaxiSplashState();
}

class _BakeTaxiSplashState extends State<BakeTaxiSplash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2500),
  );
  late final Animation<double> _logoFade = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.0, 0.68, curve: Curves.easeOut),
  );
  late final Animation<double> _logoScale = Tween<double>(begin: 0.78, end: 1.0)
      .animate(CurvedAnimation(parent: _controller,
          curve: const Interval(0.0, 0.72, curve: Curves.easeOutBack)));
  late final Animation<Offset> _textSlide = Tween<Offset>(
    begin: const Offset(0, 0.55), end: Offset.zero,
  ).animate(CurvedAnimation(parent: _controller,
      curve: const Interval(0.24, 0.78, curve: Curves.easeOutCubic)));
  late final Animation<double> _textFade = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.24, 0.78, curve: Curves.easeOut),
  );
  bool _showHome = false;

  @override
  void initState() {
    super.initState();
    _controller.forward().whenComplete(() {
      if (mounted) setState(() => _showHome = true);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: const Duration(milliseconds: 420),
    switchInCurve: Curves.easeOut,
    switchOutCurve: Curves.easeIn,
    transitionBuilder: (child, animation) => FadeTransition(
      opacity: animation, child: child,
    ),
    child: _showHome
      ? KeyedSubtree(key: const ValueKey('home'), child: widget.child)
      : Scaffold(
          key: const ValueKey('splash'),
          backgroundColor: const Color(0xFF0B132B),
          body: SafeArea(
            child: LayoutBuilder(builder: (context, constraints) {
              return Stack(
                children: [
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FadeTransition(
                          opacity: _logoFade,
                          child: ScaleTransition(
                            scale: _logoScale,
                            child: Container(
                              width: 184,
                              height: 184,
                              padding: const EdgeInsets.all(7),
                              decoration: BoxDecoration(
                                color: const Color(0xFF111D3B),
                                borderRadius: BorderRadius.circular(34),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFFFFD36A).withOpacity(0.34),
                                    blurRadius: 34,
                                    spreadRadius: 3,
                                  ),
                                  BoxShadow(
                                    color: const Color(0xFFFFC857).withOpacity(0.16),
                                    blurRadius: 58,
                                    spreadRadius: 8,
                                  ),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(28),
                                child: Image.asset(widget.logoAsset,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => const Icon(
                                    Icons.local_taxi_rounded,
                                    size: 92, color: Color(0xFFFFD36A),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 28),
                        FadeTransition(
                          opacity: _textFade,
                          child: SlideTransition(
                            position: _textSlide,
                            child: Column(children: [
                              const Text('BAKE TAXI',
                                style: TextStyle(
                                  color: Color(0xFFFFD36A),
                                  fontSize: 30,
                                  letterSpacing: 4.2,
                                  fontWeight: FontWeight.w900,
                                )),
                              const SizedBox(height: 9),
                              Text(widget.subtitle,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Color(0xFFE5EAF5),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  letterSpacing: 0.3,
                                )),
                            ]),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    left: 28, right: 28, bottom: 24,
                    child: AnimatedBuilder(
                      animation: _controller,
                      builder: (context, _) => ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          height: 4,
                          color: const Color(0xFF273451),
                          alignment: Alignment.centerLeft,
                          child: FractionallySizedBox(
                            widthFactor: _controller.value,
                            child: Container(
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFD36A),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFFFFD36A).withOpacity(0.7),
                                    blurRadius: 10,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            }),
          ),
        ),
  );
}
