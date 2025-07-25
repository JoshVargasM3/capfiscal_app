import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import '../widgets/bottom_nav_bar.dart';
import '../widgets/custom_drawer.dart';
import '../helpers/favorites_manager.dart';
import '../widgets/video_item.dart';

class UserProfileScreen extends StatefulWidget {
  const UserProfileScreen({super.key});

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> with SingleTickerProviderStateMixin {
  final FirebaseStorage _storage = FirebaseStorage.instance;
  List<Reference> _favoriteDocs = [];
  List<Reference> _favoriteVideos = [];
  bool _loading = true;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _fetchFavorites();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchFavorites() async {
    setState(() => _loading = true);
    try {
      final favoriteNames = await FavoritesManager.getFavorites();
      final docsResult = await _storage.ref('/').listAll();
      final videosResult = await _storage.ref('/videos/').listAll();
      setState(() {
        _favoriteDocs = docsResult.items.where((f) => favoriteNames.contains(f.name)).toList();
        _favoriteVideos = videosResult.items.where((v) => favoriteNames.contains(v.name)).toList();
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
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Perfil'),
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        actions: [
          IconButton(onPressed: _fetchFavorites, icon: const Icon(Icons.refresh)),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.description), text: 'Documentos'),
            Tab(icon: Icon(Icons.video_library), text: 'Videos'),
          ],
        ),
      ),
      drawer: const CustomDrawer(),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildFavoritesDocsView(),
                _buildFavoritesVideosView(),
              ],
            ),
      bottomNavigationBar: const BottomNavBar(currentIndex: 3),
    );
  }

  Widget _buildFavoritesDocsView() {
    if (_favoriteDocs.isEmpty) {
      return const Center(child: Text('No tienes documentos favoritos'));
    }
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: _favoriteDocs.length,
      itemBuilder: (ctx, i) {
        final file = _favoriteDocs[i];
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
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildFavoritesVideosView() {
    if (_favoriteVideos.isEmpty) {
      return const Center(child: Text('No tienes videos favoritos'));
    }
    return ListView.builder(
      itemCount: _favoriteVideos.length,
      itemBuilder: (ctx, i) {
        final video = _favoriteVideos[i];
        return FutureBuilder<String>(
          future: video.getDownloadURL(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (!snapshot.hasData) {
              return const ListTile(title: Text('Error al cargar video'));
            }
            return VideoItem(
              videoUrl: snapshot.data!,
              title: video.name,
            );
          },
        );
      },
    );
  }
}
