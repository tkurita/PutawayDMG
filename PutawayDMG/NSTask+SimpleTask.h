#import <Foundation/Foundation.h>

@interface NSTask (SimpleTask)
+ (NSTask *)taskLaunchingWithPath:(NSString *)launchPath arguments:(NSArray *)args;
- (NSString *)stdoutString;
- (NSString *)stderrString;
@end
