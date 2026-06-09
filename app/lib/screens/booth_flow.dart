import 'package:flutter/material.dart';

import '../flow/flow_controller.dart';
import '../theme.dart';
import 'attract_screen.dart';
import 'capture_screen.dart';
import 'countdown_screen.dart';
import 'info_entry_screen.dart';
import 'preview_screen.dart';
import 'processing_screen.dart';
import 'result_screen.dart';
import 'style_picker_screen.dart';

/// Root of the guest experience — swaps screens by phase, with the AMD logo
/// (top-left) and "Powered by AMD Compute" footer persistent on every screen.
class BoothFlow extends StatelessWidget {
  const BoothFlow({super.key, required this.flow});
  final FlowController flow;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: Stack(
            children: [
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.only(top: 66, bottom: 36),
                  child: ListenableBuilder(
                    listenable: flow,
                    builder: (context, _) {
                      final screen = switch (flow.phase) {
                        AppPhase.attract => AttractScreen(flow: flow),
                        AppPhase.info => InfoEntryScreen(flow: flow),
                        AppPhase.style => StylePickerScreen(flow: flow),
                        AppPhase.preview => PreviewScreen(flow: flow),
                        AppPhase.countdown => CountdownScreen(flow: flow),
                        AppPhase.capture => CaptureScreen(flow: flow),
                        AppPhase.processing => ProcessingScreen(flow: flow),
                        AppPhase.result => ResultScreen(flow: flow),
                      };
                      return AnimatedSwitcher(
                        duration: const Duration(milliseconds: 350),
                        transitionBuilder: (child, anim) => FadeTransition(
                          opacity: anim,
                          child: SlideTransition(
                            position: Tween(
                              begin: const Offset(0, 0.04),
                              end: Offset.zero,
                            ).animate(anim),
                            child: child,
                          ),
                        ),
                        child: KeyedSubtree(
                          key: ValueKey(flow.phase),
                          child: screen,
                        ),
                      );
                    },
                  ),
                ),
              ),
              // AMD logo, top-left
              const Positioned(top: 18, left: 24, child: AmdLogo(height: 38)),
              // footer
              const Positioned(
                left: 0,
                right: 0,
                bottom: 10,
                child: Center(
                  child: Text(
                    'POWERED BY AMD COMPUTE',
                    style: TextStyle(
                      fontSize: 12,
                      letterSpacing: 3,
                      color: Colors.white38,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
