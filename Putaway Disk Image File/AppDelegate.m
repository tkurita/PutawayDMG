#import "AppDelegate.h"

typedef id(^MapBlock)(id);
@interface NSArray (Map)
- (NSArray *)map:(MapBlock)block;
@end

@implementation NSArray (Map)
- (NSArray *)map:(MapBlock)block {
    NSMutableArray *resultArray = [[NSMutableArray alloc] init];
    for (id object in self) {
        [resultArray addObject:block(object)];
    }
    return resultArray;
}
@end

@implementation AppDelegate

NSArray *filterImageVolumes(NSArray *fselection, NSArray *mounted_images)
{
    NSMutableArray *target_images = [NSMutableArray array];
    for (NSString *a_path in fselection) {
        for (NSDictionary *mount_info in mounted_images) {
            NSString *mount_point = mount_info[@"system-entities"][0][@"mount-point"];
            if ([a_path hasPrefix:mount_point]) {
                [target_images addObject:mount_info];
                break;
            }
        }
    }
    return target_images;
}

- (NSTask *)launchTaskWithWaiting:(NSString *)launchPath arguments:(NSArray *)args
{
    NSTask *a_task = [[NSTask new] autorelease];
    [a_task setLaunchPath:launchPath];
    [a_task setArguments:args];
    [a_task setStandardOutput:[NSPipe pipe]];
    [a_task setStandardError:[NSPipe pipe]];
    
    [a_task launch];
    [a_task waitUntilExit];
    return a_task;
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    NSUserNotificationCenter *user_notification_center = [NSUserNotificationCenter defaultUserNotificationCenter];
    //[user_notification_center setDelegate:self];
	//[DonationReminder remindDonation];
    
    NSDictionary *user_info = aNotification.userInfo;
    NSUserNotification *user_notification = [user_info objectForKey:NSApplicationLaunchUserNotificationKey];
    if (user_notification) {
#if useLog
        NSLog(@"UserNotification : %@", user_notification);
        NSLog(@"userInfo : %@", user_notification.userInfo);
#endif
        [user_notification_center removeDeliveredNotification:user_notification];
        [NSApp terminate:self];
        goto bail;
    }
    
    //if (![[user_info objectForKey:NSApplicationLaunchIsDefaultLaunchKey] boolValue]) return;
    
    NSArray *mounted_images = [self listMountedDiskImages];
    if (! [mounted_images count]) {
        NSAlert *alert = [NSAlert alertWithMessageText:@"No disk image is mounted."
                                         defaultButton:@"OK"
                                       alternateButton:nil otherButton:nil informativeTextWithFormat:@""];
        [alert runModal];
        goto bail;
    }
    
    NSDictionary *first_image = mounted_images[0];
    NSString *mount_point = first_image[@"system-entities"][0][@"mount-point"];
    NSLog(@"%@", mount_point);
    NSArray *fsel_array = [ASBridge finderSelectionWithMountPoint:mount_point];
    NSLog(@"%@", fsel_array);
    NSArray *target_volumes = filterImageVolumes(fsel_array, mounted_images);
    if (![target_volumes count]) {
        NSOpenPanel *open_panel = [NSOpenPanel openPanel];
        [open_panel setCanChooseDirectories:YES];
        [open_panel setCanChooseFiles:NO];
        [open_panel setDirectoryURL:[NSURL fileURLWithPath:mount_point]];
        [open_panel setPrompt:@"Choose a disk of a disk image" ];
        if ([open_panel runModal] == NSFileHandlingPanelCancelButton ) {
            goto bail;
        }
        NSArray *urls = [open_panel URLs];
        NSArray *selected_items = [urls map:^id(NSURL *url) {return [url path];}];
        target_volumes = filterImageVolumes(selected_items, mounted_images);
    }
    
    if (![target_volumes count]) {
        NSAlert *alert = [NSAlert alertWithMessageText:@"Select a mounted disk image volume."
                                         defaultButton:@"OK"
                                      alternateButton:nil otherButton:nil informativeTextWithFormat:@""];
        [alert runModal];
        goto bail;
    }
    
    NSUserNotificationCenter *uncenter = [NSUserNotificationCenter defaultUserNotificationCenter];
    
    for (NSDictionary *mount_info in target_volumes) {
        NSUserNotification *unotification = [[NSUserNotification new] autorelease];
        unotification.title = @"Detaching";
        NSString *mount_point = mount_info[@"system-entities"][0][@"mount-point"];
        unotification.informativeText = mount_point;
        [uncenter deliverNotification:unotification];
        NSString *dev_entry = mount_info[@"system-entities"][0][@"dev-entry"];
       
        NSTask *detach_task = [self launchTaskWithWaiting:@"/usr/bin/hdiutil"
                                arguments:@[@"detach", dev_entry]];
        if ([detach_task terminationStatus] != 0) {
            NSString *err_text = [[[NSString alloc] initWithData:
                                   [[[detach_task standardError] fileHandleForReading] availableData]
                                                        encoding:NSUTF8StringEncoding] autorelease];
            NSAlert *alert = [NSAlert alertWithMessageText:@"Failed to detach a disk."
                                             defaultButton:@"OK"
                                           alternateButton:nil otherButton:nil
                                 informativeTextWithFormat:@"%@ : %@", mount_point, err_text];
            [alert runModal];
            goto bail;
        }
        
        unotification = [[NSUserNotification new] autorelease];
        unotification.title = @"Deleting a disk image"; 
        CFDataRef bookmark_data = CFURLCreateBookmarkDataFromAliasRecord(kCFAllocatorDefault,
                                                          (CFDataRef)mount_info[@"image-alias"]);
        Boolean isState;
        CFErrorRef error = NULL;
        CFURLRef image_alias = CFURLCreateByResolvingBookmarkData(kCFAllocatorDefault, bookmark_data,
                                                                  0, NULL, NULL, &isState, &error);
        if (error) {
            CFShow(error);
            goto bail;
        }
        NSString *image_path = [(NSURL *)image_alias path];
        unotification.informativeText = image_path;
        [uncenter deliverNotification:unotification];

        /*[[NSWorkspace sharedWorkspace] recycleURLs:@[(NSURL *)image_alias]
                                 completionHandler:^void(NSDictionary *newURLs, NSError *error) {
                                     NSLog(@"new URL : %@, error:%@", newURLs, error);
                                 }]; //sometimes does not work
         */
        
        [[NSWorkspace sharedWorkspace] performFileOperation:NSWorkspaceRecycleOperation
                                             source:[image_path stringByDeletingLastPathComponent]
                                                destination:@""
                                                      files:@[[image_path lastPathComponent]]
                                                        tag:nil];

    }
bail:
    
    [NSApp terminate:self];
}

- (NSArray *)listMountedDiskImages
{
    NSTask *a_task = [[NSTask new] autorelease];
    [a_task setLaunchPath:@"/usr/bin/hdiutil"];
    [a_task setArguments:@[@"info", @"-plist"]];
    NSPipe *out_pipe = [NSPipe pipe];
    NSFileHandle *stdout_handle = [out_pipe fileHandleForReading];
    NSPipe *err_pipe = [NSPipe pipe];
    //NSFileHandle  *stderr_handle = [err_pipe fileHandleForReading];
    [a_task setStandardOutput:out_pipe];
    [a_task setStandardError:err_pipe];
    
    [a_task launch];
    
    NSData *buff;
    NSMutableData *out_data = [NSMutableData data];
    while ((buff = [stdout_handle availableData]) && [buff length]) {
        [out_data appendData:buff];
    }
    
    NSString *stdout_string = [[NSString alloc] initWithData:out_data encoding:NSUTF8StringEncoding];
    NSDictionary *plist = [[stdout_string autorelease] propertyList];
    NSArray *mounted_images = plist[@"images"];
    //if (! [mouted_images count]) return nil;
    return mounted_images;
}


@end
