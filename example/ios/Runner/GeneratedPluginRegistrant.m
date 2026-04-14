//
//  Generated file. Do not edit.
//

// clang-format off

#import "GeneratedPluginRegistrant.h"

#if __has_include(<esp_blufi/EspBlufiPlugin.h>)
#import <esp_blufi/EspBlufiPlugin.h>
#else
@import esp_blufi;
#endif

#if __has_include(<flutter_blue_plus_darwin/FlutterBluePlusPlugin.h>)
#import <flutter_blue_plus_darwin/FlutterBluePlusPlugin.h>
#else
@import flutter_blue_plus_darwin;
#endif

#if __has_include(<integration_test/IntegrationTestPlugin.h>)
#import <integration_test/IntegrationTestPlugin.h>
#else
@import integration_test;
#endif

#if __has_include(<reactive_ble_mobile/ReactiveBlePlugin.h>)
#import <reactive_ble_mobile/ReactiveBlePlugin.h>
#else
@import reactive_ble_mobile;
#endif

@implementation GeneratedPluginRegistrant

+ (void)registerWithRegistry:(NSObject<FlutterPluginRegistry>*)registry {
  [EspBlufiPlugin registerWithRegistrar:[registry registrarForPlugin:@"EspBlufiPlugin"]];
  [FlutterBluePlusPlugin registerWithRegistrar:[registry registrarForPlugin:@"FlutterBluePlusPlugin"]];
  [IntegrationTestPlugin registerWithRegistrar:[registry registrarForPlugin:@"IntegrationTestPlugin"]];
  [ReactiveBlePlugin registerWithRegistrar:[registry registrarForPlugin:@"ReactiveBlePlugin"]];
}

@end
