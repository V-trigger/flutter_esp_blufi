import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'ble_models.dart';
import 'ble_service.dart';

/// 基于 [FlutterBluePlus] 的 [BleService] 实现。
///
/// 如需切换到 flutter_reactive_ble 等其它库，
/// 只需新建一个 `BleServiceFrb` 并在启动时替换即可。
class BleServiceFbp implements BleService {
  // ── 适配器状态 ──────────────────────────────────────────────────────────

  @override
  BleAdapterState get currentAdapterState =>
      _mapAdapterState(FlutterBluePlus.adapterStateNow);

  @override
  Stream<BleAdapterState> get adapterStateStream =>
      FlutterBluePlus.adapterState.map(_mapAdapterState);

  @override
  Future<BleAdapterState> waitForAdapterState({
    Duration timeout = const Duration(seconds: 4),
  }) async {
    try {
      final state = await FlutterBluePlus.adapterState
          .where((s) => s != BluetoothAdapterState.unknown)
          .first
          .timeout(timeout);
      return _mapAdapterState(state);
    } catch (_) {
      return currentAdapterState;
    }
  }

  @override
  Future<void> turnOnBluetooth({int timeoutSeconds = 60}) async {
    await FlutterBluePlus.turnOn(timeout: timeoutSeconds);
    await FlutterBluePlus.adapterState
        .where((s) => s == BluetoothAdapterState.on)
        .first
        .timeout(const Duration(seconds: 8));
  }

  // ── 扫描 ────────────────────────────────────────────────────────────────

  @override
  Stream<List<BleScanResult>> get scanResultsStream =>
      FlutterBluePlus.scanResults.map(
        (list) => list.map(_mapScanResult).toList(),
      );

  @override
  Future<void> startScan({
    List<String>? withNames,
    Duration? timeout,
    bool continuousUpdates = false,
  }) async {
    await FlutterBluePlus.startScan(
      withNames: withNames ?? [],
      timeout: timeout ?? const Duration(seconds: 20),
      continuousUpdates: continuousUpdates,
    );
  }

  @override
  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
  }

  // ── 连接管理 ─────────────────────────────────────────────────────────────

  @override
  Future<void> connect(
    BleDevice device, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final native = _requireNativeDevice(device);
    await native.connect(license: License.free, timeout: timeout);
  }

  @override
  Future<void> disconnect(BleDevice device) async {
    final native = _requireNativeDevice(device);
    await native.disconnect();
  }

  @override
  Future<void> clearGattCache(BleDevice device) async {
    final native = _requireNativeDevice(device);
    await native.clearGattCache();
  }

  @override
  List<BleDevice> get connectedDevices =>
      FlutterBluePlus.connectedDevices.map(_mapDevice).toList();

  @override
  Future<List<BleDevice>> getSystemDevices(List<String> serviceUuids) async {
    final guids = serviceUuids.map((s) => Guid(s)).toList();
    final devices = await FlutterBluePlus.systemDevices(guids);
    return devices.map(_mapDevice).toList();
  }

  // ── GATT 服务发现 ────────────────────────────────────────────────────────

  @override
  Future<List<BleServiceInfo>> discoverServices(BleDevice device) async {
    final native = _requireNativeDevice(device);
    final services = await native.discoverServices();
    return services.map(_mapService).toList();
  }

  // ── 特征值操作 ──────────────────────────────────────────────────────────

  @override
  Future<void> setNotifyValue(BleCharacteristic characteristic, bool enabled) async {
    final native = _requireNativeCharacteristic(characteristic);
    await native.setNotifyValue(enabled);
  }

  @override
  Stream<List<int>> characteristicValueStream(BleCharacteristic characteristic) {
    final native = _requireNativeCharacteristic(characteristic);
    return native.lastValueStream;
  }

  @override
  Future<void> writeCharacteristic(
    BleCharacteristic characteristic,
    List<int> value, {
    bool withoutResponse = false,
  }) async {
    final native = _requireNativeCharacteristic(characteristic);
    await native.write(value, withoutResponse: withoutResponse);
  }

  // ── WiFi 配网（FBP 不支持） ──────────────────────────────────────────────

  @override
  Stream<BleProvisionEvent> get provisionEventStream =>
      throw UnsupportedError('BleServiceFbp 不支持配网');

  @override
  Future<void> requestDeviceWifiScan() =>
      throw UnsupportedError('BleServiceFbp 不支持 WiFi 扫描');

  @override
  Future<void> configProvision({String? ssid, String? password}) =>
      throw UnsupportedError('BleServiceFbp 不支持配网');

  @override
  Future<void> requestDeviceStatus() =>
      throw UnsupportedError('BleServiceFbp 不支持设备状态查询');

  @override
  Future<void> sendCustomData({String? data}) =>
      throw UnsupportedError('BleServiceFbp 不支持自定义数据');

  // ═══════════════════════════════════════════════════════════════════════════
  //  内部映射工具
  // ═══════════════════════════════════════════════════════════════════════════

  static BleAdapterState _mapAdapterState(BluetoothAdapterState s) => switch (s) {
        BluetoothAdapterState.on => BleAdapterState.on,
        BluetoothAdapterState.off => BleAdapterState.off,
        BluetoothAdapterState.unauthorized => BleAdapterState.unauthorized,
        BluetoothAdapterState.turningOn => BleAdapterState.turningOn,
        BluetoothAdapterState.turningOff => BleAdapterState.turningOff,
        _ => BleAdapterState.unknown,
      };

  static BleDevice _mapDevice(BluetoothDevice d) => BleDevice(
        id: d.remoteId.str,
        name: d.platformName,
        nativeRef: d,
      );

  static BleScanResult _mapScanResult(ScanResult r) {
    final advName = r.device.advName.isNotEmpty ? r.device.advName : r.device.platformName;
    return BleScanResult(
      device: _mapDevice(r.device),
      advertisedName: advName,
    );
  }

  static BleServiceInfo _mapService(BluetoothService s) => BleServiceInfo(
        uuid: s.uuid.str,
        characteristics: s.characteristics.map((c) => _mapCharacteristic(c, s.uuid.str)).toList(),
      );

  static BleCharacteristic _mapCharacteristic(BluetoothCharacteristic c, String serviceUuid) =>
      BleCharacteristic(
        uuid: c.uuid.str,
        serviceUuid: serviceUuid,
        canNotify: c.properties.notify,
        canIndicate: c.properties.indicate,
        canWrite: c.properties.write,
        canWriteWithoutResponse: c.properties.writeWithoutResponse,
        nativeRef: c,
      );

  // ── nativeRef 提取 ──

  static BluetoothDevice _requireNativeDevice(BleDevice device) {
    final ref = device.nativeRef;
    if (ref is BluetoothDevice) return ref;
    throw StateError('BleDevice.nativeRef 不是 BluetoothDevice，当前实现仅支持 FBP');
  }

  static BluetoothCharacteristic _requireNativeCharacteristic(BleCharacteristic c) {
    final ref = c.nativeRef;
    if (ref is BluetoothCharacteristic) return ref;
    throw StateError('BleCharacteristic.nativeRef 不是 BluetoothCharacteristic，当前实现仅支持 FBP');
  }
}
