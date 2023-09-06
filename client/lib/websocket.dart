import 'dart:async';
import 'dart:collection';

import 'package:appstrument/proto/appstrument.pb.dart';
import 'package:appstrument/proto/data_model.pb.dart';
import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class AppstrumentClient {
  static AppstrumentClient defaultClient = AppstrumentClient('null', 0);

  final HashMap<int, Completer<AppstrumentResponse>> _completers = HashMap();
  final GZipDecoder _gZipDecoder = GZipDecoder();
  int _packetId = 0;
  String _logcatBuffer = "";
  late WebSocketChannel _channel;
  late void Function(String)? logcatListener;

  AppstrumentClient(String host, int port) {
    if (host == 'null') {
      return;
    }
    _channel = WebSocketChannel.connect(
      Uri.parse('ws://$host:$port'),
    );
    _channel.stream.listen((event) {
      var bytes = _gZipDecoder.decodeBytes(event as Uint8List);
      var response = AppstrumentResponse.fromBuffer(bytes);
      if (response.hasLogcatStream()) {
        logcatListener?.call(response.logcatStream.text);
      } else {
        _completers[response.id]?.complete(response);
        _completers.remove(response.id);
      }
    });
  }

  Future<AppstrumentResponse> _newCompleter(int id) {
    var completer = Completer<AppstrumentResponse>();
    _completers[id] = completer;
    return completer.future;
  }

  Future<List<LoadedClass>> getAllLoadedClasses() async {
    var id = _packetId++;
    var request = AppstrumentRequest(
      id: id,
      loadedClasses: GetLoadedClassesRequest(queryType: GetLoadedClassesRequest_QueryType.FULL),
    );
    _channel.sink.add(request.writeToBuffer());
    return _newCompleter(id).then((value) => value.loadedClasses.classes);
  }

  Future<ExecuteSlatResponse> executeSlat(String code) async {
    var id = _packetId++;
    var request = AppstrumentRequest(
      id: id,
      executeSlat: ExecuteSlatRequest(code: code),
    );
    _channel.sink.add(request.writeToBuffer());
    return _newCompleter(id).then((value) => value.executeSlat);
  }

  Future<List<JavaField>> getStaticFields(String className) async {
    var id = _packetId++;
    var request = AppstrumentRequest(
      id: id,
      staticFields: GetStaticFieldsRequest(className: className),
    );
    _channel.sink.add(request.writeToBuffer());
    return _newCompleter(id).then((value) => value.staticFields.fields);
  }

  Future<List<JavaField>> getObjectFields(int objectId) async {
    var id = _packetId++;
    var request = AppstrumentRequest(
      id: id,
      objectFields: GetObjectFieldsRequest(objectId: objectId),
    );
    _channel.sink.add(request.writeToBuffer());
    return _newCompleter(id).then((value) => value.objectFields.fields);
  }

  Future<GetProcessStatusResponse> getProcessStatus() async {
    var id = _packetId++;
    var request = AppstrumentRequest(
      id: id,
      processStatus: GetProcessStatusRequest(),
    );
    _channel.sink.add(request.writeToBuffer());
    return _newCompleter(id).then((value) => value.processStatus);
  }
}
