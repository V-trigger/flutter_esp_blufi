/// BluFi 事件基类（sealed class）。
///
/// 原生层通过 EventChannel 推送的所有事件都会被解析为 [BlufiEvent] 的具体子类。
/// 业务层使用 `switch (event)` + pattern matching 分发处理。
sealed class BlufiEvent {
  const BlufiEvent();

  /// 将原生层推送的 Map 数据解析为对应的事件子类。
  ///
  /// Map 结构：`{ 'key': 事件类型, 'value': 事件数据, 'address': 设备地址 }`
  factory BlufiEvent.fromMap(Map<dynamic, dynamic> map) {
    final key = map['key'] as String?;
    final value = map['value'];
    final address = map['address'] as String? ?? '';

    switch (key) {
      case 'ble_scan_result':
        final v = value as Map<dynamic, dynamic>;
        return BleScanResultEvent(
          address: v['address'] as String? ?? '',
          name: v['name'] as String? ?? '',
          rssi: _toInt(v['rssi']),
        );
      case 'wifi_scan_result':
        if (value is Map) {
          return WifiScanResultEvent(
            ssid: value['ssid'] as String? ?? '',
            rssi: _toInt(value['rssi']),
            address: value['address'] as String? ?? address,
          );
        }
        return ErrorEvent(code: -1, address: address, message: 'wifi scan failed');
      case 'stop_scan_ble':
        return const StopScanEvent();
      case 'peripheral_connected':
        return ConnectionStateEvent(connected: true, address: address);
      case 'peripheral_disconnected':
        return ConnectionStateEvent(connected: false, address: address);
      case 'gatt_prepared':
        return GattPreparedEvent(success: value == '1', address: address);
      case 'negotiate_security':
        return NegotiateSecurityEvent(success: value == '1', address: address);
      case 'configure_params':
        return ConfigureResultEvent(success: value == '1', address: address);
      case 'device_status':
        return DeviceStatusEvent(success: value == '1', address: address);
      case 'device_wifi_connect':
        return DeviceWifiConnectEvent(connected: value == '1', address: address);
      case 'device_version':
        return DeviceVersionEvent(
          version: value?.toString() ?? '',
          success: value != '0',
          address: address,
        );
      case 'post_custom_data':
        return PostCustomDataEvent(success: value == '1', address: address);
      case 'receive_custom_data':
        return ReceiveCustomDataEvent(
          data: value?.toString() ?? '',
          success: value != '0',
          address: address,
        );
      case 'paired_device':
        if (value is Map) {
          return PairedDeviceEvent(
            name: value['name'] as String? ?? '',
            deviceAddress: value['address'] as String? ?? '',
          );
        }
        return const PairedDeviceEvent(name: '', deviceAddress: '');
      case 'error':
        if (value is Map) {
          return ErrorEvent(
            code: _toInt(value['code']),
            address: value['address'] as String? ?? address,
            message: value['message'] as String?,
          );
        }
        return ErrorEvent(code: -1, address: address, message: value?.toString());
      default:
        return UnknownEvent(key: key ?? '', rawValue: value, address: address);
    }
  }

  /// 安全地将动态类型转为 int。
  static int _toInt(dynamic v) {
    if (v is int) return v;
    if (v is String) return int.tryParse(v) ?? 0;
    if (v is double) return v.toInt();
    return 0;
  }
}

/// BLE 扫描发现的设备。
class BleScanResultEvent extends BlufiEvent {
  /// 设备地址（Android: MAC, iOS: UUID）。
  final String address;

  /// 设备广播名称。
  final String name;

  /// 信号强度（负值，越接近 0 越强）。
  final int rssi;

  const BleScanResultEvent({
    required this.address,
    required this.name,
    required this.rssi,
  });

  @override
  String toString() =>
      'BleScanResultEvent(address: $address, name: $name, rssi: $rssi)';
}

/// 设备扫描到的一个 WiFi 网络。
class WifiScanResultEvent extends BlufiEvent {
  final String ssid;
  final int rssi;
  final String address;

  const WifiScanResultEvent({
    required this.ssid,
    required this.rssi,
    required this.address,
  });

  @override
  String toString() => 'WifiScanResultEvent(ssid: $ssid, rssi: $rssi)';
}

/// BLE 扫描已停止。
class StopScanEvent extends BlufiEvent {
  const StopScanEvent();

  @override
  String toString() => 'StopScanEvent()';
}

/// BLE 连接状态变化（连接 / 断开）。
class ConnectionStateEvent extends BlufiEvent {
  final bool connected;
  final String address;

  const ConnectionStateEvent({
    required this.connected,
    required this.address,
  });

  @override
  String toString() =>
      'ConnectionStateEvent(connected: $connected, address: $address)';
}

/// GATT 就绪事件（BluFi 协议握手完成，可以开始配网操作）。
class GattPreparedEvent extends BlufiEvent {
  final bool success;
  final String address;

  const GattPreparedEvent({required this.success, required this.address});

  @override
  String toString() => 'GattPreparedEvent(success: $success)';
}

/// DH 密钥协商结果。
class NegotiateSecurityEvent extends BlufiEvent {
  final bool success;
  final String address;

  const NegotiateSecurityEvent({required this.success, required this.address});

  @override
  String toString() => 'NegotiateSecurityEvent(success: $success)';
}

/// WiFi 配网参数下发结果。
class ConfigureResultEvent extends BlufiEvent {
  final bool success;
  final String address;

  const ConfigureResultEvent({required this.success, required this.address});

  @override
  String toString() => 'ConfigureResultEvent(success: $success)';
}

/// 设备状态查询结果。
class DeviceStatusEvent extends BlufiEvent {
  final bool success;
  final String address;

  const DeviceStatusEvent({required this.success, required this.address});

  @override
  String toString() => 'DeviceStatusEvent(success: $success)';
}

/// 设备 WiFi 连接状态（配网后设备是否成功连上路由器）。
class DeviceWifiConnectEvent extends BlufiEvent {
  final bool connected;
  final String address;

  const DeviceWifiConnectEvent({
    required this.connected,
    required this.address,
  });

  @override
  String toString() => 'DeviceWifiConnectEvent(connected: $connected)';
}

/// 设备固件版本信息。
class DeviceVersionEvent extends BlufiEvent {
  final String version;
  final bool success;
  final String address;

  const DeviceVersionEvent({
    required this.version,
    required this.success,
    required this.address,
  });

  @override
  String toString() => 'DeviceVersionEvent(version: $version)';
}

/// 自定义数据发送结果。
class PostCustomDataEvent extends BlufiEvent {
  final bool success;
  final String address;

  const PostCustomDataEvent({required this.success, required this.address});

  @override
  String toString() => 'PostCustomDataEvent(success: $success)';
}

/// 收到设备推送的自定义数据。
class ReceiveCustomDataEvent extends BlufiEvent {
  /// 设备发来的数据内容（UTF-8 字符串）。
  final String data;
  final bool success;
  final String address;

  const ReceiveCustomDataEvent({
    required this.data,
    required this.success,
    required this.address,
  });

  @override
  String toString() =>
      'ReceiveCustomDataEvent(data: $data, success: $success)';
}

/// 系统已配对的蓝牙设备（仅 Android）。
class PairedDeviceEvent extends BlufiEvent {
  final String name;
  final String deviceAddress;

  const PairedDeviceEvent({required this.name, required this.deviceAddress});

  @override
  String toString() =>
      'PairedDeviceEvent(name: $name, address: $deviceAddress)';
}

/// 原生层报告的错误。
class ErrorEvent extends BlufiEvent {
  final int code;
  final String address;
  final String? message;

  const ErrorEvent({required this.code, required this.address, this.message});

  @override
  String toString() => 'ErrorEvent(code: $code, message: $message)';
}

/// 未识别的事件（兜底，用于前向兼容）。
class UnknownEvent extends BlufiEvent {
  final String key;
  final dynamic rawValue;
  final String address;

  const UnknownEvent({
    required this.key,
    this.rawValue,
    required this.address,
  });

  @override
  String toString() => 'UnknownEvent(key: $key, value: $rawValue)';
}
