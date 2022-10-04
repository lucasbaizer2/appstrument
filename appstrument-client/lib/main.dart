import 'package:appstrument/page_root.dart';
import 'package:appstrument/views/connect.dart';
import 'package:appstrument/views/home.dart';
import 'package:appstrument/views/patch.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(const AppstrumentApp());
}

class _AppstrumentScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
      };
}

class AppstrumentApp extends StatelessWidget {
  const AppstrumentApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Appstrument',
      theme: ThemeData(primarySwatch: Colors.purple),
      scrollBehavior: _AppstrumentScrollBehavior(),
      routes: {
        '/home': (context) => const PageRoot(child: HomePage()),
        '/connect': (context) => const PageRoot(child: ConnectPage()),
        '/patch': (context) => const PageRoot(child: PatchPage()),
      },
      initialRoute: '/connect',
    );
  }
}
