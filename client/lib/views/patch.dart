import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:process_run/shell.dart';

class PatchPage extends StatefulWidget {
  const PatchPage({super.key});

  @override
  State<PatchPage> createState() => _PatchPageState();
}

class _PatchPageState extends State<PatchPage> {
  String _status = '';

  @override
  void initState() {
    super.initState();

    _status = 'Copying dependencies...';
    Future.wait([_copyBinaryAsset('apktool.jar'), _copyBinaryAsset('sign.jar')])
        .then((value) {
      setState(() => _status = '');
    });
  }

  Future<void> _copyBinaryAsset(String file) async {
    ByteData binaryAsset = await rootBundle.load('assets/java/' + file);
    Directory tmpDir = await getTemporaryDirectory();
    Directory subDir = await Directory('${tmpDir.path}/appstrument').create();
    await File('${subDir.path}/$file').writeAsBytes(binaryAsset.buffer
        .asUint8List(binaryAsset.offsetInBytes, binaryAsset.lengthInBytes));
  }

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

    Directory tmpDir = await getTemporaryDirectory();
    Directory patchDir = Directory('${tmpDir.path}/appstrument/patch');
    String apkPath = result.paths[0]!;

    Shell shell = Shell();
    await shell.run(
      'java -jar "${tmpDir.path}/appstrument/apktool.jar" decode $apkPath -o "${patchDir.path}"',
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
                ElevatedButton(
                  child: const Text('Select APK File'),
                  onPressed: () => _selectApk(),
                ),
                if (_status != '') ...[
                  const SizedBox(height: 10.0),
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
