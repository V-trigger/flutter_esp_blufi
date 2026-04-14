import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'esp_blufi_event.dart';
import 'esp_blufi_platform_interface.dart';

/// 基于 MethodChannel + EventChannel 的 [EspBlufiPlatform] 实现。
///
/// - MethodChannel `esp_blufi`：Dart → 原生的指令调用（扫描、连接、配网等）。
/// - EventChannel `esp_blufi/state`：原生 → Dart 的事件推送（扫描结果、连接状态、配网结果等）。
class MethodChannelEspBlufi extends EspBlufiPlatform {
  /// 指令通道：Dart 调用原生方法。
  @visibleForTesting
  final methodChannel = const MethodChannel('esp_blufi');

  /// 事件通道：原生向 Dart 推送事件。
  final EventChannel _eventChannel = const EventChannel('esp_blufi/state');

  /// 将原生推送的原始 Map 转换为类型安全的 [BlufiEvent] 广播流。
  late final Stream<BlufiEvent> _eventStream;

  static final MethodChannelEspBlufi _instance = MethodChannelEspBlufi._();
  static MethodChannelEspBlufi get instance => _instance;

  MethodChannelEspBlufi._() {
    _eventStream = _eventChannel.receiveBroadcastStream().map((event) {
      if (event is Map) {
        return BlufiEvent.fromMap(event);
      }
      return UnknownEvent(key: 'raw', rawValue: event, address: '');
    }).asBroadcastStream();
  }

  @override
  Stream<BlufiEvent> get eventStream => _eventStream;

  @override
  Future<String?> getPlatformVersion() async {
    return await methodChannel.invokeMethod<String>('getPlatformVersion');
  }

  @override
  Future<void> scanDeviceInfo({String? filterString}) async {
    await methodChannel
        .invokeMethod('scanDeviceInfo', <String, dynamic>{'filter': filterString});
  }

  @override
  Future<void> stopScan() async {
    await methodChannel.invokeMethod('stopScan');
  }

  @override
  Future<void> connectPeripheral({String? peripheralAddress}) async {
    await methodChannel.invokeMethod(
        'connectPeripheral', <String, dynamic>{'peripheral': peripheralAddress});
  }

  @override
  Future<void> requestCloseConnection() async {
    await methodChannel.invokeMethod('requestCloseConnection');
  }

  @override
  Future<void> requestDeviceWifiScan() async {
    await methodChannel.invokeMethod('requestDeviceWifiScan');
  }

  @override
  Future<void> configProvision({String? ssid, String? password}) async {
    await methodChannel.invokeMethod(
        'configProvision', <String, dynamic>{'ssid': ssid, 'password': password});
  }

  @override
  Future<void> getAllPairedDevice() async {
    await methodChannel.invokeMethod('getAllPairedDevice');
  }

  @override
  Future<void> requestDeviceStatus() async {
    await methodChannel.invokeMethod('requestDeviceStatus');
  }

  @override
  Future<void> sendCustomData({String? data}) async {
    await methodChannel
        .invokeMethod('sendCustomData', <String, dynamic>{'data': data});
  }
}
