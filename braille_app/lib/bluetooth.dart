import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';

import 'crash_log.dart';

class BrailleDevice extends ChangeNotifier {
  final FlutterReactiveBle _ble = FlutterReactiveBle();

  static final _esp32ServiceUUID = Uuid.parse(
    '4fafc201-1fb5-459e-8fcc-c5c9c331914b'
  );

  static final _inputUUID = Uuid.parse(
    'beb5483e-36e1-4688-b7f5-ea07361b26a8'
  );

  static final _outputUUID = Uuid.parse(
    'a0c14c2b-ce60-4e5e-9a25-946aa608cb37'
  );

  String? _deviceId;
  bool _isConnected = false;
  bool get isConnected => _isConnected;

  StreamSubscription<BleStatus>? _statusSub;
  StreamSubscription<DiscoveredDevice>? _scanSubscription;
  StreamSubscription<ConnectionStateUpdate>? _connectionSubscription;
  StreamSubscription<List<int>>? _inputSubscription;

  final _pressController = StreamController<int>.broadcast();
  Stream<int> get onPress => _pressController.stream;

  Future<void> scanForBrailleDevice() async {
    final permissions = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
    ].request();

    if (!permissions[Permission.bluetoothScan]!.isGranted ||
        !permissions[Permission.bluetoothConnect]!.isGranted) {
      debugPrint("bluetooth permissions not granted");
      return;
    }

    if (_ble.status != BleStatus.ready) {
      debugPrint("bluetooth status: ${_ble.status}");
      return;
    }

    debugPrint("looking for BrailleLearner");

    await _scanSubscription?.cancel();

    _scanSubscription = _ble.scanForDevices(
      withServices: [_esp32ServiceUUID],
      scanMode: ScanMode.lowLatency,
    ).listen((device) {
      debugPrint("found device called ${device.name}");

      if (device.name == "BrailleLearner") {
        _scanSubscription?.cancel();
        _deviceId = device.id;

        debugPrint("BrailleLearner found");
        connectToBrailleDevice();
      }
    }, onError: (error, stack) {
      CrashLog.error("BLE", "scanning error: $error", stack);
    });
  }

  void connectToBrailleDevice() {
    if (_deviceId == null) return;

    debugPrint("connecting...");

    _connectionSubscription?.cancel();

    _connectionSubscription = _ble.connectToDevice(
      id: _deviceId!,
      servicesWithCharacteristicsToDiscover: {
        _esp32ServiceUUID: [_inputUUID, _outputUUID],
      },

      connectionTimeout: const Duration(seconds: 10),
    ).listen((connectionState) {
      CrashLog.log(
        "BLE",
        "Connection state: ${connectionState.connectionState}"
        "${connectionState.failure != null ? " (reason: ${connectionState.failure})" : ""}",
      );

      if (connectionState.connectionState ==
        DeviceConnectionState.connected) {
        _isConnected = true;
        notifyListeners();
        listenForBraille();
      }

      if (connectionState.connectionState ==
        DeviceConnectionState.disconnected) {
        _inputSubscription?.cancel();
        _inputSubscription = null;
        _isConnected = false;
        notifyListeners();
      }
    }, onError: (error, stack) {
      CrashLog.error("BLE", "Connection error: $error", stack);
    });
  }

  void listenForBraille() {
    if (_deviceId == null) return;

    _inputSubscription?.cancel();

    _inputSubscription = _ble.subscribeToCharacteristic(
      QualifiedCharacteristic(
        serviceId: _esp32ServiceUUID,
        characteristicId: _inputUUID,
        deviceId: _deviceId!,
      ),
    ).listen((data) {
      if (data.length == 1) {
        int receivedInteger = data[0];
        CrashLog.log("BLE", "Received integer: $receivedInteger");
        _pressController.add(receivedInteger);
      }
    }, onError: (error, stack) {
      CrashLog.error("BLE", "Input subscription error: $error", stack);
    });
  }

  Future<void> sendBrailleResult(bool isCorrect) async {
    final deviceId = _deviceId;
    if (deviceId == null || !isConnected) return;

    final characteristic = QualifiedCharacteristic(
      serviceId: _esp32ServiceUUID,
      characteristicId: _outputUUID,
      deviceId: deviceId,
    );

    int command = isCorrect ? 0x01 : 0x02;

    try {
      await _ble.writeCharacteristicWithResponse(
        characteristic,
        value: [command],
      );

      CrashLog.log("BLE", "Sent result: $isCorrect, $command");
    } catch (error, stack) {
      CrashLog.error("BLE", "Failed to send command: $error", stack);
    }
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    _scanSubscription?.cancel();
    _connectionSubscription?.cancel();
    _inputSubscription?.cancel();
    _pressController.close();
    super.dispose();
  }

  void start() {
    _statusSub?.cancel();
    _statusSub = _ble.statusStream.listen((status) {
      CrashLog.log("BLE", "BLE status: $status");
      if (status == BleStatus.ready) {
        scanForBrailleDevice();
      }
    });
  }
}