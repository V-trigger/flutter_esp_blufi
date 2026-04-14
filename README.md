# esp_blufi

[English](#english) | [中文](#中文)

---

## English

A Flutter plugin for Wi-Fi provisioning via the **ESP BLUFI** protocol. Communicate with ESP32 devices over BLE to configure Wi-Fi credentials, query device status, and exchange custom data.

Supports **Android** and **iOS** (physical devices only — BLE is unavailable on simulators/emulators).

### Installation

```yaml
dependencies:
  esp_blufi:
    git:
      url: https://github.com/V-trigger/flutter_esp_blufi.git
```

```bash
flutter pub get
```

### Platform Setup

#### Android

Add the following permissions to `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.BLUETOOTH" />
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN" />
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
```

> On Android 12+ (API 31), `BLUETOOTH_SCAN` and `BLUETOOTH_CONNECT` are required. Request them at runtime before calling scan/connect.

#### iOS

Add the following to `ios/Runner/Info.plist`:

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>This app uses Bluetooth to configure Wi-Fi on ESP32 devices.</string>
<key>NSBluetoothPeripheralUsageDescription</key>
<string>This app uses Bluetooth to configure Wi-Fi on ESP32 devices.</string>
```

### Quick Start

```dart
import 'package:esp_blufi/esp_blufi.dart';

final blufi = EspBlufi();

// 1. Listen to events
blufi.eventStream.listen((event) {
  switch (event) {
    case BleScanResultEvent():
      print('Found device: ${event.name} (${event.address})');
    case ConnectionStateEvent():
      print('Connected: ${event.connected}');
    case GattPreparedEvent():
      if (event.success) print('GATT ready, can proceed');
    case ConfigureResultEvent():
      print('Provision ${event.success ? "succeeded" : "failed"}');
    case WifiScanResultEvent():
      print('WiFi: ${event.ssid} (RSSI: ${event.rssi})');
    case ReceiveCustomDataEvent():
      print('Custom data: ${event.data}');
    case ErrorEvent():
      print('Error code: ${event.code}');
    default:
      break;
  }
});

// 2. Scan for BLE devices
await blufi.scanDeviceInfo(filterString: 'BLUFI');

// 3. Connect to a device (use address from BleScanResultEvent)
await blufi.connectPeripheral(peripheralAddress: 'AA:BB:CC:DD:EE:FF');

// 4. Send Wi-Fi credentials
await blufi.configProvision(ssid: 'MyWiFi', password: 'password123');

// 5. Query device status
await blufi.requestDeviceStatus();

// 6. Send/receive custom data
await blufi.sendCustomData(data: '{"cmd":"hello"}');

// 7. Disconnect
await blufi.requestCloseConnection();
```

### API Reference

| Method | Description |
|--------|-------------|
| `scanDeviceInfo({String? filterString})` | Start BLE scan, optionally filter by device name |
| `stopScan()` | Stop BLE scanning |
| `connectPeripheral({String? peripheralAddress})` | Connect to a scanned BLE device |
| `requestCloseConnection()` | Disconnect from the current device |
| `configProvision({String? ssid, String? password})` | Send Wi-Fi SSID and password to the device |
| `requestDeviceWifiScan()` | Request the device to scan nearby Wi-Fi networks |
| `requestDeviceStatus()` | Query the device's current Wi-Fi connection status |
| `sendCustomData({String? data})` | Send custom string data to the device |
| `getAllPairedDevice()` | List bonded/paired Bluetooth devices (Android only) |
| `getPlatformVersion()` | Get the native platform version string |

### Event Types

All events are delivered through `eventStream` as typed `BlufiEvent` subclasses:

| Event Class | Description |
|-------------|-------------|
| `BleScanResultEvent` | A BLE device was found during scanning |
| `WifiScanResultEvent` | A Wi-Fi network was found by the device |
| `StopScanEvent` | BLE scanning has stopped |
| `ConnectionStateEvent` | BLE connection state changed (connected/disconnected) |
| `GattPreparedEvent` | GATT services are ready for communication |
| `NegotiateSecurityEvent` | Security negotiation result |
| `ConfigureResultEvent` | Wi-Fi provisioning result |
| `DeviceStatusEvent` | Device status query result |
| `DeviceWifiConnectEvent` | Device Wi-Fi connection state |
| `DeviceVersionEvent` | Device firmware version |
| `PostCustomDataEvent` | Custom data send result |
| `ReceiveCustomDataEvent` | Custom data received from device |
| `PairedDeviceEvent` | A paired Bluetooth device (Android) |
| `ErrorEvent` | An error occurred |

### Requirements

- Flutter >= 3.3.0
- Dart SDK >= 3.2.3
- Android: minSdk 19
- iOS: physical device required

---

## 中文

一个基于 **ESP BLUFI** 协议的 Flutter 插件，通过 BLE 与 ESP32 设备通信，实现 Wi-Fi 配网、设备状态查询和自定义数据收发。

支持 **Android** 和 **iOS**（仅物理设备，模拟器不支持 BLE）。

### 安装

```yaml
dependencies:
  esp_blufi:
    git:
      url: https://github.com/V-trigger/flutter_esp_blufi.git
```

```bash
flutter pub get
```

### 平台配置

#### Android

在 `android/app/src/main/AndroidManifest.xml` 中添加以下权限：

```xml
<uses-permission android:name="android.permission.BLUETOOTH" />
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN" />
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
```

> Android 12+（API 31）需要 `BLUETOOTH_SCAN` 和 `BLUETOOTH_CONNECT` 权限，请在调用扫描/连接前动态申请。

#### iOS

在 `ios/Runner/Info.plist` 中添加：

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>此应用使用蓝牙为 ESP32 设备配置 Wi-Fi。</string>
<key>NSBluetoothPeripheralUsageDescription</key>
<string>此应用使用蓝牙为 ESP32 设备配置 Wi-Fi。</string>
```

### 快速上手

```dart
import 'package:esp_blufi/esp_blufi.dart';

final blufi = EspBlufi();

// 1. 监听事件流
blufi.eventStream.listen((event) {
  switch (event) {
    case BleScanResultEvent():
      print('发现设备: ${event.name} (${event.address})');
    case ConnectionStateEvent():
      print('连接状态: ${event.connected}');
    case GattPreparedEvent():
      if (event.success) print('GATT 就绪，可以继续操作');
    case ConfigureResultEvent():
      print('配网${event.success ? "成功" : "失败"}');
    case WifiScanResultEvent():
      print('WiFi: ${event.ssid} (信号: ${event.rssi})');
    case ReceiveCustomDataEvent():
      print('收到自定义数据: ${event.data}');
    case ErrorEvent():
      print('错误码: ${event.code}');
    default:
      break;
  }
});

// 2. 扫描 BLE 设备
await blufi.scanDeviceInfo(filterString: 'BLUFI');

// 3. 连接设备（使用 BleScanResultEvent 中的 address）
await blufi.connectPeripheral(peripheralAddress: 'AA:BB:CC:DD:EE:FF');

// 4. 发送 Wi-Fi 凭证
await blufi.configProvision(ssid: 'MyWiFi', password: 'password123');

// 5. 查询设备状态
await blufi.requestDeviceStatus();

// 6. 收发自定义数据
await blufi.sendCustomData(data: '{"cmd":"hello"}');

// 7. 断开连接
await blufi.requestCloseConnection();
```

### API 参考

| 方法 | 说明 |
|------|------|
| `scanDeviceInfo({String? filterString})` | 开始 BLE 扫描，可按设备名过滤 |
| `stopScan()` | 停止 BLE 扫描 |
| `connectPeripheral({String? peripheralAddress})` | 连接已扫描到的 BLE 设备 |
| `requestCloseConnection()` | 断开当前连接 |
| `configProvision({String? ssid, String? password})` | 向设备发送 Wi-Fi SSID 和密码 |
| `requestDeviceWifiScan()` | 请求设备扫描附近的 Wi-Fi 网络 |
| `requestDeviceStatus()` | 查询设备当前 Wi-Fi 连接状态 |
| `sendCustomData({String? data})` | 向设备发送自定义字符串数据 |
| `getAllPairedDevice()` | 列出已配对的蓝牙设备（仅 Android） |
| `getPlatformVersion()` | 获取原生平台版本字符串 |

### 事件类型

所有事件通过 `eventStream` 以类型化的 `BlufiEvent` 子类传递：

| 事件类 | 说明 |
|--------|------|
| `BleScanResultEvent` | BLE 扫描发现设备 |
| `WifiScanResultEvent` | 设备扫描到的 Wi-Fi 网络 |
| `StopScanEvent` | BLE 扫描已停止 |
| `ConnectionStateEvent` | BLE 连接状态变化（连接/断开） |
| `GattPreparedEvent` | GATT 服务就绪，可以通信 |
| `NegotiateSecurityEvent` | 安全协商结果 |
| `ConfigureResultEvent` | Wi-Fi 配网结果 |
| `DeviceStatusEvent` | 设备状态查询结果 |
| `DeviceWifiConnectEvent` | 设备 Wi-Fi 连接状态 |
| `DeviceVersionEvent` | 设备固件版本 |
| `PostCustomDataEvent` | 自定义数据发送结果 |
| `ReceiveCustomDataEvent` | 收到设备发来的自定义数据 |
| `PairedDeviceEvent` | 已配对的蓝牙设备（Android） |
| `ErrorEvent` | 发生错误 |

### 环境要求

- Flutter >= 3.3.0
- Dart SDK >= 3.2.3
- Android: minSdk 19
- iOS: 需要物理设备

---

## License

MIT
