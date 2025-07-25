import 'package:shared_preferences/shared_preferences.dart';

class FavoritesManager {
  static const String _favoritesKey = 'favorite_files';

  static Future<List<String>> getFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_favoritesKey) ?? [];
  }

  static Future<void> toggleFavorite(String fileName) async {
    final prefs = await SharedPreferences.getInstance();
    final favorites = prefs.getStringList(_favoritesKey) ?? [];

    if (favorites.contains(fileName)) {
      favorites.remove(fileName);
    } else {
      favorites.add(fileName);
    }

    await prefs.setStringList(_favoritesKey, favorites);
  }

  static Future<bool> isFavorite(String fileName) async {
    final prefs = await SharedPreferences.getInstance();
    final favorites = prefs.getStringList(_favoritesKey) ?? [];
    return favorites.contains(fileName);
  }
}
