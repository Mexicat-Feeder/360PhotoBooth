import 'package:flutter/material.dart';

import '../ble/booth_protocol.dart';
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
          Text(
            "Looking good, ${flow.name}!",
            style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          const Text(
            'Center yourself in frame, then start.',
            style: TextStyle(fontSize: 16, color: Colors.white60),
          ),
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
          const SizedBox(height: 18),
          _BoothControls(
            dir: flow.dir,
            speed: flow.speed,
            durationSeconds: flow.spinSecs,
            onDirChanged: (value) => setState(() => flow.dir = value),
            onSpeedChanged: (value) => setState(() => flow.speed = value),
            onDurationChanged: (value) => setState(() => flow.spinSecs = value),
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 22,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(100),
                  ),
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

class _BoothControls extends StatelessWidget {
  const _BoothControls({
    required this.dir,
    required this.speed,
    required this.durationSeconds,
    required this.onDirChanged,
    required this.onSpeedChanged,
    required this.onDurationChanged,
  });

  final SpinDir dir;
  final int speed;
  final int durationSeconds;
  final ValueChanged<SpinDir> onDirChanged;
  final ValueChanged<int> onSpeedChanged;
  final ValueChanged<int> onDurationChanged;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Brand.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white12),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SegmentedButton<SpinDir>(
              segments: const [
                ButtonSegment(
                  value: SpinDir.ccw,
                  icon: Icon(Icons.rotate_left),
                  label: Text('Counter Clock'),
                ),
                ButtonSegment(
                  value: SpinDir.cw,
                  icon: Icon(Icons.rotate_right),
                  label: Text('Clock'),
                ),
              ],
              selected: {dir},
              showSelectedIcon: false,
              onSelectionChanged: (selection) => onDirChanged(selection.first),
            ),
            const SizedBox(height: 10),
            _ControlSlider(
              label: 'Speed',
              value: speed,
              min: 1,
              max: 9,
              divisions: 8,
              onChanged: onSpeedChanged,
            ),
            _ControlSlider(
              label: 'Duration',
              value: durationSeconds,
              min: 1,
              max: 30,
              divisions: 29,
              suffix: 's',
              onChanged: onDurationChanged,
            ),
          ],
        ),
      ),
    );
  }
}

class _ControlSlider extends StatelessWidget {
  const _ControlSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
    this.suffix = '',
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final int divisions;
  final String suffix;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final valueText = '$value$suffix';
    return Row(
      children: [
        SizedBox(
          width: 78,
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Expanded(
          child: Slider(
            value: value.toDouble(),
            min: min.toDouble(),
            max: max.toDouble(),
            divisions: divisions,
            label: valueText,
            onChanged: (next) => onChanged(next.round()),
          ),
        ),
        SizedBox(
          width: 38,
          child: Text(
            valueText,
            textAlign: TextAlign.right,
            style: const TextStyle(
              color: Colors.white,
              fontFeatures: [FontFeature.tabularFigures()],
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}
