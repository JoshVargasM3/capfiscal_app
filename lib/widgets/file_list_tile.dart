import 'package:flutter/material.dart';

class FileListTile extends StatelessWidget {
  const FileListTile({
    super.key,
    required this.name,
    required this.onTap,
    required this.isFavoriteFuture,
    required this.onToggleFavorite,
    this.leadingSize = 56,
    this.pdfIconColor = const Color(0xFFE1B85C), // DORADO SOLO para PDF
  });

  final String name;
  final VoidCallback onTap;
  final Future<bool> isFavoriteFuture;
  final Future<void> Function() onToggleFavorite;
  final double leadingSize;
  final Color pdfIconColor;

  static const _surface = Color(0xFF1C1C21);
  static const _surfaceAlt = Color(0xFF2A2A2F);
  static const _text = Color(0xFFEFEFEF);
  static const _muted = Color(0xFFBEBEC6);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white12),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
            child: Row(
              children: [
                // Ícono PDF (más grande y dorado)
                Container(
                  width: leadingSize,
                  height: leadingSize,
                  decoration: BoxDecoration(
                    color: _surfaceAlt,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.picture_as_pdf,
                      color: pdfIconColor, size: leadingSize * .6),
                ),
                const SizedBox(width: 12),
                // Texto
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _fileNameWithoutExt(name),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _text,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 2),
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
                FutureBuilder<bool>(
                  future: isFavoriteFuture,
                  builder: (context, snap) {
                    final isFav = snap.data ?? false;
                    return IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip:
                          isFav ? 'Quitar de favoritos' : 'Agregar a favoritos',
                      icon: Icon(isFav ? Icons.favorite : Icons.favorite_border,
                          color: isFav ? Colors.redAccent : Colors.black38),
                      onPressed: () async => onToggleFavorite(),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _fileNameWithoutExt(String n) {
    final i = n.lastIndexOf('.');
    return i > 0 ? n.substring(0, i) : n;
  }
}
