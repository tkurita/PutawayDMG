#import "NSTask+SimpleTask.h"

@implementation NSTask (SimpleTask)

- (void)readStdout
{
	NSMutableData *stdoutData = [NSMutableData new];
	NSFileHandle *out_h = [[self standardOutput] fileHandleForReading];
	while(1) {
		//NSLog(@"will read");
		NSData *data_out = [out_h availableData];
		
		if ([data_out length]) {
			[stdoutData appendData:data_out];
		} else {
			break;
		}
	}
	
	[out_h closeFile];
}

+ (NSTask *)taskLaunchingWithPath:(NSString *)launchPath arguments:(NSArray *)args
{
    NSTask *a_task = [self new];
    [a_task setLaunchPath:launchPath];
    [a_task setArguments:args];
    [a_task setStandardOutput:[NSPipe pipe]];
    [a_task setStandardError:[NSPipe pipe]];
    
    [a_task launch];
    //[a_task readStdout];
    //[a_task waitUntilExit];
    return a_task;
}


- (NSString *)stdoutString
{

	NSMutableData *stdoutData = [NSMutableData new];
	NSFileHandle *out_h = [[self standardOutput] fileHandleForReading];
	while(1) {
		//NSLog(@"will read");
		NSData *data_out = [out_h availableData];
		
		if ([data_out length]) {
			[stdoutData appendData:data_out];
		} else {
			break;
		}
	}
//	[self waitUntilExit];
//    NSData *data_out = [out_h availableData];
//    
//    if ([data_out length]) {
//        [stdoutData appendData:data_out];
//    }
    
	[out_h closeFile];
    return [[NSString alloc] initWithData:stdoutData encoding:NSUTF8StringEncoding];
}


- (NSString *)stderrString
{
    return [[NSString alloc] initWithData:
             [[[self standardError] fileHandleForReading] availableData]
                                  encoding:NSUTF8StringEncoding];
}

@end
