import 'dart:async';
import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:io/io.dart' as io;

import 'package:archive/archive_io.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:process_run/shell.dart';
import 'package:xml/xml.dart';
import 'package:xml/xpath.dart';

class PatchPage extends StatefulWidget {
  const PatchPage({super.key});

  @override
  State<PatchPage> createState() => _PatchPageState();
}

class _PatchPageState extends State<PatchPage> {
  String _status = '';
  StreamController<String>? _processController;

  @override
  void initState() {
    super.initState();

    _status = 'Copying dependencies...';
    Future.wait([
      _copyBinaryAsset('apktool.jar'),
      _copyBinaryAsset('apksigner.jar'),
      _copyBinaryAsset('patch.zip'),
    ]).then((value) {
      setState(() => _status = 'Extracting patches...');
      InputFileStream input =
          InputFileStream('${Directory.systemTemp.path}/appstrument/patch.zip');
      Archive archive = ZipDecoder().decodeBuffer(input);
      extractArchiveToDisk(
        archive,
        '${Directory.systemTemp.path}/appstrument/patch',
        bufferSize: 65536,
      );
      setState(() => _status = '');
    });
  }

  Future<void> _copyBinaryAsset(String file) async {
    ByteData binaryAsset = await rootBundle.load('assets/java/' + file);
    Directory subDir =
        await Directory('${Directory.systemTemp.path}/appstrument').create();
    await File('${subDir.path}/$file').writeAsBytes(binaryAsset.buffer
        .asUint8List(binaryAsset.offsetInBytes, binaryAsset.lengthInBytes));
  }

  Future<void> _patchApplicationClass(
      List<String> smaliDirs, String className) async {
    String classNamePath = className.replaceAll('.', path.separator);
    for (String smaliDir in smaliDirs) {
      File smaliFile = File('$smaliDir/$classNamePath.smali');
      if (await smaliFile.exists()) {
        String rawSmali = await smaliFile.readAsString();
        List<String> lines = rawSmali.split('\n');

        const String function = 'FUNCTION';
        const String registers = 'REGISTERS';
        const String invokeSuper = 'SUPER';
        const String done = 'DONE';
        String appPatch = '''
    const-string v6, "Appstrument patch in $className reached!"

    invoke-static {v6}, Lappstrument/server/LogUtil;->print(Ljava/lang/Object;)V

    const-class v6, Lappstrument/server/AppstrumentService;

    new-instance v7, Landroid/content/Intent;

    invoke-direct {v7, p0, v6}, Landroid/content/Intent;-><init>(Landroid/content/Context;Ljava/lang/Class;)V

    invoke-virtual {p0, v7}, L$classNamePath;->startService(Landroid/content/Intent;)Landroid/content/ComponentName;''';

        String mode = function;
        for (int i = 0; i < lines.length; i++) {
          String line = lines[i].trim();
          if (mode == function) {
            if (line == '.method public onCreate()V') {
              mode = registers;
            }
          } else if (mode == registers) {
            if (line.startsWith('.locals')) {
              lines[i] = '    .registers 10';
              mode = invokeSuper;
            } else if (line.startsWith('.registers')) {
              lines[i] = '    .registers 10';
              mode = invokeSuper;
            }
          } else if (mode == invokeSuper) {
            if (line.startsWith('invoke-super')) {
              lines.insert(i + 1, appPatch);
              mode = done;
              break;
            }
          }
        }

        if (mode != done) {
          throw Exception('mode was $mode, expected $done');
        }

        await smaliFile.writeAsString(lines.join('\n'));

        return;
      }
    }

    throw Exception(
        'could not find smali file with application class name "$className"');
  }

  Future<void> _patchApk() async {
    setState(() => _status = 'Patching APK...');

    Directory patch =
        Directory('${Directory.systemTemp.path}/appstrument/patch');
    Directory decoded =
        Directory('${Directory.systemTemp.path}/appstrument/decoded-apk');

    await io.copyPath('${patch.path}/lib', '${decoded.path}/lib');

    List<String> smaliDirs = [];
    for (FileSystemEntity entity in await decoded.list().toList()) {
      if (entity is Directory &&
          path.basename(entity.path).startsWith('smali')) {
        smaliDirs.add(entity.path);
      }
    }
    smaliDirs.sort((aAbs, bAbs) {
      String a = path.basename(aAbs);
      String b = path.basename(bAbs);
      if (a == b) {
        return 0;
      }
      if (a == 'smali') {
        return -1;
      } else if (b == 'smali') {
        return 1;
      }

      return int.parse(a.substring('smali_classes'.length))
          .compareTo(int.parse(b.substring('smali_classes'.length)));
    });
    await io.copyPath('${patch.path}/smali', smaliDirs.last);

    XmlDocument patchDoc = XmlDocument.parse(
        await File('${patch.path}/AndroidManifest.xml').readAsString());
    XmlDocument decodedDoc = XmlDocument.parse(
        await File('${decoded.path}/AndroidManifest.xml').readAsString());

    XmlNode decodedManifestRoot = decodedDoc.xpath('/manifest').single;
    List<String> permissions = [];
    for (XmlElement child in decodedManifestRoot.childElements) {
      if (child.name.local == 'uses-permission') {
        permissions.add(child.getAttribute('android:name')!);
      }
    }

    XmlNode decodedApplication =
        decodedDoc.xpath('/manifest/application').single;
    String? applicationName =
        decodedApplication.getAttributeNode('android:name')?.value;
    if (applicationName != null) {
      await _patchApplicationClass(smaliDirs, applicationName);
    } else {
      decodedApplication.setAttribute(
          'android:name', 'appstrument.server.AppstrumentApplication');
    }

    decodedApplication.getAttributeNode('android:extractNativeLibs')!.value =
        'true';

    List<String> requiredPermissions = [
      'android.permission.INTERNET',
      'android.permission.ACCESS_NETWORK_STATE',
      'android.permission.ACCESS_WIFI_STATE'
    ];
    for (String requiredPermission in requiredPermissions) {
      if (!permissions.contains(requiredPermission)) {
        XmlBuilder builder = XmlBuilder();
        builder.element('uses-permission', attributes: {
          'android:name': requiredPermission,
        });
        patchDoc.children.add(builder.buildFragment());
      }
    }

    List<XmlNode> decodedApplicationChildren =
        decodedDoc.xpath('/manifest/application').single.children;
    XmlNode patchService =
        patchDoc.xpath('/manifest/application/service').single;

    decodedApplicationChildren.add(patchService.copy());

    await File('${decoded.path}/AndroidManifest.xml')
        .writeAsString(decodedDoc.toXmlString(pretty: true));

    _encodeApk();
  }

  Future<void> _encodeApk() async {
    if (_processController == null) {
      Shell shell = Shell();
      await shell.run(
        'java -jar "${Directory.systemTemp.path}/appstrument/apktool.jar" build "${Directory.systemTemp.path}/appstrument/decoded-apk" -o "${Directory.systemTemp.path}/appstrument/encoded.apk" --use-aapt2',
        onProcess: (process) {
          _processController = StreamController.broadcast();
          _processController!.stream
              .listen((event) => setState(() => _status = event));

          _processController!.addStream(process.outLines).then((value) {
            _processController = null;

            _signApk();
          });
        },
      );
    }
  }

  Future<void> _saveApk() async {
    String? result;
    while (result == null) {
      result = await FilePicker.platform.saveFile(
        dialogTitle: 'Select Directory to Save Patched APK File',
        type: FileType.custom,
        allowedExtensions: ['apk'],
      );
    }
    File source = File(
        '${Directory.systemTemp.path}/appstrument/encoded-aligned-debugSigned.apk');
    await source.copy(result);
    await source.delete();
  }

  Future<void> _signApk() async {
    if (_processController == null) {
      Shell shell = Shell();
      await shell.run(
        'java -jar "${Directory.systemTemp.path}/appstrument/apksigner.jar" -a "${Directory.systemTemp.path}/appstrument/encoded.apk" -o "${Directory.systemTemp.path}/appstrument"',
        onProcess: (process) {
          setState(() => _status = 'Signing patched APK...');

          _processController = StreamController.broadcast();
          _processController!.addStream(process.outLines).then((value) {
            _processController = null;
            setState(() => _status = 'Done!');

            _saveApk();
          });
        },
      );
    }
  }

  Future<void> _decodeApk(String apkPath) async {
    Directory decodeDir =
        Directory('${Directory.systemTemp.path}/appstrument/decoded-apk');

    if (await decodeDir.exists()) {
      await decodeDir.delete(recursive: true);
    }

    if (_processController == null) {
      Shell shell = Shell();
      await shell.run(
        'java -jar "${Directory.systemTemp.path}/appstrument/apktool.jar" decode $apkPath -o "${decodeDir.path}"',
        onProcess: (process) {
          _processController = StreamController.broadcast();
          _processController!.stream
              .listen((event) => setState(() => _status = event));

          _processController!.addStream(process.outLines).then((value) {
            _processController = null;

            _patchApk();
          });
        },
      );
    }
  }

  Future<void> _selectApk() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      dialogTitle: 'Select APK File',
      type: FileType.custom,
      allowedExtensions: ['apk'],
    );
    if (result == null || result.paths.length != 1 || result.paths[0] == null) {
      return;
    }

    _decodeApk(result.paths[0]!);
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
                  onPressed: _status == '' || _status == 'Done!'
                      ? () => _selectApk()
                      : null,
                ),
                if (_status != '') ...[
                  const SizedBox(height: 10.0),
                  Text(_status),
                  if (_status != 'Done!') ...[
                    const SizedBox(height: 10.0),
                    const CircularProgressIndicator(),
                  ],
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
