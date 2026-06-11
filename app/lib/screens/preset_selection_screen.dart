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
  String _prefetchedUrlsKey = '';

  @override
  void dispose() {
    NetworkVideoLoopPlayer.cancelPendingDownloads();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final flow = widget.flow;
    final presets = flow.presetPreviews;
    _prefetchPreviews(presets);
    final selected = flow.selectedPresetId;
    final activePreset = _selectedPreset(presets, selected);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 700;
        final horizontalPadding = constraints.maxWidth < 430 ? 16.0 : 24.0;
        final previewHeight = (constraints.maxHeight * 0.46).clamp(
          220.0,
          isWide ? 420.0 : 460.0,
        );

        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            8,
            horizontalPadding,
            24,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                flow.hasName
                    ? 'Choose a look, ${flow.displayName}'
                    : 'Choose a look',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Tap each look to preview it. The selected look renders at final quality.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.white60),
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: previewHeight,
                child: Center(
                  child: AspectRatio(
                    aspectRatio: 9 / 16,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: Brand.glow(0.35, blur: 42),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: activePreset?.previewUrl == null
                            ? const Center(
                                child: CircularProgressIndicator(
                                  color: Brand.redBright,
                                ),
                              )
                            : NetworkVideoLoopPlayer(
                                key: ValueKey(activePreset!.previewUrl),
                                url: activePreset.previewUrl!,
                              ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                activePreset?.name ?? '',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                activePreset?.description ?? '',
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: Colors.white54),
              ),
              const SizedBox(height: 14),
              GridView.builder(
                itemCount: presets.length,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: isWide ? 4 : 2,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: isWide ? 2.45 : 3.25,
                ),
                itemBuilder: (context, index) {
                  final preset = presets[index];
                  return _PresetButton(
                    preset: preset,
                    selected: selected == preset.id,
                    onTap: () =>
                        setState(() => flow.selectedPresetId = preset.id),
                  );
                },
              ),
              const SizedBox(height: 16),
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
      },
    );
  }

  PresetPreview? _selectedPreset(
    List<PresetPreview> presets,
    String? selectedId,
  ) {
    for (final preset in presets) {
      if (preset.id == selectedId) return preset;
    }
    return presets.isEmpty ? null : presets.first;
  }

  void _prefetchPreviews(List<PresetPreview> presets) {
    final urls = [
      for (final preset in presets)
        if (preset.previewUrl != null) preset.previewUrl!,
    ];
    final key = urls.join('|');
    if (urls.isEmpty || key == _prefetchedUrlsKey) return;
    _prefetchedUrlsKey = key;
    NetworkVideoLoopPlayer.prefetchAll(urls);
  }
}

class _PresetButton extends StatelessWidget {
  const _PresetButton({
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
          : Brand.surface.withValues(alpha: 0.82),
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
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                Icon(
                  selected
                      ? Icons.play_circle_fill
                      : Icons.radio_button_unchecked,
                  color: selected ? Colors.greenAccent : Colors.white30,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    preset.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
