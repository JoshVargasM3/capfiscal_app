import 'package:flutter/material.dart';

class CapfiscalBottomNav extends StatelessWidget {
  const CapfiscalBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    this.background = const Color(0xFFEDEAEA), // gris claro del mockup
    this.activeColor = const Color(0xFF6B1A1A), // borgoña
    this.inactiveColor = const Color(0xFF6B1A1A),
  });

  final int currentIndex;
  final ValueChanged<int> onTap;
  final Color background;
  final Color activeColor;
  final Color inactiveColor;

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
              onTap: onTap,
              activeColor: activeColor,
              inactiveColor: inactiveColor,
            ),
            _Item(
              icon: Icons.ondemand_video_rounded, // Videos
              index: 1,
              currentIndex: currentIndex,
              onTap: onTap,
              activeColor: activeColor,
              inactiveColor: inactiveColor,
            ),
            _Item(
              icon: Icons.home_rounded, // Home
              index: 2,
              currentIndex: currentIndex,
              onTap: onTap,
              activeColor: activeColor,
              inactiveColor: inactiveColor,
            ),
            _Item(
              icon: Icons.chat_bubble_rounded, // Chat
              index: 3,
              currentIndex: currentIndex,
              onTap: onTap,
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
    required this.onTap,
    required this.activeColor,
    required this.inactiveColor,
  });

  final IconData icon;
  final int index;
  final int currentIndex;
  final ValueChanged<int> onTap;
  final Color activeColor;
  final Color inactiveColor;

  @override
  Widget build(BuildContext context) {
    final bool active = index == currentIndex;

    return GestureDetector(
      onTap: () => onTap(index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: active ? activeColor : Colors.transparent,
          borderRadius: BorderRadius.circular(14), // “píldora” del mockup
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
