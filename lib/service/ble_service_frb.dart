import 'dart:async';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

import 'ble_models.dart';
import 'ble_service.dart';

/// 基于 [FlutterReactiveBle] 的 [BleService] 实现。
class BleServiceFrb implements BleService {
  // ── 适配器状态 ──────────────────────────────────────────────────────────

  final FlutterReactiveBle _ble = FlutterReactiveBle();

  @override
  BleAdapterState get currentAdapterState =>
      _mapAdapterState(_ble.status);

  @override
  Stream<BleAdapterState> get adapterStateStream =>
      _ble.statusStream.map(_mapAdapterState);

  @override
  Future<BleAdapterState> waitForAdapterState({
    Duration timeout = const Duration(seconds: 4),
  }) async {
    try {
      final state = await _ble.statusStream
          .where((s) => s != BleStatus.unknown)
          .first
          .timeout(timeout);
      return _mapAdapterState(state);
    } catch (_) {
      return currentAdapterState;
    }
  }

  @override
  Future<void> turnOnBluetooth({int timeoutSeconds = 60}) async {
    throw UnsupportedError('FRB 不支持主动开启蓝牙，请引导用户在系统设置中手动开启');
  }

  // ── 扫描 ────────────────────────────────────────────────────────────────

  // 字段
  StreamController<List<BleScanResult>>? _scanController;
  StreamSubscription? _scanSub;
  final List<BleScanResult> _scanBuffer = [];
  @override
  Stream<List<BleScanResult>> get scanResultsStream {
    // 如果还没开始扫描，返回一个空的 stream 等着
    _scanController ??= StreamController<List<BleScanResult>>.broadcast();
    return _scanController!.stream;
  }

  @override
  Future<void> startScan({
    List<String>? withNames,
    Duration? timeout,
    bool continuousUpdates = false,
  }) async {
    _scanController ??= StreamController<List<BleScanResult>>.broadcast();
    _scanBuffer.clear();

    _scanSub = _ble.scanForDevices(
      withServices: [],                    // 不按 service UUID 过滤
      scanMode: ScanMode.lowLatency,
    ).listen((device) {
      // FRB 每次推一个设备，我们手动累积成列表（模拟 FBP 的行为）
      final result = _mapScanResult(device);
      // 按名称过滤（FRB 没有 withNames 参数，需要手动过滤）
      if (withNames != null && withNames.isNotEmpty) {
        if (!withNames.contains(result.advertisedName)) return;
      }

      // 去重：已存在则更新，不存在则添加
      final idx = _scanBuffer.indexWhere((e) => e.device.id == result.device.id);
      if (idx >= 0) {
        _scanBuffer[idx] = result;
      } else {
        _scanBuffer.add(result);
      }
      _scanController!.add(List.from(_scanBuffer));
    });
    // 超时自动停止
    if (timeout != null) {
      Future.delayed(timeout, () => stopScan());
    }
  }

  @override
  Future<void> stopScan() async {
    await _scanSub?.cancel();
    _scanSub = null;
  }

  // ── 连接管理 ─────────────────────────────────────────────────────────────

  // 存储每个设备的连接订阅
  final Map<String, StreamSubscription> _connectionSubs = {};
  // 存储每个设备的连接设备
  final Map<String, BleDevice> _connectedDevices = {};

  @override
  Future<void> connect(
    BleDevice device, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    if (_connectionSubs.containsKey(device.id)) {
      return; // 已经在连接/已连接，直接返回
    }

    final completer = Completer<void>();

    final sub =  _ble.connectToDevice(
      id: device.id,
      connectionTimeout: timeout
    ).listen((ConnectionStateUpdate update) {
      if (update.connectionState == DeviceConnectionState.connected) {
        _connectedDevices[device.id] = device;
        if (!completer.isCompleted) completer.complete();
      } else if (update.connectionState == DeviceConnectionState.disconnected) {
        if (!completer.isCompleted) {
          completer.completeError(StateError('连接失败或已断开'));
        }
      }
    },onError: (e) {
      if (!completer.isCompleted) completer.completeError(e);
    });

    _connectionSubs[device.id] = sub;
    return completer.future;
  }

  @override
  Future<void> disconnect(BleDevice device) async {
    await _connectionSubs[device.id]?.cancel();
    _connectionSubs.remove(device.id);
    _connectedDevices.remove(device.id);
  }

  @override
  Future<void> clearGattCache(BleDevice device) async {
    await _ble.clearGattCache(device.id);
  }

  @override
  List<BleDevice> get connectedDevices =>
      _connectedDevices.values.toList();

  @override
  Future<List<BleDevice>> getSystemDevices(List<String> serviceUuids) async {
    // FRB 不支持查询系统级缓存设备，
    // 配网清理逻辑会跳过这些设备，影响不大。
    return [];
  }

  // ── GATT 服务发现 ────────────────────────────────────────────────────────

  @override
  Future<List<BleServiceInfo>> discoverServices(BleDevice device) async {
    final services = await _ble.getDiscoveredServices(device.id);
    return services.map((s) =>_mapService(s, device.id)).toList();
  }

  // ── 特征值操作 ──────────────────────────────────────────────────────────

  @override
  Future<void> setNotifyValue(BleCharacteristic characteristic, bool enabled) async {
    // FRB 在 subscribeToCharacteristic 时自动开启 notify，无需手动操作。
    // 取消 notify 则通过取消 Stream 订阅实现。
  }

  @override
  Stream<List<int>> characteristicValueStream(BleCharacteristic characteristic) {
    return _ble.subscribeToCharacteristic(characteristic.nativeRef);
  }

  @override
  Future<void> writeCharacteristic(
    BleCharacteristic characteristic,
    List<int> value, {
    bool withoutResponse = false,
  }) async {
    if (withoutResponse) {
      await _ble.writeCharacteristicWithoutResponse(characteristic.nativeRef, value: value);
    } else {
      await _ble.writeCharacteristicWithResponse(characteristic.nativeRef, value: value);
    }
  }

  // ── WiFi 配网（FRB 不支持） ──────────────────────────────────────────────

  @override
  Stream<BleProvisionEvent> get provisionEventStream =>
      throw UnsupportedError('BleServiceFrb 不支持配网');

  @override
  Future<void> requestDeviceWifiScan() =>
      throw UnsupportedError('BleServiceFrb 不支持 WiFi 扫描');

  @override
  Future<void> configProvision({String? ssid, String? password}) =>
      throw UnsupportedError('BleServiceFrb 不支持配网');

  @override
  Future<void> requestDeviceStatus() =>
      throw UnsupportedError('BleServiceFrb 不支持设备状态查询');

  @override
  Future<void> sendCustomData({String? data}) =>
      throw UnsupportedError('BleServiceFrb 不支持自定义数据');

  // ═══════════════════════════════════════════════════════════════════════════
  //  内部映射工具
  // ═══════════════════════════════════════════════════════════════════════════

  static BleAdapterState _mapAdapterState(BleStatus s) => switch (s) {
    BleStatus.ready => BleAdapterState.on,
    BleStatus.poweredOff => BleAdapterState.off,
    BleStatus.unauthorized => BleAdapterState.unauthorized,
    _ => BleAdapterState.unknown,
  };

  static BleDevice _mapDevice(DiscoveredDevice d) => BleDevice(
        id: d.id,
        name: d.name,
        nativeRef: d,
      );

  static BleScanResult _mapScanResult(DiscoveredDevice r) {
    final advName = r.name.isNotEmpty ? r.name : r.id;
    return BleScanResult(
      device: _mapDevice(r),
      advertisedName: advName,
    );
  }

  static BleServiceInfo _mapService(Service s, String deviceId) => BleServiceInfo(
        uuid: s.id.toString(),
        characteristics: s.characteristics.map((c) => _mapCharacteristic(c, s, deviceId)).toList(),
      );

  static BleCharacteristic _mapCharacteristic(Characteristic c, Service s, String deviceId) =>
      BleCharacteristic(
        uuid: c.id.toString(),
        serviceUuid: s.id.toString(),
        canNotify: c.isNotifiable,
        canIndicate: c.isIndicatable,
        canWrite: c.isWritableWithResponse,
        canWriteWithoutResponse: c.isWritableWithoutResponse,
        nativeRef: QualifiedCharacteristic(
          characteristicId: c.id,
          serviceId: s.id,
          deviceId: deviceId,
        ),
      );
}
