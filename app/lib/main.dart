import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import 'backend/backend_client.dart';
import 'ble/booth_controller.dart';
import 'ble/fake_booth_controller.dart';
import 'ble/real_booth_controller.dart';
import 'camera/camera_service.dart';
import 'camera/real_camera_android.dart';
import 'camera/real_camera_linux.dart';
import 'camera/real_camera_windows.dart';
import 'flow/flow_controller.dart';
import 'screens/booth_flow.dart';
import 'theme.dart';

/// true = simulated booth (Android emulator / no Bluetooth). false = real BLE.
const bool kUseFakeBooth = false;
const String kWorkflow = String.fromEnvironment(
  'BOOTH_WORKFLOW',
  defaultValue: 'vangogh_vid2vid',
);

/// Backend base URL. Linux/desktop dev -> localhost; Android emulator -> 10.0.2.2.
String backendBaseUrl() {
  const override = String.fromEnvironment('BOOTH_BACKEND');
  if (override.isNotEmpty) return override;
  if (Platform.isAndroid) return 'http://192.168.50.166:8000'; // use env
  return 'http://localhost:8000';
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  final BoothController booth = kUseFakeBooth
      ? FakeBoothController()
      : RealBoothController();
  final CameraService camera = Platform.isAndroid
      ? RealCameraAndroid()
      : Platform.isLinux
      ? RealCameraLinux()
      : Platform.isWindows
      ? RealCameraWindows()
      : FakeCameraService();
  final backend = BackendClient(backendBaseUrl());

  // mirror booth log to stdout for debugging
  booth.log.listen((m) => print('[booth] $m')); // ignore: avoid_print

  final flow = FlowController(
    booth: booth,
    camera: camera,
    backend: backend,
    workflow: kWorkflow,
  );
  flow.init();

  runApp(BoothApp(flow: flow));
}

class BoothApp extends StatelessWidget {
  const BoothApp({super.key, required this.flow});
  final FlowController flow;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '360 Booth',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: BoothFlow(flow: flow),
    );
  }
}
