#import "UmengCommonSdkPlugin.h"
#import <UMCommon/UMConfigure.h>
#import <UMCommon/MobClick.h>

@interface UMengflutterpluginForUMCommon : NSObject
@end
@implementation UMengflutterpluginForUMCommon

+ (BOOL)handleMethodCall:(FlutterMethodCall*)call result:(FlutterResult)result{
    BOOL resultCode = YES;
    if ([@"setLogEnabled" isEqualToString:call.method]) {
        [UMConfigure setLogEnabled:[((NSArray *)call.arguments)[0] boolValue]];
        result(nil);
    }
    else if ([@"initCommon" isEqualToString:call.method]){
        NSArray* arguments = (NSArray *)call.arguments;
        NSString* appkey = arguments[1];
        NSString* channel = arguments[2];
        [UMConfigure initWithAppkey:appkey channel:channel];
        result(nil);
    }
    else{
        resultCode = NO;
    }
    return resultCode;
}
@end

@interface UMengflutterpluginForAnalytics : NSObject
@end
@implementation UMengflutterpluginForAnalytics : NSObject

+ (BOOL)handleMethodCall:(FlutterMethodCall*)call result:(FlutterResult)result{
    BOOL resultCode = YES;
    NSArray* arguments = (NSArray *)call.arguments;
    if ([@"onEvent" isEqualToString:call.method]){
        NSString* eventName = arguments[0];
        NSDictionary* properties = arguments[1];
        [MobClick event:eventName attributes:properties];
        result(nil);
    }
    else if ([@"onProfileSignIn" isEqualToString:call.method]){
        NSString* userID = arguments[0];
        [MobClick profileSignInWithPUID:userID];
        result(nil);
    }
    else if ([@"onProfileSignOff" isEqualToString:call.method]){
        [MobClick profileSignOff];
        result(nil);
    }
    else if ([@"setPageCollectionModeAuto" isEqualToString:call.method]){
        [MobClick setAutoPageEnabled:YES];
        result(nil);
    }
    else if ([@"setPageCollectionModeManual" isEqualToString:call.method]){
        [MobClick setAutoPageEnabled:NO];
        result(nil);
    }
    else if ([@"onPageStart" isEqualToString:call.method]){
        NSString* pageName = arguments[0];
        [MobClick beginLogPageView:pageName];
        result(nil);
    }
    else if ([@"onPageEnd" isEqualToString:call.method]){
        NSString* pageName = arguments[0];
        [MobClick endLogPageView:pageName];
        result(nil);
    }
    else if ([@"reportError" isEqualToString:call.method]){
        NSLog(@"reportError API not existed ");
        result(nil);
     }
    else{
        resultCode = NO;
    }
    return resultCode;
}

@end

@implementation UmengCommonSdkPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  FlutterMethodChannel* channel = [FlutterMethodChannel
      methodChannelWithName:@"umeng_common_sdk"
            binaryMessenger:[registrar messenger]];
  UmengCommonSdkPlugin* instance = [[UmengCommonSdkPlugin alloc] init];
  [registrar addMethodCallDelegate:instance channel:channel];
}

- (void)handleMethodCall:(FlutterMethodCall*)call result:(FlutterResult)result {
  if ([@"getPlatformVersion" isEqualToString:call.method]) {
    result([@"iOS " stringByAppendingString:[[UIDevice currentDevice] systemVersion]]);
    return;
  } else {
    //result(FlutterMethodNotImplemented);
  }

    BOOL resultCode = [UMengflutterpluginForUMCommon handleMethodCall:call result:result];
    if (resultCode) return;

    resultCode = [UMengflutterpluginForAnalytics handleMethodCall:call result:result];
    if (resultCode) return;

    result(FlutterMethodNotImplemented);
}

@end
