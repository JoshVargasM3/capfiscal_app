// lib/features/biblioteca/ui/widgets/filters_sheet.dart
import 'package:flutter/material.dart';

class FiltersSheet extends StatelessWidget {
  const FiltersSheet({
    super.key,
    required this.categories,
    required this.activeCategory,
    required this.onApply,
  });

  final List<String> categories;
  final String activeCategory;
  final void Function(String? selectedCategory) onApply;

  static const _maroon = Color(0xFF6B1A1A);

  @override
  Widget build(BuildContext context) {
    String temp = activeCategory;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const Text('Filtros',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: Text('Categorías',
                style: Theme.of(context).textTheme.labelLarge),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: categories.map((cat) {
              final selected = temp == cat;
              return ChoiceChip(
                selected: selected,
                label: Text(cat),
                selectedColor: _maroon.withOpacity(.15),
                labelStyle:
                    TextStyle(color: selected ? _maroon : Colors.black87),
                onSelected: (_) => temp = selected ? '' : cat,
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => onApply(null),
                  child: const Text('Limpiar'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: _maroon),
                  onPressed: () => onApply(temp.isEmpty ? null : temp),
                  child: const Text('Aplicar'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
