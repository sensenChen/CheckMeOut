// ----------------------------------------------------------------------------
// Copyright (c) Microsoft Corporation. All rights reserved.
// ----------------------------------------------------------------------------

#import "ZumoPushTests.h"
#import "ZumoTest.h"
#import "ZumoTestGlobals.h"

// Helper class which will receive the push requests, and call a callback either
// after a timer ends or after a push notification is received.
@interface ZumoPushClient : NSObject <PushNotificationReceiver>
{
    NSTimer *timer;
}

@property (nonatomic, readonly, weak) ZumoTest *test;
@property (nonatomic, readonly, strong) ZumoTestCompletion completion;
@property (nonatomic, readonly, strong) NSDictionary *payload;

@end

@implementation ZumoPushClient

@synthesize test = _test, completion = _completion;

- (id)initForTest:(__weak ZumoTest*)test withPayload:(NSDictionary *)payload waitFor:(NSTimeInterval)seconds withTestCompletion:(ZumoTestCompletion)completion {
    self = [super init];
    if (self) {
        _test = test;
        _completion = completion;
        _payload = [payload copy];
        timer = [NSTimer scheduledTimerWithTimeInterval:seconds target:self selector:@selector(timerFired:) userInfo:nil repeats:NO];
        [[ZumoTestGlobals sharedInstance] setPushNotificationDelegate:self];
    }
    
    return self;
}

- (void)timerFired:(NSTimer *)theTimer {
    if (_payload) {
        [_test addLog:@"Push notification not received within the allowed time. Need to retry?"];
        [_test setTestStatus:TSFailed];
        _completion(NO);
    } else {
        [_test addLog:@"Push notification not received for invalid payload - success."];
        [_test setTestStatus:TSPassed];
        _completion(YES);
    }
}

- (void)pushReceived:(NSDictionary *)userInfo {
    [timer invalidate];
    [_test addLog:[NSString stringWithFormat:@"Push notification received: %@", userInfo]];
    if (_payload) {

        if ([self compareExpectedPayload:_payload withActual:userInfo]) {
            [_test setTestStatus:TSPassed];
            _completion(YES);
        } else {
            [_test addLog:[NSString stringWithFormat:@"Error, payloads are different. Expected: %@, actual: %@", _payload, userInfo]];
            [_test setTestStatus:TSFailed];
            _completion(NO);
        }
    } else {
        [_test addLog:@"This is a negative test, the payload should not have been received!"];
        [_test setTestStatus:TSFailed];
        _completion(NO);
    }
}

- (BOOL)compareExpectedPayload:(NSDictionary *)expected withActual:(NSDictionary *)actual {
    BOOL allEqual = YES;
    for (NSString *key in [expected keyEnumerator]) {
        id actualValue = actual[key];
        if (!actualValue) {
            allEqual = NO;
            [_test addLog:[NSString stringWithFormat:@"Key %@ in the expected payload, but not in the push received", key]];
        } else {
            id expectedValue = [expected objectForKey:key];
            if ([actualValue isKindOfClass:[NSDictionary class]] && [expectedValue isKindOfClass:[NSDictionary class]]) {
                // Compare recursively
                if (![self compareExpectedPayload:(NSDictionary *)expectedValue withActual:(NSDictionary *)actualValue]) {
                    [_test addLog:[NSString stringWithFormat:@"Value for key %@ in the expected payload is different than the one on the push received", key]];
                    allEqual = NO;
                }
            } else {
                // Use simple comparison
                if (![expectedValue isEqual:actualValue]) {
                    [_test addLog:[NSString stringWithFormat:@"Value for key %@ in the expected payload (%@) is different than the one on the push received (%@)", key, expectedValue, actualValue]];
                    allEqual = NO;
                }
            }
        }
    }
    
    if (allEqual) {
        for (NSString *key in [actual keyEnumerator]) {
            if (!expected[key]) {
                allEqual = NO;
                [_test addLog:[NSString stringWithFormat:@"Key %@ in the push received, but not in the expected payload", key]];
            }
        }
    }
    
    return allEqual;
}

@end

// Main implementation
@implementation ZumoPushTests

static NSString *tableName = @"iosPushTest";
static NSString *pushClientKey = @"PushClientKey";

+ (NSArray *)createTests {
    NSMutableArray *result = [[NSMutableArray alloc] init];
    if ([self isRunningOnSimulator]) {
        [result addObject:[ZumoTest createTestWithName:@"No push on simulator" andExecution:^(ZumoTest *test, UIViewController *viewController, ZumoTestCompletion completion) {
            [test addLog:@"Running on a simulator, no push tests can be executed"];
            [test setTestStatus:TSPassed];
            completion(YES);
        }]];
    } else {
        [result addObject:[self createValidatePushRegistrationTest]];
        
        if (![ZumoPushTests isNhEnabled]) {
            [result addObject:[self createFeedbackTest]];
        }
        
        [result addObject:[self createPushTestWithName:@"Push simple alert" forPayload:@{@"alert":@"push received"} expectedPayload:@{@"aps":@{@"alert":@"push received"}} withDelay:0]];
        [result addObject:[self createPushTestWithName:@"Push simple badge" forPayload:@{@"badge":@9} expectedPayload:@{@"aps":@{@"badge":@9}} withDelay:0]];
        [result addObject:[self createPushTestWithName:@"Push simple sound and alert" forPayload:@{@"alert":@"push received",@"sound":@"default"} expectedPayload:@{@"aps":@{@"alert":@"push received",@"sound":@"default"}} withDelay:0]];
        [result addObject:[self createPushTestWithName:@"Push alert with loc info and parameters" forPayload:@{@"alert":@{@"loc-key":@"LOC_STRING",@"loc-args":@[@"first",@"second"]}} expectedPayload:@{@"aps":@{@"alert":@{@"loc-key":@"LOC_STRING",@"loc-args":@[@"first",@"second"]}}} withDelay:0]];
        [result addObject:[self createPushTestWithName:@"Push with only custom info (no alert / badge / sound)" forPayload:@{@"aps":@{},@"foo":@"bar"} expectedPayload:@{@"aps":@{},@"foo":@"bar"} withDelay:0]];
        [result addObject:[self createPushTestWithName:@"Push with alert, badge and sound" forPayload:@{@"aps":@{@"alert":@"simple alert", @"badge":@7, @"sound":@"default"},@"custom":@"value"} expectedPayload:@{@"aps":@{@"alert":@"simple alert", @"badge":@7, @"sound":@"default"},@"custom":@"value"} withDelay:0]];
        [result addObject:[self createPushTestWithName:@"Push with alert with non-ASCII characters" forPayload:@{@"alert":@"Latin-ãéìôü ÇñÑ, arabic-لكتاب على الطاولة, chinese-这本书在桌子上"} expectedPayload:@{@"aps":@{@"alert":@"Latin-ãéìôü ÇñÑ, arabic-لكتاب على الطاولة, chinese-这本书在桌子上"}} withDelay:0]];
    
        [result addObject:[self createPushTestWithName:@"(Neg) Push with large payload" forPayload:@{@"alert":[@"" stringByPaddingToLength:256 withString:@"*" startingAtIndex:0]} expectedPayload:nil withDelay:0]];
    }
    
    return result;
}

+ (BOOL)isNhEnabled {
    NSDictionary *runtimeFeatures = [[[ZumoTestGlobals sharedInstance] globalTestParameters] objectForKey:RUNTIME_FEATURES_KEY];
    NSNumber *nhEnabledPropertyNames = [runtimeFeatures objectForKey:FEATURE_NH_PUSH_ENABLED];
    return [nhEnabledPropertyNames boolValue];
}

+ (BOOL)isRunningOnSimulator {
    NSString *deviceModel = [[UIDevice currentDevice] model];
    if ([deviceModel rangeOfString:@"Simulator" options:NSCaseInsensitiveSearch].location == NSNotFound) {
        return NO;
    } else {
        return YES;
    }
}

+ (ZumoTest *)createValidatePushRegistrationTest {
    ZumoTest *result = [ZumoTest createTestWithName:@"Validate push registration" andExecution:^(ZumoTest *test, UIViewController *viewController, ZumoTestCompletion completion) {
        if ([self isRunningOnSimulator]) {
            [test addLog:@"Test running on a simulator, skipping test."];
            [test setTestStatus:TSSkipped];
            completion(YES);
            return;
        }
        
        ZumoTestGlobals *globals = [ZumoTestGlobals sharedInstance];
        [test addLog:[globals remoteNotificationRegistrationStatus]];
        if ([globals deviceToken]) {
            [test addLog:[NSString stringWithFormat:@"Device token: %@", [globals deviceToken]]];
            [test setTestStatus:TSPassed];
            completion(YES);
        } else {
            UIAlertView *av = [[UIAlertView alloc] initWithTitle:@"Error" message:@"Push tests will not work on the emulator; if this is the case, all subsequent tests will fail, and that's expected." delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
            [av show];
            [test setTestStatus:TSFailed];
            completion(NO);
        }
    }];
    
    return result;
}

+ (void)sendNotificationViaInsert:(MSClient *)client test:(ZumoTest *)test seconds:(int)seconds deviceToken:(NSString *)deviceToken payload:(NSDictionary *)payload expectedPayload:(NSDictionary *)expectedPayload completion:(ZumoTestCompletion)completion {
    MSTable *table = [client tableWithName:tableName];
    NSURL *appUrl = [client applicationURL];
    [test addLog:[NSString stringWithFormat:@"Sending a request to %@ / table %@", [appUrl description], tableName]];
    NSDictionary *item = @{@"method" : @"send", @"payload" : payload, @"token": deviceToken, @"delay": @(seconds)};
    [table insert:item completion:^(NSDictionary *insertedItem, NSError *error) {
        if (error) {
            [test addLog:[NSString stringWithFormat:@"Error requesting push: %@", error]];
            [test setTestStatus:TSFailed];
            completion(NO);
        } else {
            NSTimeInterval timeToWait = 15;
            ZumoPushClient *pushClient = [[ZumoPushClient alloc] initForTest:test withPayload:expectedPayload waitFor:timeToWait withTestCompletion:completion];
            [[test propertyBag] setValue:pushClient forKey:pushClientKey];
            
            // completion will be called on the push client...
        }
    }];
}

+ (ZumoTest *)createPushTestWithName:(NSString *)name forPayload:(NSDictionary *)payload expectedPayload:(NSDictionary *)expectedPayload withDelay:(int)seconds {
    ZumoTest *result = [ZumoTest createTestWithName:name andExecution:^(ZumoTest *test, UIViewController *viewController, ZumoTestCompletion completion) {
        if ([self isRunningOnSimulator]) {
            [test addLog:@"Test running on a simulator, skipping test."];
            [test setTestStatus:TSSkipped];
            completion(YES);
            return;
        }
        
        NSData *deviceToken = [[ZumoTestGlobals sharedInstance] deviceToken];
        NSString *deviceTokenString = [[deviceToken.description stringByReplacingOccurrencesOfString:@" " withString:@""] stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"<>"]];
        if (!deviceToken) {
            [test addLog:@"Device not correctly registered for push"];
            [test setTestStatus:TSFailed];
            completion(NO);
        } else {
            MSClient *client = [[ZumoTestGlobals sharedInstance] client];
            if ([ZumoPushTests isNhEnabled]) {
                [client.push registerNativeWithDeviceToken:deviceToken tags:@[deviceTokenString] completion:^(NSError *error) {
                    if (error) {
                        [test addLog:[NSString stringWithFormat:@"Encountered error registering with Mobile Service: %@", error.description]];
                        [test setTestStatus:TSFailed];
                        completion(NO);
                        return;
                    }
                    
                    [self sendNotificationViaInsert:client test:test seconds:seconds deviceToken:deviceTokenString payload:payload expectedPayload:expectedPayload completion:completion];
                }];
            } else {
                [self sendNotificationViaInsert:client test:test seconds:seconds deviceToken:deviceTokenString payload:payload expectedPayload:expectedPayload completion:completion];
            }
        }
    }];
    
    return result;
}

+ (ZumoTest *)createFeedbackTest {
    ZumoTest *result = [ZumoTest createTestWithName:@"Simple feedback test" andExecution:^(ZumoTest *test, UIViewController *viewController, ZumoTestCompletion completion) {
        if ([self isRunningOnSimulator]) {
            [test addLog:@"Test running on a simulator, skipping test."];
            [test setTestStatus:TSSkipped];
            completion(YES);
            return;
        }
        
        if ([ZumoPushTests isNhEnabled]) {
            [test addLog:@"Service has enhanced push enabled. Skipping feedback test."];
            [test setTestStatus:TSSkipped];
            completion(YES);
            return;
        }

        if (![[ZumoTestGlobals sharedInstance] deviceToken]) {
            [test addLog:@"Device not correctly registered for push"];
            [test setTestStatus:TSFailed];
            completion(NO);
        } else {
            MSClient *client = [[ZumoTestGlobals sharedInstance] client];
            MSTable *table = [client tableWithName:tableName];
            NSDictionary *item = @{@"method" : @"getFeedback"};
            [table insert:item completion:^(NSDictionary *item, NSError *error) {
                BOOL passed = NO;
                if (error) {
                    [test addLog:[NSString stringWithFormat:@"Error requesting feedback: %@", error]];
                } else {
                    NSArray *devices = item[@"devices"];
                    if (devices) {
                        [test addLog:[NSString stringWithFormat:@"Retrieved devices from feedback script: %@", devices]];
                        passed = YES;
                    } else {
                        [test addLog:[NSString stringWithFormat:@"No 'devices' field in response: %@", item]];
                    }
                }
                
                [test setTestStatus:(passed ? TSPassed : TSFailed)];
                completion(passed);
            }];
        }
    }];
    
    return result;
}

+ (NSString *)groupDescription {
    return @"Tests to validate that the server-side push module can correctly deliver messages to the iOS client.";
}

@end