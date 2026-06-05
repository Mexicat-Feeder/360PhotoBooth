import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import 'backend/backend_client.dart';
import 'ble/booth_controller.dart';
import 'ble/fake_booth_controller.dart';
import 'ble/real_booth_controller.dart';
import 'camera/camera_service.dart';
import 'camera/real_camera_linux.dart';
import 'flow/flow_controller.dart';
import 'screens/booth_flow.dart';
import 'theme.dart';

/// true = simulated booth (Android emulator / no Bluetooth). false = real BLE.
const bool kUseFakeBooth = false;

/// Backend base URL. Linux/desktop dev -> localhost; Android emulator -> 10.0.2.2.
String backendBaseUrl() {
  const override = String.fromEnvironment('BOOTH_BACKEND');
  if (override.isNotEmpty) return override;
  if (Platform.isAndroid) return 'http://10.0.2.2:8500';
  return 'http://localhost:8500';
}

void main() {
  final BoothController booth =
      kUseFakeBooth ? FakeBoothController() : RealBoothController();
  // Linux desktop (this box) uses the real webcam via ffmpeg; emulator uses Fake.
  final CameraService camera =
      Platform.isLinux ? RealCameraLinux() : FakeCameraService();
  final backend = BackendClient(backendBaseUrl());

  // mirror booth log to stdout for debugging
  booth.log.listen((m) => print('[booth] $m')); // ignore: avoid_print

  final flow = FlowController(booth: booth, camera: camera, backend: backend);
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
