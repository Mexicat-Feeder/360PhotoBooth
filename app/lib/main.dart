import 'package:flutter/material.dart';

import 'ble/booth_controller.dart';
import 'ble/fake_booth_controller.dart';
import 'ble/real_booth_controller.dart';
import 'screens/booth_test_screen.dart';

/// Set to true to use the simulated booth (Android emulator / pure-UI work,
/// where there's no Bluetooth radio). false = real BLE (Linux desktop, phone).
const bool kUseFakeBooth = false;

void main() {
  final BoothController controller =
      kUseFakeBooth ? FakeBoothController() : RealBoothController();
  // Mirror the activity log to stdout so it shows up in the console/logs too.
  controller.log.listen((m) => print('[booth] $m')); // ignore: avoid_print
  controller.stateStream.listen((s) => print('[booth] state: ${s.name}')); // ignore: avoid_print
  runApp(BoothApp(controller: controller));
}

class BoothApp extends StatelessWidget {
  const BoothApp({super.key, required this.controller});

  final BoothController controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '360 Booth',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: BoothTestScreen(controller: controller),
    );
  }
}
