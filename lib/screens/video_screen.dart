import 'package:flutter/material.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../widgets/bottom_nav_bar.dart';
import '../widgets/custom_drawer.dart';
import '../widgets/video_item.dart';
import '../helpers/favorites_manager.dart';

class VideoScreen extends StatefulWidget {
  const VideoScreen({super.key});

  @override
  State<VideoScreen> createState() => _VideoScreenState();
}

class _VideoScreenState extends State<VideoScreen> {
  final FirebaseStorage _storage = FirebaseStorage.instance;
  List<Reference> _videoFiles = [];
  bool _loading = true;
  final Map<String, bool> _expandedMap = {};

  @override
  void initState() {
    super.initState();
    _fetchVideos();
  }

  Future<void> _fetchVideos() async {
    setState(() => _loading = true);
    try {
      final result = await _storage.ref('/videos/').listAll();
      setState(() {
        _videoFiles = result.items;
        _expandedMap.clear();
        for (var file in result.items) {
          _expandedMap[file.name] = false;
        }
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  void _toggleExpand(String fileName) {
    setState(() {
      _expandedMap[fileName] = !(_expandedMap[fileName] ?? false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Videos'),
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        actions: [
          IconButton(onPressed: _fetchVideos, icon: const Icon(Icons.refresh)),
        ],
      ),
      drawer: const CustomDrawer(),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _videoFiles.isEmpty
              ? const Center(child: Text('No se encontraron videos'))
              : ListView.separated(
                  padding: const EdgeInsets.all(8),
                  itemCount: _videoFiles.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (ctx, i) {
                    final file = _videoFiles[i];
                    final isExpanded = _expandedMap[file.name] ?? false;
                    return FutureBuilder<String>(
                      future: file.getDownloadURL(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(child: CircularProgressIndicator());
                        }
                        if (!snapshot.hasData) {
                          return const ListTile(title: Text('Error al cargar video'));
                        }
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            VideoItem(
                              videoUrl: snapshot.data!,
                              title: file.name,
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      file.name,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  FutureBuilder<bool>(
                                    future: FavoritesManager.isFavorite(file.name),
                                    builder: (context, snapshot) {
                                      final isFav = snapshot.data ?? false;
                                      return IconButton(
                                        icon: Icon(
                                          isFav ? Icons.favorite : Icons.favorite_border,
                                          color: isFav ? Colors.yellow : Colors.black,
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
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              child: Text(
                                'Esta es una descripción breve del video. Puedes expandir para ver más detalles o instrucciones adicionales sobre este contenido.',
                                maxLines: isExpanded ? 5 : 2,
                                overflow: isExpanded ? TextOverflow.visible : TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 14, color: Colors.black54),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: TextButton(
                                onPressed: () => _toggleExpand(file.name),
                                child: Text(isExpanded ? 'Ver menos' : 'Ver más'),
                              ),
                            ),
                          ],
                        );
                      },
                    );
                  },
                ),
      bottomNavigationBar: const BottomNavBar(currentIndex: 1),
    );
  }
}
