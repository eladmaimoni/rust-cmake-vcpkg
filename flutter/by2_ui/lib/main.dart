import 'package:flutter/material.dart';
import 'package:by2_ui/src/rust/api/simple.dart';
import 'package:by2_ui/src/rust/frb_generated.dart';

Future<void> main() async {
  await RustLib.init();
  runApp(const MyApp());
}

class StatefulAddButton extends StatefulWidget {
  const StatefulAddButton({super.key});

  @override
  State<StatefulAddButton> createState() => _StatefulAddButtonState();
}

class _StatefulAddButtonState extends State<StatefulAddButton> {
  int _result = 1;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ElevatedButton(
          onPressed: () {
            final result = add(a: _result, b: 1);
            setState(() {
              _result = result;
            });
          },
          child: const Text('Call Rust `add(2, 3)`'),
        ),
        Text('Result: $_result'),
      ],
    );
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('flutter_rust_bridge quickstart 4')),
        body: Column(
          children: [
            // button to call Rust `add(2, 3)`
            const SizedBox(height: 20),
            StatefulAddButton(),
            const SizedBox(height: 20),
            Center(
              child: Text(
                'Action: Call Rust `greet("Tom")`\nResult: `${greet(name: "Tom")}`',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
