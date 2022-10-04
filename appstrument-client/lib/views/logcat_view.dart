import 'package:appstrument/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/src/widgets/container.dart';
import 'package:flutter/src/widgets/framework.dart';

class LogcatView extends StatefulWidget {
  const LogcatView({super.key});

  @override
  State<LogcatView> createState() => _LogcatViewState();
}

class _LogcatViewState extends State<LogcatView> {
  final TextEditingController _logcatOutputController = TextEditingController();

  @override
  void initState() {
    super.initState();

    _logcatOutputController.text = 'Connected to Logcat.\n\n';
    AppState.client.logcatListener = (text) {
      setState(() {
        _logcatOutputController.text += text + '\n';
      });
    };
  }

  @override
  void dispose() {
    _logcatOutputController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Logcat',
          style: TextStyle(fontSize: 24.0),
        ),
        const SizedBox(height: 10.0),
        Expanded(
            child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.vertical,
              reverse: true,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Text(
                  _logcatOutputController.text,
                  softWrap: false,
                  overflow: TextOverflow.visible,
                  style: const TextStyle(fontSize: 16.0, fontFamily: 'Courier New'),
                ),
              ),
            ),
          ],
        )),
      ],
    );
  }
}
