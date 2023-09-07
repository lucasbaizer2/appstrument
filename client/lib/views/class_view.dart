import 'package:appstrument/app_state.dart';
import 'package:appstrument/proto/data_model.pb.dart';
import 'package:appstrument/util.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ClassView extends StatefulWidget {
  const ClassView({super.key});

  @override
  State<ClassView> createState() => _ClassViewState();
}

class _JavaFieldViewer extends StatefulWidget {
  final JavaField field;

  const _JavaFieldViewer(this.field);

  @override
  State<_JavaFieldViewer> createState() => _JavaFieldViewerState();
}

class _JavaFieldViewerState extends State<_JavaFieldViewer> {
  late Future<List<JavaField>> _objectFields;
  bool _showObjectFields = false;

  Widget _getTypeWidget() {
    if (widget.field.type == 'java.lang.String') {
      return const Text('String', style: TextStyle(color: Colors.brown));
    }
    if (widget.field.type == 'boolean') {
      return const Text('boolean', style: TextStyle(color: Colors.blue));
    }
    if (widget.field.type.contains('.')) {
      return Text(widget.field.type, style: const TextStyle(color: Colors.purple));
    }
    return Text(widget.field.type, style: const TextStyle(color: Colors.green));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: widget.field.hasValue() && widget.field.value.hasObjectType()
              ? () {
                  {
                    setState(() {
                      if (!_showObjectFields) {
                        _objectFields = AppState.client.getObjectFields(widget.field.objectId);
                      }
                      _showObjectFields = !_showObjectFields;
                    });
                  }
                }
              : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 5.0, horizontal: 5.0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.field.hasValue() && widget.field.value.hasObjectType()) ...[
                  Icon(_showObjectFields ? Icons.keyboard_arrow_down_outlined : Icons.chevron_right, size: 20.0),
                ] else
                  ...[],
                Text(widget.field.name + ': '),
                _getTypeWidget(),
                const Text(' = '),
                getJavaValueWidget(widget.field.value, null),
              ],
            ),
          ),
        ),
        if (_showObjectFields) ...[
          Padding(
            padding: const EdgeInsets.only(left: 20.0),
            child: FutureBuilder<List<JavaField>>(
              future: _objectFields,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const CircularProgressIndicator();
                } else {
                  var data = snapshot.data!;
                  if (data.isEmpty) {
                    return const Text('No instance fields defined.');
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: data.map((e) => _JavaFieldViewer(e)).toList(),
                  );
                }
              },
            ),
          ),
        ] else
          ...[],
      ],
    );
  }
}

class _ClassViewItem extends StatefulWidget {
  final LoadedClass loadedClass;
  final String optimizedName;

  const _ClassViewItem(this.loadedClass, this.optimizedName);

  @override
  State<_ClassViewItem> createState() => _ClassViewItemState();
}

class _ClassViewItemState extends State<_ClassViewItem> /*with AutomaticKeepAliveClientMixin*/ {
  static final Image _classIcon = Image.asset(
    'assets/icons/java_class.png',
    width: 25.0,
    height: 25.0,
  );
  static final Image _interfaceIcon = Image.asset(
    'assets/icons/java_interface.png',
    width: 25.0,
    height: 25.0,
  );
  static final Image _enumIcon = Image.asset(
    'assets/icons/java_enum.png',
    width: 25.0,
    height: 25.0,
  );
  static final Image _annotationIcon = Image.asset(
    'assets/icons/java_annotation.png',
    width: 25.0,
    height: 25.0,
  );

  late final String _tooltipText = widget.loadedClass.className;
  late Future<List<JavaField>> _staticFields;
  bool _showStaticFields = false;
  final GlobalKey _tooltipKey = GlobalKey();

  // @override
  // bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();

    if (widget.loadedClass.className == 'appstrument.server.AppstrumentApplication') {
      print('field: ' + _showStaticFields.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    // super.build(context);

    if (widget.loadedClass.className == 'appstrument.server.AppstrumentApplication') {
      print('rebuilding: ' + _showStaticFields.toString());
    }

    Image classIcon = _classIcon;
    LoadedClassType classType = widget.loadedClass.classType;
    if (classType == LoadedClassType.CLASS || classType == LoadedClassType.UNRESOLVED) {
      classIcon = _classIcon;
    } else if (classType == LoadedClassType.INTERFACE) {
      classIcon = _interfaceIcon;
    } else if (classType == LoadedClassType.ENUM) {
      classIcon = _enumIcon;
    } else if (classType == LoadedClassType.ANNOTATION) {
      classIcon = _annotationIcon;
    }
    return Card(
      elevation: 3.0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Tooltip(
            key: _tooltipKey,
            message: _tooltipText,
            waitDuration: const Duration(seconds: 1),
            enableFeedback: false,
            child: Padding(
              padding: const EdgeInsets.all(5.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  IconButton(
                    splashRadius: 20.0,
                    iconSize: 24.0,
                    icon: Icon(
                      _showStaticFields ? Icons.keyboard_arrow_down_outlined : Icons.chevron_right,
                      size: 20.0,
                    ),
                    onPressed: () {
                      setState(() {
                        if (widget.loadedClass.className == 'appstrument.server.AppstrumentApplication') {
                          print('setting state: ' + _showStaticFields.toString());
                        }
                        if (!_showStaticFields) {
                          _staticFields = AppState.client.getStaticFields(widget.loadedClass.className);
                        }
                        _showStaticFields = !_showStaticFields;
                      });
                    },
                  ),
                  classIcon,
                  const SizedBox(width: 5.0),
                  Flexible(
                    child: GestureDetector(
                      onDoubleTap: () async {
                        await Clipboard.setData(ClipboardData(text: widget.loadedClass.className));

                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text('Copied to clipboard!'),
                        ));
                      },
                      child: Text(
                        widget.loadedClass.className,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 16.0),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_showStaticFields) ...[
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Padding(
                padding: const EdgeInsets.only(left: 40.0, bottom: 5.0),
                child: FutureBuilder<List<JavaField>>(
                  future: _staticFields,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const CircularProgressIndicator();
                    } else {
                      var data = snapshot.data!;
                      if (data.isEmpty) {
                        return const Text('No static fields defined.');
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: data.map((e) => _JavaFieldViewer(e)).toList(),
                      );
                    }
                  },
                ),
              ),
            ),
          ] else
            ...[]
        ],
      ),
    );
  }
}

class _ClassViewItemData {
  final LoadedClass loadedClass;
  final String optimizedName;

  const _ClassViewItemData(this.loadedClass, this.optimizedName);
}

class _ClassViewState extends State<ClassView> {
  late Future<List<_ClassViewItemData>> _classes;
  String _searchFilter = '';
  bool _includeStandardLibraryClasses = false;
  bool _includeInterfaces = false;

  @override
  void initState() {
    super.initState();

    _loadClasses();
  }

  void _loadClasses() {
    _classes = AppState.client.getAllLoadedClasses().then((values) async {
      values = values.where((element) => !element.className.contains('\$')).toList();
      values.sort((a, b) => a.className.compareTo(b.className));
      return values.map((e) => _ClassViewItemData(e, e.className.toLowerCase())).toList();
    });
  }

  bool _filterClass(LoadedClassType classType, String optimizedClassName) {
    if (!_includeInterfaces) {
      if (classType == LoadedClassType.INTERFACE || classType == LoadedClassType.ANNOTATION) {
        return false;
      }
    }
    if (!_includeStandardLibraryClasses) {
      if (optimizedClassName.startsWith('android') ||
          optimizedClassName.startsWith('kotlin') ||
          optimizedClassName.startsWith('appstrument') ||
          optimizedClassName.startsWith('org.java_websocket')) {
        return false;
      }
    }
    if (_searchFilter != '' && !optimizedClassName.contains(_searchFilter)) {
      return false;
    }

    return true;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Text(
              'Class List',
              style: TextStyle(fontSize: 24.0),
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              splashRadius: 20.0,
              onPressed: () {
                setState(() => _loadClasses());
              },
            ),
          ],
        ),
        const SizedBox(height: 10.0),
        TextField(
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'Search Classes',
          ),
          onChanged: (value) => setState(() => _searchFilter = value.toLowerCase()),
        ),
        Row(
          children: [
            Expanded(
              child: CheckboxListTile(
                title: const Text('Include Standard'),
                value: _includeStandardLibraryClasses,
                onChanged: (value) => setState(() => _includeStandardLibraryClasses = value ?? false),
              ),
            ),
            Expanded(
              child: CheckboxListTile(
                title: const Text('Include Interfaces'),
                value: _includeInterfaces,
                onChanged: (value) => setState(() => _includeInterfaces = value ?? false),
              ),
            ),
          ],
        ),
        FutureBuilder<List<_ClassViewItemData>>(
          future: _classes,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            var items = snapshot.data!;
            List<_ClassViewItemData> filteredItems = [];
            for (int i = 0; i < items.length; i++) {
              var item = items[i];
              if (_filterClass(item.loadedClass.classType, item.optimizedName)) {
                filteredItems.add(item);
              }
            }

            return Flexible(
              child: ScrollConfiguration(
                behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemBuilder: (context, index) => _ClassViewItem(
                    filteredItems[index].loadedClass,
                    filteredItems[index].optimizedName,
                  ),
                  itemCount: filteredItems.length,
                ),
              ),
            );
          },
        )
      ],
    );
  }
}
