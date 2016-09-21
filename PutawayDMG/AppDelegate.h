#import <Foundation/Foundation.h>

@interface ASBridge : NSObject
- (NSArray *)selectionInFinder;
@end

@interface AppDelegate : NSObject {
    IBOutlet ASBridge *asBridgeInstance;
}

@end
