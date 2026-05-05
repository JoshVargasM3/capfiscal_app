import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FavoritesManager {
  // Clave global antigua (compat)
  static const String _legacyKey = 'favorite_files';
  static final ValueNotifier<int> changes = ValueNotifier<int>(0);

  // Clave namespaced por usuario
  static String _key(String uid) => 'favorite_files_$uid';

  /// Si existen favoritos globales antiguos, los copia a la clave del usuario.
  static Future<void> _migrateIfNeeded(String uid) async {
    final sp = await SharedPreferences.getInstance();
    final userKey = _key(uid);

    if (sp.containsKey(userKey)) return; // ya migrado para este uid

    final legacy = sp.getStringList(_legacyKey);
    if (legacy != null && legacy.isNotEmpty) {
      final existing = sp.getStringList(userKey) ?? <String>[];
      final merged = {...existing, ...legacy}.toList();
      await sp.setStringList(userKey, merged);
      // Si quieres eliminar completamente los globales, descomenta:
      // await sp.remove(_legacyKey);
    }
  }

  /// Obtiene la lista de favoritos del usuario.
  static Future<List<String>> getFavorites(String uid) async {
    await _migrateIfNeeded(uid);
    final sp = await SharedPreferences.getInstance();
    return sp.getStringList(_key(uid)) ?? const [];
  }

  /// Alterna un favorito (agrega/quita) para el usuario.
  static Future<void> toggleFavorite(String uid, String itemKey) async {
    await _migrateIfNeeded(uid);
    final sp = await SharedPreferences.getInstance();
    final key = _key(uid);
    final set = <String>{...?sp.getStringList(key)};

    if (set.contains(itemKey)) {
      set.remove(itemKey);
    } else {
      set.add(itemKey);
    }

    await sp.setStringList(key, set.toList());
    changes.value++;
  }

  /// Verifica si un item es favorito para el usuario.
  static Future<bool> isFavorite(String uid, String itemKey) async {
    final list = await getFavorites(uid);
    return list.contains(itemKey);
  }

  /// (Opcional) Limpia todos los favoritos del usuario.
  static Future<void> clearFavorites(String uid) async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_key(uid));
    changes.value++;
  }
}
