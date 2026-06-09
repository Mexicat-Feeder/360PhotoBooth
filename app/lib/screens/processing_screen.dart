import 'package:flutter/material.dart';

import '../flow/flow_controller.dart';
import '../theme.dart';

class ProcessingScreen extends StatelessWidget {
  const ProcessingScreen({super.key, required this.flow});
  final FlowController flow;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: flow,
      builder: (context, _) {
        final pct = (flow.progress.clamp(0, 1) * 100).round();
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GlowRing(
                value: flow.progress <= 0 ? null : flow.progress,
                size: 230,
                child: flow.previewUrl != null
                    ? ClipOval(
                        child: Image.network(
                          flow.previewUrl!,
                          width: 175,
                          height: 175,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => _pctText(pct),
                        ),
                      )
                    : _pctText(pct),
              ),
              const SizedBox(height: 36),
              const Text('Generating your AI video',
                  style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              const Text('Running locally on AMD Ryzen AI — no cloud',
                  style: TextStyle(fontSize: 16, color: Colors.white60)),
            ],
          ),
        );
      },
    );
  }

  Widget _pctText(int pct) => Text('$pct%',
      style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w800));
}
