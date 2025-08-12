// lib/features/biblioteca/ui/widgets/file_list_tile.dart
import 'package:flutter/material.dart';

class FileListTile extends StatelessWidget {
  const FileListTile({
    super.key,
    required this.name,
    required this.onTap,
    required this.isFavoriteFuture,
    required this.onToggleFavorite,
  });

  final String name;
  final VoidCallback onTap;
  final Future<bool> isFavoriteFuture;
  final Future<void> Function() onToggleFavorite;

  static const _lightGrey = Color(0xFFE7E7E7);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.black12),
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.red.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Icon(Icons.picture_as_pdf,
                    color: Colors.red.shade700, size: 34),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 16),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: 32,
                      decoration: BoxDecoration(
                        color: _lightGrey,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: const Text(
                        'DESCRIPCIÓN',
                        style: TextStyle(
                            color: Colors.black54,
                            fontSize: 12,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
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
    );
  }
}
