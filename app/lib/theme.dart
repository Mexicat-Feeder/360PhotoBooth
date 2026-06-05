import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Branding + design system — black / red, glowy, AMD-flavored kiosk.
class Brand {
  static const String name = '360°';
  static const String tagline = 'AI Photo Booth';

  static const Color bg0 = Color(0xFF070607);
  static const Color bg1 = Color(0xFF1A0707);
  static const Color surface = Color(0xFF1E1414);
  static const Color red = Color(0xFFED1C24); // AMD red
  static const Color redBright = Color(0xFFFF4D4D);
  static const Color redDeep = Color(0xFF8B0000);

  static const LinearGradient accent = LinearGradient(
    colors: [redBright, red],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const LinearGradient backdrop = LinearGradient(
    colors: [bg0, bg1],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  /// Standard red glow shadow.
  static List<BoxShadow> glow(double alpha, {double blur = 40, double spread = -4}) =>
      [
        BoxShadow(
          color: red.withValues(alpha: alpha),
          blurRadius: blur,
          spreadRadius: spread,
        ),
      ];
}

ThemeData buildTheme() {
  final base = ThemeData(brightness: Brightness.dark, useMaterial3: true);
  final scheme = ColorScheme.fromSeed(
    seedColor: Brand.red,
    brightness: Brightness.dark,
  ).copyWith(surface: Brand.surface, primary: Brand.red);
  return base.copyWith(
    colorScheme: scheme,
    scaffoldBackgroundColor: Brand.bg0,
    textTheme: GoogleFonts.outfitTextTheme(base.textTheme).apply(
      bodyColor: Colors.white,
      displayColor: Colors.white,
    ),
  );
}

/// AMD logo, pre-rendered white on transparent (assets/amd_logo_white.png).
class AmdLogo extends StatelessWidget {
  const AmdLogo({super.key, this.height = 34});
  final double height;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/amd_logo_white.png',
      height: height,
      filterQuality: FilterQuality.high,
    );
  }
}

class AppBackground extends StatelessWidget {
  const AppBackground({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(gradient: Brand.backdrop),
      child: Stack(
        children: [
          Positioned(
            top: -140,
            left: -120,
            child: _glow(Brand.red.withValues(alpha: 0.30), 420),
          ),
          Positioned(
            bottom: -180,
            right: -140,
            child: _glow(Brand.redDeep.withValues(alpha: 0.40), 460),
          ),
          Positioned.fill(child: child),
        ],
      ),
    );
  }

  Widget _glow(Color c, double size) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [c, c.withValues(alpha: 0)]),
        ),
      );
}

/// Glowing gradient pill button.
class GradientButton extends StatelessWidget {
  const GradientButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.expand = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final btn = Opacity(
      opacity: enabled ? 1 : 0.4,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: Brand.accent,
          borderRadius: BorderRadius.circular(100),
          boxShadow: enabled
              ? Brand.glow(0.6, blur: 48, spread: -2)
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(100),
            onTap: onPressed,
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 44, vertical: 22),
              child: Row(
                mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    Icon(icon, color: Colors.white, size: 26),
                    const SizedBox(width: 12),
                  ],
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      letterSpacing: 0.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return expand ? SizedBox(width: double.infinity, child: btn) : btn;
  }
}

/// A glowing circular progress ring. [value] null = indeterminate.
class GlowRing extends StatelessWidget {
  const GlowRing({
    super.key,
    this.value,
    this.size = 220,
    this.stroke = 12,
    this.child,
  });
  final double? value;
  final double size;
  final double stroke;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: Brand.glow(0.55, blur: 60, spread: 2),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(
              value: value,
              strokeWidth: stroke,
              backgroundColor: Brand.surface,
              valueColor: const AlwaysStoppedAnimation(Brand.redBright),
            ),
          ),
          ?child,
        ],
      ),
    );
  }
}

/// Animated 360° brand mark (rotating red gradient ring).
class BrandMark extends StatefulWidget {
  const BrandMark({super.key, this.size = 180, this.spin = true});
  final double size;
  final bool spin;

  @override
  State<BrandMark> createState() => _BrandMarkState();
}

class _BrandMarkState extends State<BrandMark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 8),
  )..repeat();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: Brand.glow(0.5, blur: 70, spread: 4),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          RotationTransition(
            turns:
                widget.spin ? _c : const AlwaysStoppedAnimation(0),
            child: Container(
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: SweepGradient(colors: [
                  Brand.redDeep,
                  Brand.red,
                  Brand.redBright,
                  Brand.redDeep,
                ]),
              ),
              padding: const EdgeInsets.all(8),
              child: const DecoratedBox(
                decoration:
                    BoxDecoration(shape: BoxShape.circle, color: Brand.bg0),
              ),
            ),
          ),
          Text(
            Brand.name,
            style: TextStyle(
              fontSize: widget.size * 0.26,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }
}
