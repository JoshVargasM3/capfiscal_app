// lib/features/biblioteca/ui/widgets/file_grid_card.dart
import 'package:flutter/material.dart';

class FileGridCard extends StatelessWidget {
  const FileGridCard({
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Ink(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.black12),
          borderRadius: BorderRadius.circular(14),
          color: Colors.white,
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Container(
                width: double.infinity,
                height: 84,
                decoration: BoxDecoration(
                  color: Colors.red.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Icon(Icons.picture_as_pdf,
                    color: Colors.red.shade700, size: 48),
              ),
              const SizedBox(height: 10),
              Text(
                name.toUpperCase(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              Container(
                height: 30,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: _lightGrey,
                  borderRadius: BorderRadius.circular(6),
                ),
                alignment: Alignment.center,
                child: const Text(
                  'DESCRIPCIÓN',
                  style: TextStyle(
                      color: Colors.black54,
                      fontSize: 12,
                      fontWeight: FontWeight.w600),
                ),
              ),
              const Spacer(),
              FutureBuilder<bool>(
                future: isFavoriteFuture,
                builder: (context, snap) {
                  final isFav = snap.data ?? false;
                  return Align(
                    alignment: Alignment.centerRight,
                    child: IconButton(
                      iconSize: 20,
                      icon: Icon(isFav ? Icons.favorite : Icons.favorite_border,
                          color: isFav ? Colors.redAccent : Colors.black38),
                      onPressed: () async => onToggleFavorite(),
                    ),
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
