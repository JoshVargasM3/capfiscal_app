import 'package:flutter/material.dart';
import '../../theme/cap_colors.dart';

class PaymentMethodCard extends StatelessWidget {
  const PaymentMethodCard({
    super.key,
    this.platformLabel,
  });

  /// Ej: "App Store" / "Google Play"
  final String? platformLabel;

  @override
  Widget build(BuildContext context) {
    final label = (platformLabel ?? '').trim();

    return Card(
      color: CapColors.surface,
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: const Icon(Icons.store, color: CapColors.gold),
        title: Text(
          'Pagos gestionados por ${label.isEmpty ? 'la tienda' : label}',
          style: const TextStyle(
            color: CapColors.text,
            fontWeight: FontWeight.w800,
          ),
        ),
        subtitle: const Text(
          'Apple/Google gestionan tu método de pago. '
          'Puedes cambiarlo desde la configuración de tu cuenta en la tienda.',
          style: TextStyle(color: CapColors.textMuted),
        ),
      ),
    );
  }
}
