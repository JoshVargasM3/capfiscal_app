import 'package:flutter/material.dart';

class CapfiscalTopBar extends StatelessWidget implements PreferredSizeWidget {
  const CapfiscalTopBar({
    super.key,
    required this.onMenu,
    required this.onRefresh,
    this.onProfile, // <- opcional, ya no se usa pero no rompe llamadas viejas
    this.logoAsset = 'assets/capfiscal_logo.png',
    this.showRefresh = true,
  });

  final VoidCallback onMenu;
  final VoidCallback onRefresh;
  final VoidCallback? onProfile; // <- quedó opcional para compatibilidad
  final String logoAsset;
  final bool showRefresh;

  @override
  Size get preferredSize => const Size.fromHeight(64);

  void _goHome(BuildContext context) {
    final current = ModalRoute.of(context)?.settings.name;
    if (current != '/home') {
      Navigator.pushReplacementNamed(context, '/home');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0A0A0B), Color(0xFF2A2A2F)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        border: Border(
          bottom: BorderSide(
            color: Color(0x33E1B85C), // línea dorada tenue
            width: 1,
          ),
        ),
      ),
      padding: const EdgeInsets.only(top: 8),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 56,
          child: Row(
            children: [
              // Botón menú
              IconButton(
                onPressed: onMenu,
                splashRadius: 22,
                icon: const Icon(
                  Icons.menu,
                  color: Color(0xFFE1B85C), // dorado
                  size: 26,
                ),
              ),

              // Logo centrado (tap -> Home)
              Expanded(
                child: Center(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _goHome(context),
                    child: SizedBox(
                      height: 36,
                      child: Image.asset(
                        logoAsset,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Text(
                          'CAPFISCAL',
                          style: TextStyle(
                            color: Color(0xFFE1B85C),
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // Botón refrescar opcional
              if (showRefresh)
                IconButton(
                  tooltip: 'Actualizar',
                  onPressed: onRefresh,
                  splashRadius: 22,
                  icon: const Icon(
                    Icons.refresh,
                    color: Color(0xFFE1B85C),
                    size: 24,
                  ),
                ),

              // ❌ Se elimina el botón de perfil (dejamos onProfile solo por compatibilidad)
            ],
          ),
        ),
      ),
    );
  }
}
