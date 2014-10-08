#import "AppDelegate.h"
#import "NSTask+SimpleTask.h"

#define useLog 1

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
            if ([a_path isEqualToString:mount_point]
                    || [a_path hasPrefix:[mount_point stringByAppendingString:@"/"]]) {
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

- (NSArray *)listMountedDiskImages
{
    NSTask *a_task = [NSTask taskLaunchingWithPath:@"/usr/bin/hdiutil"
                                       arguments:@[@"info", @"-plist"]];
        
    NSDictionary *plist = [[a_task stdoutString] propertyList];
    NSArray *mounted_images = plist[@"images"];
    if (! [mounted_images count]) {
        NSAlert *alert = [NSAlert alertWithMessageText:@"No disk image is mounted."
                                         defaultButton:@"OK"
                                       alternateButton:nil otherButton:nil informativeTextWithFormat:@""];
        [alert runModal];
        return nil;
    }
    return mounted_images;
}

- (BOOL)proceessWithSelection:(NSArray *)selection mountedImages:(NSArray *)mntImages
{
    NSArray *target_volumes = filterImageVolumes(selection, mntImages);
    if (![target_volumes count]) {
        NSOpenPanel *open_panel = [NSOpenPanel openPanel];
        [open_panel setCanChooseDirectories:YES];
        [open_panel setCanChooseFiles:NO];
        NSDictionary *first_image = mntImages[0];
        NSString *mount_point = first_image[@"system-entities"][0][@"mount-point"];
        [open_panel setDirectoryURL:[NSURL fileURLWithPath:mount_point]];
        [open_panel setPrompt:@"Choose a disk of a disk image" ];
        if ([open_panel runModal] == NSFileHandlingPanelCancelButton ) {
            return NO;
        }
        NSArray *urls = [open_panel URLs];
        NSArray *selected_items = [urls map:^id(NSURL *url) {return [url path];}];
        target_volumes = filterImageVolumes(selected_items, mntImages);
    }
    
    if (![target_volumes count]) {
        NSAlert *alert = [NSAlert alertWithMessageText:@"Select a mounted disk image volume."
                                         defaultButton:@"OK"
                                       alternateButton:nil otherButton:nil informativeTextWithFormat:@""];
        [alert runModal];
        return NO;
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
            return NO;
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
            return NO;
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
    return YES;
}

- (void)application:(NSApplication *)sender openFiles:(NSArray *)filenames
{
    NSArray *mounted_images = [self listMountedDiskImages];
    if (! mounted_images) {
        goto bail;
    }
    
    [self proceessWithSelection:filenames mountedImages:mounted_images];
    /*
     NSApplicationDelegateReplySuccess = 0,
     NSApplicationDelegateReplyCancel = 1,
     NSApplicationDelegateReplyFailure = 2
     */
bail:
    [NSApp replyToOpenOrPrint:NSApplicationDelegateReplySuccess];
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
#if useLog
	NSLog(@"applicationDidFinishLaunching");
#endif
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
        goto bail;
    }
    
    if (![[user_info objectForKey:NSApplicationLaunchIsDefaultLaunchKey] boolValue]) return;
    
    NSArray *mounted_images = [self listMountedDiskImages];
    if (! mounted_images) {
        goto bail;
    }
    
    NSArray *fsel_array = [ASBridge selectionInFinder];
#if useLog
    NSLog(@"Finder Selection : %@", fsel_array);
#endif
    [self proceessWithSelection:fsel_array mountedImages:mounted_images];
bail:
    
    [NSApp terminate:self];
}

- (void)applicationWillFinishLaunching:(NSNotification *)aNotification
{
#if useLog
	NSLog(@"applicationWillFinishLaunching");
#endif
	[NSApp setServicesProvider:self];
}

- (void)revealDiskImageFileFromPasteboard:(NSPasteboard *)pboard userData:(NSString *)data error:(NSString **)error
{
#if useLog
	NSLog(@"start revealDiskImageFile");
#endif
    NSArray *types = [pboard types];
	NSArray *filenames;
	if (![types containsObject:NSFilenamesPboardType]
		|| !(filenames = [pboard propertyListForType:NSFilenamesPboardType])) {
        *error = NSLocalizedString(@"Error: Pasteboard doesn't contain file paths.",
								   @"Pasteboard couldn't give string.");
        return;
    }
    
    NSArray *mounted_images = [self listMountedDiskImages];
    if (! mounted_images) {
        goto bail;
    }
    NSArray *target_volumes = filterImageVolumes(filenames, mounted_images);
    if (![target_volumes count]) {
        NSLog(@"Can't find a image file corresponding to the selection");
        goto bail;
    }
    
    for (NSDictionary *mount_info in target_volumes) {
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
        [[NSWorkspace sharedWorkspace] selectFile:image_path inFileViewerRootedAtPath:@""];
    }
	
bail:
    [NSApp terminate:self];
}

@end
