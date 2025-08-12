// lib/widgets/custom_drawer.dart
import 'package:flutter/material.dart';

class CustomDrawer extends StatelessWidget {
  const CustomDrawer({super.key});

  static const _brand = Color(0xFF6B1A1A);

  @override
  Widget build(BuildContext context) {
    final current = ModalRoute.of(context)?.settings.name;

    void _go(String route) {
      Navigator.pop(context); // Cierra el drawer primero
      if (current == route) return; // Ya estás ahí
      Navigator.pushReplacementNamed(context, route);
    }

    Widget tile({
      required IconData icon,
      required String title,
      String? subtitle,
      required String route,
    }) {
      final bool selected = current == route;
      return ListTile(
        leading: Icon(icon, color: _brand),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? _brand : Colors.black87,
          ),
        ),
        subtitle: subtitle != null ? Text(subtitle) : null,
        selected: selected,
        selectedTileColor: _brand.withOpacity(.10),
        onTap: () => _go(route),
        trailing: const Icon(Icons.chevron_right),
      );
    }

    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            // Encabezado con logo y nombre
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(
                  bottom: BorderSide(color: Color(0x22000000)),
                ),
              ),
              child: Row(
                children: [
                  // Logo
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE7E7E7),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Image.asset(
                      'assets/capfiscal_logo.png',
                      fit: BoxFit.contain,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Título app
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        'CAPFISCAL',
                        style: TextStyle(
                          color: _brand,
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                          letterSpacing: .3,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Biblioteca & Capacitación',
                        style: TextStyle(
                          color: Colors.black54,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Opciones
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(top: 8),
                children: [
                  tile(
                    icon: Icons.home_rounded,
                    title: 'Inicio',
                    subtitle: 'Explora novedades',
                    route: '/home',
                  ),
                  const Divider(height: 8),
                  tile(
                    icon: Icons.library_books_rounded,
                    title: 'Biblioteca Legal',
                    subtitle: 'Documentos disponibles',
                    route: '/biblioteca',
                  ),
                  tile(
                    icon: Icons.ondemand_video_rounded,
                    title: 'Videos',
                    subtitle: 'Reproductor de videos',
                    route: '/video',
                  ),
                  tile(
                    icon: Icons.chat_bubble_rounded,
                    title: 'Chat',
                    subtitle: 'Centro de mensajería',
                    route: '/chat',
                  ),
                  tile(
                    icon: Icons.person_rounded,
                    title: 'Perfil',
                    subtitle: 'Mis datos y suscripción',
                    route: '/perfil',
                  ),
                ],
              ),
            ),

            // Pie con versión o créditos (opcional)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Row(
                children: const [
                  Icon(Icons.info_outline, size: 16, color: Colors.black45),
                  SizedBox(width: 8),
                  Text(
                    'v1.0.0',
                    style: TextStyle(color: Colors.black45, fontSize: 12),
                  ),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }
}
