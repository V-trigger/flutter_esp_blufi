package yu.legend.esp_blufi;

import android.Manifest;
import android.annotation.TargetApi;
import android.app.Activity;
import android.bluetooth.BluetoothAdapter;
import android.bluetooth.BluetoothDevice;
import android.bluetooth.BluetoothGatt;
import android.bluetooth.BluetoothGattCallback;
import android.bluetooth.BluetoothGattCharacteristic;
import android.bluetooth.BluetoothGattDescriptor;
import android.bluetooth.BluetoothGattService;
import android.bluetooth.BluetoothManager;
import android.bluetooth.BluetoothProfile;
import android.bluetooth.le.BluetoothLeScanner;
import android.bluetooth.le.ScanResult;
import android.bluetooth.le.ScanSettings;
import android.content.Context;
import android.content.pm.PackageManager;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import android.text.TextUtils;

import androidx.annotation.NonNull;
import androidx.annotation.RequiresApi;
import androidx.core.content.ContextCompat;

import java.lang.reflect.Method;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;
import yu.legend.esp_blufi.params.BlufiConfigureParams;
import yu.legend.esp_blufi.params.BlufiParameter;
import yu.legend.esp_blufi.response.BlufiScanResult;
import yu.legend.esp_blufi.response.BlufiStatusResponse;
import yu.legend.esp_blufi.response.BlufiVersionResponse;

public class EspBlufiPlugin implements FlutterPlugin, MethodCallHandler, ActivityAware {
  private Map<String, ScanResult> mDeviceMap;
  private ScanCallback mScanCallback;
  private String mBlufiFilter;
  private volatile long mScanStartTime;
  private Future mUpdateFuture;
  private BluetoothDevice mDevice;
  private BlufiClient mBlufiClient;
  private volatile boolean mConnected;
  private Context mContext;
  private ActivityPluginBinding activityBinding;
  private EventChannel stateChannel;
  private EventChannel.EventSink sink;
  private final BlufiLog mLog = new BlufiLog(getClass());
  private Handler handler;
  private Activity activity;
  private BluetoothManager mBluetoothManager;
  private MethodChannel channel;

  private boolean hasBluetoothPermission() {
    if (mContext == null) return false;
    if (Build.VERSION.SDK_INT > Build.VERSION_CODES.R) {
      return ContextCompat.checkSelfPermission(mContext, Manifest.permission.BLUETOOTH_CONNECT)
                 == PackageManager.PERMISSION_GRANTED
          && ContextCompat.checkSelfPermission(mContext, Manifest.permission.BLUETOOTH_SCAN)
                 == PackageManager.PERMISSION_GRANTED;
    } else {
      return ContextCompat.checkSelfPermission(mContext, Manifest.permission.BLUETOOTH)
                 == PackageManager.PERMISSION_GRANTED
          && ContextCompat.checkSelfPermission(mContext, Manifest.permission.BLUETOOTH_ADMIN)
                 == PackageManager.PERMISSION_GRANTED;
    }
  }

  private String getDeviceAddress() {
    if (mDevice != null && hasBluetoothPermission()) {
      return mDevice.getAddress();
    }
    return "";
  }

  private void sendEvent(Map<String, Object> event) {
    if (sink != null && handler != null) {
      handler.post(() -> {
        if (sink != null) {
          sink.success(event);
        }
      });
    }
  }

  private Map<String, Object> makeEvent(String key, Object value) {
    Map<String, Object> event = new HashMap<>();
    event.put("key", key);
    event.put("value", value);
    event.put("address", getDeviceAddress());
    return event;
  }

  private Map<String, Object> makeScanEvent(String address, String name, int rssi) {
    Map<String, Object> value = new HashMap<>();
    value.put("address", address);
    value.put("name", name);
    value.put("rssi", rssi);
    Map<String, Object> event = new HashMap<>();
    event.put("key", "ble_scan_result");
    event.put("value", value);
    return event;
  }

  private Map<String, Object> makeWifiScanEvent(String ssid, int rssi) {
    Map<String, Object> value = new HashMap<>();
    value.put("ssid", ssid);
    value.put("rssi", rssi);
    value.put("address", getDeviceAddress());
    Map<String, Object> event = new HashMap<>();
    event.put("key", "wifi_scan_result");
    event.put("value", value);
    return event;
  }

  @Override
  public void onAttachedToEngine(@NonNull FlutterPluginBinding flutterPluginBinding) {
    handler = new Handler(Looper.getMainLooper());
    channel = new MethodChannel(flutterPluginBinding.getBinaryMessenger(), "esp_blufi");
    channel.setMethodCallHandler(this);
    stateChannel = new EventChannel(flutterPluginBinding.getBinaryMessenger(), "esp_blufi/state");
    stateChannel.setStreamHandler(new EventChannel.StreamHandler() {
      @Override
      public void onListen(Object arguments, EventChannel.EventSink events) {
        sink = events;
      }

      @Override
      public void onCancel(Object arguments) {
        sink = null;
      }
    });
    mContext = flutterPluginBinding.getApplicationContext();
    mDeviceMap = new ConcurrentHashMap<>();
    mScanCallback = new ScanCallback();
  }

  @Override
  public void onMethodCall(@NonNull MethodCall call, @NonNull Result result) {
    switch (call.method) {
      case "getPlatformVersion":
        result.success("Android " + Build.VERSION.RELEASE);
        break;

      case "scanDeviceInfo": {
        String filter = call.argument("filter");
        scan(filter, result);
        break;
      }

      case "stopScan":
        stopScan();
        result.success(null);
        break;

      case "connectPeripheral": {
        String deviceId = call.argument("peripheral");
        if (deviceId == null) {
          result.error("INVALID_ARGUMENT", "peripheral address is required", null);
          break;
        }
        ScanResult scanResult = mDeviceMap.get(deviceId);
        if (scanResult == null) {
          result.error("DEVICE_NOT_FOUND", "No scanned device with address: " + deviceId, null);
          break;
        }
        connectDevice(scanResult.getDevice());
        result.success(true);
        break;
      }

      case "requestCloseConnection":
        disconnectGatt();
        result.success(null);
        break;

      case "requestDeviceWifiScan":
        requestDeviceWifiScan();
        result.success(null);
        break;

      case "configProvision": {
        String ssid = call.argument("ssid");
        if (ssid == null) ssid = call.argument("username");
        String password = call.argument("password");
        configure(ssid, password);
        result.success(null);
        break;
      }

      case "getAllPairedDevice":
        getAllPairedDevice();
        result.success(null);
        break;

      case "requestDeviceStatus":
        requestDeviceStatus();
        result.success(null);
        break;

      case "sendCustomData": {
        String data = call.argument("data");
        postCustomData(data);
        result.success(null);
        break;
      }

      default:
        result.notImplemented();
        break;
    }
  }

  @Override
  public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
    channel.setMethodCallHandler(null);
    stateChannel.setStreamHandler(null);
    stopScan();
    if (mBlufiClient != null) {
      mBlufiClient.close();
      mBlufiClient = null;
    }
    if (mDeviceMap != null) {
      mDeviceMap.clear();
    }
    sink = null;
    mContext = null;
  }

  @Override
  public void onAttachedToActivity(ActivityPluginBinding activityPluginBinding) {
    this.activityBinding = activityPluginBinding;
    this.activity = activityPluginBinding.getActivity();
    mBluetoothManager = (BluetoothManager) mContext.getSystemService(Context.BLUETOOTH_SERVICE);
  }

  @Override
  public void onDetachedFromActivityForConfigChanges() {
    activity = null;
    activityBinding = null;
  }

  @Override
  public void onReattachedToActivityForConfigChanges(ActivityPluginBinding activityPluginBinding) {
    this.activityBinding = activityPluginBinding;
    this.activity = activityPluginBinding.getActivity();
  }

  @Override
  public void onDetachedFromActivity() {
    mBluetoothManager = null;
    activity = null;
    activityBinding = null;
  }

  @RequiresApi(api = Build.VERSION_CODES.LOLLIPOP)
  private class ScanCallback extends android.bluetooth.le.ScanCallback {
    @Override
    public void onScanFailed(int errorCode) {
      super.onScanFailed(errorCode);
      Map<String, Object> errorData = new HashMap<>();
      errorData.put("code", errorCode);
      errorData.put("message", "BLE scan failed");
      sendEvent(makeEvent("error", errorData));
    }

    @Override
    public void onBatchScanResults(List<ScanResult> results) {
      for (ScanResult result : results) {
        onLeScan(result);
      }
    }

    @Override
    public void onScanResult(int callbackType, ScanResult result) {
      onLeScan(result);
    }

    private void onLeScan(ScanResult scanResult) {
      if (!hasBluetoothPermission()) return;

      String name = scanResult.getDevice().getName();

      if (!TextUtils.isEmpty(mBlufiFilter)) {
        if (name == null || !name.toLowerCase().contains(mBlufiFilter.toLowerCase())) {
          return;
        }
      }

      if (name != null) {
        mDeviceMap.put(scanResult.getDevice().getAddress(), scanResult);
        sendEvent(makeScanEvent(
            scanResult.getDevice().getAddress(), name, scanResult.getRssi()));
      }
    }
  }

  private void getAllPairedDevice() {
    if (!hasBluetoothPermission()) return;
    if (mBluetoothManager == null) return;
    BluetoothAdapter adapter = mBluetoothManager.getAdapter();
    if (adapter == null) return;

    Set<BluetoothDevice> bondedDevices = adapter.getBondedDevices();
    for (BluetoothDevice device : bondedDevices) {
      String name = device.getName();
      if (name == null) name = "";
      Map<String, Object> value = new HashMap<>();
      value.put("name", name);
      value.put("address", device.getAddress());
      sendEvent(makeEvent("paired_device", value));
    }
  }

  private void scan(String filter, Result result) {
    startScan21(filter, result);
  }

  @TargetApi(Build.VERSION_CODES.LOLLIPOP)
  private void startScan21(String filter, Result result) {
    if (mBluetoothManager == null) {
      result.error("BLUETOOTH_UNAVAILABLE", "BluetoothManager not available", null);
      return;
    }
    BluetoothAdapter adapter = mBluetoothManager.getAdapter();
    BluetoothLeScanner scanner = adapter != null ? adapter.getBluetoothLeScanner() : null;

    if (adapter == null || !adapter.isEnabled() || scanner == null) {
      result.success(false);
      return;
    }

    if (!hasBluetoothPermission()) {
      result.error("PERMISSION_DENIED", "Bluetooth permissions not granted", null);
      return;
    }

    mDeviceMap.clear();
    mBlufiFilter = filter;
    mScanStartTime = SystemClock.elapsedRealtime();

    scanner.startScan(null,
        new ScanSettings.Builder().setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY).build(),
        mScanCallback);
    result.success(true);
  }

  private void stopScan() {
    stopScan21();
  }

  @TargetApi(Build.VERSION_CODES.LOLLIPOP)
  private void stopScan21() {
    if (mBluetoothManager == null) return;
    BluetoothAdapter adapter = mBluetoothManager.getAdapter();
    if (adapter == null) return;
    BluetoothLeScanner scanner = adapter.getBluetoothLeScanner();

    if (scanner != null && hasBluetoothPermission()) {
      scanner.stopScan(mScanCallback);
    }
    if (mUpdateFuture != null) {
      mUpdateFuture.cancel(true);
    }
    sendEvent(makeEvent("stop_scan_ble", "1"));
  }

  private void connectDevice(BluetoothDevice device) {
    mDevice = device;
    if (mBlufiClient != null) {
      mBlufiClient.close();
      mBlufiClient = null;
    }

    mBlufiClient = new BlufiClient(mContext, mDevice);
    mBlufiClient.setGattCallback(new GattCallback());
    mBlufiClient.setBlufiCallback(new BlufiCallbackMain());
    mBlufiClient.setGattWriteTimeout(BlufiParameter.GATT_WRITE_TIMEOUT);
    mBlufiClient.connect();
  }

  private void disconnectGatt() {
    if (mBlufiClient != null) {
      mBlufiClient.close();
      mBlufiClient = null;
    }
    if (mDevice != null && hasBluetoothPermission()) {
      removeBond(mDevice);
      mDevice = null;
    }
    mConnected = false;
  }

  private void removeBond(BluetoothDevice device) {
    try {
      Method method = device.getClass().getMethod("removeBond", (Class[]) null);
      method.invoke(device);
    } catch (Exception e) {
      mLog.w("removeBond failed: " + e.getMessage());
    }
  }

  private void configure(String ssid, String password) {
    if (mBlufiClient == null || ssid == null) return;
    BlufiConfigureParams params = new BlufiConfigureParams();
    params.setOpMode(1);
    params.setStaSSIDBytes(ssid.getBytes());
    params.setStaPassword(password);
    mBlufiClient.configure(params);
  }

  private void requestDeviceStatus() {
    if (mBlufiClient != null) {
      mBlufiClient.requestDeviceStatus();
    }
  }

  private void requestDeviceWifiScan() {
    if (mBlufiClient != null) {
      mBlufiClient.requestDeviceWifiScan();
    }
  }

  private void postCustomData(String dataString) {
    if (mBlufiClient != null && dataString != null) {
      mBlufiClient.postCustomData(dataString.getBytes());
    }
  }

  private void onGattConnected() {
    mConnected = true;
  }

  private void onGattDisconnected() {
    mConnected = false;
  }

  @RequiresApi(api = Build.VERSION_CODES.JELLY_BEAN_MR2)
  private class GattCallback extends BluetoothGattCallback {
    @Override
    public void onConnectionStateChange(BluetoothGatt gatt, int status, int newState) {
      String devAddr = gatt.getDevice().getAddress();
      mLog.d(String.format(Locale.ENGLISH, "onConnectionStateChange addr=%s, status=%d, newState=%d",
          devAddr, status, newState));
      if (status == BluetoothGatt.GATT_SUCCESS) {
        switch (newState) {
          case BluetoothProfile.STATE_CONNECTED:
            onGattConnected();
            sendEvent(makeEvent("peripheral_connected", "1"));
            break;
          case BluetoothProfile.STATE_DISCONNECTED:
            if (!hasBluetoothPermission()) return;
            gatt.close();
            onGattDisconnected();
            sendEvent(makeEvent("peripheral_disconnected", "1"));
            break;
        }
      } else {
        gatt.close();
        onGattDisconnected();
        sendEvent(makeEvent("peripheral_disconnected", "1"));
      }
    }

    @Override
    public void onMtuChanged(BluetoothGatt gatt, int mtu, int status) {
      mLog.d(String.format(Locale.ENGLISH, "onMtuChanged status=%d, mtu=%d", status, mtu));
      if (status == BluetoothGatt.GATT_SUCCESS) {
        mBlufiClient.setPostPackageLengthLimit(255);
        sendEvent(makeEvent("gatt_prepared", "1"));
      } else {
        mBlufiClient.setPostPackageLengthLimit(20);
        sendEvent(makeEvent("gatt_prepared", "0"));
      }
    }

    @Override
    public void onServicesDiscovered(BluetoothGatt gatt, int status) {
      mLog.d(String.format(Locale.ENGLISH, "onServicesDiscovered status=%d", status));
      if (status != BluetoothGatt.GATT_SUCCESS) {
        if (!hasBluetoothPermission()) return;
        gatt.disconnect();
      }
    }

    @Override
    public void onDescriptorWrite(BluetoothGatt gatt, BluetoothGattDescriptor descriptor, int status) {
      mLog.d(String.format(Locale.ENGLISH, "onDescriptorWrite status=%d", status));
    }

    @Override
    public void onCharacteristicWrite(BluetoothGatt gatt, BluetoothGattCharacteristic characteristic, int status) {
      if (status != BluetoothGatt.GATT_SUCCESS) {
        if (!hasBluetoothPermission()) return;
        gatt.disconnect();
      }
    }
  }

  private class BlufiCallbackMain extends BlufiCallback {
    @RequiresApi(api = Build.VERSION_CODES.JELLY_BEAN_MR2)
    @Override
    public void onGattPrepared(BlufiClient client, BluetoothGatt gatt, BluetoothGattService service,
                               BluetoothGattCharacteristic writeChar, BluetoothGattCharacteristic notifyChar) {
      if (service == null) {
        mLog.w("Discover service failed");
        if (hasBluetoothPermission()) gatt.disconnect();
        sendEvent(makeEvent("gatt_prepared", "0"));
        return;
      }
      if (writeChar == null) {
        mLog.w("Get write characteristic failed");
        gatt.disconnect();
        sendEvent(makeEvent("gatt_prepared", "0"));
        return;
      }
      if (notifyChar == null) {
        mLog.w("Get notification characteristic failed");
        gatt.disconnect();
        sendEvent(makeEvent("gatt_prepared", "0"));
        return;
      }

      int mtu = BlufiParameter.DEFAULT_MTU_LENGTH;
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
        boolean requestMtu = gatt.requestMtu(mtu);
        if (!requestMtu) {
          mLog.w("Request mtu failed");
          sendEvent(makeEvent("gatt_prepared", "0"));
        }
      }
    }

    @Override
    public void onNegotiateSecurityResult(BlufiClient client, int status) {
      sendEvent(makeEvent("negotiate_security", status == STATUS_SUCCESS ? "1" : "0"));
    }

    @Override
    public void onPostConfigureParams(BlufiClient client, int status) {
      sendEvent(makeEvent("configure_params", status == STATUS_SUCCESS ? "1" : "0"));
    }

    @Override
    public void onDeviceStatusResponse(BlufiClient client, int status, BlufiStatusResponse response) {
      if (status == STATUS_SUCCESS) {
        sendEvent(makeEvent("device_status", "1"));
        sendEvent(makeEvent("device_wifi_connect", response.isStaConnectWifi() ? "1" : "0"));
      } else {
        sendEvent(makeEvent("device_status", "0"));
      }
    }

    @Override
    public void onDeviceScanResult(BlufiClient client, int status, List<BlufiScanResult> results) {
      if (status == STATUS_SUCCESS) {
        for (BlufiScanResult scanResult : results) {
          sendEvent(makeWifiScanEvent(scanResult.getSsid(), scanResult.getRssi()));
        }
      } else {
        sendEvent(makeEvent("wifi_scan_result", "0"));
      }
    }

    @Override
    public void onDeviceVersionResponse(BlufiClient client, int status, BlufiVersionResponse response) {
      if (status == STATUS_SUCCESS) {
        sendEvent(makeEvent("device_version", response.getVersionString()));
      } else {
        sendEvent(makeEvent("device_version", "0"));
      }
    }

    @Override
    public void onPostCustomDataResult(BlufiClient client, int status, byte[] data) {
      sendEvent(makeEvent("post_custom_data", status == STATUS_SUCCESS ? "1" : "0"));
    }

    @Override
    public void onReceiveCustomData(BlufiClient client, int status, byte[] data) {
      if (status == STATUS_SUCCESS) {
        String customStr = new String(data);
        sendEvent(makeEvent("receive_custom_data", customStr));
      } else {
        sendEvent(makeEvent("receive_custom_data", "0"));
      }
    }

    @Override
    public void onError(BlufiClient client, int errCode) {
      Map<String, Object> errorData = new HashMap<>();
      errorData.put("code", errCode);
      errorData.put("address", getDeviceAddress());
      sendEvent(makeEvent("error", errorData));
      if (errCode == CODE_GATT_WRITE_TIMEOUT) {
        client.close();
        onGattDisconnected();
      }
    }
  }
}
