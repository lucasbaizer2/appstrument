import 'dart:async';

import 'package:appstrument/app_state.dart';
import 'package:appstrument/websocket.dart';
import 'package:flutter/material.dart';
import 'package:process_run/shell.dart';

class ConnectPage extends StatefulWidget {
  const ConnectPage({super.key});

  @override
  State<ConnectPage> createState() => _ConnectPageState();
}

class _ConnectPageState extends State<ConnectPage> {
  final Shell _shell = Shell();
  late Future<List<String>> _devices;
  late Timer _adbDevicesTimer;

  @override
  void initState() {
    super.initState();

    _devices = Future.delayed(const Duration(days: 1)).then((value) => []);
    _adbDevicesTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _devices = _shell.run('adb devices').then((value) {
          List<String> devices = value.outLines
              .skip(1)
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .map(
                (e) => e.split('\t')[0],
              )
              .toList();
          return devices;
        });
      });
    });
  }

  @override
  void dispose() {
    _adbDevicesTimer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(25.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Connect to Server', style: TextStyle(fontSize: 24.0)),
              FutureBuilder(
                future: _devices,
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: snapshot.data!
                          .map(
                            (e) => TextButton(
                              onPressed: () async {
                                await _shell.run('adb -s "$e" forward tcp:32900 tcp:32900');
                                AppState.client = AppstrumentClient('localhost', 32900);
                                Navigator.pushReplacementNamed(context, '/home');
                              },
                              child: Text(e),
                            ),
                          )
                          .toList(),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
