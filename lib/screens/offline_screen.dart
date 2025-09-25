import 'package:flutter/material.dart';

class OfflineScreen extends StatelessWidget {
  const OfflineScreen({
    super.key,
    required this.onRetry,
    required this.onContinueOffline,
  });

  final VoidCallback onRetry;
  final VoidCallback onContinueOffline;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0B),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.wifi_off_rounded, size: 72, color: Colors.white70),
              const SizedBox(height: 24),
              const Text(
                'Sin conexión a internet',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Conéctate para acceder a la versión completa de Capfiscal. '
                'Mientras tanto puedes continuar en un modo básico con algunas '
                'herramientas sin conexión.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, height: 1.4),
              ),
              const SizedBox(height: 32),
              _OfflineFeatureCard(
                icon: Icons.notes_rounded,
                title: 'Notas guardadas',
                description:
                    'Consulta y organiza apuntes locales incluso cuando no tienes internet.',
              ),
              const SizedBox(height: 12),
              _OfflineFeatureCard(
                icon: Icons.lightbulb_rounded,
                title: 'Guías rápidas',
                description: 'Accede a recordatorios y tips clave que descargamos en tu dispositivo.',
              ),
              const SizedBox(height: 32),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Reintentar conexión'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white24),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: onContinueOffline,
                      icon: const Icon(Icons.offline_pin_rounded),
                      label: const Text('Usar modo offline limitado'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFE1B85C),
                        foregroundColor: Colors.black,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'Podrás volver a la experiencia completa apenas recuperemos la conexión.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OfflineFeatureCard extends StatelessWidget {
  const _OfflineFeatureCard({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 32, color: const Color(0xFFE1B85C)),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: const TextStyle(color: Colors.white70, height: 1.3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
