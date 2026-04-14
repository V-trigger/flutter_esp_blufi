import 'esp_blufi_event.dart';
import 'esp_blufi_platform_interface.dart';

export 'esp_blufi_event.dart';

/// ESP BluFi 插件的公开 API。
///
/// 通过 [eventStream] 监听原生层推送的所有事件（类型安全的 sealed class），
/// 通过各方法向原生层发起指令。
class EspBlufi {
  static EspBlufiPlatform get _platform => EspBlufiPlatform.instance;

  /// 原生 BluFi 层推送的所有事件流（broadcast stream）。
  ///
  /// 事件类型见 [BlufiEvent] 及其子类，可用 pattern matching 分发处理。
  Stream<BlufiEvent> get eventStream => _platform.eventStream;

  /// 仅 BLE 扫描结果事件的过滤流。
  Stream<BleScanResultEvent> get scanResults => eventStream
      .where((e) => e is BleScanResultEvent)
      .cast<BleScanResultEvent>();

  /// 仅设备 WiFi 扫描结果事件的过滤流。
  Stream<WifiScanResultEvent> get wifiScanResults => eventStream
      .where((e) => e is WifiScanResultEvent)
      .cast<WifiScanResultEvent>();

  /// 仅 BLE 连接状态变化事件的过滤流。
  Stream<ConnectionStateEvent> get connectionState => eventStream
      .where((e) => e is ConnectionStateEvent)
      .cast<ConnectionStateEvent>();

  /// 仅错误事件的过滤流。
  Stream<ErrorEvent> get errors =>
      eventStream.where((e) => e is ErrorEvent).cast<ErrorEvent>();

  /// 获取当前平台版本号（调试用）。
  Future<String?> getPlatformVersion() {
    return _platform.getPlatformVersion();
  }

  /// 开始 BLE 扫描。
  ///
  /// [filterString] 可选，按设备名子串过滤（原生层仅返回名称包含此字符串的设备）。
  /// 扫描结果通过 [scanResults] 流推送。
  Future<void> scanDeviceInfo({String? filterString}) {
    return _platform.scanDeviceInfo(filterString: filterString);
  }

  /// 停止 BLE 扫描。
  Future<void> stopScan() {
    return _platform.stopScan();
  }

  /// 连接指定 BLE 外设。
  ///
  /// [peripheralAddress] 为设备地址（Android: MAC, iOS: UUID）。
  /// 连接结果通过 [connectionState] 流推送，GATT 就绪通过 [GattPreparedEvent] 通知。
  Future<void> connectPeripheral({String? peripheralAddress}) {
    return _platform.connectPeripheral(peripheralAddress: peripheralAddress);
  }

  /// 请求断开当前 BLE 连接。
  Future<void> requestCloseConnection() {
    return _platform.requestCloseConnection();
  }

  /// 请求已连接的设备扫描附近 WiFi 网络。
  ///
  /// 扫描到的每个 WiFi 通过 [wifiScanResults] 流逐条推送。
  Future<void> requestDeviceWifiScan() {
    return _platform.requestDeviceWifiScan();
  }

  /// 向设备下发 WiFi 配网凭证。
  ///
  /// 下发结果通过 [ConfigureResultEvent] 推送，
  /// 设备连接 WiFi 的结果通过 [DeviceWifiConnectEvent] 推送。
  Future<void> configProvision({String? ssid, String? password}) {
    return _platform.configProvision(ssid: ssid, password: password);
  }

  /// 获取系统已配对的蓝牙设备列表（仅 Android 有效）。
  ///
  /// 结果通过 [PairedDeviceEvent] 逐条推送。
  Future<void> getAllPairedDevice() {
    return _platform.getAllPairedDevice();
  }

  /// 查询设备当前状态（WiFi 连接情况等）。
  ///
  /// 结果通过 [DeviceStatusEvent] 和 [DeviceWifiConnectEvent] 推送。
  Future<void> requestDeviceStatus() {
    return _platform.requestDeviceStatus();
  }

  /// 向设备发送自定义数据。
  ///
  /// 发送结果通过 [PostCustomDataEvent] 推送，
  /// 设备回复的数据通过 [ReceiveCustomDataEvent] 推送。
  Future<void> sendCustomData({String? data}) {
    return _platform.sendCustomData(data: data);
  }
}
