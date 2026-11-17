#import <React/RCTBridgeModule.h>
#import <React/RCTEventEmitter.h>
#import <React/RCTViewManager.h>

@interface RCT_EXTERN_MODULE(VavaNative, RCTEventEmitter)
RCT_EXTERN_METHOD(request:(NSString *)command payload:(NSDictionary *)payload resolver:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject)
@end

@interface RCT_EXTERN_MODULE(VavaVideoManager, RCTViewManager)
RCT_EXPORT_VIEW_PROPERTY(uri, NSString)
RCT_EXPORT_VIEW_PROPERTY(paused, BOOL)
RCT_EXPORT_VIEW_PROPERTY(seekFraction, double)
RCT_EXPORT_VIEW_PROPERTY(onProgress, RCTDirectEventBlock)
RCT_EXPORT_VIEW_PROPERTY(onError, RCTDirectEventBlock)
@end

@interface RCT_EXTERN_MODULE(VavaCallVideoManager, RCTViewManager)
@end

@interface RCT_EXTERN_MODULE(VavaLocalWebViewManager, RCTViewManager)
RCT_EXPORT_VIEW_PROPERTY(onMessage, RCTDirectEventBlock)
RCT_EXPORT_VIEW_PROPERTY(onFailure, RCTDirectEventBlock)
RCT_EXPORT_VIEW_PROPERTY(messages, NSString)
RCT_EXPORT_VIEW_PROPERTY(onDelivered, RCTDirectEventBlock)
@end
