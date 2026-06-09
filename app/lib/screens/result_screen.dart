import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../flow/flow_controller.dart';
import '../theme.dart';
import '../widgets/video_loop_player.dart';

class ResultScreen extends StatelessWidget {
  const ResultScreen({super.key, required this.flow});
  final FlowController flow;

  @override
  Widget build(BuildContext context) {
    if (flow.error != null) {
      return _Message(
        icon: Icons.error_outline,
        color: Colors.redAccent,
        title: 'Something went wrong',
        subtitle: flow.error!,
        flow: flow,
      );
    }
    if (flow.resultLocalPath == null) {
      return _Message(
        icon: Icons.mark_email_read_outlined,
        color: Colors.greenAccent,
        title: 'You are all set',
        subtitle:
            'Your final video is being emailed to ${flow.email} as an attachment.',
        flow: flow,
      );
    }
    return flow.showQr ? _qrView() : _videoView();
  }

  // Step 1 — play the stylized video in-app
  Widget _videoView() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        children: [
          Text(
            'Here’s your AI video, ${flow.name}! 🎨',
            style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          const Text(
            'Painted by AMD Ryzen AI — Van Gogh style',
            style: TextStyle(fontSize: 16, color: Colors.white60),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: Brand.glow(0.45, blur: 60),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: flow.resultLocalPath != null
                        ? VideoLoopPlayer(path: flow.resultLocalPath!)
                        : const Center(
                            child: Text(
                              'video unavailable',
                              style: TextStyle(color: Colors.white54),
                            ),
                          ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          GradientButton(
            label: 'NEXT',
            icon: Icons.arrow_forward,
            onPressed: flow.goToQr,
          ),
        ],
      ),
    );
  }

  // Step 2 — QR to take it home
  Widget _qrView() {
    final url = flow.resultUrl;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.check_circle, color: Colors.greenAccent, size: 56),
          const SizedBox(height: 14),
          const Text(
            'Scan to take it home',
            style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: Brand.glow(0.4, blur: 50),
            ),
            child: url == null
                ? const SizedBox(
                    width: 220,
                    height: 220,
                    child: Center(
                      child: Text(
                        'no link',
                        style: TextStyle(color: Colors.black54),
                      ),
                    ),
                  )
                : QrImageView(data: url, size: 220),
          ),
          const SizedBox(height: 14),
          Text(
            'Also sent to ${flow.email}',
            style: const TextStyle(color: Colors.white38),
          ),
          const SizedBox(height: 36),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: flow.goToVideo,
                icon: const Icon(Icons.arrow_back),
                label: const Text('Back'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white24),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 20,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(100),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              GradientButton(
                label: 'DONE',
                icon: Icons.refresh,
                onPressed: flow.reset,
              ),
            ],
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
            Text(
              title,
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54),
            ),
            const SizedBox(height: 32),
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
