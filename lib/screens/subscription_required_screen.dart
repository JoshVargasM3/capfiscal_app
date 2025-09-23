import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/subscription_service.dart';

class SubscriptionRequiredScreen extends StatefulWidget {
  const SubscriptionRequiredScreen({
    required this.status,
    required this.onRefresh,
    required this.onSignOut,
    this.errorMessage,
    super.key,
  });

  final SubscriptionStatus status;
  final Future<SubscriptionStatus> Function()? onRefresh;
  final Future<void> Function()? onSignOut;
  final String? errorMessage;

  @override
  State<SubscriptionRequiredScreen> createState() =>
      _SubscriptionRequiredScreenState();
}

class _SubscriptionRequiredScreenState
    extends State<SubscriptionRequiredScreen> {
  bool _refreshing = false;
  bool _openingContact = false;

  static const _bgTop = Color(0xFF0A0A0B);
  static const _bgMid = Color(0xFF2A2A2F);
  static const _bgBottom = Color(0xFF4A4A50);
  static const _surface = Color(0xFF1C1C21);
  static const _gold = Color(0xFFE1B85C);

  Future<void> _handleRefresh() async {
    if (widget.onRefresh == null) return;
    setState(() => _refreshing = true);
    try {
      final status = await widget.onRefresh!.call();
      if (!mounted) return;
      final msg = switch (status.state) {
        SubscriptionState.active => 'Tu suscripción está activa.',
        SubscriptionState.grace =>
          'Tienes acceso en periodo de gracia temporal.',
        SubscriptionState.pending =>
          'Tu pago sigue pendiente de confirmación.',
        SubscriptionState.blocked =>
          'Tu cuenta está bloqueada. Contacta a soporte.',
        SubscriptionState.expired =>
          'Seguimos detectando la suscripción expirada.',
        SubscriptionState.none =>
          'Aún no hay una suscripción registrada.',
      };
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No pudimos actualizar: $e')),
      );
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _contactSupport() async {
    if (_openingContact) return;
    setState(() => _openingContact = true);
    const email = 'capfiscal.app@gmail.com';
    final uri = Uri(
      scheme: 'mailto',
      path: email,
      queryParameters: {
        'subject': 'Ayuda con mi suscripción CAPFISCAL',
      },
    );
    try {
      final launched = await launchUrl(uri);
      if (!launched) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('No se pudo abrir el correo. Escríbenos a capfiscal.app@gmail.com'),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No pudimos abrir el correo: $e')),
      );
    } finally {
      if (mounted) setState(() => _openingContact = false);
    }
  }

  Future<void> _signOut() async {
    if (widget.onSignOut == null) return;
    await widget.onSignOut!.call();
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.status;
    final title = switch (status.state) {
      SubscriptionState.active => 'Acceso concedido temporalmente',
      SubscriptionState.grace => 'Periodo de gracia activo',
      SubscriptionState.pending => 'Pago en revisión',
      SubscriptionState.blocked => 'Suscripción bloqueada',
      SubscriptionState.expired => 'Tu suscripción terminó',
      SubscriptionState.none => 'Activa tu suscripción',
    };

    final subtitle = widget.errorMessage ?? switch (status.state) {
      SubscriptionState.active =>
        'Detectamos un estado activo manual. Verifica tus datos.',
      SubscriptionState.grace =>
        'Aprovecha para completar tu renovación antes de que termine.',
      SubscriptionState.pending =>
        'Tu pago se registró, pero aún no se libera el acceso.',
      SubscriptionState.blocked =>
        'El equipo CAPFISCAL bloqueó tu acceso. Escríbenos si crees que es un error.',
      SubscriptionState.expired =>
        'Necesitas renovar tu plan mensual para seguir editando y descargando documentos.',
      SubscriptionState.none =>
        'Aún no contamos con una suscripción activa asociada a tu cuenta.',
    };

    final details = <_DetailRow>[
      _DetailRow(
        label: 'Inicio',
        value: _formatDate(status.startDate),
      ),
      _DetailRow(
        label: 'Vence',
        value: _formatDate(status.endDate),
      ),
      _DetailRow(
        label: 'Método de pago',
        value: status.paymentMethod?.isNotEmpty == true
            ? status.paymentMethod!
            : 'Sin registrar',
      ),
    ];

    final remaining = status.remaining;
    if (remaining != null && remaining > Duration.zero) {
      details.add(
        _DetailRow(
          label: status.state == SubscriptionState.grace
              ? 'Tiempo de gracia restante'
              : 'Tiempo restante',
          value: _formatDuration(remaining),
        ),
      );
    }

    final accent = switch (status.state) {
      SubscriptionState.blocked => Colors.redAccent,
      SubscriptionState.expired => Colors.orangeAccent,
      SubscriptionState.pending => Colors.blueAccent,
      _ => _gold,
    };

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [_bgTop, _bgMid, _bgBottom],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.lock_outline, size: 68, color: accent),
                    const SizedBox(height: 18),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            letterSpacing: .4,
                          ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      subtitle,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFFBEBEC6),
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: _surface.withOpacity(.9),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: Colors.white12),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black54,
                            blurRadius: 18,
                            offset: Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Detalle de tu plan',
                            style:
                                Theme.of(context).textTheme.titleMedium?.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                    ),
                          ),
                          const SizedBox(height: 12),
                          for (final row in details) ...[
                            _DetailRowWidget(row: row),
                            const Divider(color: Colors.white12, height: 18),
                          ],
                          Text(
                            'Última actualización: ${_formatDateTime(status.updatedAt ?? status.checkedAt)}',
                            style: const TextStyle(
                              color: Color(0xFF8E8E96),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: _refreshing ? null : _handleRefresh,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: accent,
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: _refreshing
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor:
                                      AlwaysStoppedAnimation<Color>(Colors.black),
                                ),
                              )
                            : const Text(
                                'Revisar nuevamente',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: OutlinedButton(
                        onPressed: _openingContact ? null : _contactSupport,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white38),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: _openingContact
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor:
                                      AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              )
                            : const Text('Contactar soporte'),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextButton.icon(
                      onPressed: _signOut,
                      icon: const Icon(Icons.logout, color: Color(0xFFBEBEC6)),
                      label: const Text(
                        'Cerrar sesión',
                        style: TextStyle(color: Color(0xFFBEBEC6)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DetailRow {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;
}

class _DetailRowWidget extends StatelessWidget {
  const _DetailRowWidget({required this.row});

  final _DetailRow row;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            row.label,
            style: const TextStyle(color: Color(0xFF8E8E96)),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              row.value,
              textAlign: TextAlign.end,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

String _formatDate(DateTime? date) {
  if (date == null) return '—';
  final local = date.toLocal();
  return '${local.day.toString().padLeft(2, '0')}/'
      '${local.month.toString().padLeft(2, '0')}/'
      '${local.year}';
}

String _formatDateTime(DateTime date) {
  final local = date.toLocal();
  final time = '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  return '${local.day.toString().padLeft(2, '0')}/'
      '${local.month.toString().padLeft(2, '0')}/'
      '${local.year} $time';
}

String _formatDuration(Duration duration) {
  final totalHours = duration.inHours;
  final days = duration.inDays;
  if (days >= 1) {
    final remainingHours = totalHours - days * 24;
    if (remainingHours > 0) {
      return '$days día${days == 1 ? '' : 's'} y $remainingHours h';
    }
    return '$days día${days == 1 ? '' : 's'}';
  }
  final minutes = duration.inMinutes - totalHours * 60;
  if (totalHours >= 1) {
    if (minutes > 0) {
      return '$totalHours h $minutes min';
    }
    return '$totalHours h';
  }
  return '${duration.inMinutes} min';
}
