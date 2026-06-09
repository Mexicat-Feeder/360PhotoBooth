import 'package:flutter/material.dart';

import '../flow/flow_controller.dart';
import '../theme.dart';

class SubmittedScreen extends StatelessWidget {
  const SubmittedScreen({super.key, required this.flow});

  final FlowController flow;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.mark_email_read_outlined,
              color: Colors.greenAccent,
              size: 68,
            ),
            const SizedBox(height: 18),
            const Text(
              'Job sent',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            Text(
              'Your video will be generated and emailed to ${flow.email} as an attachment.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, color: Colors.white60),
            ),
            const SizedBox(height: 28),
            const Text(
              'Returning to start...',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.white38),
            ),
            const SizedBox(height: 22),
            GradientButton(
              label: 'START OVER',
              icon: Icons.refresh,
              onPressed: flow.reset,
            ),
          ],
        ),
      ),
    );
  }
}
