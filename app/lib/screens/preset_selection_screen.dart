import 'package:flutter/material.dart';

import '../backend/backend_client.dart';
import '../flow/flow_controller.dart';
import '../theme.dart';
import '../widgets/network_video_loop_player.dart';

class PresetSelectionScreen extends StatefulWidget {
  const PresetSelectionScreen({super.key, required this.flow});

  final FlowController flow;

  @override
  State<PresetSelectionScreen> createState() => _PresetSelectionScreenState();
}

class _PresetSelectionScreenState extends State<PresetSelectionScreen> {
  @override
  Widget build(BuildContext context) {
    final flow = widget.flow;
    final presets = flow.presetPreviews;
    final selected = flow.selectedPresetId;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Choose a look, ${flow.name}',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          const Text(
            'These are fast previews. The selected look renders at final quality.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: Colors.white60),
          ),
          const SizedBox(height: 18),
          Expanded(
            child: GridView.builder(
              itemCount: presets.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 0.62,
              ),
              itemBuilder: (context, index) {
                final preset = presets[index];
                return _PresetCard(
                  preset: preset,
                  selected: selected == preset.id,
                  onTap: () =>
                      setState(() => flow.selectedPresetId = preset.id),
                );
              },
            ),
          ),
          const SizedBox(height: 18),
          GradientButton(
            label: 'SEND THIS LOOK',
            icon: Icons.mail_outline,
            expand: true,
            onPressed: selected == null
                ? null
                : () => flow.selectPresetAndProcess(selected),
          ),
        ],
      ),
    );
  }
}

class _PresetCard extends StatelessWidget {
  const _PresetCard({
    required this.preset,
    required this.selected,
    required this.onTap,
  });

  final PresetPreview preset;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? Brand.red.withValues(alpha: 0.26)
          : Brand.surface.withValues(alpha: 0.78),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? Brand.redBright : Colors.white12,
              width: selected ? 2 : 1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: ColoredBox(
                      color: Colors.black,
                      child: preset.previewUrl == null
                          ? const Center(
                              child: CircularProgressIndicator(
                                color: Brand.redBright,
                              ),
                            )
                          : NetworkVideoLoopPlayer(url: preset.previewUrl!),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        preset.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Icon(
                      selected
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      color: selected ? Colors.greenAccent : Colors.white30,
                      size: 20,
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  preset.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: Colors.white54),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
