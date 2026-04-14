import 'package:esp_blufi/esp_blufi_event.dart';
import 'package:esp_blufi/esp_blufi_method_channel.dart';
import 'package:esp_blufi/esp_blufi_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

abstract class MockEspBlufiPlatform
    with MockPlatformInterfaceMixin
    implements EspBlufiPlatform {
  @override
  Future<String?> getPlatformVersion() => Future.value('42');

  @override
  Stream<BlufiEvent> get eventStream => const Stream.empty();

  @override
  Future<void> configProvision({String? ssid, String? password}) {
    throw UnimplementedError();
  }

  @override
  Future<void> connectPeripheral({String? peripheralAddress}) {
    throw UnimplementedError();
  }

  @override
  Future<void> getAllPairedDevice() {
    throw UnimplementedError();
  }

  @override
  Future<void> requestCloseConnection() {
    throw UnimplementedError();
  }

  @override
  Future<void> requestDeviceStatus() {
    throw UnimplementedError();
  }

  @override
  Future<void> scanDeviceInfo({String? filterString}) {
    throw UnimplementedError();
  }

  @override
  Future<void> sendCustomData({String? data}) {
    throw UnimplementedError();
  }

  @override
  Future<void> stopScan() {
    throw UnimplementedError();
  }

  @override
  Future<void> requestDeviceWifiScan() {
    throw UnimplementedError();
  }
}

void main() {
  final EspBlufiPlatform initialPlatform = EspBlufiPlatform.instance;

  test('\$MethodChannelEspBlufi is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelEspBlufi>());
  });

  group('BlufiEvent.fromMap', () {
    test('parses ble_scan_result', () {
      final event = BlufiEvent.fromMap({
        'key': 'ble_scan_result',
        'value': {'address': 'AA:BB:CC', 'name': 'ESP32', 'rssi': -50},
      });
      expect(event, isA<BleScanResultEvent>());
      final scan = event as BleScanResultEvent;
      expect(scan.address, 'AA:BB:CC');
      expect(scan.name, 'ESP32');
      expect(scan.rssi, -50);
    });

    test('parses wifi_scan_result', () {
      final event = BlufiEvent.fromMap({
        'key': 'wifi_scan_result',
        'value': {'ssid': 'MyWifi', 'rssi': -40, 'address': 'AA:BB:CC'},
      });
      expect(event, isA<WifiScanResultEvent>());
      final wifi = event as WifiScanResultEvent;
      expect(wifi.ssid, 'MyWifi');
      expect(wifi.rssi, -40);
    });

    test('parses peripheral_connected', () {
      final event = BlufiEvent.fromMap({
        'key': 'peripheral_connected',
        'value': '1',
        'address': 'AA:BB:CC',
      });
      expect(event, isA<ConnectionStateEvent>());
      expect((event as ConnectionStateEvent).connected, isTrue);
    });

    test('parses peripheral_disconnected', () {
      final event = BlufiEvent.fromMap({
        'key': 'peripheral_disconnected',
        'value': '1',
        'address': 'AA:BB:CC',
      });
      expect(event, isA<ConnectionStateEvent>());
      expect((event as ConnectionStateEvent).connected, isFalse);
    });

    test('parses gatt_prepared success', () {
      final event = BlufiEvent.fromMap({
        'key': 'gatt_prepared',
        'value': '1',
        'address': 'AA:BB:CC',
      });
      expect(event, isA<GattPreparedEvent>());
      expect((event as GattPreparedEvent).success, isTrue);
    });

    test('parses error event with map value', () {
      final event = BlufiEvent.fromMap({
        'key': 'error',
        'value': {'code': 42, 'address': 'AA:BB:CC'},
        'address': 'AA:BB:CC',
      });
      expect(event, isA<ErrorEvent>());
      expect((event as ErrorEvent).code, 42);
    });

    test('parses unknown key as UnknownEvent', () {
      final event = BlufiEvent.fromMap({
        'key': 'some_future_key',
        'value': 'data',
        'address': '',
      });
      expect(event, isA<UnknownEvent>());
    });
  });
}
