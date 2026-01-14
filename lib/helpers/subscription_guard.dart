import 'package:flutter/material.dart';

import '../services/subscription_service.dart';
import '../widgets/subscription_scope.dart';

/// Centralises runtime checks to ensure gated content is only accessible when
/// the paid subscription is active.
class SubscriptionGuard {
  const SubscriptionGuard._();

  /// Returns the current subscription status if available in the widget tree.
  static SubscriptionStatus? statusOf(BuildContext context) {
    return SubscriptionScope.maybeOf(context)?.status;
  }

  /// Whether the subscription grants access right now.
  static bool hasAccess(BuildContext context) {
    final status = statusOf(context);
    return status?.isAccessGranted ?? false;
  }

  /// Ensures the user still has an active subscription before allowing gated
  /// actions (downloads, exports, etc.). Returns `true` when access is granted.
  ///
  /// ✅ Cambio: intenta refrescar automáticamente (Stripe source of truth)
  /// antes de bloquear, usando `SubscriptionScope.onRefresh`.
  static Future<bool> ensureActive(BuildContext context) async {
    final scope = SubscriptionScope.maybeOf(context);
    if (scope == null) {
      await _showBlockedDialog(
        context,
        message:
            'No pudimos validar tu suscripción. Intenta refrescar tu sesión.',
      );
      return false;
    }

    // 1) Si ya trae status y da acceso, listo.
    final initialStatus = scope.status;
    if (initialStatus?.isAccessGranted ?? false) return true;

    // 2) Si no hay status o está bloqueada, intentamos refresh una vez.
    //    (Esto es clave después de cambiar método de pago en Stripe Portal.)
    SubscriptionStatus? refreshed;
    if (scope.onRefresh != null) {
      try {
        refreshed = await scope.onRefresh!();
      } catch (_) {
        // silencioso
      }
    }

    final finalStatus = refreshed ?? scope.status;

    // 3) Si con el refresh ya está activo, permitir.
    if (finalStatus?.isAccessGranted ?? false) return true;

    // 4) Si sigue sin acceso, bloquea con opción de "Actualizar estado".
    await _showBlockedDialog(
      context,
      message: finalStatus == null
          ? 'No pudimos validar tu suscripción. Intenta refrescar tu sesión.'
          : 'Tu suscripción no está activa. Renueva tu plan para continuar.',
      onRefresh: scope.onRefresh,
    );
    return false;
  }

  static Future<void> _showBlockedDialog(
    BuildContext context, {
    required String message,
    Future<SubscriptionStatus> Function()? onRefresh,
  }) async {
    final theme = Theme.of(context);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Suscripción requerida'),
          content: Text(message),
          actions: [
            if (onRefresh != null)
              TextButton(
                onPressed: () async {
                  Navigator.of(dialogContext).pop();
                  try {
                    await onRefresh();
                  } catch (_) {}
                },
                child: const Text('Actualizar estado'),
              ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(
                'Entendido',
                style: TextStyle(color: theme.colorScheme.primary),
              ),
            ),
          ],
        );
      },
    );
  }
}
