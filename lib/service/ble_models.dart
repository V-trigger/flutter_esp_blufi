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
