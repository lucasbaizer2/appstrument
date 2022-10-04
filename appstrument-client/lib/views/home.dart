import 'package:appstrument/app_state.dart';
import 'package:appstrument/views/class_view.dart';
import 'package:appstrument/views/logcat_view.dart';
import 'package:appstrument/views/process_view.dart';
import 'package:appstrument/views/slat_view.dart';
import 'package:flutter/material.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(25.0),
      child: Row(
        children: [
          const Expanded(
            flex: 3,
            child: Card(
              child: Padding(
                padding: EdgeInsets.all(25.0),
                child: ClassView(),
              ),
            ),
          ),
          Expanded(
            flex: 4,
            child: Column(
              children: const [
                Expanded(
                  flex: 5,
                  child: Card(
                    child: Padding(
                      padding: EdgeInsets.all(25.0),
                      child: SlatView(),
                    ),
                  ),
                ),
                Expanded(
                  flex: 5,
                  child: Card(
                    child: Padding(
                      padding: EdgeInsets.all(25.0),
                      child: LogcatView(),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Expanded(
            flex: 3,
            child: Card(
              child: Padding(
                padding: EdgeInsets.all(25.0),
                child: ProcessView(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
