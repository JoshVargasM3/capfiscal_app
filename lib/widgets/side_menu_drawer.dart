import 'package:flutter/material.dart';
import '../screens/user_profile_screen.dart';

class SideMenuDrawer extends StatelessWidget {
  const SideMenuDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: ListView(
        children: [
          const DrawerHeader(child: Icon(Icons.account_circle, size: 100)),
          ListTile(
            leading: const Icon(Icons.person),
            title: const Text('Datos del Usuario'),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const UserProfileScreen())),
          ),
        ],
      ),
    );
  }
}
