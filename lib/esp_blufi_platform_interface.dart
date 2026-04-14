import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'esp_blufi_event.dart';
import 'esp_blufi_method_channel.dart';

abstract class EspBlufiPlatform extends PlatformInterface {
  EspBlufiPlatform() : super(token: _token);

  static final Object _token = Object();

  static EspBlufiPlatform _instance = MethodChannelEspBlufi.instance;

  static EspBlufiPlatform get instance => _instance;

  static set instance(EspBlufiPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Stream<BlufiEvent> get eventStream;

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('getPlatformVersion() has not been implemented.');
  }

  Future<void> scanDeviceInfo({String? filterString}) {
    throw UnimplementedError('scanDeviceInfo() has not been implemented.');
  }

  Future<void> stopScan() {
    throw UnimplementedError('stopScan() has not been implemented.');
  }

  Future<void> connectPeripheral({String? peripheralAddress}) {
    throw UnimplementedError('connectPeripheral() has not been implemented.');
  }

  Future<void> requestCloseConnection() {
    throw UnimplementedError(
        'requestCloseConnection() has not been implemented.');
  }

  Future<void> requestDeviceWifiScan() {
    throw UnimplementedError(
        'requestDeviceWifiScan() has not been implemented.');
  }

  Future<void> configProvision({String? ssid, String? password}) {
    throw UnimplementedError('configProvision() has not been implemented.');
  }

  Future<void> getAllPairedDevice() {
    throw UnimplementedError('getAllPairedDevice() has not been implemented.');
  }

  Future<void> requestDeviceStatus() {
    throw UnimplementedError('requestDeviceStatus() has not been implemented.');
  }

  Future<void> sendCustomData({String? data}) {
    throw UnimplementedError('sendCustomData() has not been implemented.');
  }
}
