import 'package:flutter/material.dart';

import 'offline_notes_screen.dart';

class OfflineHomeScreen extends StatelessWidget {
  const OfflineHomeScreen({
    super.key,
    required this.onRetryOnline,
  });

  final VoidCallback onRetryOnline;

  String _formatToday() {
    final now = DateTime.now();
    return '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';
  }

  void _showQuickTips(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1C1C21),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tips rápidos (${_formatToday()})',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 12),
                const _TipTile(
                  icon: Icons.check_circle_outline,
                  title: 'Checklist de fiscalización',
                  description:
                      'Repasa los puntos esenciales antes de una visita y evita omisiones.',
                ),
                const _TipTile(
                  icon: Icons.library_books_outlined,
                  title: 'Documentos clave',
                  description:
                      'Ten a mano las últimas resoluciones que descargaste para consulta rápida.',
                ),
                const _TipTile(
                  icon: Icons.timer_outlined,
                  title: 'Agenda offline',
                  description:
                      'Sincroniza tus próximas tareas para recibir recordatorios locales.',
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () => Navigator.of(ctx).maybePop(),
                  icon: const Icon(Icons.close),
                  label: const Text('Cerrar'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0B),
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: const Text('Capfiscal – Modo offline'),
        actions: [
          IconButton(
            onPressed: onRetryOnline,
            icon: const Icon(Icons.wifi_rounded),
            tooltip: 'Intentar reconectar',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: Colors.white.withOpacity(0.04),
              border: Border.all(color: Colors.white12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.offline_pin_rounded,
                    size: 28, color: Color(0xFFE1B85C)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        'Modo limitado activo',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        'Algunas funciones que requieren sincronización en la nube se han desactivado. '
                        'Cuando recuperes internet podrás continuar justo donde lo dejaste.',
                        style: TextStyle(color: Colors.white70, height: 1.3),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _OfflineActionCard(
            icon: Icons.notes_rounded,
            title: 'Notas guardadas',
            description:
                'Organiza apuntes rápidos, compromisos y pendientes. Se guardan solo en tu dispositivo.',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const OfflineNotesScreen(),
              ),
            ),
          ),
          const SizedBox(height: 16),
          _OfflineActionCard(
            icon: Icons.lightbulb_rounded,
            title: 'Guías rápidas',
            description:
                'Consulta resúmenes operativos y recordatorios para tus procesos frecuentes.',
            onTap: () => _showQuickTips(context),
          ),
          const SizedBox(height: 16),
          _OfflineActionCard(
            icon: Icons.download_for_offline_rounded,
            title: 'Documentos descargados',
            description:
                'Abre archivos que guardaste anteriormente en tu almacenamiento local.',
            onTap: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                    'Busca tus descargas desde el gestor de archivos del dispositivo.'),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Sugerencias para trabajar sin conexión',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: const [
              _SuggestionChip(label: 'Revisa tu checklist'),
              _SuggestionChip(label: 'Actualiza tus notas'),
              _SuggestionChip(label: 'Organiza tus pendientes'),
              _SuggestionChip(label: 'Planifica próximas visitas'),
            ],
          ),
        ],
      ),
    );
  }
}

class _OfflineActionCard extends StatelessWidget {
  const _OfflineActionCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withOpacity(0.04),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 28, color: const Color(0xFFE1B85C)),
              const SizedBox(width: 12),
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
                    const SizedBox(height: 6),
                    Text(
                      description,
                      style: const TextStyle(color: Colors.white70, height: 1.3),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.white54),
            ],
          ),
        ),
      ),
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  const _SuggestionChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        color: Colors.white.withOpacity(0.05),
        border: Border.all(color: Colors.white12),
      ),
      child: Text(
        label,
        style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _TipTile extends StatelessWidget {
  const _TipTile({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFFE1B85C)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
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
