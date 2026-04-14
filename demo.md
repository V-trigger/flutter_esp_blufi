```dart
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:esp_blufi/esp_blufi.dart';
import 'package:go_router/go_router.dart';
import 'package:yaguo/features/device/service/ble/ble_models.dart';
import 'package:yaguo/features/device/service/ble/ble_service.dart';
import 'package:yaguo/features/device/widgets/provision_log_panel.dart';
import 'package:yaguo/features/device/widgets/provision_progress_indicator.dart';
import 'package:yaguo/features/device/widgets/provision_success_dialog.dart';
import 'package:yaguo/features/device/widgets/wifi_credential_dialog.dart';
import 'package:yaguo/features/device/widgets/utils/device_ble_utils.dart';

// ─────────────────────────────────────────────────────────────────────────────
// 配网页面——全自动流程
//
// 进入即自动扫描 → 连接 → 弹出WiFi选择 → 配网 → 完成弹窗
// ─────────────────────────────────────────────────────────────────────────────

enum _ProvisionPhase { scanning, connecting, wifiSelect, provisioning, done, error }

class DeviceProvisionScreen extends StatefulWidget {
  const DeviceProvisionScreen({
    super.key,
    this.bleNameStage1 = 'YG_Planter',
    this.bleNameStage2 = 'BLUFI_DEVICE',
    this.deviceName = '种植机mini',
  });

  final String bleNameStage1;
  final String bleNameStage2;
  final String deviceName;

  @override
  State<DeviceProvisionScreen> createState() => _DeviceProvisionScreenState();
}

class _DeviceProvisionScreenState extends State<DeviceProvisionScreen>
    with TickerProviderStateMixin {
  // ── BLE 抽象层 ──
  final BleService _ble = BleService.instance;

  // ── 流程阶段 ──
  _ProvisionPhase _phase = _ProvisionPhase.scanning;
  String _statusText = '正在搜索设备…';
  String _errorText = '';

  // ── 进度 ──
  double _progress = 0.0;
  late final AnimationController _pulseCtrl;
  Timer? _progressTimer;

  // ── 日志 ──
  final List<String> _logs = [];
  bool _logExpanded = false;

  // ── Stage 1 (BLE 抽象层) ──
  StreamSubscription<List<BleScanResult>>? _bleScanSub;
  final List<StreamSubscription<List<int>>> _notifySubs = [];
  BleDevice? _stage1Device;
  BleCharacteristic? _writeChar;
  bool _okSent = false;
  String? _mac;
  // ignore: unused_field
  String? _sn;

  // ── Stage 2 (EspBlufi) ──
  final EspBlufi _blufi = EspBlufi();
  StreamSubscription<BlufiEvent>? _blufiEventSub;
  bool _stage2Running = false;
  String? _blufiAddress;
  ValueNotifier<List<WifiEntry>>? _wifiListNotifier;
  bool _bleConnected = false;
  bool _wifiSheetOpen = false;

  // ── WiFi 凭据（用户在底部弹窗中输入）──
  WifiCredentialResult? _wifiCreds;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startFlow());
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    _pulseCtrl.dispose();
    _bleScanSub?.cancel();
    _blufiEventSub?.cancel();
    for (final s in _notifySubs) {
      s.cancel();
    }
    _wifiListNotifier?.dispose();
    super.dispose();
  }

  // ════════════════════════════════════════════════════════════════════════════
  //  工具方法
  // ════════════════════════════════════════════════════════════════════════════

  void _log(String s) {
    if (!mounted) return;
    debugPrint('[Provision] $s');
    setState(() => _logs.add(s));
  }

  void _setPhase(_ProvisionPhase p, String text) {
    if (!mounted) return;
    setState(() {
      _phase = p;
      _statusText = text;
    });
  }

  void _animateProgressTo(double target, {Duration duration = const Duration(seconds: 2)}) {
    _progressTimer?.cancel();
    final start = _progress;
    final diff = target - start;
    if (diff <= 0) return;
    const interval = Duration(milliseconds: 50);
    final steps = (duration.inMilliseconds / interval.inMilliseconds).ceil();
    var step = 0;
    _progressTimer = Timer.periodic(interval, (t) {
      step++;
      final fraction = math.min(step / steps, 1.0);
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _progress = start + diff * fraction);
      if (fraction >= 1.0) t.cancel();
    });
  }

  // ════════════════════════════════════════════════════════════════════════════
  //  顶层流程入口
  // ════════════════════════════════════════════════════════════════════════════

  Future<void> _startFlow() async {
    _okSent = false;
    _stage2Running = false;
    _blufiAddress = null;
    _bleConnected = false;
    _wifiSheetOpen = false;
    _mac = null;
    _sn = null;
    _wifiCreds = null;
    _logs.clear();
    setState(() => _progress = 0.0);
    _setPhase(_ProvisionPhase.scanning, '正在搜索设备…');

    try {
      await _cleanupAllConnections();
      await _stage1StartScan();
    } catch (e) {
      _log('流程异常：$e');
      _setPhase(_ProvisionPhase.error, '配网失败');
      _errorText = e.toString();
    }
  }

  /// 断开所有已连接设备并清除 GATT 缓存，防止第二次配网命中旧缓存
  Future<void> _cleanupAllConnections() async {
    for (final s in _notifySubs) {
      await s.cancel();
    }
    _notifySubs.clear();
    _bleScanSub?.cancel();
    _bleScanSub = null;
    _writeChar = null;

    await _ble.stopScan();

    for (final device in _ble.connectedDevices) {
      _log('清理残留连接：${device.name}');
      try { await _ble.clearGattCache(device); } catch (_) {}
      try { await _ble.disconnect(device); } catch (_) {}
    }

    try { _blufi.stopScan(); } catch (_) {}

    _stage1Device = null;

    final systemDevices = await _ble.getSystemDevices(["1800"]);
    for (final d in systemDevices) {
      if (d.name.contains("YG_Planter") || d.name.contains("BLUFI")) {
        await _ble.disconnect(d);
      }
    }

    await Future.delayed(const Duration(milliseconds: 1000));
  }

  // ════════════════════════════════════════════════════════════════════════════
  //  Stage 1：BLE 抽象层 — 扫描 → 连接 → 获取mac/sn → 发OK
  // ════════════════════════════════════════════════════════════════════════════

  Future<void> _stage1StartScan() async {
    // ① 前置检查：确保蓝牙权限已授予（Android 需要 SCAN/CONNECT 权限）
    await DeviceBleUtils.ensureBlePermissions(log: _log);
    // ② 前置检查：确保蓝牙适配器已开启（未开启会尝试拉起系统弹窗）
    await DeviceBleUtils.ensureBleReady(log: _log);

    // ③ 取消上一次可能残留的扫描订阅，防止重复触发回调
    _bleScanSub?.cancel();
    _log('开始扫描 ${widget.bleNameStage1} …');

    // ④ 先订阅扫描结果流——这样在 startScan 开始产出结果时就能立刻收到
    //    scanResultsStream 是一个持续推送的 Stream，每发现新设备都会回调
    _bleScanSub = _ble.scanResultsStream.listen((results) {
      // results 是本轮扫描截至目前的累积设备列表
      for (final r in results) {
        // 匹配目标设备名（例如 "YG_Planter"）
        if (r.advertisedName == widget.bleNameStage1) {
          _log('发现 ${widget.bleNameStage1}');
          // 找到目标后立即：取消订阅 + 停止扫描，避免重复触发
          _bleScanSub?.cancel();
          _bleScanSub = null;
          _ble.stopScan();
          // 进入下一步：连接该设备（unawaited 不阻塞当前回调）
          unawaited(_stage1Connect(r));
          return;
        }
      }
    });

    // ⑤ 确保上一轮扫描已彻底停止，再发起新一轮扫描
    await _ble.stopScan();
    // ⑥ 发起 BLE 扫描
    //    - withNames: 只关注广播名为 bleNameStage1 的设备，过滤无关设备
    //    - timeout: 20 秒后底层库自动停止扫描
    //    - continuousUpdates: 持续推送更新（而非只推送新发现的设备）
    await _ble.startScan(
      withNames: [widget.bleNameStage1],
      timeout: const Duration(seconds: 20),
      continuousUpdates: true,
    );

    // ⑦ 超时兜底：等待 20 秒后，如果仍处于 scanning 阶段且未发送过 OK，
    //    说明始终没扫到目标设备，主动报错
    await Future<void>.delayed(const Duration(seconds: 20));
    if (_phase == _ProvisionPhase.scanning && !_okSent && mounted) {
      await _ble.stopScan();
      _bleScanSub?.cancel();
      _bleScanSub = null;
      _log('扫描超时，未找到 ${widget.bleNameStage1}');
      _setPhase(_ProvisionPhase.error, '未找到设备');
      _errorText = '未搜索到 ${widget.bleNameStage1}，请确认设备已开启';
    }
  }

  /// 阶段 1 连接流程：连接设备 → 发现 GATT 服务 → 订阅通知 → 等待设备推送 mac/sn
  ///
  /// 参数 [r] 是上一步扫描到的目标设备（YG_Planter）。
  Future<void> _stage1Connect(BleScanResult r) async {
    final device = r.device;
    _setPhase(_ProvisionPhase.connecting, '正在连接设备…');
    _animateProgressTo(0.10, duration: const Duration(seconds: 2));

    // ── ① 连接设备 + 发现 GATT 服务（最多重试 3 次）──────────────────────
    //
    // BLE 连接可能因设备瞬间断电、信号不稳等原因失败，所以做了重试机制。
    // 连接成功后立刻调用 discoverServices 获取设备上所有 GATT 服务和特征值。
    //
    // 什么是 GATT 服务/特征值？
    //   - BLE 设备通过 GATT 协议暴露自己的能力，组织结构为：
    //     Device → Service(s) → Characteristic(s)
    //   - Service 是功能分组（比如电池服务、自定义数据服务）
    //   - Characteristic 是具体的数据通道，有不同属性：
    //     · notify/indicate: 设备可以主动推送数据给手机（我们用来接收 mac/sn）
    //     · write:           手机可以向设备写入数据（我们用来发送 "OK"）

    List<BleServiceInfo> services = [];
    final notifyChars = <BleCharacteristic>[]; // 收集所有支持 notify 的特征值
    BleCharacteristic? pickedWrite;            // 找到第一个支持 write 的特征值

    for (var attempt = 1; attempt <= 3; attempt++) {
      try {
        _log('连接 ${widget.bleNameStage1}（第 $attempt 次）…');
        await _ble.connect(device, timeout: const Duration(seconds: 15));
        _stage1Device = device; // 记录下来，后续清理时需要断开它
        _log('已连接，发现服务/特征值…');
        services = await _ble.discoverServices(device);
        break; // 连接 + 发现服务都成功，跳出重试循环
      } catch (e) {
        _log('第 $attempt 次失败：$e');
        // 失败后先尝试断开（释放底层资源），再决定是否重试
        try { await _ble.disconnect(device); } catch (_) {}
        if (attempt == 3) {
          // 3 次都失败，放弃
          _setPhase(_ProvisionPhase.error, '连接失败');
          _errorText = '$e';
          return;
        }
        _log('等待 1s 后重试…');
        await Future.delayed(const Duration(seconds: 1));
      }
    }

    // ── ② 从发现的服务中筛选出需要的特征值 ──────────────────────────────
    //
    // 遍历所有 Service 下的所有 Characteristic，按属性分类收集：
    //   - 支持 notify/indicate 的 → notifyChars（用来接收设备推送的 mac/sn）
    //   - 支持 write 的 → pickedWrite（用来向设备发送 "OK" 指令）
    for (final s in services) {
      for (final c in s.characteristics) {
        if (c.supportsNotifyOrIndicate) notifyChars.add(c);
        if (pickedWrite == null && c.supportsWrite) {
          pickedWrite = c;
        }
      }
    }
    _writeChar = pickedWrite;

    // 如果没找到 write 或 notify 特征值，说明设备固件不符合预期
    if (_writeChar == null || notifyChars.isEmpty) {
      _log('未发现所需特征值');
      _setPhase(_ProvisionPhase.error, '设备通信异常');
      _errorText = '未发现所需 BLE 特征值';
      return;
    }

    // ── ③ 开启 notify 订阅，等待设备推送 mac/sn ─────────────────────────
    //
    // 对每个支持 notify 的特征值：
    //   1. setNotifyValue(true) → 告诉设备"我要订阅你的通知"
    //   2. 监听 characteristicValueStream → 设备每次推送数据都会触发回调
    //   3. 回调中把收到的字节解码为字符串，尝试从中解析 "mac:xxx,sn:xxx" 格式
    //   4. 解析成功 → 记录 mac/sn → 触发 _onMacSnReceived（发送 OK 并进入阶段 2）
    _log('开启通知，等待 mac/sn …');
    for (final c in notifyChars) {
      try {
        await _ble.setNotifyValue(c, true);
        final sub = _ble.characteristicValueStream(c).listen((bytes) {
          if (bytes.isEmpty) return;
          // 将原始字节解码为 UTF-8 字符串（allowMalformed 防止乱码崩溃）
          final text = utf8.decode(bytes, allowMalformed: true).trim();
          // 尝试匹配 "mac:xxxx,sn:xxxx" 格式，不匹配则忽略
          final parsed = DeviceBleUtils.tryParseMacAndSn(text);
          if (parsed == null) return;
          _mac = parsed.mac;
          _sn = parsed.sn;
          _log('收到 mac=${parsed.mac}, sn=${parsed.sn}');
          // 收到 mac/sn → 下一步发送 OK
          unawaited(_onMacSnReceived());
        });
        // 保存订阅引用，dispose 时统一取消
        _notifySubs.add(sub);
      } catch (e) {
        _log('开启通知失败：$e');
      }
    }

    // ── ④ 10 秒超时兜底 ─────────────────────────────────────────────────
    //
    // 如果设备一直不推送 mac/sn（固件异常或硬件故障），
    // 10 秒后主动报错，提示用户断电重置设备。
    Future.delayed(const Duration(seconds: 10), () {
      if (!_okSent && mounted) {
        _log('等待 mac/sn 超时（10s）');
        _setPhase(_ProvisionPhase.error, '设备无响应');
        _errorText = '未能获取设备信息，请断电重置设备后再试';
      }
    });
  }

  // ════════════════════════════════════════════════════════════════════════════
  //  过渡：发 OK → 等1s → 清理 BLE → 进入阶段2
  // ════════════════════════════════════════════════════════════════════════════

  /// 阶段 1 → 阶段 2 的过渡方法。
  ///
  /// 收到设备推送的 mac/sn 后调用，职责：
  ///   发 OK → 等设备切换蓝牙模式 → 彻底清理阶段 1 资源 → 启动阶段 2
  Future<void> _onMacSnReceived() async {
    // ── ① 防重入 ─────────────────────────────────────────────────────────
    // notify 可能在短时间内多次回调（设备重发等），
    // 用 _okSent 标志确保整个过渡流程只执行一次。
    if (_okSent) return;
    _okSent = true;

    // ── ② 向设备发送 "OK" ────────────────────────────────────────────────
    // 告诉设备"手机已收到 mac/sn"，设备收到 OK 后会关闭当前蓝牙（YG_Planter），
    // 并启动第二个蓝牙服务（BLUFI_DEVICE）进入配网模式。
    final c = _writeChar;
    if (c == null) {
      _okSent = false;
      _log('无可写特征值');
      return;
    }
    try {
      await _ble.writeCharacteristic(
        c,
        utf8.encode('OK'),
        // 如果特征值支持 writeWithoutResponse 就用它（更快，不等确认），
        // 否则用普通 write（会等设备回 ACK）。
        withoutResponse: c.canWriteWithoutResponse,
      );
      _log('已发送 OK');
    } catch (e) {
      // 写入失败 → 重置标志，允许下次 notify 回调再试
      _okSent = false;
      _log('发送 OK 失败：$e');
      return;
    }

    // ── ③ 等待设备切换蓝牙模式 ───────────────────────────────────────────
    // 设备收到 OK 后需要一点时间关闭 YG_Planter 并启动 BLUFI_DEVICE，
    // 这里等 1 秒给设备留出切换时间。
    await Future.delayed(const Duration(seconds: 1));

    // ── ④ 彻底清理阶段 1 的所有 BLE 资源 ─────────────────────────────────
    // 阶段 1 用的是通用 BLE（抽象层），阶段 2 会换用 EspBlufi 库，
    // 必须把阶段 1 的连接、订阅、扫描全部释放干净，
    // 否则两套 BLE 栈可能互相冲突（尤其 iOS 上 CoreBluetooth 是共享的）。
    _log('清理阶段 1 …');
    // 取消所有 notify 订阅
    for (final s in _notifySubs) {
      await s.cancel();
    }
    _notifySubs.clear();
    // 取消扫描订阅 & 停止扫描
    _bleScanSub?.cancel();
    _bleScanSub = null;
    await _ble.stopScan();
    // 清除 GATT 缓存并断开阶段 1 设备
    // clearGattCache 确保下次重连不会命中旧的缓存数据
    if (_stage1Device != null) {
      try { await _ble.clearGattCache(_stage1Device!); } catch (_) {}
      try { await _ble.disconnect(_stage1Device!); } catch (_) {}
    }
    _stage1Device = null;
    _writeChar = null;
    _log('阶段 1 清理完成');

    _animateProgressTo(0.15, duration: const Duration(seconds: 1));

    // ── ⑤ 进入阶段 2：EspBlufi 扫描并连接 BLUFI_DEVICE ─────────────────
    await _stage2Start();
  }

  // ════════════════════════════════════════════════════════════════════════════
  //  Stage 2：EspBlufi — 连接 BLUFI_DEVICE → 扫WiFi → 弹窗 → 配网
  // ════════════════════════════════════════════════════════════════════════════

  Future<void> _stage2Start() async {
    if (_stage2Running) return;
    _stage2Running = true;
    _blufiAddress = null;

    _setPhase(_ProvisionPhase.connecting, '正在连接配网模块…');
    _animateProgressTo(0.20, duration: const Duration(seconds: 2));

    var configOk = false;
    var wifiConfirmed = false;
    var statusRetries = 0;
    var gattReady = false;

    _wifiListNotifier?.dispose();
    _wifiListNotifier = ValueNotifier<List<WifiEntry>>([]);

    _blufiEventSub?.cancel();
    _blufiEventSub = _blufi.eventStream.listen((event) async {
      switch (event) {
        case BleScanResultEvent(:final name, :final address):
          if (name == widget.bleNameStage2 && _blufiAddress == null) {
            _blufiAddress = address;
            _log('发现 ${widget.bleNameStage2}');
            _blufi.stopScan();
            _log('正在连接 ${widget.bleNameStage2} …');
            _blufi.connectPeripheral(peripheralAddress: address);
          }

        case ConnectionStateEvent(:final connected):
          if (connected) {
            _bleConnected = true;
            _log('${widget.bleNameStage2} BLE 已连接，等待 GATT …');
          } else {
            _bleConnected = false;
            if (_wifiSheetOpen && mounted) {
              _log('WiFi 选择期间 BLE 断开，需要重新开始');
              Navigator.of(context).pop(null);
            } else if (configOk && !wifiConfirmed) {
              _log('设备断开 BLE（WiFi 配置已下发），等待确认结果 …');
              Future.delayed(const Duration(seconds: 15), () {
                if (!wifiConfirmed && mounted && _phase == _ProvisionPhase.provisioning) {
                  _log('等待配网结果超时');
                  _setPhase(_ProvisionPhase.error, '配网失败');
                  _errorText = '未收到设备确认，请检查设备指示灯是否常亮，若已常亮则配网成功';
                }
              });
            } else if (!configOk) {
              _log('设备 BLE 断开');
            }
          }

        case GattPreparedEvent(:final success):
          if (success && !gattReady) {
            gattReady = true;
            _log('GATT 就绪');
            _animateProgressTo(0.25, duration: const Duration(seconds: 1));
            if (_wifiCreds != null) {
              _startProvisioning();
            } else {
              unawaited(_showWifiSelection());
            }
          }

        case WifiScanResultEvent(:final ssid, :final rssi):
          if (ssid.isNotEmpty && _wifiListNotifier != null) {
            final list = List<WifiEntry>.from(_wifiListNotifier!.value);
            final idx = list.indexWhere((e) => e.ssid == ssid);
            if (idx >= 0) {
              if (rssi > list[idx].rssi) {
                list[idx] = WifiEntry(ssid: ssid, rssi: rssi);
              }
            } else {
              list.add(WifiEntry(ssid: ssid, rssi: rssi));
            }
            list.sort((a, b) => b.rssi.compareTo(a.rssi));
            _wifiListNotifier!.value = list;
          }

        case ConfigureResultEvent(:final success):
          if (success) {
            configOk = true;
            _log('WiFi 配置已下发，等待设备连接路由器 …');
            _animateProgressTo(0.85, duration: const Duration(seconds: 4));
            await Future.delayed(const Duration(seconds: 3));
            statusRetries = 0;
            _log('查询设备 WiFi 连接状态 …');
            _blufi.requestDeviceStatus();
          } else {
            _log('WiFi 配置下发失败');
            _setPhase(_ProvisionPhase.error, '配网失败');
            _errorText = 'WiFi 配置下发失败';
          }

        case DeviceWifiConnectEvent(:final connected):
          if (connected) {
            wifiConfirmed = true;
            _log('设备已连上 WiFi');
            _onProvisionSuccess();
          } else if (!wifiConfirmed) {
            statusRetries++;
            if (statusRetries < 3) {
              _log('设备尚未连上 WiFi, 2s 后重试 …');
              await Future.delayed(const Duration(seconds: 2));
              _blufi.requestDeviceStatus();
            } else {
              _log('设备未能连上 WiFi(已重试 $statusRetries 次）');
              _setPhase(_ProvisionPhase.error, '配网失败');
              _errorText = '配网失败,请检查WiFi密码是否正确,请确认使用的是 2.4G 网络';
            }
          }

        case DeviceStatusEvent(:final success):
          if (!success && configOk && !wifiConfirmed) {
            _log('状态查询返回未连接，继续等待 …');
          }

        case ErrorEvent(:final message):
          _log('BLUFI 错误：${message ?? "unknown"}');

        case StopScanEvent():
          break;

        default:
          _log('BLUFI: $event');
      }
    });

    await DeviceBleUtils.ensureBlePermissions(log: _log);
    await _ble.stopScan();

    _blufi.stopScan();
    await Future.delayed(const Duration(milliseconds: 500));

    _log('启动 EspBlufi 扫描 ${widget.bleNameStage2} …');
    _blufi.scanDeviceInfo(filterString: widget.bleNameStage2);
  }

  /// GATT 就绪后：弹出 WiFi 选择底部弹窗
  Future<void> _showWifiSelection() async {
    _setPhase(_ProvisionPhase.wifiSelect, '请选择 WiFi 网络');

    _wifiListNotifier!.value = [];
    _blufi.requestDeviceWifiScan();
    _log('请求设备扫描 WiFi …');

    await Future.delayed(const Duration(seconds: 3));
    _log('WiFi 扫描完成，共 ${_wifiListNotifier!.value.length} 个');

    if (!mounted) return;

    _wifiSheetOpen = true;
    final creds = await showWifiBottomSheet(
      context,
      wifiList: _wifiListNotifier!,
      onRefresh: () {
        _wifiListNotifier!.value = [];
        _log('重新扫描 WiFi …');
        _blufi.requestDeviceWifiScan();
      },
    );
    _wifiSheetOpen = false;

    if (creds == null) {
      if (!_bleConnected) {
        _log('BLE 连接已断开，请重新开始');
        _setPhase(_ProvisionPhase.error, '连接已断开');
        _errorText = '设备 BLE 连接超时断开，请点击重新开始';
      } else {
        _log('已取消配网');
        if (mounted) context.pop();
      }
      return;
    }

    _wifiCreds = creds;

    if (!_bleConnected) {
      _log('BLE 已断开，尝试重新连接 ${widget.bleNameStage2} …');
      _setPhase(_ProvisionPhase.connecting, '正在重新连接设备…');
      _stage2Running = false;
      _blufiAddress = null;
      await _stage2Start();
      return;
    }

    _startProvisioning();
  }

  void _startProvisioning() {
    final creds = _wifiCreds!;
    _setPhase(_ProvisionPhase.provisioning, '正在配置设备…');
    _animateProgressTo(0.30, duration: const Duration(seconds: 1));

    _log('下发 WiFi（SSID: ${creds.ssid}）…');

    Future.delayed(const Duration(seconds: 1), () {
      if (_phase == _ProvisionPhase.provisioning && mounted) {
        _animateProgressTo(0.70, duration: const Duration(seconds: 4));
        if (mounted) setState(() => _statusText = '正在传输配置信息…');
      }
    });

    _blufi.configProvision(ssid: creds.ssid, password: creds.password);
  }

  void _onProvisionSuccess() {
    _progressTimer?.cancel();
    setState(() => _progress = 1.0);
    _setPhase(_ProvisionPhase.done, '配网成功');
    _log('配网完成！');
    _showSuccessDialog();
  }

  Future<void> _showSuccessDialog() async {
    if (!mounted) return;
    await showProvisionSuccessDialog(
      context,
      deviceName: widget.deviceName,
      mac: _mac,
      sn: _sn,
    );
    if (mounted) context.pop();
  }

  // ════════════════════════════════════════════════════════════════════════════
  //  UI
  // ════════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          onPressed: () => context.pop(),
          icon: const Icon(Icons.arrow_back_ios_new, size: 18, color: Color(0xFF2A2D34)),
        ),
        title: Text(
          '添加${widget.deviceName}',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Color(0xFF1A1C20)),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildProgressCircle(),
                      const SizedBox(height: 28),
                      Text(
                        _statusText,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1A1C20),
                        ),
                      ),
                      const SizedBox(height: 8),
                      _buildSubtext(),
                      if (_phase == _ProvisionPhase.error) ...[
                        const SizedBox(height: 24),
                        _buildRetryButton(),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            _buildLogSection(),
          ],
        ),
      ),
    );
  }

  ProvisionIndicatorMode get _indicatorMode => switch (_phase) {
    _ProvisionPhase.scanning => ProvisionIndicatorMode.scanning,
    _ProvisionPhase.done => ProvisionIndicatorMode.done,
    _ProvisionPhase.error => ProvisionIndicatorMode.error,
    _ => ProvisionIndicatorMode.progress,
  };

  Widget _buildProgressCircle() {
    return ProvisionProgressIndicator(
      mode: _indicatorMode,
      progress: _progress,
      pulseAnimation: _pulseCtrl,
    );
  }

  Widget _buildSubtext() {
    String sub;
    switch (_phase) {
      case _ProvisionPhase.scanning:
        sub = '请确保设备已开启并在附近';
      case _ProvisionPhase.connecting:
        sub = '正在与设备建立连接';
      case _ProvisionPhase.wifiSelect:
        sub = '请在弹窗中选择 WiFi 并输入密码';
      case _ProvisionPhase.provisioning:
        sub = '正在将 WiFi 信息传输到设备';
      case _ProvisionPhase.done:
        sub = '设备配置完成';
      case _ProvisionPhase.error:
        sub = _errorText;
    }
    return Text(
      sub,
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 13, color: Color(0xFF8E939B)),
    );
  }

  Widget _buildRetryButton() {
    return FilledButton.icon(
      onPressed: _startFlow,
      icon: const Icon(Icons.refresh_rounded, size: 18),
      label: const Text('重新开始'),
      style: FilledButton.styleFrom(
        backgroundColor: const Color(0xFF35CD83),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
      ),
    );
  }

  Widget _buildLogSection() {
    return ProvisionLogPanel(
      logs: _logs,
      expanded: _logExpanded,
      onToggle: () => setState(() => _logExpanded = !_logExpanded),
    );
  }
}

```

BL602_BLE_DEV 是你设备上 BL602 芯片的默认蓝牙广播名。

BL602 是博流（Bouffalo Lab）的 WiFi+BLE combo 芯片，你的种植机硬件用的就是这颗芯片。正常流程中它被固件配置为 YG_Planter（Stage 1）或 BLUFI_DEVICE（Stage 2），但长按重置后，芯片在固件完成初始化之前会短暂地用出厂默认名 BL602_BLE_DEV 广播。

自动连接的原因和解决方案：

为什么会自动连上？

Stage 2 中 EspBlufi 的原生层（BlufiClient）连接设备时，操作系统会缓存这个 BLE 外设的配对/绑定信息。设备重置后用 BL602_BLE_DEV 重新广播，但底层的 MAC/UUID 没变，所以 iOS 的 CoreBluetooth（或 Android 的蓝牙栈）根据缓存自动重连了。

为什么你的清理代码有时不管用？

你的清理逻辑有两个盲区：

_ble.connectedDevices 只返回 FBP/FRB 管理的连接 —— EspBlufi 发起的连接它不知道
getSystemDevices 的名字过滤只匹配 "YG_Planter" 和 "BLUFI" —— BL602_BLE_DEV 不在里面
建议修改两处：

第一，在清理里加上对 BL602 的匹配：