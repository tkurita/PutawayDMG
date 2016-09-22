#import "AppDelegate.h"
#import "NSTask+SimpleTask.h"
#import "../DonationReminder/DonationReminder.h"

#define useLog 0

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
static BOOL ALREADY_LAUNCHED = NO;

NSString *findMountPoint(NSArray *systemEntities)
{
    NSString *mount_point = nil;
    for (NSDictionary *sys_entity in systemEntities) {
        mount_point = sys_entity[@"mount-point"];
        if (mount_point) {
                break;
            }
    }
    return mount_point;
}

NSArray *filterImageVolumes(NSArray *fselection, NSArray *mounted_images)
{
    NSMutableArray *target_images = [NSMutableArray array];
    for (NSString *a_path in fselection) {
        for (NSDictionary *mount_info in mounted_images) {
            for (NSDictionary *sys_entity in mount_info[@"system-entities"]) {
                NSString *mount_point = sys_entity[@"mount-point"];
                if (mount_point &&
                    ([a_path isEqualToString:mount_point] ||
                       [a_path hasPrefix:[mount_point stringByAppendingString:@"/"]])) {
                        NSMutableDictionary *mount_info_mod = [mount_info mutableCopy];
                        mount_info_mod[@"mount-point"] = mount_point;
                        mount_info_mod[@"dev-entry"] = sys_entity[@"dev-entry"];
                        [target_images addObject:mount_info_mod];
                        break;
                }
            }
        }
    }
    return target_images;
}

- (NSTask *)launchTaskWithWaiting:(NSString *)launchPath arguments:(NSArray *)args
{
    NSTask *a_task = [NSTask new];
    [a_task setLaunchPath:launchPath];
    [a_task setArguments:args];
    [a_task setStandardOutput:[NSPipe pipe]];
    [a_task setStandardError:[NSPipe pipe]];
    
    [a_task launch];
    /* 
     When a target disk image is obtained by an open panel not seletion in Finder,
     -waitUntilExit method cause unknown termination of this app.
     Use simple loop instead of -waitUntilExit method.
     */
    while (a_task.isRunning) usleep(200);
    return a_task;
}

- (NSArray *)listMountedDiskImages
{
    NSTask *a_task = [NSTask taskLaunchingWithPath:@"/usr/bin/hdiutil"
                                       arguments:@[@"info", @"-plist"]];
        
    NSDictionary *plist = [[a_task stdoutString] propertyList];
    NSArray *mounted_images = plist[@"images"];
    if (! [mounted_images count]) {
        NSAlert *alert = [NSAlert alertWithMessageText:
                                        NSLocalizedString(@"No disk image is mounted.", @"error message")
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
        NSString *mount_point = nil;
        for (NSDictionary *an_image in mntImages) {
            mount_point = findMountPoint(an_image[@"system-entities"]);
            if (mount_point) { // may some disk image is not mounted (ex. Flash Player updater)
                break;
            }
        }

        if (mount_point) {
            NSOpenPanel *open_panel = [NSOpenPanel openPanel];
            [open_panel setCanChooseDirectories:YES];
            [open_panel setCanChooseFiles:NO];        
            [open_panel setDirectoryURL:[NSURL fileURLWithPath:mount_point]];
            [open_panel setPrompt:NSLocalizedString(@"Choose a disk of a disk image", @"button in chooser")];
            if ([open_panel runModal] == NSFileHandlingPanelCancelButton ) {
                return NO;
            }
            NSArray *urls = [open_panel URLs];
            NSArray *selected_items = [urls map:^id(NSURL *url) {return [url path];}];
            target_volumes = filterImageVolumes(selected_items, mntImages);
        }
    }
    
    if (![target_volumes count]) {
        NSAlert *alert = [NSAlert alertWithMessageText:
                                        NSLocalizedString(@"Select a mounted disk image volume.", @"alert")
                                         defaultButton:@"OK"
                                       alternateButton:nil otherButton:nil informativeTextWithFormat:@""];
        [alert runModal];
        return NO;
    }
    
    NSUserNotificationCenter *uncenter = [NSUserNotificationCenter defaultUserNotificationCenter];
    
    for (NSDictionary *mount_info in target_volumes) {
        NSUserNotification *unotification = [NSUserNotification new];
        unotification.title = NSLocalizedString(@"Detaching", @"notification");
        NSString *mount_point = mount_info[@"mount-point"];
        unotification.informativeText = mount_point;
        [uncenter deliverNotification:unotification];
        NSString *dev_entry = mount_info[@"dev-entry"];
        
        NSTask *detach_task = [self launchTaskWithWaiting:@"/usr/bin/hdiutil"
                                                arguments:@[@"detach", dev_entry]];
        if ([detach_task terminationStatus] != 0) {
            NSString *err_text = [[NSString alloc] initWithData:
                                   [[[detach_task standardError] fileHandleForReading] availableData]
                                                        encoding:NSUTF8StringEncoding];
            NSAlert *alert = [NSAlert alertWithMessageText:
                                    NSLocalizedString(@"Failed to detach a disk.", @"alert")
                                             defaultButton:@"OK"
                                           alternateButton:nil otherButton:nil
                                 informativeTextWithFormat:@"%@ : %@", mount_point, err_text];
            [alert runModal];
            return NO;
        }
        
        unotification = [NSUserNotification new];
        unotification.title = NSLocalizedString(@"Deleting a disk image", @"notification");
        CFDataRef bookmark_data = CFURLCreateBookmarkDataFromAliasRecord(kCFAllocatorDefault,
                                                        (__bridge CFDataRef)mount_info[@"image-alias"]);
        Boolean isState;
        CFErrorRef error = NULL;
        NSURL *image_alias = (__bridge_transfer NSURL *)CFURLCreateByResolvingBookmarkData(
                                                            kCFAllocatorDefault, bookmark_data,
                                                                  0, NULL, NULL, &isState, &error);
        if (error) {
            CFShow(error);
            return NO;
        }
        
        NSString *image_path = [image_alias path];
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

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)theApplication
{
#if useLog
	NSLog(@"applicationShouldTerminateAfterLastWindowClosed");
#endif
    NSArray *wins = [NSApp windows];
    // even a window of DonationReminder is remained, this method will be called.
    // then check visivility of all windows.
#if useLog
    NSLog(@"Number of windows : %d", [wins count]);
#endif
    for (NSWindow *a_win in wins) {
        if ([a_win isVisible]) return NO;
    }
    return YES;
}

- (void)terminateIfNoWindows
{
    if ([self applicationShouldTerminateAfterLastWindowClosed:NSApp]) {
        [NSApp terminate:self];
    }
}


- (void)preformPutawaySelection
{
    NSArray *mounted_images = [self listMountedDiskImages];
    if (mounted_images) {
        NSArray *fsel_array = [asBridgeInstance selectionInFinder];
#if useLog
        NSLog(@"Finder Selection : %@", fsel_array);
#endif
        if ([fsel_array count]) {
            [self proceessWithSelection:fsel_array mountedImages:mounted_images];
        }
    }
    ALREADY_LAUNCHED = YES;
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
#if useLog
	NSLog(@"applicationDidFinishLaunching");
#endif
    NSUserNotificationCenter *user_notification_center = [NSUserNotificationCenter defaultUserNotificationCenter];
    //[user_notification_center setDelegate:self];
	[DonationReminder remindDonation];

    
    NSDictionary *user_info = aNotification.userInfo;
#if useLog
    NSLog(@"aNotification.userInfo : %@", user_info);
#endif
    NSUserNotification *user_notification = [user_info objectForKey:NSApplicationLaunchUserNotificationKey];
    if (user_notification) {
#if useLog
        NSLog(@"UserNotification : %@", user_notification);
        NSLog(@"userInfo : %@", user_notification.userInfo);
#endif
        [user_notification_center removeDeliveredNotification:user_notification];
        ALREADY_LAUNCHED = YES;
    } else if([[user_info objectForKey:NSApplicationLaunchIsDefaultLaunchKey] boolValue]) {
        // sometime NSApplicationLaunchIsDefaultLaunchKey is NO, even if AppleEvent is kAEOpenApplication.
        [self preformPutawaySelection];
    } else {
        // launched to open or print a file, to perform a Service action
        NSAppleEventDescriptor *ev = [[NSAppleEventManager sharedAppleEventManager] currentAppleEvent];
        NSAppleEventDescriptor *prop_data;
        switch ([ev eventID]) {
            case kAEOpenDocuments:
#if useLog
                NSLog(@"kAEOpenDocuments");
#endif
                break;
            case kAEOpenApplication:
#if useLog
                NSLog(@"kAEOpenApplication : %@", [ev paramDescriptorForKeyword:keyAEPropData]);
#endif
                prop_data = [ev paramDescriptorForKeyword:keyAEPropData];
                if (prop_data) {
                    switch([prop_data enumCodeValue]) {
                        case keyAELaunchedAsLogInItem:
                        case keyAELaunchedAsServiceItem:
                            return;
                    }
                } else {
                    [self preformPutawaySelection];
                }
                break;
        }
    } 
    
    // for when the DonationReminder window is not opened.
    [self terminateIfNoWindows];
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
        NSLog(@"No mounted disk images");
        return;
    }
    NSArray *target_volumes = filterImageVolumes(filenames, mounted_images);
    if (![target_volumes count]) {
        NSLog(@"Can't find a image file corresponding to the selection");
        return;
    }
    
    for (NSDictionary *mount_info in target_volumes) {
        CFDataRef bookmark_data = CFURLCreateBookmarkDataFromAliasRecord(kCFAllocatorDefault,
                                                      (__bridge CFDataRef)mount_info[@"image-alias"]);
        Boolean isState;
        CFErrorRef error = NULL;
        NSURL *image_alias = (__bridge_transfer NSURL *)CFURLCreateByResolvingBookmarkData(
                                                                kCFAllocatorDefault, bookmark_data,
                                                                  0, NULL, NULL, &isState, &error);
        if (error) {
            CFShow(error);
            return;
        }
        NSString *image_path = [image_alias path];
        [[NSWorkspace sharedWorkspace] selectFile:image_path inFileViewerRootedAtPath:@""];
    }
    
    if (!ALREADY_LAUNCHED) {
        [self terminateIfNoWindows];
    }
}

- (IBAction)makeDonation:(id)sender
{
    [DonationReminder goToDonation];
}

@end
