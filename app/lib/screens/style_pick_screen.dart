import 'package:flutter/material.dart';

import '../flow/flow_controller.dart';
import '../theme.dart';

/// Gallery of stylized preview stills — tap one to render it as a full video.
class StylePickScreen extends StatelessWidget {
  const StylePickScreen({super.key, required this.flow});
  final FlowController flow;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
      child: Column(
        children: [
          Text('Pick your style, ${flow.name}!',
              style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          const Text('Tap a look — we’ll paint your full 360 video in it.',
              style: TextStyle(fontSize: 16, color: Colors.white60)),
          const SizedBox(height: 16),
          Expanded(
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 230,
                childAspectRatio: 0.82,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
              ),
              itemCount: flow.styles.length,
              itemBuilder: (context, i) {
                final s = flow.styles[i];
                return _StyleTile(
                  label: s.label,
                  url: s.previewUrl,
                  onTap: () => flow.selectStyle(s.id),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _StyleTile extends StatelessWidget {
  const _StyleTile(
      {required this.label, required this.url, required this.onTap});
  final String label;
  final String url;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Brand.surface,
          borderRadius: BorderRadius.circular(20),
          boxShadow: Brand.glow(0.18, blur: 24),
          border: Border.all(color: Colors.white12),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Image.network(
                url,
                fit: BoxFit.cover,
                loadingBuilder: (c, w, p) => p == null
                    ? w
                    : const Center(
                        child: CircularProgressIndicator(
                            color: Brand.redBright, strokeWidth: 2)),
                errorBuilder: (_, _, _) =>
                    const Center(child: Icon(Icons.image_not_supported)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }
}
