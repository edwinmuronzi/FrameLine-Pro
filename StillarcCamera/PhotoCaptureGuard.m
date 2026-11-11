#import "PhotoCaptureGuard.h"
@implementation PhotoCaptureGuard
+ (NSString *)submitToOutput:(AVCapturePhotoOutput *)output settings:(AVCapturePhotoSettings *)settings delegate:(id<AVCapturePhotoCaptureDelegate>)delegate {
    @try {
        [output capturePhotoWithSettings:settings delegate:delegate];
        return nil;
    } @catch (NSException *exception) {
        return [NSString stringWithFormat:@"%@: %@", exception.name, exception.reason ?: @"Photo request rejected"];
    }
}
@end
