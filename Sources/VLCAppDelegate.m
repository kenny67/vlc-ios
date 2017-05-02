/*****************************************************************************
 * VLCAppDelegate.m
 * VLC for iOS
 *****************************************************************************
 * Copyright (c) 2013-2015 VideoLAN. All rights reserved.
 * $Id$
 *
 * Authors: Felix Paul Kühne <fkuehne # videolan.org>
 *          Gleb Pinigin <gpinigin # gmail.com>
 *          Jean-Romain Prévost <jr # 3on.fr>
 *          Luis Fernandes <zipleen # gmail.com>
 *          Carola Nitz <nitz.carola # googlemail.com>
 *          Tamas Timar <ttimar.vlc # gmail.com>
 *          Tobias Conradi <videolan # tobias-conradi.de>
 *
 * Refer to the COPYING file of the official project for license.
 *****************************************************************************/

#import "VLCAppDelegate.h"
#import "VLCMediaFileDiscoverer.h"
#import "NSString+SupportedMedia.h"
#import "UIDevice+VLC.h"
#import "VLCLibraryViewController.h"
#import "VLCHTTPUploaderController.h"
#import "VLCMigrationViewController.h"
#import <BoxSDK/BoxSDK.h>
#import "VLCPlaybackController.h"
#import "VLCPlaybackController+MediaLibrary.h"
#import "VLCPlayerDisplayController.h"
#import <MediaPlayer/MediaPlayer.h>
#import <DropboxSDK/DropboxSDK.h>
#import <HockeySDK/HockeySDK.h>
#import "VLCSidebarController.h"
#import "VLCKeychainCoordinator.h"
#import "VLCActivityManager.h"
#import "GTScrollNavigationBar.h"

NSString *const VLCDropboxSessionWasAuthorized = @"VLCDropboxSessionWasAuthorized";

#define BETA_DISTRIBUTION 1

@interface VLCAppDelegate () <VLCMediaFileDiscovererDelegate>
{
    BOOL _passcodeValidated;
    BOOL _isRunningMigration;
    BOOL _isComingFromHandoff;
    VLCWatchCommunication *_watchCommunication;
}

@end

@implementation VLCAppDelegate

+ (void)initialize
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

    NSNumber *skipLoopFilterDefaultValue;
    int deviceSpeedCategory = [[UIDevice currentDevice] VLCSpeedCategory];
    if (deviceSpeedCategory < 3)
        skipLoopFilterDefaultValue = kVLCSettingSkipLoopFilterNonKey;
    else
        skipLoopFilterDefaultValue = kVLCSettingSkipLoopFilterNonRef;

    NSDictionary *appDefaults = @{kVLCSettingPasscodeAllowTouchID : @(1),
                                  kVLCSettingContinueAudioInBackgroundKey : @(YES),
                                  kVLCSettingStretchAudio : @(NO),
                                  kVLCSettingTextEncoding : kVLCSettingTextEncodingDefaultValue,
                                  kVLCSettingSkipLoopFilter : skipLoopFilterDefaultValue,
                                  kVLCSettingSubtitlesFont : kVLCSettingSubtitlesFontDefaultValue,
                                  kVLCSettingSubtitlesFontColor : kVLCSettingSubtitlesFontColorDefaultValue,
                                  kVLCSettingSubtitlesFontSize : kVLCSettingSubtitlesFontSizeDefaultValue,
                                  kVLCSettingSubtitlesBoldFont: kVLCSettingSubtitlesBoldFontDefaultValue,
                                  kVLCSettingDeinterlace : kVLCSettingDeinterlaceDefaultValue,
                                  kVLCSettingHWDecoding : kVLCSettingHWDecodingDefault,
                                  kVLCSettingNetworkCaching : kVLCSettingNetworkCachingDefaultValue,
                                  kVLCSettingVolumeGesture : @(YES),
                                  kVLCSettingPlayPauseGesture : @(YES),
                                  kVLCSettingBrightnessGesture : @(YES),
                                  kVLCSettingSeekGesture : @(YES),
                                  kVLCSettingCloseGesture : @(YES),
                                  kVLCSettingVariableJumpDuration : @(NO),
                                  kVLCSettingVideoFullscreenPlayback : @(YES),
                                  kVLCSettingContinuePlayback : @(1),
                                  kVLCSettingContinueAudioPlayback : @(1),
                                  kVLCSettingFTPTextEncoding : kVLCSettingFTPTextEncodingDefaultValue,
                                  kVLCSettingWiFiSharingIPv6 : kVLCSettingWiFiSharingIPv6DefaultValue,
                                  kVLCSettingEqualizerProfile : kVLCSettingEqualizerProfileDefaultValue,
                                  kVLCSettingPlaybackForwardSkipLength : kVLCSettingPlaybackForwardSkipLengthDefaultValue,
                                  kVLCSettingPlaybackBackwardSkipLength : kVLCSettingPlaybackBackwardSkipLengthDefaultValue,
                                  kVLCSettingOpenAppForPlayback : kVLCSettingOpenAppForPlaybackDefaultValue,
                                  kVLCAutomaticallyPlayNextItem : @(YES)};
    [defaults registerDefaults:appDefaults];
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    BITHockeyManager *hockeyManager = [BITHockeyManager sharedHockeyManager];
    [hockeyManager configureWithBetaIdentifier:@"0114ca8e265244ce588d2ebd035c3577"
                                liveIdentifier:@"c95f4227dff96c61f8b3a46a25edc584"
                                      delegate:nil];

    // Configure the SDK in here only!
    [hockeyManager startManager];
    [hockeyManager.authenticator authenticateInstallation];

    /* listen to validation notification */
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(passcodeWasValidated:)
                                                 name:VLCPasscodeValidated
                                               object:nil];

    // Change the keyboard for UISearchBar
    [[UITextField appearance] setKeyboardAppearance:UIKeyboardAppearanceDark];
    // For the cursor
    [[UITextField appearance] setTintColor:[UIColor VLCOrangeTintColor]];
    // Don't override the 'Cancel' button color in the search bar with the previous UITextField call. Use the default blue color
    [[UIBarButtonItem appearanceWhenContainedIn:[UISearchBar class], nil] setTitleTextAttributes:@{NSForegroundColorAttributeName: [UIColor colorWithRed:0.0 green:122.0/255.0 blue:1.0 alpha:1.0]} forState:UIControlStateNormal];
    // For the edit selection indicators
    [[UITableView appearance] setTintColor:[UIColor VLCOrangeTintColor]];

    [[UISwitch appearance] setOnTintColor:[UIColor VLCOrangeTintColor]];

    // Init the HTTP Server and clean its cache
    [[VLCHTTPUploaderController sharedInstance] cleanCache];

    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    // enable crash preventer
    void (^setupBlock)() = ^{
        _libraryViewController = [[VLCLibraryViewController alloc] init];
        VLCSidebarController *sidebarVC = [VLCSidebarController sharedInstance];
        VLCNavigationController *navCon = [[VLCNavigationController alloc] initWithNavigationBarClass: [GTScrollNavigationBar class] toolbarClass:nil];
        [navCon setViewControllers:@[_libraryViewController] animated:NO];

        sidebarVC.contentViewController = navCon;

        VLCPlayerDisplayController *playerDisplayController = [VLCPlayerDisplayController sharedInstance];
        playerDisplayController.childViewController = sidebarVC.fullViewController;

        self.window.rootViewController = playerDisplayController;
        [self.window makeKeyAndVisible];

        [self validatePasscode];

        BOOL spotlightEnabled = ![[VLCKeychainCoordinator defaultCoordinator] passcodeLockEnabled];
        [[MLMediaLibrary sharedMediaLibrary] setSpotlightIndexingEnabled:spotlightEnabled];
        [[MLMediaLibrary sharedMediaLibrary] applicationWillStart];

        VLCMediaFileDiscoverer *discoverer = [VLCMediaFileDiscoverer sharedInstance];
        NSArray *searchPaths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        discoverer.directoryPath = [searchPaths firstObject];
        [discoverer addObserver:self];
        [discoverer startDiscovering];
    };

    NSError *error = nil;

    if ([[MLMediaLibrary sharedMediaLibrary] libraryMigrationNeeded]){
        _isRunningMigration = YES;

        VLCMigrationViewController *migrationController = [[VLCMigrationViewController alloc] initWithNibName:@"VLCMigrationViewController" bundle:nil];
        migrationController.completionHandler = ^{

            //migrate
            setupBlock();
            _isRunningMigration = NO;
            [[MLMediaLibrary sharedMediaLibrary] updateMediaDatabase];
            [[VLCMediaFileDiscoverer sharedInstance] updateMediaList];
        };

        self.window.rootViewController = migrationController;
        [self.window makeKeyAndVisible];

    } else {
        if (error != nil) {
            APLog(@"removed persistentStore since it was corrupt");
            NSURL *storeURL = ((MLMediaLibrary *)[MLMediaLibrary sharedMediaLibrary]).persistentStoreURL;
            [[NSFileManager defaultManager] removeItemAtURL:storeURL error:&error];
        }
        setupBlock();
    }

    if ([VLCWatchCommunication isSupported]) {
        _watchCommunication = [VLCWatchCommunication sharedInstance];
        // TODO: push DB changes instead
        //    [_watchCommunication startRelayingNotificationName:NSManagedObjectContextDidSaveNotification object:nil];
        [_watchCommunication startRelayingNotificationName:VLCPlaybackControllerPlaybackMetadataDidChange object:nil];
    }

    /* add our static shortcut items the dynamic way to ease l10n and dynamic elements to be introduced later */
    if ([UIApplicationShortcutItem class] != nil) {
        if (application.shortcutItems == nil || application.shortcutItems.count < 4) {
            UIApplicationShortcutItem *localLibraryItem = [[UIApplicationShortcutItem alloc] initWithType:kVLCApplicationShortcutLocalLibrary
                                                                                           localizedTitle:NSLocalizedString(@"SECTION_HEADER_LIBRARY",nil)
                                                                                        localizedSubtitle:nil
                                                                                                     icon:[UIApplicationShortcutIcon iconWithTemplateImageName:@"AllFiles"]
                                                                                                 userInfo:nil];
            UIApplicationShortcutItem *localServerItem = [[UIApplicationShortcutItem alloc] initWithType:kVLCApplicationShortcutLocalServers
                                                                                           localizedTitle:NSLocalizedString(@"LOCAL_NETWORK",nil)
                                                                                        localizedSubtitle:nil
                                                                                                     icon:[UIApplicationShortcutIcon iconWithTemplateImageName:@"Local"]
                                                                                                 userInfo:nil];
            UIApplicationShortcutItem *openNetworkStreamItem = [[UIApplicationShortcutItem alloc] initWithType:kVLCApplicationShortcutOpenNetworkStream
                                                                                           localizedTitle:NSLocalizedString(@"OPEN_NETWORK",nil)
                                                                                        localizedSubtitle:nil
                                                                                                     icon:[UIApplicationShortcutIcon iconWithTemplateImageName:@"OpenNetStream"]
                                                                                                 userInfo:nil];
            UIApplicationShortcutItem *cloudsItem = [[UIApplicationShortcutItem alloc] initWithType:kVLCApplicationShortcutClouds
                                                                                           localizedTitle:NSLocalizedString(@"CLOUD_SERVICES",nil)
                                                                                        localizedSubtitle:nil
                                                                                                     icon:[UIApplicationShortcutIcon iconWithTemplateImageName:@"iCloudIcon"]
                                                                                                 userInfo:nil];
            application.shortcutItems = @[localLibraryItem, localServerItem, openNetworkStreamItem, cloudsItem];
        }
    }

    return YES;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Handoff

- (BOOL)application:(UIApplication *)application willContinueUserActivityWithType:(NSString *)userActivityType
{
    if ([userActivityType isEqualToString:kVLCUserActivityLibraryMode] ||
        [userActivityType isEqualToString:kVLCUserActivityPlaying] ||
        [userActivityType isEqualToString:kVLCUserActivityLibrarySelection])
        return YES;

    return NO;
}

- (BOOL)application:(UIApplication *)application
continueUserActivity:(NSUserActivity *)userActivity
 restorationHandler:(void (^)(NSArray *))restorationHandler
{
    NSString *userActivityType = userActivity.activityType;
    NSDictionary *dict = userActivity.userInfo;
    if([userActivityType isEqualToString:kVLCUserActivityLibraryMode] ||
       [userActivityType isEqualToString:kVLCUserActivityLibrarySelection]) {

        VLCLibraryMode libraryMode = (VLCLibraryMode)[(NSNumber *)dict[@"state"] integerValue];

        if (libraryMode <= VLCLibraryModeAllSeries) {
            [[VLCSidebarController sharedInstance] selectRowAtIndexPath:[NSIndexPath indexPathForRow:libraryMode inSection:0]
                                                         scrollPosition:UITableViewScrollPositionTop];
            [self.libraryViewController setLibraryMode:libraryMode];
        }

        [self.libraryViewController restoreUserActivityState:userActivity];
        _isComingFromHandoff = YES;
        return YES;
    } else {
        NSURL *uriRepresentation = nil;
        if ([userActivityType isEqualToString:CSSearchableItemActionType]) {
            uriRepresentation = [NSURL URLWithString:dict[CSSearchableItemActivityIdentifier]];
        } else {
            uriRepresentation = dict[@"playingmedia"];
        }

        if (!uriRepresentation) {
            return NO;
        }

        NSManagedObject *managedObject = [[MLMediaLibrary sharedMediaLibrary] objectForURIRepresentation:uriRepresentation];
        if (managedObject == nil) {
            APLog(@"%s file not found: %@",__PRETTY_FUNCTION__,userActivity);
            return NO;
        }
        [[VLCPlaybackController sharedInstance] openMediaLibraryObject:managedObject];
        return YES;
    }
    return NO;
}

- (void)application:(UIApplication *)application
didFailToContinueUserActivityWithType:(NSString *)userActivityType
              error:(NSError *)error
{
    if (error.code != NSUserCancelledError){
        //TODO: present alert
    }
}

- (BOOL)application:(UIApplication *)application
            openURL:(NSURL *)url
  sourceApplication:(NSString *)sourceApplication
         annotation:(id)annotation
{
    if ([[DBSession sharedSession] handleOpenURL:url]) {
        [[NSNotificationCenter defaultCenter] postNotificationName:VLCDropboxSessionWasAuthorized object:nil];
        return YES;
    }

    if (_libraryViewController && url != nil) {
        APLog(@"%@ requested %@ to be opened", sourceApplication, url);

        if (url.isFileURL) {
            NSArray *searchPaths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
            NSString *directoryPath = searchPaths[0];
            NSURL *destinationURL = [NSURL fileURLWithPath:[NSString stringWithFormat:@"%@/%@", directoryPath, url.lastPathComponent]];
            NSError *theError;
            [[NSFileManager defaultManager] moveItemAtURL:url toURL:destinationURL error:&theError];
            if (theError.code != noErr)
                APLog(@"saving the file failed (%li): %@", (long)theError.code, theError.localizedDescription);

            [[VLCMediaFileDiscoverer sharedInstance] updateMediaList];
        } else if ([url.scheme isEqualToString:@"vlc-x-callback"] || [url.host isEqualToString:@"x-callback-url"]) {
            // URL confirmes to the x-callback-url specification
            // vlc-x-callback://x-callback-url/action?param=value&x-success=callback
            APLog(@"x-callback-url with host '%@' path '%@' parameters '%@'", url.host, url.path, url.query);
            NSString *action = [url.path stringByReplacingOccurrencesOfString:@"/" withString:@""];
            NSURL *movieURL;
            NSURL *successCallback;
            NSURL *errorCallback;
            NSString *fileName;
            for (NSString *entry in [url.query componentsSeparatedByString:@"&"]) {
                NSArray *keyvalue = [entry componentsSeparatedByString:@"="];
                if (keyvalue.count < 2) continue;
                NSString *key = keyvalue[0];
                NSString *value = [keyvalue[1] stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];

                if ([key isEqualToString:@"url"])
                    movieURL = [NSURL URLWithString:value];
                else if ([key isEqualToString:@"filename"])
                    fileName = value;
                else if ([key isEqualToString:@"x-success"])
                    successCallback = [NSURL URLWithString:value];
                else if ([key isEqualToString:@"x-error"])
                    errorCallback = [NSURL URLWithString:value];
            }
            if ([action isEqualToString:@"stream"] && movieURL) {
                VLCPlaybackController *vpc = [VLCPlaybackController sharedInstance];
                vpc.fullscreenSessionRequested = YES;
                [vpc playURL:movieURL successCallback:successCallback errorCallback:errorCallback];
            }
            else if ([action isEqualToString:@"download"] && movieURL) {
                [self downloadMovieFromURL:movieURL fileNameOfMedia:fileName];
            }
        } else {
            NSString *receivedUrl = [url absoluteString];
            if ([receivedUrl length] > 6) {
                NSString *verifyVlcUrl = [receivedUrl substringToIndex:6];
                if ([verifyVlcUrl isEqualToString:@"vlc://"]) {
                    NSString *parsedString = [receivedUrl substringFromIndex:6];
                    NSUInteger location = [parsedString rangeOfString:@"//"].location;

                    /* Safari & al mangle vlc://http:// so fix this */
                    if (location != NSNotFound && [parsedString characterAtIndex:location - 1] != 0x3a) { // :
                            parsedString = [NSString stringWithFormat:@"%@://%@", [parsedString substringToIndex:location], [parsedString substringFromIndex:location+2]];
                    } else {
                        parsedString = [receivedUrl substringFromIndex:6];
                        if (![parsedString hasPrefix:@"http://"] && ![parsedString hasPrefix:@"https://"] && ![parsedString hasPrefix:@"ftp://"]) {
                            parsedString = [@"http://" stringByAppendingString:[receivedUrl substringFromIndex:6]];
                        }
                    }
                    url = [NSURL URLWithString:parsedString];
                }
            }
            [[VLCSidebarController sharedInstance] selectRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]
                                                         scrollPosition:UITableViewScrollPositionNone];

            NSString *scheme = url.scheme;
            if ([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"] || [scheme isEqualToString:@"ftp"]) {
                VLCAlertView *alert = [[VLCAlertView alloc] initWithTitle:NSLocalizedString(@"OPEN_STREAM_OR_DOWNLOAD", nil) message:url.absoluteString cancelButtonTitle:NSLocalizedString(@"BUTTON_DOWNLOAD", nil) otherButtonTitles:@[NSLocalizedString(@"PLAY_BUTTON", nil)]];
                alert.completion = ^(BOOL cancelled, NSInteger buttonIndex) {
                    if (cancelled)
                        [self downloadMovieFromURL:url fileNameOfMedia:nil];
                    else {
                        VLCPlaybackController *vpc = [VLCPlaybackController sharedInstance];
                        [vpc playURL:url successCallback:nil errorCallback:nil];
                    }
                };
                [alert show];
            } else {
                VLCPlaybackController *vpc = [VLCPlaybackController sharedInstance];
                vpc.fullscreenSessionRequested = YES;
                [vpc playURL:url successCallback:nil errorCallback:nil];
            }
        }
        return YES;
    }
    return NO;
}

- (void)applicationWillEnterForeground:(UIApplication *)application
{
    [[MLMediaLibrary sharedMediaLibrary] applicationWillStart];
}

- (void)applicationWillResignActive:(UIApplication *)application
{
    _passcodeValidated = NO;
    [self.libraryViewController setEditing:NO animated:NO];
    [self validatePasscode];
    [[MLMediaLibrary sharedMediaLibrary] applicationWillExit];
}

- (void)applicationDidBecomeActive:(UIApplication *)application
{
    if (!_isRunningMigration && !_isComingFromHandoff) {
        [[MLMediaLibrary sharedMediaLibrary] updateMediaDatabase];
        [[VLCMediaFileDiscoverer sharedInstance] updateMediaList];
    } else if(_isComingFromHandoff) {
        _isComingFromHandoff = NO;
    }
}

- (void)applicationWillTerminate:(UIApplication *)application
{
    _passcodeValidated = NO;
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)application:(UIApplication *)application performActionForShortcutItem:(UIApplicationShortcutItem *)shortcutItem completionHandler:(void (^)(BOOL))completionHandler
{
    [[VLCSidebarController sharedInstance] performActionForShortcutItem:shortcutItem];
}

#pragma mark - media discovering

- (void)mediaFileAdded:(NSString *)fileName loading:(BOOL)isLoading
{
    if (!isLoading) {
        MLMediaLibrary *sharedLibrary = [MLMediaLibrary sharedMediaLibrary];
        [sharedLibrary addFilePaths:@[fileName]];

        /* exclude media files from backup (QA1719) */
        NSURL *excludeURL = [NSURL fileURLWithPath:fileName];
        [excludeURL setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:nil];

        // TODO Should we update media db after adding new files?
        [sharedLibrary updateMediaDatabase];
        [_libraryViewController updateViewContents];
    }
}

- (void)mediaFileDeleted:(NSString *)name
{
    [[MLMediaLibrary sharedMediaLibrary] updateMediaDatabase];
    [_libraryViewController updateViewContents];
}

- (void)mediaFilesFoundRequiringAdditionToStorageBackend:(NSArray<NSString *> *)foundFiles
{
    [[MLMediaLibrary sharedMediaLibrary] addFilePaths:foundFiles];
    [[(VLCAppDelegate *)[UIApplication sharedApplication].delegate libraryViewController] updateViewContents];
}

#pragma mark - pass code validation

- (void)passcodeWasValidated:(NSNotification *)aNotifcation
{
    _passcodeValidated = YES;
    [self.libraryViewController updateViewContents];
    if ([VLCPlaybackController sharedInstance].isPlaying)
        [[VLCPlayerDisplayController sharedInstance] pushPlaybackView];
}

- (BOOL)passcodeValidated
{
    return _passcodeValidated;
}

- (void)validatePasscode
{
    VLCKeychainCoordinator *keychainCoordinator = [VLCKeychainCoordinator defaultCoordinator];

    if (!_passcodeValidated && [keychainCoordinator passcodeLockEnabled]) {
        [[VLCPlayerDisplayController sharedInstance] dismissPlaybackView];

        [keychainCoordinator validatePasscode];
    } else {
        _passcodeValidated = YES;
        [self passcodeValidated];
    }
}

#pragma mark - download handling

- (void)downloadMovieFromURL:(NSURL *)url
             fileNameOfMedia:(NSString *)fileName
{
    [[VLCDownloadViewController sharedInstance] addURLToDownloadList:url fileNameOfMedia:fileName];
    [[VLCSidebarController sharedInstance] selectRowAtIndexPath:[NSIndexPath indexPathForRow:2 inSection:1]
                                                 scrollPosition:UITableViewScrollPositionNone];
}

#pragma mark - remote events pre 7.1

- (void)remoteControlReceivedWithEvent:(UIEvent *)event {
    [[VLCPlaybackController sharedInstance] remoteControlReceivedWithEvent:event];
}

#pragma mark - watch stuff
- (void)application:(UIApplication *)application
handleWatchKitExtensionRequest:(NSDictionary *)userInfo
              reply:(void (^)(NSDictionary *))reply
{
    if ([VLCWatchCommunication isSupported]) {
        [self.watchCommunication session:[WCSession defaultSession] didReceiveMessage:userInfo replyHandler:reply];
    }
}



@end
