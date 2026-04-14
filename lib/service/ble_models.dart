/// 库无关的 BLE 抽象模型。
///
/// 上层业务只依赖这些类型，不直接依赖任何具体 BLE 库。
library;

// ─────────────────────────────────────────────────────────────────────────────
//  适配器状态
// ─────────────────────────────────────────────────────────────────────────────

enum BleAdapterState { unknown, on, off, unauthorized, turningOn, turningOff }

// ─────────────────────────────────────────────────────────────────────────────
//  设备
// ─────────────────────────────────────────────────────────────────────────────

class BleDevice {
  /// 平台标识（iOS: UUID, Android: MAC）。
  final String id;

  /// 设备名称（platformName / advName）。
  final String name;

  /// 底层库持有的原始设备对象，仅供 [BleService] 实现内部使用。
  final dynamic nativeRef;

  const BleDevice({required this.id, required this.name, this.nativeRef});

  @override
  String toString() => 'BleDevice($name, $id)';
}

// ─────────────────────────────────────────────────────────────────────────────
//  扫描结果
// ─────────────────────────────────────────────────────────────────────────────

class BleScanResult {
  final BleDevice device;

  /// 广播包中的设备名称（可能与 [BleDevice.name] 不同）。
  final String advertisedName;

  const BleScanResult({required this.device, required this.advertisedName});
}

// ─────────────────────────────────────────────────────────────────────────────
//  GATT 服务 & 特征值
// ─────────────────────────────────────────────────────────────────────────────

class BleServiceInfo {
  final String uuid;
  final List<BleCharacteristic> characteristics;

  const BleServiceInfo({required this.uuid, required this.characteristics});
}

class BleCharacteristic {
  final String uuid;
  final String serviceUuid;
  final bool canNotify;
  final bool canIndicate;
  final bool canWrite;
  final bool canWriteWithoutResponse;

  /// 底层库持有的原始特征值对象，仅供 [BleService] 实现内部使用。
  final dynamic nativeRef;

  const BleCharacteristic({
    required this.uuid,
    required this.serviceUuid,
    this.canNotify = false,
    this.canIndicate = false,
    this.canWrite = false,
    this.canWriteWithoutResponse = false,
    this.nativeRef,
  });

  bool get supportsNotifyOrIndicate => canNotify || canIndicate;
  bool get supportsWrite => canWrite || canWriteWithoutResponse;

  @override
  String toString() => 'BleCharacteristic($uuid)';
}

// ─────────────────────────────────────────────────────────────────────────────
//  WiFi 配网相关模型（仅 BluFi 等支持配网的实现使用）
// ─────────────────────────────────────────────────────────────────────────────

class BleWifiNetwork {
  final String ssid;
  final int rssi;

  const BleWifiNetwork({required this.ssid, required this.rssi});

  @override
  String toString() => 'BleWifiNetwork($ssid, rssi: $rssi)';
}

sealed class BleProvisionEvent {
  const BleProvisionEvent();
}

/// 设备扫描到的一个 WiFi 网络。
class BleWifiScanResultEvent extends BleProvisionEvent {
  final BleWifiNetwork network;
  final String address;

  const BleWifiScanResultEvent({required this.network, required this.address});

  @override
  String toString() =>
      'BleWifiScanResultEvent(${network.ssid}, rssi: ${network.rssi})';
}

/// WiFi 配网结果。
class BleProvisionResultEvent extends BleProvisionEvent {
  final bool success;
  final String address;

  const BleProvisionResultEvent(
      {required this.success, required this.address});

  @override
  String toString() => 'BleProvisionResultEvent(success: $success)';
}

/// 设备状态查询结果。
class BleDeviceStatusEvent extends BleProvisionEvent {
  final bool wifiConnected;
  final String address;

  const BleDeviceStatusEvent(
      {required this.wifiConnected, required this.address});

  @override
  String toString() => 'BleDeviceStatusEvent(wifiConnected: $wifiConnected)';
}

/// 自定义数据收发事件。
class BleCustomDataEvent extends BleProvisionEvent {
  final String data;

  /// true = 收到设备发来的数据，false = 本端发送结果。
  final bool isReceived;
  final bool success;
  final String address;

  const BleCustomDataEvent({
    required this.data,
    required this.isReceived,
    required this.success,
    required this.address,
  });

  @override
  String toString() =>
      'BleCustomDataEvent(isReceived: $isReceived, success: $success, data: $data)';
}

/// GATT 就绪事件（BluFi 协议握手完成后触发）。
class BleGattPreparedEvent extends BleProvisionEvent {
  final bool success;
  final String address;

  const BleGattPreparedEvent({required this.success, required this.address});

  @override
  String toString() => 'BleGattPreparedEvent(success: $success)';
}

/// 安全协商结果。
class BleNegotiateSecurityEvent extends BleProvisionEvent {
  final bool success;
  final String address;

  const BleNegotiateSecurityEvent(
      {required this.success, required this.address});

  @override
  String toString() => 'BleNegotiateSecurityEvent(success: $success)';
}

/// 配网流程中的错误。
class BleProvisionErrorEvent extends BleProvisionEvent {
  final int code;
  final String? message;
  final String address;

  const BleProvisionErrorEvent({
    required this.code,
    this.message,
    required this.address,
  });

  @override
  String toString() => 'BleProvisionErrorEvent(code: $code, message: $message)';
}
