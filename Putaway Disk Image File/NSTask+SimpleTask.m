#import "NSTask+SimpleTask.h"

@implementation NSTask (SimpleTask)
+ (NSTask *)taskLaunchingWithPath:(NSString *)launchPath arguments:(NSArray *)args
{
    NSTask *a_task = [[self new] autorelease];
    [a_task setLaunchPath:launchPath];
    [a_task setArguments:args];
    [a_task setStandardOutput:[NSPipe pipe]];
    [a_task setStandardError:[NSPipe pipe]];
    
    [a_task launch];
    [a_task waitUntilExit];
    return a_task;
}

- (NSString *)stdoutString
{
    return [[[NSString alloc] initWithData:
                           [[[self standardOutput] fileHandleForReading] availableData]
                                                encoding:NSUTF8StringEncoding] autorelease];
}

- (NSString *)stderrString
{
    return [[[NSString alloc] initWithData:
             [[[self standardError] fileHandleForReading] availableData]
                                  encoding:NSUTF8StringEncoding] autorelease];
}

@end
