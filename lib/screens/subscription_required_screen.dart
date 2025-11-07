import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/subscription_config.dart';
import '../services/payment_service.dart';
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
    extends State<SubscriptionRequiredScreen> with WidgetsBindingObserver {
  bool _refreshing = false;
  bool _openingContact = false;
  bool _activatingManually = false;
  bool _processingPayment = false;
  bool _waitingCheckoutResult = false;
  bool _sawCheckoutTransition = false;
  String? _activeCheckoutSessionId;
  final _manualMethod = TextEditingController();
  final SubscriptionService _subscriptionService = SubscriptionService();
  final SubscriptionPaymentService _paymentService =
      SubscriptionPaymentService.instance;

  static const _bgTop = Color(0xFF0A0A0B);
  static const _bgMid = Color(0xFF2A2A2F);
  static const _bgBottom = Color(0xFF4A4A50);
  static const _surface = Color(0xFF1C1C21);
  static const _gold = Color(0xFFE1B85C);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _manualMethod.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_waitingCheckoutResult) return;

    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _sawCheckoutTransition = true;
    } else if (state == AppLifecycleState.resumed && _sawCheckoutTransition) {
      _sawCheckoutTransition = false;
      unawaited(_completeHostedCheckout());
    }
  }

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

  Future<void> _activateManually() async {
    if (_activatingManually) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No encontramos tu sesión activa.')),
      );
      return;
    }

    final method = _manualMethod.text.trim();
    if (method.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Escribe un método o referencia de pago.'),
        ),
      );
      return;
    }

    setState(() => _activatingManually = true);
    try {
      final now = DateTime.now().toUtc();
      await _subscriptionService.updateSubscription(
        user.uid,
        startDate: now,
        endDate: now.add(const Duration(days: 30)),
        paymentMethod: method,
        status: 'manual_active',
      );
      _manualMethod.clear();
      if (widget.onRefresh != null) {
        await widget.onRefresh!.call();
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Activamos tu acceso manualmente.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo activar: $e')),
      );
    } finally {
      if (mounted) setState(() => _activatingManually = false);
    }
  }

  Future<void> _completeHostedCheckout() async {
    if (_processingPayment) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
      setState(() {
        _waitingCheckoutResult = false;
        _sawCheckoutTransition = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Inicia sesión para confirmar tu pago.')),
      );
      return;
    }

    final sessionId = _activeCheckoutSessionId;
    if (sessionId == null || sessionId.isEmpty) {
      if (!mounted) return;
      setState(() {
        _waitingCheckoutResult = false;
        _sawCheckoutTransition = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No encontramos la sesión de pago por confirmar.')),
      );
      return;
    }

    if (!mounted) return;
    setState(() {
      _processingPayment = true;
      _waitingCheckoutResult = false;
    });

    try {
      final confirmation =
          await _paymentService.confirmHostedCheckout(sessionId);

      if (confirmation.isActive) {
        _activeCheckoutSessionId = null;
        if (widget.onRefresh != null) {
          await widget.onRefresh!.call();
        }
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              confirmation.message ??
                  'Pago confirmado. Activamos tu acceso por 30 días.',
            ),
          ),
        );
      } else if (confirmation.isPending) {
        if (!mounted) return;
        setState(() {
          _waitingCheckoutResult = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              confirmation.message ??
                  'Stripe sigue procesando el pago. Intentaremos nuevamente en unos segundos.',
            ),
          ),
        );
        Future.delayed(const Duration(seconds: 6), () {
          if (!mounted) return;
          if (_waitingCheckoutResult && !_processingPayment) {
            _completeHostedCheckout();
          }
        });
      } else {
        _activeCheckoutSessionId = null;
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              confirmation.message ??
                  'Stripe no confirmó el pago. Reintenta o contacta a soporte.',
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No pudimos actualizar tu suscripción: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _processingPayment = false;
          _sawCheckoutTransition = false;
        });
      }
    }
  }

  Future<void> _startPayment() async {
    if (_processingPayment || _waitingCheckoutResult) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Inicia sesión para completar el pago.')),
      );
      return;
    }

    if (!SubscriptionConfig.hasCheckoutConfiguration) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Configura el enlace de pago de Stripe.'),
        ),
      );
      return;
    }

    setState(() => _processingPayment = true);
    try {
      final session = await _paymentService.createHostedCheckout();
      _activeCheckoutSessionId = session.sessionId;

      final mode = kIsWeb
          ? LaunchMode.platformDefault
          : LaunchMode.externalApplication;

      final launched = await launchUrl(
        session.url,
        mode: mode,
        webOnlyWindowName: kIsWeb ? '_self' : null,
      );

      if (!launched) {
        throw StateError('No se pudo abrir la página de pago de Stripe.');
      }

      if (!mounted) return;
      setState(() {
        _waitingCheckoutResult = true;
        _sawCheckoutTransition = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Cuando completes el pago regresa a la app, activaremos tu acceso automáticamente.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _waitingCheckoutResult = false;
        _activeCheckoutSessionId = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No pudimos procesar el pago: $e')),
      );
    } finally {
      if (mounted) setState(() => _processingPayment = false);
    }
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

    final showPaymentSection = status.state == SubscriptionState.none ||
        status.state == SubscriptionState.expired;
    final showPaymentButton =
        showPaymentSection && SubscriptionConfig.hasCheckoutConfiguration;
    final showPaymentConfigHint =
        showPaymentSection && !SubscriptionConfig.hasCheckoutConfiguration;

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
                          const SizedBox(height: 18),
                          if (showPaymentSection) ...[
                            Text(
                              'Pagar suscripción',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                            const SizedBox(height: 8),
                            if (showPaymentButton)
                              SizedBox(
                                width: double.infinity,
                                height: 46,
                                child: ElevatedButton.icon(
                                  onPressed:
                                      (_processingPayment || _waitingCheckoutResult)
                                          ? null
                                          : _startPayment,
                                  icon: _processingPayment
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            valueColor:
                                                AlwaysStoppedAnimation<Color>(
                                                    Colors.black),
                                          ),
                                        )
                                      : _waitingCheckoutResult
                                          ? const Icon(Icons.hourglass_bottom)
                                          : const Icon(Icons.credit_card),
                                  label: Text(
                                    _processingPayment
                                        ? 'Abriendo pago…'
                                        : _waitingCheckoutResult
                                            ? 'Esperando confirmación…'
                                            : 'Pagar y activar',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _gold,
                                    foregroundColor: Colors.black,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                ),
                              )
                            else if (showPaymentConfigHint)
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF2A2A30),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.white12),
                                ),
                                child: const Text(
                                  'Configura STRIPE_CHECKOUT_URL para habilitar el botón de pago.',
                                  style: TextStyle(
                                    color: Color(0xFFBEBEC6),
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            const SizedBox(height: 20),
                          ],
                          Text(
                            'Activar manualmente',
                            style:
                                Theme.of(context).textTheme.titleSmall?.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                    ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _manualMethod,
                            enabled: !_activatingManually,
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              labelText: 'Método o referencia de pago',
                              labelStyle:
                                  const TextStyle(color: Color(0xFF8E8E96)),
                              prefixIcon: const Icon(
                                Icons.credit_card,
                                color: Color(0xFF8E8E96),
                              ),
                              filled: true,
                              fillColor: const Color(0xFF2A2A30),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(color: Colors.white12),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(color: Colors.white12),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(color: _gold),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            height: 46,
                            child: ElevatedButton(
                              onPressed:
                                  _activatingManually ? null : _activateManually,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _gold,
                                foregroundColor: Colors.black,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              child: _activatingManually
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                                Colors.black),
                                      ),
                                    )
                                  : const Text(
                                      'Activar acceso',
                                      style: TextStyle(fontWeight: FontWeight.w700),
                                    ),
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
