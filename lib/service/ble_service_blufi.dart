import 'dart:async';

import '../esp_blufi.dart';
import 'ble_models.dart';
import 'ble_service.dart';

/// 基于 [EspBlufi] 插件的 [BleService] 实现。
///
/// BluFi 协议内部管理 GATT 连接和加密，因此底层 GATT 级方法
/// （`discoverServices`、`setNotifyValue`、`writeCharacteristic` 等）
/// 不适用，会抛出 [UnsupportedError]。
///
/// 高层配网方法（WiFi 扫描、下发凭证、自定义数据）则完整支持。
class BleServiceBlufi implements BleService {
  final EspBlufi _blufi = EspBlufi();

  final _connectedDevices = <BleDevice>[];

  late final Stream<BlufiEvent> _sharedEventStream =
      _blufi.eventStream.asBroadcastStream();

  // ── 适配器状态 ──────────────────────────────────────────────────────────

  @override
  BleAdapterState get currentAdapterState => BleAdapterState.unknown;

  @override
  Stream<BleAdapterState> get adapterStateStream => const Stream.empty();

  @override
  Future<BleAdapterState> waitForAdapterState({
    Duration timeout = const Duration(seconds: 4),
  }) async =>
      BleAdapterState.unknown;

  @override
  Future<void> turnOnBluetooth({int timeoutSeconds = 60}) async {}

  // ── 扫描 ────────────────────────────────────────────────────────────────

  final _scanResultsController =
      StreamController<List<BleScanResult>>.broadcast();
  StreamSubscription<BleScanResultEvent>? _scanSubscription;
  final List<BleScanResult> _accumulatedResults = [];

  @override
  Stream<List<BleScanResult>> get scanResultsStream =>
      _scanResultsController.stream;

  @override
  Future<void> startScan({
    List<String>? withNames,
    Duration? timeout,
    bool continuousUpdates = false,
  }) async {
    _accumulatedResults.clear();
    _scanSubscription?.cancel();

    _scanSubscription = _sharedEventStream
        .where((e) => e is BleScanResultEvent)
        .cast<BleScanResultEvent>()
        .listen((event) {
      final device = BleDevice(id: event.address, name: event.name);
      final result = BleScanResult(device: device, advertisedName: event.name);

      final existingIdx =
          _accumulatedResults.indexWhere((r) => r.device.id == device.id);
      if (existingIdx >= 0) {
        _accumulatedResults[existingIdx] = result;
      } else {
        _accumulatedResults.add(result);
      }
      _scanResultsController.add(List.unmodifiable(_accumulatedResults));
    });

    await _blufi.scanDeviceInfo(
      filterString: withNames?.firstOrNull,
    );

    if (timeout != null) {
      Future.delayed(timeout, stopScan);
    }
  }

  @override
  Future<void> stopScan() async {
    _scanSubscription?.cancel();
    _scanSubscription = null;
    await _blufi.stopScan();
  }

  // ── 连接管理 ─────────────────────────────────────────────────────────────

  @override
  Future<void> connect(
    BleDevice device, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    await _blufi.connectPeripheral(peripheralAddress: device.id);

    final event = await _sharedEventStream
        .where((e) =>
            e is ConnectionStateEvent ||
            e is GattPreparedEvent ||
            e is ErrorEvent)
        .first
        .timeout(timeout);

    if (event is ErrorEvent) {
      throw Exception('连接失败: ${event.message ?? "code ${event.code}"}');
    }
    if (event is ConnectionStateEvent && !event.connected) {
      throw Exception('连接失败: 设备断开');
    }

    if (!_connectedDevices.any((d) => d.id == device.id)) {
      _connectedDevices.add(device);
    }
  }

  @override
  Future<void> disconnect(BleDevice device) async {
    await _blufi.requestCloseConnection();
    _connectedDevices.removeWhere((d) => d.id == device.id);
  }

  @override
  Future<void> clearGattCache(BleDevice device) async {}

  @override
  List<BleDevice> get connectedDevices => List.unmodifiable(_connectedDevices);

  @override
  Future<List<BleDevice>> getSystemDevices(List<String> serviceUuids) async =>
      const [];

  // ── GATT 服务发现（BluFi 内部处理，不对外暴露） ──────────────────────────

  @override
  Future<List<BleServiceInfo>> discoverServices(BleDevice device) =>
      throw UnsupportedError('BluFi 协议内部管理 GATT，不支持手动服务发现');

  // ── 特征值操作（BluFi 内部处理，不对外暴露） ────────────────────────────

  @override
  Future<void> setNotifyValue(
          BleCharacteristic characteristic, bool enabled) =>
      throw UnsupportedError('BluFi 协议内部管理 GATT，不支持手动特征值操作');

  @override
  Stream<List<int>> characteristicValueStream(
          BleCharacteristic characteristic) =>
      throw UnsupportedError('BluFi 协议内部管理 GATT，不支持手动特征值操作');

  @override
  Future<void> writeCharacteristic(
    BleCharacteristic characteristic,
    List<int> value, {
    bool withoutResponse = false,
  }) =>
      throw UnsupportedError('BluFi 协议内部管理 GATT，不支持手动特征值操作');

  // ── WiFi 配网 ──────────────────────────────────────────────────────────

  @override
  Stream<BleProvisionEvent> get provisionEventStream =>
      _sharedEventStream.expand<BleProvisionEvent>((event) sync* {
        switch (event) {
          case WifiScanResultEvent(:final ssid, :final rssi, :final address):
            yield BleWifiScanResultEvent(
              network: BleWifiNetwork(ssid: ssid, rssi: rssi),
              address: address,
            );
          case ConfigureResultEvent(:final success, :final address):
            yield BleProvisionResultEvent(success: success, address: address);
          case DeviceStatusEvent(:final success, :final address):
            yield BleDeviceStatusEvent(wifiConnected: success, address: address);
          case DeviceWifiConnectEvent(:final connected, :final address):
            yield BleDeviceStatusEvent(
                wifiConnected: connected, address: address);
          case GattPreparedEvent(:final success, :final address):
            yield BleGattPreparedEvent(success: success, address: address);
          case NegotiateSecurityEvent(:final success, :final address):
            yield BleNegotiateSecurityEvent(
                success: success, address: address);
          case PostCustomDataEvent(:final success, :final address):
            yield BleCustomDataEvent(
              data: '',
              isReceived: false,
              success: success,
              address: address,
            );
          case ReceiveCustomDataEvent(
              :final data,
              :final success,
              :final address
            ):
            yield BleCustomDataEvent(
              data: data,
              isReceived: true,
              success: success,
              address: address,
            );
          case ErrorEvent(:final code, :final message, :final address):
            yield BleProvisionErrorEvent(
              code: code,
              message: message,
              address: address,
            );
          default:
            break;
        }
      });

  @override
  Future<void> requestDeviceWifiScan() => _blufi.requestDeviceWifiScan();

  @override
  Future<void> configProvision({String? ssid, String? password}) =>
      _blufi.configProvision(ssid: ssid, password: password);

  @override
  Future<void> requestDeviceStatus() => _blufi.requestDeviceStatus();

  @override
  Future<void> sendCustomData({String? data}) =>
      _blufi.sendCustomData(data: data);
}
