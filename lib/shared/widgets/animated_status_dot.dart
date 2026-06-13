import 'package:flutter/material.dart';

/// Chấm tròn phát sóng ripple liên tục — thường dùng cho indicator status đang chạy.
class AnimatedStatusDot extends StatefulWidget {
  final Color color;
  final double size;
  final bool pulsing;

  const AnimatedStatusDot({
    super.key,
    required this.color,
    this.size = 12,
    this.pulsing = true,
  });

  @override
  State<AnimatedStatusDot> createState() => _AnimatedStatusDotState();
}

class _AnimatedStatusDotState extends State<AnimatedStatusDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void initState() {
    super.initState();
    if (widget.pulsing) _controller.repeat();
  }

  @override
  void didUpdateWidget(covariant AnimatedStatusDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pulsing && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.pulsing && _controller.isAnimating) {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size * 3,
      height: widget.size * 3,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (widget.pulsing)
            AnimatedBuilder(
              animation: _controller,
              builder: (_, _) {
                final t = _controller.value;
                final scale = 1 + t * 1.8;
                final opacity = (1 - t).clamp(0.0, 1.0);
                return Opacity(
                  opacity: opacity * 0.6,
                  child: Transform.scale(
                    scale: scale,
                    child: Container(
                      width: widget.size,
                      height: widget.size,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: widget.color,
                      ),
                    ),
                  ),
                );
              },
            ),
          Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.color,
              boxShadow: [
                BoxShadow(
                  color: widget.color.withValues(alpha: 0.4),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
