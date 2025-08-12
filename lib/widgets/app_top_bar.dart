// lib/widgets/app_top_bar.dart
import 'package:flutter/material.dart';

class CapfiscalTopBar extends StatelessWidget implements PreferredSizeWidget {
  const CapfiscalTopBar({
    super.key,
    required this.onMenu,
    required this.onRefresh,
    required this.onProfile,
    this.logoAsset = 'assets/capfiscal_logo.png',
    this.backgroundColor = const Color(0xFF6B1A1A),
    this.showRefresh = true,
  });

  final VoidCallback onMenu;
  final VoidCallback onRefresh;
  final VoidCallback onProfile;
  final String logoAsset;
  final Color backgroundColor;
  final bool showRefresh;

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context) {
    return Container(
      color: backgroundColor,
      padding: const EdgeInsets.only(top: 8),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 56,
          child: Row(
            children: [
              IconButton(
                onPressed: onMenu,
                icon: const Icon(Icons.menu, color: Colors.white),
              ),
              Expanded(
                child: Center(
                  child: SizedBox(
                    height: 36,
                    child: Image.asset(
                      logoAsset,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Text(
                        'CAPFISCAL',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (showRefresh)
                IconButton(
                  tooltip: 'Actualizar',
                  onPressed: onRefresh,
                  icon: const Icon(Icons.refresh, color: Colors.white),
                ),
              IconButton(
                tooltip: 'Perfil',
                onPressed: onProfile,
                icon: const Icon(Icons.person, color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
