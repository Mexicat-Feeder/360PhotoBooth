import 'dart:async';

import 'package:flutter/material.dart';

import '../flow/flow_controller.dart';
import '../theme.dart';

class CountdownScreen extends StatefulWidget {
  const CountdownScreen({super.key, required this.flow});
  final FlowController flow;

  @override
  State<CountdownScreen> createState() => _CountdownScreenState();
}

class _CountdownScreenState extends State<CountdownScreen> {
  static const int _start = 5;
  int _n = _start;
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() => _n--);
      if (_n <= 0) {
        timer.cancel();
        widget.flow.runCaptureAndProcess();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('Step onto the platform!',
              style: TextStyle(fontSize: 32, fontWeight: FontWeight.w700)),
          const SizedBox(height: 40),
          TweenAnimationBuilder<double>(
            key: ValueKey(_n),
            tween: Tween(begin: 0.6, end: 1.0),
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOutBack,
            builder: (_, scale, child) =>
                Transform.scale(scale: scale, child: child),
            child: Container(
              width: 200,
              height: 200,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: Brand.accent,
              ),
              child: Text('$_n',
                  style: const TextStyle(
                      fontSize: 96, fontWeight: FontWeight.w800)),
            ),
          ),
          const SizedBox(height: 40),
          const Text('Get ready to strike a pose ✨',
              style: TextStyle(fontSize: 18, color: Colors.white60)),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }
}
