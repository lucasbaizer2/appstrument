import 'package:appstrument/app_state.dart';
import 'package:appstrument/websocket.dart';
import 'package:flutter/material.dart';

class PageRoot extends StatelessWidget {
  final Widget child;

  const PageRoot({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Appstrument')),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            const DrawerHeader(
              decoration: BoxDecoration(
                color: Colors.purple,
              ),
              child: Text('Appstrument', style: TextStyle(color: Colors.white, fontSize: 32.0)),
            ),
            ListTile(
              title: const Text('Patch APK'),
              onTap: () {
                Navigator.pop(context);
                Navigator.pushReplacementNamed(context, '/patch');
              },
            ),
            ListTile(
              title: const Text('Connect to Server'),
              onTap: () {
                Navigator.pop(context);
                Navigator.pushReplacementNamed(context, '/connect');
              },
            ),
            ListTile(
              title: const Text('View Application'),
              onTap: () {
                Navigator.pop(context);
                if (AppState.client == AppstrumentClient.defaultClient) {
                  Navigator.pushReplacementNamed(context, '/connect');
                } else {
                  Navigator.pushReplacementNamed(context, '/home');
                }
              },
            ),
          ],
        ),
      ),
      body: child,
    );
  }
}
