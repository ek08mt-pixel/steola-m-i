#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <StoreKit/StoreKit.h>
#import <UIKit/UIKit.h>

#pragma mark - Fake Transaction Class

@interface FakeSKPaymentTransaction : NSObject
@property (nonatomic, copy) NSString *productIdentifier;
@property (nonatomic, copy) NSString *transactionIdentifier;
@property (nonatomic, copy) NSDate *transactionDate;
@property (nonatomic, assign) NSInteger transactionState;
@property (nonatomic, strong) NSError *error;
@property (nonatomic, strong) NSData *transactionReceipt;
@property (nonatomic, strong) SKPayment *payment;
@end

@implementation FakeSKPaymentTransaction
- (instancetype)init {
    self = [super init];
    if (self) {
        _transactionState = 1;
        _transactionDate = [NSDate date];
        _transactionIdentifier = [[NSUUID UUID] UUIDString];
        _transactionReceipt = [NSData dataWithBytes:"receipt" length:7];
    }
    return self;
}
@end

#pragma mark - SKPaymentQueue Hooks

static void (*orig_addPayment)(id, SEL, SKPayment*);
static void hook_addPayment(id self, SEL _cmd, SKPayment *payment) {
    FakeSKPaymentTransaction *fake = [[FakeSKPaymentTransaction alloc] init];
    fake.productIdentifier = payment.productIdentifier;
    fake.payment = payment;
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        NSArray *observers = [self valueForKey:@"transactionObservers"];
        for (id obs in observers) {
            if ([obs respondsToSelector:@selector(paymentQueue:updatedTransactions:)]) {
                [obs paymentQueue:self updatedTransactions:@[fake]];
            }
        }
    });
}

static void (*orig_finish)(id, SEL, id);
static void hook_finish(id self, SEL _cmd, id t) {
    orig_finish(self, _cmd, t);
}

static id (*orig_transactions)(id, SEL);
static id hook_transactions(id self, SEL _cmd) {
    return @[];
}

#pragma mark - NSUserDefaults Hooks

static id (*orig_obj)(id, SEL, NSString*);
static id hook_obj(id self, SEL _cmd, NSString *k) {
    if (!k) return nil;
    NSString *l = [k lowercaseString];
    if ([l containsString:@"iap"]||[l containsString:@"purchase"]||[l containsString:@"unlock"]||
        [l containsString:@"premium"]||[l containsString:@"vip"]||[l containsString:@"pro"]||
        [l containsString:@"buy"]||[l containsString:@"paid"]||[l containsString:@"member"]||
        [l containsString:@"subscribe"]||[l containsString:@"coin"]||[l containsString:@"gem"]||
        [l containsString:@"diamond"]||[l containsString:@"gold"]||[l containsString:@"cash"]) {
        return @"1";
    }
    if ([l containsString:@"expire"]||[l containsString:@"end"]) return @(4102444800);
    if ([l containsString:@"level"]||[l containsString:@"tier"]) return @"999";
    return orig_obj ? orig_obj(self, _cmd, k) : nil;
}

static BOOL (*orig_bool)(id, SEL, NSString*);
static BOOL hook_bool(id self, SEL _cmd, NSString *k) {
    if (!k) return NO;
    NSString *l = [k lowercaseString];
    if ([l containsString:@"iap"]||[l containsString:@"purchase"]||[l containsString:@"unlock"]||
        [l containsString:@"premium"]||[l containsString:@"vip"]||[l containsString:@"pro"]||
        [l containsString:@"buy"]||[l containsString:@"paid"]||[l containsString:@"member"]||
        [l containsString:@"subscribe"]) return YES;
    return orig_bool ? orig_bool(self, _cmd, k) : NO;
}

static BOOL (*orig_sync)(id, SEL);
static BOOL hook_sync(id self, SEL _cmd) {
    return YES;
}

#pragma mark - NSURLSession Hook

static id (*orig_dataTask)(id, SEL, id, id);
static id hook_dataTask(id self, SEL _cmd, id request, id handler) {
    NSURL *url = [request valueForKey:@"URL"];
    NSString *str = [url absoluteString];
    NSString *lower = [str lowercaseString];
    
    if ([lower containsString:@"verifyreceipt"]||[lower containsString:@"/iap/"]||
        [lower containsString:@"/purchase/"]||[lower containsString:@"/buy/"]||
        [lower containsString:@"/payment/"]||[lower containsString:@"/order/"]||
        [lower containsString:@"/unlock/"]||[lower containsString:@"/premium/"]||
        [lower containsString:@"/vip/check"]||[lower containsString:@"/subscription/"]) {
        
        NSDictionary *fake = @{@"status":@0,@"code":@200,@"success":@YES,
            @"data":@{@"valid":@YES,@"purchased":@YES,@"unlocked":@YES,@"premium":@YES,@"vip":@YES}};
        NSData *data = [NSJSONSerialization dataWithJSONObject:fake options:0 error:nil];
        NSHTTPURLResponse *resp = [[NSHTTPURLResponse alloc] initWithURL:url statusCode:200 HTTPVersion:@"HTTP/1.1" headerFields:@{@"Content-Type":@"application/json"}];
        if (handler) {
            ((void(^)(NSData*,NSURLResponse*,NSError*))handler)(data, resp, nil);
        }
        return nil;
    }
    return orig_dataTask ? orig_dataTask(self, _cmd, request, handler) : nil;
}

#pragma mark - Runtime Class Hook

static void hookAllSelectors(void) {
    unsigned int count;
    Class *classes = objc_copyClassList(&count);
    const char *sels[] = {
        "isPurchased","isUnlocked","isPremium","hasPurchased","isIAPPurchased",
        "isProductPurchased","isItemUnlocked","isVIP","isVip","isPro","hasVIP",
        "hasPremium","hasSubscription","isSubscribed","isMember","isFeatureUnlocked",
        "isFullVersion","isPaidUser","isPremiumUser","hasValidSubscription",
        "isVIPActive","isVIPValid","canUseVIPFeature","hasVIPPermission",
        NULL
    };
    for (unsigned int i = 0; i < count; i++) {
        Class cls = classes[i];
        for (int j = 0; sels[j] != NULL; j++) {
            SEL s = sel_registerName(sels[j]);
            Method m = class_getInstanceMethod(cls, s);
            if (m) {
                method_setImplementation(m, imp_implementationWithBlock(^BOOL(id _self, SEL _cmd) { return YES; }));
            }
            m = class_getClassMethod(cls, s);
            if (m) {
                method_setImplementation(m, imp_implementationWithBlock(^BOOL(id _self, SEL _cmd) { return YES; }));
            }
        }
    }
    free(classes);
}

#pragma mark - Constructor

__attribute__((constructor))
static void IAPGodProInit(void) {
    @autoreleasepool {
        // SKPaymentQueue
        Class skq = [SKPaymentQueue class];
        Method m1 = class_getInstanceMethod(skq, @selector(addPayment:));
        if (m1) { orig_addPayment = (void*)method_getImplementation(m1); method_setImplementation(m1, (IMP)hook_addPayment); }
        Method m2 = class_getInstanceMethod(skq, @selector(finishTransaction:));
        if (m2) { orig_finish = (void*)method_getImplementation(m2); method_setImplementation(m2, (IMP)hook_finish); }
        Method m3 = class_getInstanceMethod(skq, @selector(transactions));
        if (m3) { orig_transactions = (void*)method_getImplementation(m3); method_setImplementation(m3, (IMP)hook_transactions); }
        
        // NSUserDefaults
        Class ud = [NSUserDefaults class];
        Method m4 = class_getInstanceMethod(ud, @selector(objectForKey:));
        if (m4) { orig_obj = (void*)method_getImplementation(m4); method_setImplementation(m4, (IMP)hook_obj); }
        Method m5 = class_getInstanceMethod(ud, @selector(boolForKey:));
        if (m5) { orig_bool = (void*)method_getImplementation(m5); method_setImplementation(m5, (IMP)hook_bool); }
        Method m6 = class_getInstanceMethod(ud, @selector(stringForKey:));
        if (m6) method_setImplementation(m6, (IMP)hook_obj);
        Method m7 = class_getInstanceMethod(ud, @selector(valueForKey:));
        if (m7) method_setImplementation(m7, (IMP)hook_obj);
        Method m8 = class_getInstanceMethod(ud, @selector(dictionaryForKey:));
        if (m8) method_setImplementation(m8, (IMP)hook_obj);
        Method m9 = class_getInstanceMethod(ud, @selector(integerForKey:));
        if (m9) method_setImplementation(m9, (IMP)hook_obj);
        Method m10 = class_getInstanceMethod(ud, @selector(synchronize));
        if (m10) { orig_sync = (void*)method_getImplementation(m10); method_setImplementation(m10, (IMP)hook_sync); }
        
        // NSURLSession
        Class session = [NSURLSession class];
        Method m11 = class_getInstanceMethod(session, @selector(dataTaskWithRequest:completionHandler:));
        if (m11) { orig_dataTask = (void*)method_getImplementation(m11); method_setImplementation(m11, (IMP)hook_dataTask); }
        
        // Runtime
        hookAllSelectors();
        
        NSLog(@"[IAP_GOD_PRO] LOADED SUCCESSFULLY");
    }
}
