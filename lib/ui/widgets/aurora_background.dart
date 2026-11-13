import 'dart:ui';

import 'package:material_ui/material_ui.dart';

import '../theme.dart';

/// Живой градиентный фон: три «сияния», медленно плывущие по экрану.
/// Рисуется через [CustomPainter], без сети и без тяжёлых blur-слоёв,
/// поэтому одинаково работает на устройстве и в widget-тестах.
class AuroraBackground extends StatefulWidget {
  const AuroraBackground({
    super.key,
    required this.child,
    this.animate = true,
  });

  final Widget child;
  final bool animate;

  @override
  State<AuroraBackground> createState() => _AuroraBackgroundState();
}

class _AuroraBackgroundState extends State<AuroraBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 18),
  );

  @override
  void initState() {
    super.initState();
    if (widget.animate) _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: AppColors.background),
        AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => CustomPaint(
            painter: _AuroraPainter(t: _controller.value),
            size: Size.infinite,
          ),
        ),
        widget.child,
      ],
    );
  }
}

class _AuroraPainter extends CustomPainter {
  _AuroraPainter({required this.t});

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final twoPi = 6.28318;

    void blob(Offset center, double radius, Color color) {
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [color.withValues(alpha: 0.42), color.withValues(alpha: 0)],
        ).createShader(Rect.fromCircle(center: center, radius: radius));
      canvas.drawCircle(center, radius, paint);
    }

    blob(
      Offset(
        w * (0.18 + 0.06 * _sin(t * twoPi)),
        h * (0.10 + 0.04 * _cos(t * twoPi)),
      ),
      w * 0.75,
      const Color(0xFF35E1FF),
    );
    blob(
      Offset(
        w * (0.92 + 0.05 * _cos(t * twoPi + 1.2)),
        h * (0.34 + 0.05 * _sin(t * twoPi + 0.7)),
      ),
      w * 0.65,
      const Color(0xFFFF5C8A),
    );
    blob(
      Offset(
        w * (0.35 + 0.08 * _sin(t * twoPi + 2.4)),
        h * (0.88 + 0.03 * _cos(t * twoPi + 1.9)),
      ),
      w * 0.8,
      const Color(0xFF5B8CFF),
    );

    // Лёгкая виньетка, чтобы текст всегда читался.
    final vignette = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xCC05070E), Color(0x0005070E), Color(0xF205070E)],
        stops: [0, 0.45, 1],
      ).createShader(Rect.fromLTWH(0, 0, w, h));
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), vignette);
  }

  double _sin(double x) => _fastSin(x);
  double _cos(double x) => _fastSin(x + 1.5708);

  /// Обычный sin через dart:math не тащим в painter, но точность тут не нужна.
  double _fastSin(double x) {
    const mod = 6.283185307;
    var v = x % mod;
    if (v < 0) v += mod;
    // Ряд Тейлора достаточен для плавной анимации.
    return v < 3.14159
        ? v * (1 - v * v / 6 + v * v * v * v / 120)
        : -((v - 3.14159) * (1 - (v - 3.14159) * (v - 3.14159) / 6));
  }

  @override
  bool shouldRepaint(_AuroraPainter oldDelegate) => oldDelegate.t != t;
}

/// Небольшая стеклянная подложка (эффект frosted glass).
class FrostedPanel extends StatelessWidget {
  const FrostedPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = AppRadius.card,
    this.blur = 18,
    this.color,
    this.borderColor,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final double blur;
  final Color? color;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: color ?? const Color(0x1AFFFFFF),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: borderColor ?? AppColors.stroke),
          ),
          child: child,
        ),
      ),
    );
  }
}
