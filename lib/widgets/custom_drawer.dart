// lib/widgets/custom_drawer.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class CustomDrawer extends StatelessWidget {
  const CustomDrawer({super.key});

  // 🎨 Paleta CAPFISCAL
  static const _gold = Color(0xFFE1B85C);
  static const _goldDark = Color(0xFFB88F30);
  static const _text = Colors.white;
  static const _textMuted = Color(0xFFBEBEC6);
  static const _surface = Color(0xFF1C1C21);
  static const _surfaceAlt = Color(0xFF2A2A2F);

  @override
  Widget build(BuildContext context) {
    final current = ModalRoute.of(context)?.settings.name;
    final user = FirebaseAuth.instance.currentUser;

    // Nombre visible
    String displayName = (user?.displayName ?? '').trim();
    if (displayName.isEmpty) {
      final email = user?.email ?? '';
      displayName = email.contains('@') ? email.split('@').first : 'Usuario';
    }
    displayName = displayName
        .split(' ')
        .where((p) => p.isNotEmpty)
        .map((p) => p[0].toUpperCase() + p.substring(1))
        .join(' ');

    void _go(String route) {
      Navigator.pop(context); // Cierra el drawer primero
      if (current == route) return;
      Navigator.pushReplacementNamed(context, route);
    }

    Future<void> _signOut() async {
      // Cierra el drawer
      Navigator.pop(context);
      try {
        await FirebaseAuth.instance.signOut();
        // Volvemos a la raíz ('/') y AuthGate decide -> login
        // ignore: use_build_context_synchronously
        Navigator.pushNamedAndRemoveUntil(context, '/', (r) => false);
      } catch (e) {
        // ignore: use_build_context_synchronously
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo cerrar sesión: $e')),
        );
      }
    }

    Future<void> _confirmSignOut() async {
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: _surface,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: const Text(
            'Cerrar sesión',
            style: TextStyle(color: _text, fontWeight: FontWeight.w800),
          ),
          content: const Text(
            '¿Seguro que deseas cerrar tu sesión?',
            style: TextStyle(color: _textMuted),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          actions: [
            // Cancelar (outline tenue, estilo app)
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.white24),
                foregroundColor: _text,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            // Cerrar sesión (dorado, estilo app)
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: _gold,
                foregroundColor: Colors.black,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () => Navigator.pop(context, true),
              icon: const Icon(Icons.logout),
              label: const Text('Cerrar sesión'),
            ),
          ],
        ),
      );
      if (ok == true) {
        await _signOut();
      }
    }

    Widget navItem({
      required IconData icon,
      required String title,
      required String route,
    }) {
      final bool selected = current == route;
      return InkWell(
        onTap: () => _go(route),
        borderRadius: BorderRadius.circular(12),
        splashColor: _gold.withOpacity(.12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          decoration: BoxDecoration(
            color: selected ? _surfaceAlt : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? _gold.withOpacity(.35) : Colors.white12,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, color: selected ? _gold : _text, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? _gold : _text,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: selected ? _gold : _textMuted,
                size: 20,
              ),
            ],
          ),
        ),
      );
    }

    final width = MediaQuery.of(context).size.width * 0.70; // 70%

    return Drawer(
      elevation: 16,
      width: width,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0A0A0B), Color(0xFF2A2A2F)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // ===== Encabezado con avatar grande + info a la derecha =====
              Stack(
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 22),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF141416), Color(0xFF1E1E23)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      border: Border(
                        bottom: BorderSide(color: Color(0x33E1B85C), width: 1),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // 👇 Navega a /perfil al tocar la foto
                        InkWell(
                          onTap: () => _go('/perfil'),
                          borderRadius: BorderRadius.circular(48),
                          child: CircleAvatar(
                            radius: 48,
                            backgroundColor: _surfaceAlt,
                            backgroundImage: (user?.photoURL != null &&
                                    user!.photoURL!.isNotEmpty)
                                ? NetworkImage(user.photoURL!)
                                : null,
                            child: (user?.photoURL == null ||
                                    (user?.photoURL?.isEmpty ?? true))
                                ? const Icon(Icons.person,
                                    color: _text, size: 56)
                                : null,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                '¡Saludos Colega!',
                                style: TextStyle(
                                  color: _textMuted,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                displayName.toUpperCase(),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: _gold,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: .6,
                                  height: 1.05,
                                ),
                              ),
                              if (user?.email != null) ...[
                                const SizedBox(height: 2),
                                Text(
                                  user!.email!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: _textMuted,
                                    fontSize: 11,
                                  ),
                                ),
                              ]
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    right: 6,
                    top: 6,
                    child: IconButton(
                      tooltip: 'Cerrar',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close, color: _text),
                    ),
                  ),
                ],
              ),

              // ===== Opciones (Scroll para asegurar legibilidad) =====
              Expanded(
                child: SingleChildScrollView(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  child: Column(
                    children: [
                      navItem(
                          icon: Icons.home_rounded,
                          title: 'Inicio',
                          route: '/home'),
                      const SizedBox(height: 10),
                      navItem(
                          icon: Icons.library_books_rounded,
                          title: 'Documentos',
                          route: '/biblioteca'),
                      const SizedBox(height: 10),
                      navItem(
                          icon: Icons.ondemand_video_rounded,
                          title: 'Videos',
                          route: '/video'),
                      const SizedBox(height: 10),
                      navItem(
                          icon: Icons.favorite_rounded,
                          title: 'Favoritos',
                          route: '/perfil'),
                      const SizedBox(height: 10),
                      navItem(
                          icon: Icons.chat_bubble_rounded,
                          title: 'Chat',
                          route: '/chat'),
                      const SizedBox(height: 18),
                      Container(height: 1, color: Colors.white12),
                      const SizedBox(height: 18),
                      navItem(
                          icon: Icons.person_rounded,
                          title: 'Perfil',
                          route: '/perfil'),
                    ],
                  ),
                ),
              ),

              // ===== Pie: Cerrar sesión (con confirmación y look de la app) =====
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: _goldDark, width: 1),
                        foregroundColor: _gold,
                        backgroundColor: _surface,
                      ),
                      onPressed: _confirmSignOut,
                      icon: const Icon(Icons.logout_rounded, size: 18),
                      label: const Text(
                        'Cerrar Sesión',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
