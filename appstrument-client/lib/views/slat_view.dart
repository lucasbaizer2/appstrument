import 'package:appstrument/app_state.dart';
import 'package:appstrument/proto/data_model.pb.dart';
import 'package:appstrument/util.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SlatView extends StatefulWidget {
  const SlatView({super.key});

  @override
  State<SlatView> createState() => _SlatViewState();
}

class _SlatViewState extends State<SlatView> {
  final ScrollController _slatOutputScroll = ScrollController();
  final List<Widget> _outputWidgets = [];
  final TextEditingController _slatInputController = TextEditingController();
  final FocusNode _slatKeyNode = FocusNode();
  final FocusNode _slatInputNode = FocusNode();
  final List<String> _history = [];
  int _historyRecallDepth = 1;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _slatInputController.dispose();
    super.dispose();
  }

  void _submitSlat() async {
    String input = _slatInputController.text.trim();
    if (input.isEmpty) {
      return;
    }
    if (input == 'clear') {
      setState(() {
        _outputWidgets.clear();
        _slatInputController.text = '';
      });
      return;
    }
    var slatResponse = await AppState.client.executeSlat(input);
    Widget srwStyled = getJavaValueWidget(
      slatResponse.result,
      const TextStyle(
        fontFamily: 'Courier New',
        fontSize: 16.0,
      ),
    );
    setState(() {
      _historyRecallDepth = 1;
      _history.add(input);
      _slatInputController.text = '';

      _outputWidgets.add(
        Row(
          mainAxisSize: MainAxisSize.max,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Icon(Icons.chevron_right, color: Colors.blue),
            Text(
              input,
              style: const TextStyle(
                fontFamily: 'Courier New',
                fontSize: 16.0,
              ),
            ),
          ],
        ),
      );
      _outputWidgets.add(const SizedBox(height: 5.0));
      _outputWidgets.add(
        Row(
          mainAxisSize: MainAxisSize.max,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Icon(Icons.chevron_left, color: Colors.blue),
            if (slatResponse.hasText() && slatResponse.text.isNotEmpty) ...[
              Flexible(
                child: Text(
                  slatResponse.text,
                  style: TextStyle(
                    color: Colors.grey[700],
                    fontFamily: 'Courier New',
                    fontSize: 16.0,
                  ),
                ),
              )
            ] else
              ...[],
            if (!slatResponse.error && slatResponse.result.valueType != JavaValue_JavaValueType.NOT_PRESENT) ...[
              srwStyled
            ] else if (!slatResponse.error) ...[
              Text(
                'void',
                style: TextStyle(
                  color: Colors.grey[700],
                  fontFamily: 'Courier New',
                  fontSize: 16.0,
                ),
              )
            ]
          ],
        ),
      );
      _outputWidgets.add(const Divider(
        height: 20,
        thickness: 1,
        color: Colors.grey,
      ));
    });
  }

  @override
  Widget build(BuildContext context) {
    double width = MediaQuery.of(context).size.width;
    var input = Row(
      mainAxisSize: MainAxisSize.max,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Icon(Icons.chevron_right, color: Colors.blue),
        RawKeyboardListener(
          autofocus: true,
          focusNode: _slatKeyNode,
          onKey: (event) async {
            if (event.isKeyPressed(LogicalKeyboardKey.enter)) {
              _submitSlat();
            } else if (event.isKeyPressed(LogicalKeyboardKey.arrowUp) && _historyRecallDepth <= _history.length) {
              setState(() {
                String item = _history[_history.length - _historyRecallDepth];
                _slatInputController.value = TextEditingValue(
                  text: item,
                  // selection: TextSelection.fromPosition(TextPosition(offset: item.length)),
                );
                _historyRecallDepth += 1;
              });
            } else if (event.isKeyPressed(LogicalKeyboardKey.arrowDown) && _historyRecallDepth > 0) {
              setState(() {
                _historyRecallDepth -= 1;
                String item = _history[_history.length - _historyRecallDepth];
                _slatInputController.value = TextEditingValue(
                  text: item,
                  selection: TextSelection.fromPosition(TextPosition(offset: item.length)),
                );
              });
            }
          },
          child: SizedBox(
            width: width / 2 - 325,
            child: TextFormField(
              textInputAction: TextInputAction.none,
              focusNode: _slatInputNode,
              controller: _slatInputController,
              decoration: const InputDecoration(border: UnderlineInputBorder()),
              style: const TextStyle(fontFamily: 'Courier New'),
            ),
          ),
        ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Slat Interpreter',
          style: TextStyle(fontSize: 24.0),
        ),
        const SizedBox(height: 10.0),
        Expanded(
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
            child: ListView(
              controller: _slatOutputScroll,
              physics: const PageScrollPhysics(),
              shrinkWrap: true,
              reverse: true,
              children: _outputWidgets.reversed.toList(),
            ),
          ),
        ),
        input,
      ],
    );
  }
}
