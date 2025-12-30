import 'package:flutter/material.dart';
import '../../theme/cap_colors.dart';
import '../../services/subscription_service.dart';

class PaymentMethodCard extends StatelessWidget {
  const PaymentMethodCard({
    super.key,
    required this.method,
    required this.isUpdating,
    required this.onSetPrimary,
    required this.onRemove,
  });

  final StoredPaymentMethod method;
  final bool isUpdating;
  final VoidCallback onSetPrimary;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: CapColors.surface,
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        title: Text(
          method.label,
          style: const TextStyle(color: CapColors.text),
        ),
        subtitle: Text(
          '${method.brand.toUpperCase()} · •••• ${method.last4}',
          style: const TextStyle(color: CapColors.textMuted),
        ),
        trailing: method.isDefault
            ? const Chip(
                label: Text('Principal'),
                backgroundColor: Colors.greenAccent,
                labelStyle: TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.w700,
                ),
              )
            : Wrap(
                spacing: 8,
                children: [
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.greenAccent,
                      foregroundColor: Colors.black,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: isUpdating ? null : onSetPrimary,
                    child: const Text(
                      'Principal',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    onPressed: isUpdating ? null : onRemove,
                    icon: const Icon(Icons.delete_outline,
                        color: Colors.redAccent),
                  ),
                ],
              ),
      ),
    );
  }
}
