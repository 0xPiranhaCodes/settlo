// The glass probe for #157's evidence, not part of the app. From app/:
//   flutter run -t ../docs/evidence/157/glass_probe.dart [--dart-define=DARK=true]
// It shows the real SettloShell and native bar over a list of Settlo cards.
// For 10s nothing but the background is under the bar; then a card with large
// text and a bright stripe slowly scrolls under it and stays there.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:settlo/shell.dart';
import 'package:settlo_core/settlo_core.dart';

void main() => runApp(const _Probe());

class _Probe extends StatefulWidget {
  const _Probe();

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  final _scroll = ScrollController();
  var _index = 0;

  @override
  void initState() {
    super.initState();
    debugPrint('PROBE empty');
    Timer(const Duration(seconds: 10), () async {
      debugPrint('PROBE moving');
      await _scroll.animateTo(
        200,
        duration: const Duration(seconds: 4),
        curve: Curves.linear,
      );
      debugPrint('PROBE card');
    });
  }

  @override
  Widget build(BuildContext context) {
    const dark = bool.fromEnvironment('DARK');
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: dark ? SettloTheme.dark() : SettloTheme.light(),
      home: SettloShell(
        currentIndex: _index,
        onTabSelected: (i) => setState(() => _index = i),
        child: Builder(
          builder: (context) => ListView(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(20, 80, 20, 0),
            children: [
              for (final title in ['Flat 4B', 'Goa trip']) ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: SCard(
                    child: SizedBox(
                      height: 150,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: Theme.of(context).textTheme.headlineLarge,
                          ),
                          const Spacer(),
                          Container(height: 40, color: const Color(0xFFE5484D)),
                        ],
                      ),
                    ),
                  ),
                ),
                // Background only under the bar until the scroll.
                const SizedBox(height: 700),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
