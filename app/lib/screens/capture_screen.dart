import 'package:flutter/material.dart';

import '../flow/flow_controller.dart';
import '../theme.dart';

class CaptureScreen extends StatelessWidget {
  const CaptureScreen({super.key, required this.flow});
  final FlowController flow;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _RecDot(),
              const SizedBox(width: 10),
              const Text('RECORDING',
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2)),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(child: flow.camera.buildPreview()),
          const SizedBox(height: 20),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 1, end: 0),
            duration: Duration(seconds: flow.spinSecs),
            builder: (_, t, _) {
              final remaining = (flow.spinSecs * t).ceil();
              return Column(
                children: [
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 90,
                        height: 90,
                        child: CircularProgressIndicator(
                          value: t,
                          strokeWidth: 8,
                          backgroundColor: Brand.surface,
                          valueColor: const AlwaysStoppedAnimation(Brand.redBright),
                        ),
                      ),
                      Text('$remaining',
                          style: const TextStyle(
                              fontSize: 30, fontWeight: FontWeight.w800)),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Text('Hold your pose — the booth is spinning!',
                      style: TextStyle(fontSize: 18, color: Colors.white70)),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _RecDot extends StatefulWidget {
  @override
  State<_RecDot> createState() => _RecDotState();
}

class _RecDotState extends State<_RecDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..repeat(reverse: true);

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _c,
      child: const Icon(Icons.circle, color: Colors.redAccent, size: 18),
    );
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }
}
