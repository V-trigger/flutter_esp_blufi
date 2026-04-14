import 'dart:async';

import 'ble_models.dart';

/// BLE 操作的抽象接口。
///
/// 上层业务（配网页面、工具类等）仅依赖此接口，不直接依赖 FBP / FRB 等具体库。
/// 替换底层库时只需提供新的 [BleService] 实现，无需改动业务代码。
abstract class BleService {
  // ── 单例 / 工厂 ──────────────────────────────────────────────────────────

  /// 全局共享实例。通过 [BleService.instance] 获取，
  /// 启动时用 [BleService.initialize] 设置具体实现。
  static late BleService instance;

  /// 初始化全局实例（在 app 启动时调用一次）。
  static void initialize(BleService impl) => instance = impl;

  // ── 适配器状态 ──────────────────────────────────────────────────────────

  /// 当前适配器状态。
  BleAdapterState get currentAdapterState;

  /// 适配器状态变化流（过滤掉 [BleAdapterState.unknown]）。
  Stream<BleAdapterState> get adapterStateStream;

  /// 等待适配器达到非 unknown 状态并返回。
  Future<BleAdapterState> waitForAdapterState({Duration timeout = const Duration(seconds: 4)});

  /// 请求系统打开蓝牙（仅 Android 有效）。
  Future<void> turnOnBluetooth({int timeoutSeconds = 60});

  // ── 扫描 ────────────────────────────────────────────────────────────────

  /// 扫描结果流，每次扫描周期内累积。
  Stream<List<BleScanResult>> get scanResultsStream;

  /// 开始扫描。
  Future<void> startScan({
    List<String>? withNames,
    Duration? timeout,
    bool continuousUpdates = false,
  });

  /// 停止扫描。
  Future<void> stopScan();

  // ── 连接管理 ─────────────────────────────────────────────────────────────

  /// 连接到设备。
  Future<void> connect(BleDevice device, {Duration timeout = const Duration(seconds: 15)});

  /// 断开设备连接。
  Future<void> disconnect(BleDevice device);

  /// 清除 GATT 缓存（防止缓存脏数据导致下次连接异常）。
  Future<void> clearGattCache(BleDevice device);

  /// 当前已连接的设备列表。
  List<BleDevice> get connectedDevices;

  /// 查询系统级已绑定/缓存的设备。
  Future<List<BleDevice>> getSystemDevices(List<String> serviceUuids);

  // ── GATT 服务发现 ────────────────────────────────────────────────────────

  /// 发现设备上的所有 GATT 服务及其特征值。
  Future<List<BleServiceInfo>> discoverServices(BleDevice device);

  // ── 特征值操作 ──────────────────────────────────────────────────────────

  /// 开启 / 关闭 Notify。
  Future<void> setNotifyValue(BleCharacteristic characteristic, bool enabled);

  /// 特征值最新值的持续数据流。
  Stream<List<int>> characteristicValueStream(BleCharacteristic characteristic);

  /// 写入特征值。
  Future<void> writeCharacteristic(
    BleCharacteristic characteristic,
    List<int> value, {
    bool withoutResponse = false,
  });
}
