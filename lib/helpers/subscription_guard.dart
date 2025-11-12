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
  static Future<bool> ensureActive(BuildContext context) async {
    final scope = SubscriptionScope.maybeOf(context);
    final status = scope?.status;
    if (status == null) {
      await _showBlockedDialog(
        context,
        message:
            'No pudimos validar tu suscripción. Intenta refrescar tu sesión.',
      );
      return false;
    }
    if (status.isAccessGranted) return true;

    await _showBlockedDialog(
      context,
      message:
          'Tu suscripción no está activa. Renueva tu plan para continuar.',
      onRefresh: scope?.onRefresh,
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
