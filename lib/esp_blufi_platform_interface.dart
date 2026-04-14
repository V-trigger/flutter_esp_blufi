import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'esp_blufi_event.dart';
import 'esp_blufi_method_channel.dart';

/// ESP BluFi 插件的平台接口抽象。
///
/// 定义了所有平台实现必须提供的方法签名。
/// 默认实现为 [MethodChannelEspBlufi]（基于 MethodChannel + EventChannel）。
abstract class EspBlufiPlatform extends PlatformInterface {
  EspBlufiPlatform() : super(token: _token);

  static final Object _token = Object();

  static EspBlufiPlatform _instance = MethodChannelEspBlufi.instance;

  /// 当前平台实现的单例。
  static EspBlufiPlatform get instance => _instance;

  /// 替换平台实现（用于测试或自定义实现）。
  static set instance(EspBlufiPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  /// 原生层推送的事件流，子类必须实现。
  Stream<BlufiEvent> get eventStream;

  /// 获取平台版本号。
  Future<String?> getPlatformVersion() {
    throw UnimplementedError('getPlatformVersion() has not been implemented.');
  }

  /// 开始 BLE 扫描，[filterString] 按设备名过滤。
  Future<void> scanDeviceInfo({String? filterString}) {
    throw UnimplementedError('scanDeviceInfo() has not been implemented.');
  }

  /// 停止 BLE 扫描。
  Future<void> stopScan() {
    throw UnimplementedError('stopScan() has not been implemented.');
  }

  /// 连接指定 BLE 外设。
  Future<void> connectPeripheral({String? peripheralAddress}) {
    throw UnimplementedError('connectPeripheral() has not been implemented.');
  }

  /// 请求断开 BLE 连接。
  Future<void> requestCloseConnection() {
    throw UnimplementedError(
        'requestCloseConnection() has not been implemented.');
  }

  /// 请求设备扫描附近 WiFi。
  Future<void> requestDeviceWifiScan() {
    throw UnimplementedError(
        'requestDeviceWifiScan() has not been implemented.');
  }

  /// 下发 WiFi 配网凭证。
  Future<void> configProvision({String? ssid, String? password}) {
    throw UnimplementedError('configProvision() has not been implemented.');
  }

  /// 获取已配对设备列表。
  Future<void> getAllPairedDevice() {
    throw UnimplementedError('getAllPairedDevice() has not been implemented.');
  }

  /// 查询设备当前状态。
  Future<void> requestDeviceStatus() {
    throw UnimplementedError('requestDeviceStatus() has not been implemented.');
  }

  /// 发送自定义数据。
  Future<void> sendCustomData({String? data}) {
    throw UnimplementedError('sendCustomData() has not been implemented.');
  }
}
