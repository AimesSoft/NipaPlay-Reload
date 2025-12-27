import 'package:flutter/material.dart';

import 'package:nipaplay_smb2/nipaplay_smb2.dart' as nipaplay_smb2;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final String status;

  @override
  void initState() {
    super.initState();
    try {
      nipaplay_smb2.nipaplaySmb2Bindings;
      status = 'nipaplay_smb2 loaded';
    } catch (e) {
      status = 'Failed to load nipaplay_smb2: $e';
    }
  }

  @override
  Widget build(BuildContext context) {
    const textStyle = TextStyle(fontSize: 25);
    const spacerSmall = SizedBox(height: 10);
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Native Packages'),
        ),
        body: SingleChildScrollView(
          child: Container(
            padding: const .all(10),
            child: Column(
              children: [
                const Text(
                  'This calls a native function through FFI that is shipped as source in the package. '
                  'The native code is built as part of the Flutter Runner build.',
                  style: textStyle,
                  textAlign: .center,
                ),
                spacerSmall,
                Text(
                  status,
                  style: textStyle,
                  textAlign: .center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
