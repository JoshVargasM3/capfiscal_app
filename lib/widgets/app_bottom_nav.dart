// lib/widgets/app_bottom_nav.dart
import 'package:flutter/material.dart';

class CapfiscalBottomNav extends StatelessWidget {
  const CapfiscalBottomNav({
    super.key,
    required this.currentIndex,
    this.onTap, // si lo dejas null, se usa la navegación por defecto
    this.background = const Color(0xFFEDEAEA), // gris claro del mockup
    this.activeColor = const Color(0xFF6B1A1A), // borgoña
    this.inactiveColor = const Color(0xFF6B1A1A),
  });

  final int currentIndex;
  final ValueChanged<int>? onTap;
  final Color background;
  final Color activeColor;
  final Color inactiveColor;

  void _defaultNavigate(BuildContext context, int i) {
    final routes = const ['/biblioteca', '/video', '/home', '/chat'];
    final target = routes[i];
    final current = ModalRoute.of(context)?.settings.name;

    if (current == target) return;
    Navigator.pushReplacementNamed(context, target);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
        decoration: BoxDecoration(
          color: background,
          border: const Border(
            top: BorderSide(color: Color(0x22000000)),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _Item(
              icon: Icons.menu_book_rounded, // Biblioteca
              index: 0,
              currentIndex: currentIndex,
              onPressed: (i) =>
                  onTap != null ? onTap!(i) : _defaultNavigate(context, i),
              activeColor: activeColor,
              inactiveColor: inactiveColor,
            ),
            _Item(
              icon: Icons.ondemand_video_rounded, // Videos
              index: 1,
              currentIndex: currentIndex,
              onPressed: (i) =>
                  onTap != null ? onTap!(i) : _defaultNavigate(context, i),
              activeColor: activeColor,
              inactiveColor: inactiveColor,
            ),
            _Item(
              icon: Icons.home_rounded, // Home
              index: 2,
              currentIndex: currentIndex,
              onPressed: (i) =>
                  onTap != null ? onTap!(i) : _defaultNavigate(context, i),
              activeColor: activeColor,
              inactiveColor: inactiveColor,
            ),
            _Item(
              icon: Icons.chat_bubble_rounded, // Chat
              index: 3,
              currentIndex: currentIndex,
              onPressed: (i) =>
                  onTap != null ? onTap!(i) : _defaultNavigate(context, i),
              activeColor: activeColor,
              inactiveColor: inactiveColor,
            ),
          ],
        ),
      ),
    );
  }
}

class _Item extends StatelessWidget {
  const _Item({
    required this.icon,
    required this.index,
    required this.currentIndex,
    required this.onPressed,
    required this.activeColor,
    required this.inactiveColor,
  });

  final IconData icon;
  final int index;
  final int currentIndex;
  final ValueChanged<int> onPressed;
  final Color activeColor;
  final Color inactiveColor;

  @override
  Widget build(BuildContext context) {
    final bool active = index == currentIndex;

    return GestureDetector(
      onTap: () => onPressed(index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: active ? activeColor : Colors.transparent,
          borderRadius: BorderRadius.circular(14), // píldora
        ),
        child: Icon(
          icon,
          size: 26,
          color: active ? Colors.white : inactiveColor,
        ),
      ),
    );
  }
}
