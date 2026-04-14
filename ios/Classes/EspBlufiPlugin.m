#import "EspBlufiPlugin.h"
#import "BlufiClient.h"
#import "ESPPeripheral.h"
#import "ESPFBYBLEHelper.h"
#import "ESPDataConversion.h"
#import <CoreLocation/CoreLocation.h>
#import <SystemConfiguration/CaptiveNetwork.h>

@interface EspBlufiPlugin() <CBCentralManagerDelegate, CBPeripheralDelegate, BlufiDelegate>
@property(nonatomic, strong) ESPFBYBLEHelper *espFBYBleHelper;
@property(nonatomic, copy) NSMutableDictionary *peripheralDictionary;
@property(nonatomic, strong) NSString *filterContent;
@property(strong, nonatomic) ESPPeripheral *device;
@property(strong, nonatomic) BlufiClient *blufiClient;
@property(assign, atomic) BOOL connected;
@property(nonatomic, retain) EspBlufiPluginStreamHandler *stateStreamHandler;
@end

@implementation EspBlufiPlugin

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
    FlutterMethodChannel* channel = [FlutterMethodChannel
            methodChannelWithName:@"esp_blufi"
                  binaryMessenger:[registrar messenger]];
    EspBlufiPlugin* instance = [[EspBlufiPlugin alloc] init];
    FlutterEventChannel* stateChannel = [FlutterEventChannel eventChannelWithName:@"esp_blufi/state" binaryMessenger:[registrar messenger]];
    EspBlufiPluginStreamHandler* stateStreamHandler = [[EspBlufiPluginStreamHandler alloc] init];
    [stateChannel setStreamHandler:stateStreamHandler];
    instance.stateStreamHandler = stateStreamHandler;
    [registrar addMethodCallDelegate:instance channel:channel];
}

- (instancetype)init {
    self = [super init];
    if (self) {
        self.espFBYBleHelper = [ESPFBYBLEHelper share];
        self.filterContent = [ESPDataConversion loadBlufiScanFilter];
    }
    return self;
}

#pragma mark - Event helpers

- (NSString *)deviceAddress {
    if (self.device != nil) {
        return self.device.uuid.UUIDString;
    }
    return @"";
}

- (void)sendEvent:(NSDictionary *)event {
    if (self.stateStreamHandler.sink != nil) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.stateStreamHandler.sink != nil) {
                self.stateStreamHandler.sink(event);
            }
        });
    }
}

- (NSDictionary *)makeEventWithKey:(NSString *)key value:(id)value {
    return @{
        @"key": key,
        @"value": value,
        @"address": [self deviceAddress]
    };
}

- (NSDictionary *)makeScanEventWithAddress:(NSString *)address name:(NSString *)name rssi:(int)rssi {
    return @{
        @"key": @"ble_scan_result",
        @"value": @{
            @"address": address,
            @"name": name,
            @"rssi": @(rssi)
        }
    };
}

- (NSDictionary *)makeWifiScanEventWithSsid:(NSString *)ssid rssi:(int)rssi {
    return @{
        @"key": @"wifi_scan_result",
        @"value": @{
            @"ssid": ssid,
            @"rssi": @(rssi),
            @"address": [self deviceAddress]
        }
    };
}

#pragma mark - BLE operations

- (void)scanDeviceInfo {
    [self.espFBYBleHelper startScan:^(ESPPeripheral * _Nonnull device) {
        if (device.name == nil) return;

        if (self.filterContent != nil && ![self.filterContent isEqualToString:@""] &&
            ![device.name.lowercaseString containsString:self.filterContent.lowercaseString]) return;

        self.dataDictionary[device.uuid.UUIDString] = device;
        [self sendEvent:[self makeScanEventWithAddress:device.uuid.UUIDString name:device.name rssi:device.rssi]];
    }];
}

- (void)stopScan {
    [self.espFBYBleHelper stopScan];
    [self sendEvent:[self makeEventWithKey:@"stop_scan_ble" value:@"1"]];
}

- (void)connectPeripheral:(ESPPeripheral *)peripheral {
    self.connected = NO;
    self.device = peripheral;

    if (_blufiClient) {
        [_blufiClient close];
        _blufiClient = nil;
    }

    _blufiClient = [[BlufiClient alloc] init];
    _blufiClient.centralManagerDelete = self;
    _blufiClient.peripheralDelegate = self;
    _blufiClient.blufiDelegate = self;
    [_blufiClient connect:_device.uuid.UUIDString];
}

- (void)onDisconnected {
    if (_blufiClient) {
        [_blufiClient close];
    }
}

- (void)requestCloseConnection {
    if (_blufiClient) {
        [_blufiClient requestCloseConnection];
    }
}

- (void)requestDeviceWifiScan {
    if (_blufiClient) {
        [_blufiClient requestDeviceScan];
    }
}

- (void)negotiateSecurity {
    if (_blufiClient) {
        [_blufiClient negotiateSecurity];
    }
}

- (void)requestDeviceVersion {
    if (_blufiClient) {
        [_blufiClient requestDeviceVersion];
    }
}

- (void)configProvisionWithSSID:(NSString *)ssid password:(NSString *)password {
    BlufiConfigureParams *params = [[BlufiConfigureParams alloc] init];
    params.opMode = OpModeSta;
    params.staSsid = ssid;
    params.staPassword = password;

    if (_blufiClient && _connected) {
        [_blufiClient configure:params];
    }
}

- (void)requestDeviceStatus {
    if (_blufiClient) {
        [_blufiClient requestDeviceStatus];
    }
}

- (void)postCustomData:(NSString *)data {
    if (_blufiClient && data != nil) {
        [_blufiClient postCustomData:[data dataUsingEncoding:NSUTF8StringEncoding]];
    }
}

- (NSMutableDictionary *)dataDictionary {
    if (!_peripheralDictionary) {
        _peripheralDictionary = [[NSMutableDictionary alloc] init];
    }
    return _peripheralDictionary;
}

#pragma mark - CBCentralManagerDelegate

- (void)centralManager:(CBCentralManager *)central didConnectPeripheral:(CBPeripheral *)peripheral {
    [self sendEvent:[self makeEventWithKey:@"peripheral_connected" value:@"1"]];
}

- (void)centralManager:(CBCentralManager *)central didFailToConnectPeripheral:(CBPeripheral *)peripheral error:(NSError *)error {
    [self sendEvent:[self makeEventWithKey:@"peripheral_disconnected" value:@"1"]];
    self.connected = NO;
}

- (void)centralManager:(CBCentralManager *)central didDisconnectPeripheral:(CBPeripheral *)peripheral error:(NSError *)error {
    [self onDisconnected];
    [self sendEvent:[self makeEventWithKey:@"peripheral_disconnected" value:@"1"]];
    self.connected = NO;
}

- (void)centralManagerDidUpdateState:(CBCentralManager *)central {
}

#pragma mark - BlufiDelegate

- (void)blufi:(BlufiClient *)client gattPrepared:(BlufiStatusCode)status service:(CBService *)service writeChar:(CBCharacteristic *)writeChar notifyChar:(CBCharacteristic *)notifyChar {
    if (status == StatusSuccess) {
        self.connected = YES;
        [self sendEvent:[self makeEventWithKey:@"gatt_prepared" value:@"1"]];
    } else {
        [self onDisconnected];
        [self sendEvent:[self makeEventWithKey:@"gatt_prepared" value:@"0"]];
    }
}

- (void)blufi:(BlufiClient *)client didNegotiateSecurity:(BlufiStatusCode)status {
    [self sendEvent:[self makeEventWithKey:@"negotiate_security" value:(status == StatusSuccess ? @"1" : @"0")]];
}

- (void)blufi:(BlufiClient *)client didReceiveDeviceVersionResponse:(BlufiVersionResponse *)response status:(BlufiStatusCode)status {
    if (status == StatusSuccess) {
        [self sendEvent:[self makeEventWithKey:@"device_version" value:response.getVersionString]];
    } else {
        [self sendEvent:[self makeEventWithKey:@"device_version" value:@"0"]];
    }
}

- (void)blufi:(BlufiClient *)client didPostConfigureParams:(BlufiStatusCode)status {
    [self sendEvent:[self makeEventWithKey:@"configure_params" value:(status == StatusSuccess ? @"1" : @"0")]];
}

- (void)blufi:(BlufiClient *)client didReceiveDeviceStatusResponse:(BlufiStatusResponse *)response status:(BlufiStatusCode)status {
    if (status == StatusSuccess) {
        [self sendEvent:[self makeEventWithKey:@"device_status" value:@"1"]];
        [self sendEvent:[self makeEventWithKey:@"device_wifi_connect" value:([response isStaConnectWiFi] ? @"1" : @"0")]];
    } else {
        [self sendEvent:[self makeEventWithKey:@"device_status" value:@"0"]];
    }
}

- (void)blufi:(BlufiClient *)client didReceiveDeviceScanResponse:(NSArray<BlufiScanResponse *> *)scanResults status:(BlufiStatusCode)status {
    if (status == StatusSuccess) {
        for (BlufiScanResponse *response in scanResults) {
            [self sendEvent:[self makeWifiScanEventWithSsid:response.ssid rssi:response.rssi]];
        }
    } else {
        [self sendEvent:[self makeEventWithKey:@"wifi_scan_result" value:@"0"]];
    }
}

- (void)blufi:(BlufiClient *)client didPostCustomData:(nonnull NSData *)data status:(BlufiStatusCode)status {
    [self sendEvent:[self makeEventWithKey:@"post_custom_data" value:(status == StatusSuccess ? @"1" : @"0")]];
}

- (void)blufi:(BlufiClient *)client didReceiveCustomData:(NSData *)data status:(BlufiStatusCode)status {
    if (status == StatusSuccess) {
        NSString *customString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        [self sendEvent:[self makeEventWithKey:@"receive_custom_data" value:(customString ?: @"")]];
    } else {
        [self sendEvent:[self makeEventWithKey:@"receive_custom_data" value:@"0"]];
    }
}

#pragma mark - Method Channel

- (void)handleMethodCall:(FlutterMethodCall*)call result:(FlutterResult)result {
    if ([@"getPlatformVersion" isEqualToString:call.method]) {
        result([@"iOS " stringByAppendingString:[[UIDevice currentDevice] systemVersion]]);
    }
    else if ([@"scanDeviceInfo" isEqualToString:call.method]) {
        NSString *filter = call.arguments[@"filter"];
        if (filter != nil) {
            self.filterContent = filter;
        }
        [self scanDeviceInfo];
        result(@YES);
    }
    else if ([@"stopScan" isEqualToString:call.method]) {
        [self stopScan];
        result(nil);
    }
    else if ([@"connectPeripheral" isEqualToString:call.method]) {
        NSString *peripheral = call.arguments[@"peripheral"];
        ESPPeripheral *device = self.peripheralDictionary[peripheral];
        if (device != nil) {
            [self connectPeripheral:device];
            result(@YES);
        } else {
            result([FlutterError errorWithCode:@"DEVICE_NOT_FOUND"
                                       message:@"No scanned device with given address"
                                       details:nil]);
        }
    }
    else if ([@"requestCloseConnection" isEqualToString:call.method]) {
        [self requestCloseConnection];
        result(nil);
    }
    else if ([@"negotiateSecurity" isEqualToString:call.method]) {
        [self negotiateSecurity];
        result(nil);
    }
    else if ([@"requestDeviceVersion" isEqualToString:call.method]) {
        [self requestDeviceVersion];
        result(nil);
    }
    else if ([@"configProvision" isEqualToString:call.method]) {
        NSString *ssid = call.arguments[@"ssid"];
        if (ssid == nil) ssid = call.arguments[@"username"];
        NSString *password = call.arguments[@"password"];
        [self configProvisionWithSSID:ssid password:password];
        result(nil);
    }
    else if ([@"requestDeviceStatus" isEqualToString:call.method]) {
        [self requestDeviceStatus];
        result(nil);
    }
    else if ([@"requestDeviceWifiScan" isEqualToString:call.method]) {
        [self requestDeviceWifiScan];
        result(nil);
    }
    else if ([@"sendCustomData" isEqualToString:call.method]) {
        NSString *customData = call.arguments[@"data"];
        [self postCustomData:customData];
        result(nil);
    }
    else {
        result(FlutterMethodNotImplemented);
    }
}

@end

@implementation EspBlufiPluginStreamHandler

- (FlutterError*)onListenWithArguments:(id)arguments eventSink:(FlutterEventSink)eventSink {
    self.sink = eventSink;
    return nil;
}

- (FlutterError*)onCancelWithArguments:(id)arguments {
    self.sink = nil;
    return nil;
}

@end
