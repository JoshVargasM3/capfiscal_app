import 'package:flutter/material.dart';

class FileGridCard extends StatelessWidget {
  const FileGridCard({
    super.key,
    required this.name,
    required this.onTap,
    required this.isFavoriteFuture,
    required this.onToggleFavorite,
    this.iconSize = 120, // Ícono PDF grande
    this.pdfIconColor = const Color(0xFFE1B85C), // Dorado SOLO para PDF
  });

  final String name;
  final VoidCallback onTap;
  final Future<bool> isFavoriteFuture;
  final Future<void> Function() onToggleFavorite;
  final double iconSize;
  final Color pdfIconColor;

  static const _surface = Color(0xFF1C1C21);
  static const _surfaceAlt = Color(0xFF2A2A2F);
  static const _text = Color(0xFFEFEFEF);
  static const _muted = Color(0xFFBEBEC6);

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Ink(
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white12),
        ),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Caja del ícono gigante
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: _surfaceAlt,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Center(
                        child: Icon(
                          Icons.picture_as_pdf,
                          size: iconSize,
                          color: pdfIconColor,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _fileNameWithoutExt(name),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _text,
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Descripción',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: _muted, fontSize: 12),
                  ),
                ],
              ),
            ),
            // Favorito (colores originales: rojo)
            Positioned(
              top: 2,
              right: 0,
              child: FutureBuilder<bool>(
                future: isFavoriteFuture,
                builder: (context, snap) {
                  final isFav = snap.data ?? false;
                  return IconButton(
                    tooltip:
                        isFav ? 'Quitar de favoritos' : 'Agregar a favoritos',
                    onPressed: () async => onToggleFavorite(),
                    icon: Icon(
                      isFav ? Icons.favorite : Icons.favorite_border,
                      color: isFav ? Colors.redAccent : Colors.white70,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _fileNameWithoutExt(String n) {
    final i = n.lastIndexOf('.');
    return i > 0 ? n.substring(0, i) : n;
  }
}
