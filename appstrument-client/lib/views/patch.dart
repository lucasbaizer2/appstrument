import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:process_run/shell.dart';

class PatchPage extends StatefulWidget {
  const PatchPage({super.key});

  @override
  State<PatchPage> createState() => _PatchPageState();
}

class _PatchPageState extends State<PatchPage> {
  String _status = '';

  void _selectApk() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      dialogTitle: 'Select APK File',
      type: FileType.custom,
      allowedExtensions: ['apk'],
    );
    if (result == null) {
      return;
    }

    Directory tempDir = await getTemporaryDirectory();
    String outDir = '${tempDir.absolute.path}\\appstrument_apktool';
    Shell shell = Shell();

    await shell.run(
      'java -jar C:\\Users\\Lucas\\Code\\Projects\\appstrument\\appstrument-client\\assets\\java\\apktool_2.6.0.jar decode ${result.paths[0]} -o $outDir',
      onProcess: (process) {
        process.outLines.asBroadcastStream().listen((event) {
          setState(() => _status = event.trim());
        });
      },
    );
    setState(() => _status = 'Patching APK...');
    setState(() => _status = 'Signing APK...');
    setState(() => _status = 'Done!');
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(25.0),
          child: SizedBox(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Text('Connect to Server', style: TextStyle(fontSize: 24.0)),
                const SizedBox(height: 10.0),
                ElevatedButton(
                  child: const Text('Select APK File'),
                  onPressed: () => _selectApk(),
                ),
                const SizedBox(height: 10.0),
                if (_status != '') ...[
                  Text(_status),
                  const CircularProgressIndicator(),
                ] else
                  ...[]
              ],
            ),
          ),
        ),
      ),
    );
  }
}
