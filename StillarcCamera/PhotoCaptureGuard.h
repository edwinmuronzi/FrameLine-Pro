#import <AVFoundation/AVFoundation.h>
NS_ASSUME_NONNULL_BEGIN
/// AVFoundation reports invalid photo requests using NSException, which Swift cannot catch.
@interface PhotoCaptureGuard : NSObject
+ (nullable NSString *)submitToOutput:(AVCapturePhotoOutput *)output
                            settings:(AVCapturePhotoSettings *)settings
                            delegate:(id<AVCapturePhotoCaptureDelegate>)delegate
    NS_SWIFT_NAME(submit(output:settings:delegate:));
@end
NS_ASSUME_NONNULL_END
