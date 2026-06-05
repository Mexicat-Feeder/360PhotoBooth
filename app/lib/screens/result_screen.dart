import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../flow/flow_controller.dart';
import '../theme.dart';

class ResultScreen extends StatelessWidget {
  const ResultScreen({super.key, required this.flow});
  final FlowController flow;

  @override
  Widget build(BuildContext context) {
    final err = flow.error;
    if (err != null) {
      return _Message(
        icon: Icons.error_outline,
        color: Colors.redAccent,
        title: 'Something went wrong',
        subtitle: err,
        flow: flow,
      );
    }

    final url = flow.resultUrl;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.check_circle, color: Colors.greenAccent, size: 64),
          const SizedBox(height: 16),
          Text('You look amazing, ${flow.name}!',
              style:
                  const TextStyle(fontSize: 32, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          const Text('Scan to download your AI 360 video',
              style: TextStyle(fontSize: 18, color: Colors.white60)),
          const SizedBox(height: 28),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: url == null
                ? const SizedBox(
                    width: 220,
                    height: 220,
                    child: Center(child: Text('no link', style: TextStyle(color: Colors.black54))),
                  )
                : QrImageView(data: url, size: 220),
          ),
          const SizedBox(height: 14),
          Text('Also sent to ${flow.email}',
              style: const TextStyle(color: Colors.white38)),
          const SizedBox(height: 40),
          GradientButton(
            label: 'DONE',
            icon: Icons.refresh,
            onPressed: flow.reset,
          ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.flow,
  });
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final FlowController flow;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 64),
            const SizedBox(height: 16),
            Text(title,
                style:
                    const TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white54)),
            const SizedBox(height: 32),
            GradientButton(
                label: 'START OVER', icon: Icons.refresh, onPressed: flow.reset),
          ],
        ),
      ),
    );
  }
}
