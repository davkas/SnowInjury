//
//  AppDelegate.m
//  SnowInjuryTestApp
//
//  Created by davkas on 2016/10/31.
//  Copyright © 2016年 davkas. All rights reserved.
//

#import "AppDelegate.h"
#import "SnowInjury.h"
#import "SQRLDirectoryManager.h"
#import "SQRLUpdater.h"
#import "SQRLUpdate.h"
#import "SQRLDownloadedUpdate.h"
#import <ReactiveCocoa/EXTScope.h>
#import <ReactiveCocoa/ReactiveCocoa.h>
#import "TestAppConstants.h"
#import "SQRLShipItLauncher.h"
#import "SQRLTestUpdate.h"

@interface AppDelegate ()

@property (nonatomic, strong) SQRLUpdater *updater;
@property (weak) IBOutlet NSWindow *window;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    NSString *bundlePath = [NSBundle bundleWithIdentifier:@"com.github.Squirrel.TestApplication"].bundlePath;
    NSString *logPath = [bundlePath.stringByDeletingLastPathComponent stringByAppendingPathComponent:@"TestApplication.log"];
    freopen(logPath.fileSystemRepresentation, "a+", stderr);
    
    NSLog(@"TestApplication launched at %@", bundlePath);
    
    atexit_b(^{
        NSLog(@"TestApplication quitting");
    });
    
    SQRLDirectoryManager *directoryManager = [[SQRLDirectoryManager alloc] initWithApplicationIdentifier:SQRLShipItLauncher.shipItJobLabel];
    
    NSError *error = nil;
    BOOL removed = [[[directoryManager
                      shipItStateURL]
                     flattenMap:^(NSURL *stateURL) {
                         NSError *error = nil;
                         if (![NSFileManager.defaultManager removeItemAtURL:stateURL error:&error]) {
                             return [RACSignal error:error];
                         }
                         
                         return [RACSignal empty];
                     }]
                    waitUntilCompleted:&error];
    
    if (!removed) {
        NSLog(@"Could not remove all preferences for %@: %@", directoryManager, error);
    }
    
    NSString *updateURLString = @"www.baidu.com";
    if (updateURLString == nil) {
        NSLog(@"Skipping update installation");
        return;
    }
    
    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:updateURLString]];
    self.updater = [[SQRLUpdater alloc] initWithUpdateRequest:request];
    self.updater.updateClass = SQRLTestUpdate.class;
    
    [RACObserve(self.updater, state) subscribeNext:^(NSNumber *state) {
        NSLog(@"State transition: %@", state);
        
        [NSDistributedNotificationCenter.defaultCenter postNotificationName:SQRLTestAppUpdaterStateTransitionNotificationName object:nil userInfo:@{ SQRLTestAppUpdaterStateKey: state }];
    }];
    
    __block NSUInteger updateCheckCount = 1;
    
    NSInteger updateRequestCount = [NSProcessInfo.processInfo.environment[@"SQRLUpdateRequestCount"] integerValue];
    if (updateRequestCount < 1) updateRequestCount = 1;
    
    [[[[[[[[[[RACSignal
              defer:^{
                  NSLog(@"***** UPDATE CHECK %lu *****", (unsigned long)updateCheckCount);
                  updateCheckCount++;
                  
                  return [self.updater.checkForUpdatesCommand execute:RACUnit.defaultUnit];
              }]
             doNext:^(SQRLDownloadedUpdate *update) {
                 NSLog(@"Got a candidate update: %@", update);
             }]
            // Retry until we get the expected release.
            repeat]
           skipUntilBlock:^(SQRLDownloadedUpdate *download) {
               SQRLTestUpdate *testUpdate = (id)download.update;
               NSAssert([testUpdate isKindOfClass:SQRLTestUpdate.class], @"Unexpected update type: %@", testUpdate);
               
               return testUpdate.final;
           }]
          take:updateRequestCount]
         doNext:^(id _) {
             NSLog(@"***** READY TO INSTALL UPDATE *****");
         }]
        timeout:10 onScheduler:RACScheduler.mainThreadScheduler]
       catch:^(NSError *error) {
           NSLog(@"Error in updater: %@", error);
           return [RACSignal empty];
       }]
      then:^{
          NSString *delayString = NSProcessInfo.processInfo.environment[@"SQRLUpdateDelay"];
          if (delayString == nil) return [RACSignal empty];
          
          return [[RACSignal interval:delayString.doubleValue onScheduler:RACScheduler.mainThreadScheduler] take:1];
      }]
     subscribeCompleted:^{
         [NSApp terminate:self];
     }];
}


- (void)applicationWillTerminate:(NSNotification *)aNotification {
    // Insert code here to tear down your application
}


@end
