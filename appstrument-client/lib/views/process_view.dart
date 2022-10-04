import 'dart:async';

import 'package:appstrument/app_state.dart';
import 'package:appstrument/proto/data_model.pb.dart';
import 'package:flutter/material.dart';

class ProcessView extends StatefulWidget {
  const ProcessView({super.key});

  @override
  State<ProcessView> createState() => _ProcessViewState();
}

class _ProcessViewState extends State<ProcessView> {
  late Future<List<JavaThread>> _threads;

  @override
  void initState() {
    super.initState();

    _threads = AppState.client.getProcessStatus().then((value) => value.threads);
    Timer.periodic(const Duration(milliseconds: 100), (_) {
      setState(() {
        _threads = AppState.client.getProcessStatus().then((value) => value.threads);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Process',
          style: TextStyle(fontSize: 24.0),
        ),
        const SizedBox(height: 10.0),
        FutureBuilder(
          future: _threads,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            return Expanded(
              child: ListView(
                children: [
                  ...snapshot.data!.map(
                    (e) => _ThreadView(e),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

class _ThreadView extends StatefulWidget {
  final JavaThread thread;

  const _ThreadView(this.thread);

  @override
  State<_ThreadView> createState() => _ThreadViewState();
}

class _ThreadViewState extends State<_ThreadView> {
  bool _showDetails = false;

  List<Widget> _getThreadStatus() {
    List<String> st = widget.thread.stackTrace.split('\n');

    List<Widget> widgets = [];
    if (st[0] == 'sun.misc.Unsafe.park(Native Method)' || st[0] == 'java.lang.Object.wait(Native Method)') {
      widgets.add(const Text('Status: Waiting on Mutex Lock', style: TextStyle(fontSize: 18.0)));
    } else {
      widgets.add(const Text('Status: Running', style: TextStyle(fontSize: 18.0)));
    }

    if (widget.thread.stackTrace.isEmpty) {
      widgets.add(const Text('No Stack Trace Available', style: TextStyle(fontSize: 18.0)));
    } else {
      widgets.add(const Text('Stack Trace:', style: TextStyle(fontSize: 18.0)));
    }

    return widgets;
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2.0,
      child: Padding(
        padding: const EdgeInsets.all(5.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconButton(
                  splashRadius: 20.0,
                  iconSize: 24.0,
                  icon: Icon(
                    _showDetails ? Icons.keyboard_arrow_down_outlined : Icons.chevron_right,
                    size: 20.0,
                  ),
                  onPressed: () => setState(() => _showDetails = !_showDetails),
                ),
                Text(
                  widget.thread.name,
                  style: const TextStyle(fontSize: 18.0),
                ),
              ],
            ),
            if (_showDetails) ...[
              Padding(
                padding: const EdgeInsets.only(left: 20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ..._getThreadStatus(),
                    if (widget.thread.stackTrace.isEmpty)
                      ...[]
                    else ...[
                      Padding(
                        padding: const EdgeInsets.only(left: 20.0),
                        child: Text(widget.thread.stackTrace.split('\n').map((e) => 'at ' + e).join('\n')),
                      ),
                    ],
                  ],
                ),
              ),
            ] else
              ...[],
          ],
        ),
      ),
    );
  }
}
