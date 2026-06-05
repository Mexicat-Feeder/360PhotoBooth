import 'package:flutter/material.dart';

import '../ble/booth_controller.dart';
import '../flow/flow_controller.dart';
import '../theme.dart';
import 'booth_test_screen.dart';

class AttractScreen extends StatelessWidget {
  const AttractScreen({super.key, required this.flow});
  final FlowController flow;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          top: 0,
          right: 12,
          child: IconButton(
            tooltip: 'Developer console',
            icon: const Icon(Icons.settings, color: Colors.white54, size: 28),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => BoothTestScreen(controller: flow.booth),
              ),
            ),
          ),
        ),
        Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // long-press the mark to open the BLE debug screen
          GestureDetector(
            onLongPress: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => BoothTestScreen(controller: flow.booth),
              ),
            ),
            child: const BrandMark(size: 200),
          ),
          const SizedBox(height: 28),
          Text(
            Brand.tagline.toUpperCase(),
            style: const TextStyle(
              fontSize: 20,
              letterSpacing: 6,
              color: Colors.white70,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Step in. Strike a pose.\nWatch AI reimagine you.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700, height: 1.2),
          ),
          const SizedBox(height: 48),
          GradientButton(
            label: 'TAP TO START',
            icon: Icons.auto_awesome,
            onPressed: () => flow.go(AppPhase.info),
          ),
          const SizedBox(height: 40),
          _BoothStatus(booth: flow.booth),
        ],
      ),
        ),
      ],
    );
  }
}

class _BoothStatus extends StatelessWidget {
  const _BoothStatus({required this.booth});
  final BoothController booth;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<BoothState>(
      stream: booth.stateStream,
      initialData: booth.state,
      builder: (context, snap) {
        final s = snap.data ?? BoothState.disconnected;
        final (color, label) = switch (s) {
          BoothState.connected => (Colors.greenAccent, 'Booth connected'),
          BoothState.scanning ||
          BoothState.connecting =>
            (Colors.orangeAccent, 'Connecting to booth…'),
          BoothState.error => (Colors.redAccent, 'Booth error'),
          BoothState.disconnected => (Colors.white38, 'Booth not connected'),
        };
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.circle, size: 10, color: color),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(color: Colors.white54)),
            if (s == BoothState.disconnected || s == BoothState.error) ...[
              const SizedBox(width: 10),
              TextButton(
                onPressed: booth.connect,
                child: const Text('retry'),
              ),
            ],
          ],
        );
      },
    );
  }
}
