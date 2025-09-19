import 'package:flutter/material.dart';

class CapfiscalBottomNav extends StatelessWidget {
  const CapfiscalBottomNav({
    super.key,
    required this.currentIndex,
    this.onTap, // si lo dejas null, se usa la navegación por defecto
    this.background = const Color(0xFF0A0A0B), // negro profundo
    this.activeColor = const Color(0xFFE1B85C), // dorado base
    this.inactiveColor = const Color(0xFFBEBEC6), // gris claro
  });

  final int currentIndex;
  final ValueChanged<int>? onTap;
  final Color background;
  final Color activeColor;
  final Color inactiveColor;

  void _defaultNavigate(BuildContext context, int i) {
    final routes = const [
      '/biblioteca', // 0
      '/video', // 1
      '/home', // 2
      '/chat', // 3
      '/perfil' // 4 (nuevo perfil)
    ];

    final target = routes[i];
    final current = ModalRoute.of(context)?.settings.name;

    if (current == target) return;
    Navigator.pushReplacementNamed(context, target);
  }

  @override
  Widget build(BuildContext context) {
    // tono dorado más oscuro para degradado
    const goldDark = Color(0xFFB88F30);

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
        decoration: BoxDecoration(
          color: background,
          border: const Border(
            top: BorderSide(color: Color(0x33E1B85C)), // dorado translúcido
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
              activeColorDark: goldDark,
            ),
            _Item(
              icon: Icons.ondemand_video_rounded, // Videos
              index: 1,
              currentIndex: currentIndex,
              onPressed: (i) =>
                  onTap != null ? onTap!(i) : _defaultNavigate(context, i),
              activeColor: activeColor,
              inactiveColor: inactiveColor,
              activeColorDark: goldDark,
            ),
            _Item(
              icon: Icons.home_rounded, // Home
              index: 2,
              currentIndex: currentIndex,
              onPressed: (i) =>
                  onTap != null ? onTap!(i) : _defaultNavigate(context, i),
              activeColor: activeColor,
              inactiveColor: inactiveColor,
              activeColorDark: goldDark,
            ),
            _Item(
              icon: Icons.chat_bubble_rounded, // Chat
              index: 3,
              currentIndex: currentIndex,
              onPressed: (i) =>
                  onTap != null ? onTap!(i) : _defaultNavigate(context, i),
              activeColor: activeColor,
              inactiveColor: inactiveColor,
              activeColorDark: goldDark,
            ),
            _Item(
              icon: Icons.person_rounded, // Perfil
              index: 4,
              currentIndex: currentIndex,
              onPressed: (i) =>
                  onTap != null ? onTap!(i) : _defaultNavigate(context, i),
              activeColor: activeColor,
              inactiveColor: inactiveColor,
              activeColorDark: goldDark,
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
    required this.activeColorDark,
  });

  final IconData icon;
  final int index;
  final int currentIndex;
  final ValueChanged<int> onPressed;
  final Color activeColor;
  final Color inactiveColor;
  final Color activeColorDark;

  @override
  Widget build(BuildContext context) {
    final bool active = index == currentIndex;

    // píldora con degradado dorado y sombra suave cuando está activo
    final BoxDecoration activeDeco = BoxDecoration(
      gradient: LinearGradient(
        colors: [activeColor, activeColorDark],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(18),
      boxShadow: const [
        BoxShadow(
          color: Color(0x55E1B85C),
          blurRadius: 12,
          offset: Offset(0, 4),
        ),
      ],
    );

    final BoxDecoration inactiveDeco = BoxDecoration(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
    );

    return GestureDetector(
      onTap: () => onPressed(index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: active ? activeDeco : inactiveDeco,
        child: Icon(
          icon,
          size: 26,
          color: active ? Colors.black : inactiveColor, // contraste con dorado
        ),
      ),
    );
  }
}
