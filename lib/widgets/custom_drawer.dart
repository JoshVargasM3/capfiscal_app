// lib/widgets/custom_drawer.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:math' as math;

class CustomDrawer extends StatelessWidget {
  const CustomDrawer({super.key});

  // 🎨 Paleta CAPFISCAL
  static const _gold = Color(0xFFE1B85C);
  static const _goldDark = Color(0xFFB88F30);
  static const _text = Colors.white;
  static const _textMuted = Color(0xFFBEBEC6);
  static const _surface = Color(0xFF1C1C21);
  static const _surfaceAlt = Color(0xFF2A2A2F);

  double _clamp(double v, double minV, double maxV) =>
      math.max(minV, math.min(maxV, v));

  @override
  Widget build(BuildContext context) {
    final current = ModalRoute.of(context)?.settings.name;
    final user = FirebaseAuth.instance.currentUser;

    // Nombre visible (displayName > email local-part > "Usuario")
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
      Navigator.pop(context);
      await FirebaseAuth.instance.signOut();
      // Ajusta si tu ruta de login es diferente
      // ignore: use_build_context_synchronously
      Navigator.pushNamedAndRemoveUntil(context, '/home', (r) => false);
    }

    // ======= Responsividad =======
    final screen = MediaQuery.of(context).size;
    // Drawer al 50%, pero si la pantalla es muy angosta, usamos 60% para dar respiro al texto
    final drawerWidth = screen.width * (screen.width < 360 ? 0.60 : 0.50);

    // Base de diseño ~360 px de ancho; sacamos factor de escala y lo acotamos
    final base = 360.0;
    final s = _clamp(drawerWidth / base, 0.85, 1.20);

    // Tamaños responsivos
    final pad = 16.0 * s;
    final avatarR = _clamp(50.0 * s, 40, 66); // avatar visible y grande
    final nameSize = _clamp(22.0 * s, 16, 26);
    final greetSize = _clamp(12.0 * s, 11, 14);
    final emailSize = _clamp(11.0 * s, 10, 13);
    final itemFont = _clamp(14.0 * s, 13, 16);
    final itemIcon = _clamp(22.0 * s, 18, 26);
    final chevronSize = _clamp(20.0 * s, 18, 22);
    final closeSize = _clamp(22.0 * s, 20, 24);
    final signBtnPadV = _clamp(12.0 * s, 10, 14);
    final signBtnPadH = _clamp(12.0 * s, 10, 16);
    final headerSpacing = _clamp(14.0 * s, 10, 18);

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
          padding:
              EdgeInsets.symmetric(horizontal: pad * .75, vertical: pad * .6),
          decoration: BoxDecoration(
            color: selected ? _surfaceAlt : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? _gold.withOpacity(.35) : Colors.white12,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, color: selected ? _gold : _text, size: itemIcon),
              SizedBox(width: pad * .6),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? _gold : _text,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    fontSize: itemFont,
                    height: 1.15,
                  ),
                ),
              ),
              Icon(Icons.chevron_right,
                  color: selected ? _gold : _textMuted, size: chevronSize),
            ],
          ),
        ),
      );
    }

    // Limita el textScaleFactor del SO (acota muy grandes)
    final mq = MediaQuery.of(context);
    final safeMQ = mq.copyWith(
      textScaleFactor: _clamp(mq.textScaleFactor, 0.9, 1.2),
    );

    return MediaQuery(
      data: safeMQ,
      child: Drawer(
        elevation: 16,
        width: drawerWidth,
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
                      padding: EdgeInsets.fromLTRB(pad, pad, pad, pad * 1.2),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF141416), Color(0xFF1E1E23)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        border: Border(
                          bottom:
                              BorderSide(color: Color(0x33E1B85C), width: 1),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // Avatar grande responsivo
                          CircleAvatar(
                            radius: avatarR,
                            backgroundColor: _surfaceAlt,
                            backgroundImage: (user?.photoURL != null &&
                                    user!.photoURL!.isNotEmpty)
                                ? NetworkImage(user.photoURL!)
                                : null,
                            child: (user?.photoURL == null ||
                                    (user?.photoURL?.isEmpty ?? true))
                                ? Icon(Icons.person,
                                    color: _text, size: avatarR * 1.2)
                                : null,
                          ),
                          SizedBox(width: headerSpacing),
                          // Info a la derecha
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '¡Saludos Colega!',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: _textMuted,
                                    fontSize: greetSize,
                                    height: 1.1,
                                  ),
                                ),
                                SizedBox(height: 4 * s),
                                Tooltip(
                                  message: displayName,
                                  child: Text(
                                    displayName.toUpperCase(),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: _gold,
                                      fontSize: nameSize,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: .6,
                                      height: 1.1,
                                    ),
                                  ),
                                ),
                                if (user?.email != null) ...[
                                  SizedBox(height: 2 * s),
                                  Tooltip(
                                    message: user!.email!,
                                    child: Text(
                                      user.email!,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: _textMuted,
                                        fontSize: emailSize,
                                        height: 1.1,
                                      ),
                                    ),
                                  ),
                                ]
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Botón X para cerrar
                    Positioned(
                      right: 6,
                      top: 6,
                      child: IconButton(
                        tooltip: 'Cerrar',
                        onPressed: () => Navigator.pop(context),
                        icon: Icon(Icons.close, color: _text, size: closeSize),
                      ),
                    ),
                  ],
                ),

                // ===== Opciones =====
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.symmetric(
                        horizontal: pad * .9, vertical: pad * .9),
                    children: [
                      navItem(
                          icon: Icons.home_rounded,
                          title: 'Inicio',
                          route: '/home'),
                      SizedBox(height: pad * .6),
                      navItem(
                          icon: Icons.library_books_rounded,
                          title: 'Documentos',
                          route: '/biblioteca'),
                      SizedBox(height: pad * .6),
                      navItem(
                          icon: Icons.ondemand_video_rounded,
                          title: 'Videos',
                          route: '/video'),
                      SizedBox(height: pad * .6),
                      navItem(
                          icon: Icons.favorite_rounded,
                          title: 'Favoritos',
                          route: '/perfil'),
                      SizedBox(height: pad * .6),
                      navItem(
                          icon: Icons.chat_bubble_rounded,
                          title: 'Chat',
                          route: '/chat'),
                      SizedBox(height: pad),
                      Container(height: 1, color: Colors.white12),
                      SizedBox(height: pad),
                      navItem(
                          icon: Icons.person_rounded,
                          title: 'Perfil',
                          route: '/perfil'),
                    ],
                  ),
                ),

                // ===== Pie: Cerrar sesión =====
                Padding(
                  padding: EdgeInsets.fromLTRB(pad, pad * .4, pad, pad * .8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: _goldDark, width: 1),
                          foregroundColor: _gold,
                          backgroundColor: _surface,
                          padding: EdgeInsets.symmetric(
                            horizontal: signBtnPadH,
                            vertical: signBtnPadV,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          textStyle: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: _clamp(14 * s, 12, 16),
                          ),
                        ),
                        onPressed: _signOut,
                        icon: Icon(Icons.logout_rounded,
                            size: _clamp(18 * s, 16, 20)),
                        label: const Text('Cerrar Sesión'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
