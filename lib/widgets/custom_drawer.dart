import 'package:flutter/material.dart';

class CustomDrawer extends StatelessWidget {
  const CustomDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: ListView(
        children: [
          const DrawerHeader(
            decoration: BoxDecoration(color: Colors.red),
            child: Center(
              child: Text(
                'Capfiscal App',
                style: TextStyle(color: Colors.white, fontSize: 20),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.library_books),
            title: const Text('Biblioteca Legal'),
            subtitle: const Text('Documentos disponibles'),
            onTap: () => Navigator.pushReplacementNamed(context, '/biblioteca'),
          ),
          ListTile(
            leading: const Icon(Icons.video_library),
            title: const Text('Videos'),
            subtitle: const Text('Reproductor de videos'),
            onTap: () => Navigator.pushReplacementNamed(context, '/video'),
          ),
          ListTile(
            leading: const Icon(Icons.chat),
            title: const Text('Chat'),
            subtitle: const Text('Centro de mensajería'),
            onTap: () => Navigator.pushReplacementNamed(context, '/chat'),
          ),
          ListTile(
            leading: const Icon(Icons.person),
            title: const Text('Perfil'),
            subtitle: const Text('Mis datos y documentos'),
            onTap: () => Navigator.pushReplacementNamed(context, '/perfil'),
          ),
        ],
      ),
    );
  }
}
