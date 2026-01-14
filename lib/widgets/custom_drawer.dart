import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../services/subscription_service.dart';

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
  // 🔥 Override (resultado confirmado del server)
  SubscriptionStatus? _serverOverride;
  bool _forcingServer = false;
  String? _lastForcedUid;

  Future<void> _forceServerOnce(String uid) async {
    if (_forcingServer) return;
    // evita repetir si ya forzamos este uid y ya tenemos override reciente
    if (_lastForcedUid == uid && _serverOverride != null) return;

    _forcingServer = true;
    _lastForcedUid = uid;

    try {
      final ref = FirebaseFirestore.instance.collection('users').doc(uid);
      final snap = await ref.get(const GetOptions(source: Source.server));
      final status = SubscriptionStatus.fromSnapshot(snap);
      if (!mounted) return;
      setState(() => _serverOverride = status);
    } catch (_) {
      // si falla, no reventamos UI
    } finally {
      _forcingServer = false;
    }
  }

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

    final width = MediaQuery.of(context).size.width * 0.70;

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
                        bottom: BorderSide(color: Color(0x33E1B85C), width: 1),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        InkWell(
                          onTap: () => go('/perfil'),
                          borderRadius: BorderRadius.circular(48),
                          child: CircleAvatar(
                            radius: 48,
                            backgroundColor: CustomDrawer._surfaceAlt,
                            backgroundImage: (user?.photoURL != null &&
                                    user!.photoURL!.isNotEmpty)
                                ? NetworkImage(user.photoURL!)
                                : null,
                            child: (user?.photoURL == null ||
                                    (user?.photoURL?.isEmpty ?? true))
                                ? const Icon(Icons.person,
                                    color: CustomDrawer._text, size: 56)
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

                              // ✅ Badge con cache-aware + server override
                              if (user != null) ...[
                                const SizedBox(height: 10),
                                StreamBuilder<
                                    DocumentSnapshot<Map<String, dynamic>>>(
                                  stream: FirebaseFirestore.instance
                                      .collection('users')
                                      .doc(user.uid)
                                      .snapshots(includeMetadataChanges: true),
                                  builder: (context, snap) {
                                    final nowUtc = DateTime.now().toUtc();
                                    final fromCache =
                                        snap.data?.metadata.isFromCache ?? true;

                                    SubscriptionStatus parsed =
                                        SubscriptionStatus.empty();
                                    if (snap.hasData) {
                                      parsed = SubscriptionStatus.fromSnapshot(
                                          snap.data!);
                                    }

                                    // ✅ Si llega de cache y sale vencida/none, forzamos server una vez
                                    final looksWrong = parsed.state ==
                                            SubscriptionState.expired ||
                                        parsed.state == SubscriptionState.none;

                                    if (fromCache && looksWrong) {
                                      // dispara en el próximo frame para no llamar durante build
                                      WidgetsBinding.instance
                                          .addPostFrameCallback((_) {
                                        if (!mounted) return;
                                        _forceServerOnce(user.uid);
                                      });
                                    }

                                    final status = _serverOverride ?? parsed;

                                    return _SubscriptionBadge(
                                      status: status,
                                      sourceIsCache: fromCache,
                                      uid: user.uid,
                                      nowUtc: nowUtc,
                                      onRefresh: () async {
                                        // refresh manual SIEMPRE server
                                        _serverOverride = null;
                                        await _forceServerOnce(user.uid);
                                        return _serverOverride ?? status;
                                      },
                                    );
                                  },
                                ),
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
                      icon: const Icon(Icons.close, color: CustomDrawer._text),
                    ),
                  ),
                ],
              ),

              // ===== Opciones =====
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

              // ===== Pie: Cerrar sesión =====
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
          ),
        ),
      ),
    );
  }
}

class _SubscriptionBadge extends StatefulWidget {
  const _SubscriptionBadge({
    required this.status,
    required this.onRefresh,
    required this.sourceIsCache,
    required this.uid,
    required this.nowUtc,
  });

  final SubscriptionStatus status;
  final Future<SubscriptionStatus> Function()? onRefresh;

  // debug
  final bool sourceIsCache;
  final String uid;
  final DateTime nowUtc;

  @override
  State<_SubscriptionBadge> createState() => _SubscriptionBadgeState();
}

class _SubscriptionBadgeState extends State<_SubscriptionBadge> {
  bool _loading = false;

  Future<void> _handleRefresh() async {
    if (widget.onRefresh == null || _loading) return;
    setState(() => _loading = true);
    try {
      final newStatus = await widget.onRefresh!.call();
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(_refreshMessage(newStatus))),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('No se pudo actualizar: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.status;
    final color = _subscriptionColor(status.state);
    final label = _subscriptionLabel(status);
    final hint = _subscriptionHint(status);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: CustomDrawer._surfaceAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(.55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.verified_user, color: color, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w700,
                    letterSpacing: .2,
                  ),
                ),
              ),
              if (widget.onRefresh != null)
                IconButton(
                  onPressed: _loading ? null : _handleRefresh,
                  icon: _loading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh, size: 18),
                  color: color,
                  tooltip: 'Actualizar estado (server)',
                ),
            ],
          ),
          if (hint != null) ...[
            const SizedBox(height: 4),
            Text(
              hint,
              style: const TextStyle(
                color: CustomDrawer._textMuted,
                fontSize: 11,
                height: 1.3,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

Color _subscriptionColor(SubscriptionState state) {
  switch (state) {
    case SubscriptionState.active:
      return CustomDrawer._gold;
    case SubscriptionState.grace:
      return Colors.lightBlueAccent;
    case SubscriptionState.pending:
      return Colors.blueAccent;
    case SubscriptionState.expired:
      return Colors.orangeAccent;
    case SubscriptionState.blocked:
      return Colors.redAccent;
    case SubscriptionState.none:
      return Colors.white70;
  }
}

String _subscriptionLabel(SubscriptionStatus status) {
  switch (status.state) {
    case SubscriptionState.active:
      return 'Suscripción activa';
    case SubscriptionState.grace:
      return 'Periodo de gracia';
    case SubscriptionState.pending:
      return 'Pago pendiente';
    case SubscriptionState.expired:
      return 'Suscripción vencida';
    case SubscriptionState.blocked:
      return 'Acceso bloqueado';
    case SubscriptionState.none:
      return 'Sin suscripción';
  }
}

String? _subscriptionHint(SubscriptionStatus status) {
  final remaining = status.remaining;
  switch (status.state) {
    case SubscriptionState.active:
      if (remaining != null && remaining > Duration.zero) {
        return 'Vence en ${_formatRemaining(remaining)}.';
      }
      if (status.endDate != null) {
        return 'Vence el ${_formatDate(status.endDate!)}.';
      }
      return 'Renueva antes de que expire para mantener el acceso.';
    case SubscriptionState.grace:
      if (remaining != null && remaining > Duration.zero) {
        return 'Tu gracia termina en ${_formatRemaining(remaining)}.';
      }
      return 'Aprovecha para completar tu pago hoy mismo.';
    case SubscriptionState.pending:
      return 'Estamos revisando tu pago. Recibirás acceso en cuanto se apruebe.';
    case SubscriptionState.expired:
      if (status.endDate != null) {
        return 'Terminó el ${_formatDate(status.endDate!)}. Renueva para continuar.';
      }
      return 'Renueva tu plan para seguir usando la biblioteca.';
    case SubscriptionState.blocked:
      return 'Contáctanos para revisar el estado de tu cuenta.';
    case SubscriptionState.none:
      return 'Suscríbete para desbloquear documentos exclusivos.';
  }
}

String _formatRemaining(Duration duration) {
  final days = duration.inDays;
  if (days > 0) return '$days día${days == 1 ? '' : 's'}';
  final hours = duration.inHours;
  if (hours > 0) return '$hours h';
  final minutes = duration.inMinutes;
  if (minutes > 0) return '$minutes min';
  return 'menos de un minuto';
}

String _formatDate(DateTime date) {
  final local = date.toLocal();
  return '${local.day.toString().padLeft(2, '0')}/'
      '${local.month.toString().padLeft(2, '0')}/'
      '${local.year}';
}

String _refreshMessage(SubscriptionStatus status) {
  switch (status.state) {
    case SubscriptionState.active:
      return 'Tu suscripción está activa.';
    case SubscriptionState.grace:
      return 'Continúas en periodo de gracia.';
    case SubscriptionState.pending:
      return 'Seguimos validando tu pago.';
    case SubscriptionState.expired:
      return 'Aún aparece como vencida.';
    case SubscriptionState.blocked:
      return 'La cuenta sigue bloqueada.';
    case SubscriptionState.none:
      return 'No hay suscripción registrada.';
  }
}
