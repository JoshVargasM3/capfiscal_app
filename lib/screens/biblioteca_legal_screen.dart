import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import '../widgets/bottom_nav_bar.dart';
import '../widgets/custom_drawer.dart';
import '../helpers/favorites_manager.dart';

class BibliotecaLegalScreen extends StatefulWidget {
  const BibliotecaLegalScreen({super.key});

  @override
  State<BibliotecaLegalScreen> createState() => _BibliotecaLegalScreenState();
}

class _BibliotecaLegalScreenState extends State<BibliotecaLegalScreen> {
  final FirebaseStorage _storage = FirebaseStorage.instance;
  List<Reference> _files = [];
  bool _loading = true;
  String _search = '';
  String _activeCategory = '';

  @override
  void initState() {
    super.initState();
    _fetchFiles();
  }

  Future<void> _fetchFiles() async {
    setState(() => _loading = true);
    try {
      final result = await _storage.ref('/').listAll();
      setState(() {
        _files = result.items;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  Future<void> _downloadAndOpenFile(Reference ref) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/${ref.name}');
      if (!await file.exists()) await ref.writeToFile(file);
      await OpenFilex.open(file.path);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  void _toggleCategory(String category) {
    setState(() {
      if (_activeCategory == category) {
        _activeCategory = '';
      } else {
        _activeCategory = category;
      }
      _search = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final filteredFiles = _files.where((f) {
      final fileName = f.name.toLowerCase();
      if (_search.isNotEmpty) {
        return fileName.contains(_search.toLowerCase());
      } else if (_activeCategory.isNotEmpty) {
        return fileName.contains(_activeCategory.toLowerCase());
      }
      return true;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Biblioteca Legal'),
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        actions: [
          IconButton(onPressed: _fetchFiles, icon: const Icon(Icons.refresh)),
        ],
      ),
      drawer: const CustomDrawer(),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: TextField(
              onChanged: (val) => setState(() {
                _search = val;
                _activeCategory = '';
              }),
              decoration: const InputDecoration(
                hintText: 'Buscar documentos...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                filled: true,
              ),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: ['Demanda', 'Contrato', 'Juicio', 'Requisición'].map((cat) {
                final isSelected = _activeCategory == cat;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isSelected ? Colors.blue : null,
                    ),
                    onPressed: () => _toggleCategory(cat),
                    child: Text(cat),
                  ),
                );
              }).toList(),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : filteredFiles.isEmpty
                    ? const Center(child: Text('No se encontraron documentos'))
                    : GridView.builder(
                        padding: const EdgeInsets.all(8),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                        ),
                        itemCount: filteredFiles.length,
                        itemBuilder: (ctx, i) {
                          final file = filteredFiles[i];
                          return GestureDetector(
                            onTap: () => _downloadAndOpenFile(file),
                            child: Card(
                              color: Colors.red[900],
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.description, size: 50, color: Colors.white),
                                  const SizedBox(height: 10),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 4),
                                    child: Text(
                                      file.name,
                                      textAlign: TextAlign.center,
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 2,
                                      style: const TextStyle(color: Colors.white),
                                    ),
                                  ),
                                  FutureBuilder<bool>(
                                    future: FavoritesManager.isFavorite(file.name),
                                    builder: (context, snapshot) {
                                      final isFav = snapshot.data ?? false;
                                      return IconButton(
                                        icon: Icon(
                                          isFav ? Icons.favorite : Icons.favorite_border,
                                          color: isFav ? Colors.yellow : Colors.white,
                                        ),
                                        onPressed: () async {
                                          await FavoritesManager.toggleFavorite(file.name);
                                          setState(() {});
                                        },
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
      bottomNavigationBar: const BottomNavBar(currentIndex: 0),
    );
  }
}
