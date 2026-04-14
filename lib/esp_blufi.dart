import 'esp_blufi_event.dart';
import 'esp_blufi_platform_interface.dart';

export 'esp_blufi_event.dart';

class EspBlufi {
  static EspBlufiPlatform get _platform => EspBlufiPlatform.instance;

  /// All events from the native BluFi layer as a broadcast stream.
  Stream<BlufiEvent> get eventStream => _platform.eventStream;

  /// Filtered stream of BLE scan results only.
  Stream<BleScanResultEvent> get scanResults => eventStream
      .where((e) => e is BleScanResultEvent)
      .cast<BleScanResultEvent>();

  /// Filtered stream of WiFi scan results from the device.
  Stream<WifiScanResultEvent> get wifiScanResults => eventStream
      .where((e) => e is WifiScanResultEvent)
      .cast<WifiScanResultEvent>();

  /// Filtered stream of BLE connection state changes.
  Stream<ConnectionStateEvent> get connectionState => eventStream
      .where((e) => e is ConnectionStateEvent)
      .cast<ConnectionStateEvent>();

  /// Filtered stream of error events.
  Stream<ErrorEvent> get errors =>
      eventStream.where((e) => e is ErrorEvent).cast<ErrorEvent>();

  Future<String?> getPlatformVersion() {
    return _platform.getPlatformVersion();
  }

  Future<void> scanDeviceInfo({String? filterString}) {
    return _platform.scanDeviceInfo(filterString: filterString);
  }

  Future<void> stopScan() {
    return _platform.stopScan();
  }

  Future<void> connectPeripheral({String? peripheralAddress}) {
    return _platform.connectPeripheral(peripheralAddress: peripheralAddress);
  }

  Future<void> requestCloseConnection() {
    return _platform.requestCloseConnection();
  }

  Future<void> requestDeviceWifiScan() {
    return _platform.requestDeviceWifiScan();
  }

  Future<void> configProvision({String? ssid, String? password}) {
    return _platform.configProvision(ssid: ssid, password: password);
  }

  Future<void> getAllPairedDevice() {
    return _platform.getAllPairedDevice();
  }

  Future<void> requestDeviceStatus() {
    return _platform.requestDeviceStatus();
  }

  Future<void> sendCustomData({String? data}) {
    return _platform.sendCustomData(data: data);
  }
}
