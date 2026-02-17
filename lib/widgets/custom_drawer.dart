import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class CustomDrawer extends StatefulWidget {
  const CustomDrawer({super.key});

  // 🎨 Paleta CAPFISCAL
  static const _gold = Color(0xFFE1B85C);
  static const _goldDark = Color(0xFFB88F30);
  static const _text = Colors.white;
  static const _textMuted = Color(0xFFBEBEC6);
  static const _surface = Color(0xFF1C1C21);
  static const _surfaceAlt = Color(0xFF2A2A2F);

  @override
  State<CustomDrawer> createState() => _CustomDrawerState();
}

class _CustomDrawerState extends State<CustomDrawer> {
  String _cacheBustUrl(String url) {
    final ts = DateTime.now().millisecondsSinceEpoch.toString();
    try {
      final uri = Uri.parse(url);
      final qp = Map<String, String>.from(uri.queryParameters);
      qp['v'] = ts;
      return uri.replace(queryParameters: qp).toString();
    } catch (_) {
      return url.contains('?') ? '$url&v=$ts' : '$url?v=$ts';
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = ModalRoute.of(context)?.settings.name;
    final width = MediaQuery.of(context).size.width * 0.70;

    // Navegación segura desde el Drawer
    void go(String route) {
      final navigator = Navigator.of(context);
      final currentRoute = current;

      if (navigator.canPop()) navigator.pop();
      if (currentRoute == route) return;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context, rootNavigator: true).pushReplacementNamed(route);
      });
    }

    Future<void> signOut() async {
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      try {
        await FirebaseAuth.instance.signOut();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text('No se pudo cerrar sesión: $e')),
        );
        return;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context, rootNavigator: true)
            .pushNamedAndRemoveUntil('/login', (r) => false);
      });
    }

    Future<void> confirmSignOut() async {
      final ok = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: CustomDrawer._surface,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: const Text(
            'Cerrar sesión',
            style: TextStyle(
                color: CustomDrawer._text, fontWeight: FontWeight.w800),
          ),
          content: const Text(
            '¿Seguro que deseas cerrar tu sesión?',
            style: TextStyle(color: CustomDrawer._textMuted),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          actions: [
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.white24),
                foregroundColor: CustomDrawer._text,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: CustomDrawer._gold,
                foregroundColor: Colors.black,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              icon: const Icon(Icons.logout),
              label: const Text('Cerrar sesión'),
            ),
          ],
        ),
      );

      if (!mounted) return;
      if (ok == true) await signOut();
    }

    Widget navItem({
      required IconData icon,
      required String title,
      required String route,
    }) {
      final bool selected = current == route;
      return InkWell(
        onTap: () => go(route),
        borderRadius: BorderRadius.circular(12),
        splashColor: CustomDrawer._gold.withOpacity(.12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          decoration: BoxDecoration(
            color: selected ? CustomDrawer._surfaceAlt : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? CustomDrawer._gold.withOpacity(.35)
                  : Colors.white12,
            ),
          ),
          child: Row(
            children: [
              Icon(icon,
                  color: selected ? CustomDrawer._gold : CustomDrawer._text,
                  size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? CustomDrawer._gold : CustomDrawer._text,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
              Icon(Icons.chevron_right,
                  color:
                      selected ? CustomDrawer._gold : CustomDrawer._textMuted,
                  size: 20),
            ],
          ),
        ),
      );
    }

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
          child: StreamBuilder<User?>(
            // ✅ Se actualiza cuando cambie photoURL / displayName / reload
            stream: FirebaseAuth.instance.userChanges(),
            initialData: FirebaseAuth.instance.currentUser,
            builder: (context, authSnap) {
              final user = authSnap.data;

              // Nombre visible
              String displayName = (user?.displayName ?? '').trim();
              if (displayName.isEmpty) {
                final email = user?.email ?? '';
                displayName =
                    email.contains('@') ? email.split('@').first : 'Usuario';
              }
              displayName = displayName
                  .split(' ')
                  .where((p) => p.isNotEmpty)
                  .map((p) => p[0].toUpperCase() + p.substring(1))
                  .join(' ');

              return Column(
                children: [
                  // ===== Encabezado =====
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
                            bottom:
                                BorderSide(color: Color(0x33E1B85C), width: 1),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            InkWell(
                              onTap: () => go('/perfil'),
                              borderRadius: BorderRadius.circular(48),
                              child: _ProfileAvatar(
                                user: user,
                                cacheBustUrl: _cacheBustUrl,
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
                                      color: CustomDrawer._textMuted,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    displayName.toUpperCase(),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: CustomDrawer._gold,
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
                                        color: CustomDrawer._textMuted,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],

                                  // ✅ Badge nuevo: compras por documento
                                  if (user != null) ...[
                                    const SizedBox(height: 10),
                                    _PurchasesBadge(uid: user.uid),
                                  ],
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
                          onPressed: () => Navigator.of(context).maybePop(),
                          icon: const Icon(Icons.close,
                              color: CustomDrawer._text),
                        ),
                      ),
                    ],
                  ),

                  // ===== Opciones =====
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 14),
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

                  // ===== Pie: Cerrar sesión =====
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(
                                color: CustomDrawer._goldDark, width: 1),
                            foregroundColor: CustomDrawer._gold,
                            backgroundColor: CustomDrawer._surface,
                          ),
                          onPressed: confirmSignOut,
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
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Avatar que se actualiza con Firestore + Auth photoURL
class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({
    required this.user,
    required this.cacheBustUrl,
  });

  final User? user;
  final String Function(String url) cacheBustUrl;

  @override
  Widget build(BuildContext context) {
    final u = user;
    if (u == null) {
      return const CircleAvatar(
        radius: 48,
        backgroundColor: CustomDrawer._surfaceAlt,
        child: Icon(Icons.person, color: CustomDrawer._text, size: 56),
      );
    }

    final docRef = FirebaseFirestore.instance.collection('users').doc(u.uid);

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      // ✅ Si tu perfil actualiza users/{uid}.photoUrl, aquí se refresca al instante
      stream: docRef.snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data();
        final firestoreUrl = (data?['photoUrl'] as String?)?.trim();
        final authUrl = (u.photoURL ?? '').trim();

        // Prioridad: Firestore (porque tú sincronizas Storage→Firestore), luego Auth
        final raw = (firestoreUrl != null && firestoreUrl.isNotEmpty)
            ? firestoreUrl
            : authUrl;

        final finalUrl =
            (raw.isNotEmpty) ? cacheBustUrl(raw) : null; // ✅ anti-caché

        return CircleAvatar(
          radius: 48,
          backgroundColor: CustomDrawer._surfaceAlt,
          backgroundImage: (finalUrl != null) ? NetworkImage(finalUrl) : null,
          child: (finalUrl == null)
              ? const Icon(Icons.person, color: CustomDrawer._text, size: 56)
              : null,
        );
      },
    );
  }
}

class _PurchasesBadge extends StatelessWidget {
  const _PurchasesBadge({required this.uid});
  final String uid;

  @override
  Widget build(BuildContext context) {
    final col = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('doc_purchases');

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: col.snapshots(),
      builder: (context, snap) {
        final count = snap.data?.docs.length ?? 0;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: CustomDrawer._surfaceAlt,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: CustomDrawer._gold.withOpacity(.55)),
          ),
          child: Row(
            children: [
              const Icon(Icons.shopping_bag_rounded,
                  color: CustomDrawer._gold, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Documentos comprados: $count',
                  style: const TextStyle(
                    color: CustomDrawer._gold,
                    fontWeight: FontWeight.w800,
                    letterSpacing: .2,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
