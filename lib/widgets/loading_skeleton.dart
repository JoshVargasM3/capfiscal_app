import 'package:flutter/material.dart';

class HomeModuleSkeleton extends StatefulWidget {
  const HomeModuleSkeleton({super.key});

  @override
  State<HomeModuleSkeleton> createState() => _HomeModuleSkeletonState();
}

class _HomeModuleSkeletonState extends State<HomeModuleSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final baseColor = Colors.white.withOpacity(0.08);
    final highlight = Colors.white.withOpacity(0.18);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value;
        final color = Color.lerp(baseColor, highlight, t)!;
        return Container(
          color: const Color(0xFF1C1C21),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SkeletonBlock(height: 18, width: 160, color: color),
              const SizedBox(height: 16),
              _SkeletonBlock(height: 180, width: double.infinity, color: color),
              const SizedBox(height: 24),
              Row(
                children: const [
                  Icon(Icons.lightbulb_outline, color: Colors.white70),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Mientras cargamos tus módulos, prueba estas sugerencias rápidas.',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: const [
                  _SuggestionChip(label: 'Explora la biblioteca'),
                  _SuggestionChip(label: 'Revisa tus cursos favoritos'),
                  _SuggestionChip(label: 'Anota pendientes en modo offline'),
                  _SuggestionChip(label: 'Configura alertas locales'),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SkeletonBlock extends StatelessWidget {
  const _SkeletonBlock({
    required this.height,
    required this.width,
    required this.color,
  });

  final double height;
  final double width;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: width,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(14),
      ),
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  const _SuggestionChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white12),
      ),
      child: Text(
        label,
        style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600),
      ),
    );
  }
}
