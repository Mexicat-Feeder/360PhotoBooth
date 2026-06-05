import 'package:flutter/material.dart';

import '../flow/flow_controller.dart';
import '../theme.dart';

/// Live camera preview with Start (begins the countdown) and Back (edit info).
/// The countdown only starts when the guest taps Start.
class PreviewScreen extends StatefulWidget {
  const PreviewScreen({super.key, required this.flow});
  final FlowController flow;

  @override
  State<PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends State<PreviewScreen> {
  @override
  void initState() {
    super.initState();
    widget.flow.camera.startPreview();
  }

  @override
  void dispose() {
    widget.flow.camera.stopPreview();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final flow = widget.flow;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        children: [
          Text("Looking good, ${flow.name}!",
              style:
                  const TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          const Text('Center yourself in frame, then start.',
              style: TextStyle(fontSize: 16, color: Colors.white60)),
          const SizedBox(height: 18),
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: 4 / 3,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: Brand.glow(0.35, blur: 50),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: flow.camera.buildPreview(),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: () => flow.go(AppPhase.info),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Back'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white24),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 28, vertical: 22),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(100)),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: GradientButton(
                  label: 'START',
                  icon: Icons.play_arrow,
                  expand: true,
                  onPressed: () => flow.go(AppPhase.countdown),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
