sealed class BlufiEvent {
  const BlufiEvent();

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

  static int _toInt(dynamic v) {
    if (v is int) return v;
    if (v is String) return int.tryParse(v) ?? 0;
    if (v is double) return v.toInt();
    return 0;
  }
}

class BleScanResultEvent extends BlufiEvent {
  final String address;
  final String name;
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

class StopScanEvent extends BlufiEvent {
  const StopScanEvent();

  @override
  String toString() => 'StopScanEvent()';
}

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

class GattPreparedEvent extends BlufiEvent {
  final bool success;
  final String address;

  const GattPreparedEvent({required this.success, required this.address});

  @override
  String toString() => 'GattPreparedEvent(success: $success)';
}

class NegotiateSecurityEvent extends BlufiEvent {
  final bool success;
  final String address;

  const NegotiateSecurityEvent({required this.success, required this.address});

  @override
  String toString() => 'NegotiateSecurityEvent(success: $success)';
}

class ConfigureResultEvent extends BlufiEvent {
  final bool success;
  final String address;

  const ConfigureResultEvent({required this.success, required this.address});

  @override
  String toString() => 'ConfigureResultEvent(success: $success)';
}

class DeviceStatusEvent extends BlufiEvent {
  final bool success;
  final String address;

  const DeviceStatusEvent({required this.success, required this.address});

  @override
  String toString() => 'DeviceStatusEvent(success: $success)';
}

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

class PostCustomDataEvent extends BlufiEvent {
  final bool success;
  final String address;

  const PostCustomDataEvent({required this.success, required this.address});

  @override
  String toString() => 'PostCustomDataEvent(success: $success)';
}

class ReceiveCustomDataEvent extends BlufiEvent {
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

class PairedDeviceEvent extends BlufiEvent {
  final String name;
  final String deviceAddress;

  const PairedDeviceEvent({required this.name, required this.deviceAddress});

  @override
  String toString() =>
      'PairedDeviceEvent(name: $name, address: $deviceAddress)';
}

class ErrorEvent extends BlufiEvent {
  final int code;
  final String address;
  final String? message;

  const ErrorEvent({required this.code, required this.address, this.message});

  @override
  String toString() => 'ErrorEvent(code: $code, message: $message)';
}

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
