import 'package:flutter/material.dart';

import '../backend/backend_client.dart';
import '../flow/flow_controller.dart';
import '../theme.dart';

/// Guest picks a look from the full catalog, grouped by family (AI Styles /
/// Backgrounds / Motion & Format). Sits between info entry and preview.
class StylePickerScreen extends StatelessWidget {
  const StylePickerScreen({super.key, required this.flow});
  final FlowController flow;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: flow,
      builder: (context, _) {
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              children: [
                const SizedBox(height: 8),
                const Text('Pick your look',
                    style:
                        TextStyle(fontSize: 34, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                const Text('Rendered locally on the AMD GPU — no cloud.',
                    style: TextStyle(fontSize: 15, color: Colors.white60)),
                const SizedBox(height: 18),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final fam in flow.catalog)
                          _FamilySection(
                            family: fam,
                            selectedId: flow.workflow,
                            onPick: flow.setWorkflow,
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                GradientButton(
                  label: 'CONTINUE',
                  icon: Icons.arrow_forward,
                  onPressed: () => flow.go(AppPhase.preview),
                ),
                const SizedBox(height: 4),
                TextButton(
                  onPressed: () => flow.go(AppPhase.info),
                  child: const Text('Back',
                      style: TextStyle(color: Colors.white54)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _FamilySection extends StatelessWidget {
  const _FamilySection({
    required this.family,
    required this.selectedId,
    required this.onPick,
  });
  final LookFamily family;
  final String selectedId;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 8, left: 4),
          child: Text(
            family.label.toUpperCase(),
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
              color: Colors.white54,
            ),
          ),
        ),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 2.6,
          children: [
            for (final look in family.items)
              _LookCard(
                look: look,
                selected: look.id == selectedId,
                onTap: () => onPick(look.id),
              ),
          ],
        ),
      ],
    );
  }
}

class _LookCard extends StatelessWidget {
  const _LookCard({
    required this.look,
    required this.selected,
    required this.onTap,
  });
  final LookOption look;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = look.available;
    final card = DecoratedBox(
      decoration: BoxDecoration(
        color: Brand.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: selected ? Brand.redBright : Colors.white12,
          width: selected ? 2.5 : 1,
        ),
        boxShadow: selected ? Brand.glow(0.4, blur: 24, spread: -6) : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        look.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        enabled ? look.blurb : (look.reason ?? 'Unavailable'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 11.5,
                            color: enabled ? Colors.white54 : Brand.redBright),
                      ),
                    ],
                  ),
                ),
                Icon(
                  enabled
                      ? (selected
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked)
                      : Icons.lock_outline,
                  color: enabled
                      ? (selected ? Brand.redBright : Colors.white24)
                      : Colors.white24,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return enabled ? card : Opacity(opacity: 0.45, child: card);
  }
}
