// lib/services/payment_service.dart
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

/// Resultado del flujo de checkout de suscripción.
class SubscriptionPaymentResult {
  const SubscriptionPaymentResult._(
    this.status, {
    this.subscriptionId,
    this.message,
  });

  final SubscriptionPaymentStatus status;
  final String? subscriptionId;
  final String? message;

  factory SubscriptionPaymentResult.activated({
    required String subscriptionId,
    String? message,
  }) =>
      SubscriptionPaymentResult._(
        SubscriptionPaymentStatus.activated,
        subscriptionId: subscriptionId,
        message: message,
      );

  factory SubscriptionPaymentResult.pending({String? message}) =>
      SubscriptionPaymentResult._(
        SubscriptionPaymentStatus.pending,
        message: message,
      );

  factory SubscriptionPaymentResult.canceled({String? message}) =>
      SubscriptionPaymentResult._(
        SubscriptionPaymentStatus.canceled,
        message: message,
      );
}

/// Posibles estados finales tras pedir el pago.
enum SubscriptionPaymentStatus { activated, pending, canceled }

/// Información del Checkout Session generado en Stripe.
class StripeCheckoutSession {
  const StripeCheckoutSession({
    required this.sessionId,
    required this.checkoutUrl,
  });

  final String sessionId;
  final String checkoutUrl;
}

/// Capa fina alrededor de Stripe Checkout impulsada por Cloud Functions.
class SubscriptionPaymentService {
  SubscriptionPaymentService._({FirebaseFunctions? functions})
      : _functions = functions ??
            FirebaseFunctions.instanceFor(
              app: Firebase.app(),
              region: const String.fromEnvironment(
                'FUNCTIONS_REGION',
                defaultValue: 'us-central1',
              ),
            );

  static final SubscriptionPaymentService instance =
      SubscriptionPaymentService._();

  final FirebaseFunctions _functions;

  /// Crea un Stripe Checkout Session y devuelve la URL para cobrar al usuario.
  Future<StripeCheckoutSession> createCheckoutSession({
    String? priceId,
    Map<String, dynamic>? metadata,
    required String successUrl,
    required String cancelUrl,
  }) async {
    final res = await _call(
      'createCheckoutSession',
      data: <String, dynamic>{
        'successUrl': successUrl,
        'cancelUrl': cancelUrl,
        if (priceId != null) 'priceId': priceId,
        if (metadata != null) 'metadata': metadata,
      },
    ) as Map?;

    final sessionId = res?['sessionId'] as String?;
    final url = res?['url'] as String?;

    if (sessionId == null || sessionId.isEmpty || url == null || url.isEmpty) {
      throw StateError('No se pudo generar el enlace de cobro de Stripe.');
    }

    return StripeCheckoutSession(
      sessionId: sessionId,
      checkoutUrl: url,
    );
  }

  /// Consulta al backend para verificar si el Checkout ya fue liquidado.
  Future<SubscriptionPaymentResult> confirmCheckoutSession({
    required String sessionId,
    int maxAttempts = 8,
    Duration pollDelay = const Duration(seconds: 3),
  }) async {
    SubscriptionPaymentResult? pending;

    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      final res = await _confirmCheckoutOnce(sessionId);
      if (res.status != SubscriptionPaymentStatus.pending) {
        return res;
      }
      pending = res;
      await Future<void>.delayed(pollDelay);
    }

    return pending ??
        SubscriptionPaymentResult.pending(
          message: 'Seguimos validando tu pago con Stripe.',
        );
  }

  Future<SubscriptionPaymentResult> _confirmCheckoutOnce(String sessionId) async {
    final res = await _call(
      'confirmCheckoutSession',
      data: <String, dynamic>{'sessionId': sessionId},
    ) as Map?;

    final status = (res?['status'] as String? ?? '').toLowerCase();
    final message = res?['message'] as String?;
    final subscriptionId = res?['subscriptionId'] as String?;

    switch (status) {
      case 'active':
      case 'activated':
        if (subscriptionId == null || subscriptionId.isEmpty) {
          throw StateError(
            'Stripe confirmó el pago pero no devolvió la suscripción.',
          );
        }
        return SubscriptionPaymentResult.activated(
          subscriptionId: subscriptionId,
          message: message,
        );
      case 'canceled':
      case 'cancelled':
        return SubscriptionPaymentResult.canceled(message: message);
      default:
        return SubscriptionPaymentResult.pending(message: message);
    }
  }

  /// (Opcional) portal de facturación
  Future<void> openBillingPortal() async {
    final res = await _call('createPortalSession') as Map?;
    final String? url = res?['url'] as String?;
    if (url == null || url.isEmpty) {
      throw StateError('No se pudo generar URL del portal de facturación.');
    }
    // Usa url_launcher para abrir:
    // await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  // ======================================================================
  // Helper centralizado: GARANTIZA usuario listo + ID token fresco + reintento
  // ======================================================================
  Future<dynamic> _call(String name, {Map<String, dynamic>? data}) async {
    final auth = FirebaseAuth.instance;

    // 1) Espera a que Firebase restituya la sesión si aún no está lista.
    User? user = auth.currentUser;
    if (user == null) {
      try {
        user = await auth
            .authStateChanges()
            .firstWhere((u) => u != null)
            .timeout(const Duration(seconds: 8));
      } catch (_) {
        // seguirá nulo y caerá en el throw de abajo
      }
    }
    if (user == null) {
      throw FirebaseException(
        plugin: 'cloud_functions',
        code: 'unauthenticated',
        message: 'Inicia sesión para continuar',
      );
    }

    // 2) Llamada con posible reintento si el backend responde unauthenticated.
    final callable = _functions.httpsCallable(
      name,
      options: HttpsCallableOptions(timeout: const Duration(seconds: 60)),
    );

    Future<dynamic> invoke() async {
      final token = await user!.getIdToken(true);
      final payload = <String, dynamic>{
        '__authToken': token,
        if (data != null) ...data,
      };
      final res = await callable.call(payload);
      return res.data;
    }

    try {
      return await invoke();
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'unauthenticated') {
        // Fuerza refresh y reintenta 1 vez por si el token expiró en tránsito
        return await invoke();
      }
      rethrow;
    }
  }
}
