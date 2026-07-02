#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <StoreKit/StoreKit.h>
#import <UIKit/UIKit.h>

#pragma mark - Anti-Detect

// Giả lập môi trường sạch, không bị phát hiện tweak
static BOOL fake_debugger(id self, SEL _cmd) { return NO; }
static int fake_ptrace(int a, int b, int c, int d) { return 0; }
static int fake_sysctl(int *a, unsigned int b, void *c, size_t *d, void *e, size_t f) { return 0; }

#pragma mark - Fake Transaction

@interface FakeSKPaymentTransaction : NSObject
@property (copy) NSString *productIdentifier;
@property (copy) NSString *transactionIdentifier;
@property (copy) NSDate *transactionDate;
@property NSInteger transactionState;
@property (copy) NSError *error;
@property (strong) NSData *transactionReceipt;
@property (strong) SKPayment *payment;
@end

@implementation FakeSKPaymentTransaction
- (instancetype)init {
    if (self = [super init]) {
        _transactionState = 1;
        _transactionDate = [NSDate date];
        _transactionIdentifier = [[NSUUID UUID] UUIDString];
        _transactionReceipt = [NSData dataWithBytes:"receipt" length:7];
    }
    return self;
}
@end

#pragma mark - SKPaymentQueue

static void (*orig_addPayment)(id, SEL, SKPayment*);
static void hook_addPayment(id self, SEL _cmd, SKPayment *payment) {
    FakeSKPaymentTransaction *fake = [[FakeSKPaymentTransaction alloc] init];
    fake.productIdentifier = payment.productIdentifier;
    fake.payment = payment;
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        for (id obs in [self valueForKey:@"transactionObservers"]) {
            if ([obs respondsToSelector:@selector(paymentQueue:updatedTransactions:)]) {
                [obs paymentQueue:self updatedTransactions:@[fake]];
            }
        }
    });
}

static void (*orig_finish)(id, SEL, id);
static void hook_finish(id self, SEL _cmd, id t) { orig_finish(self, _cmd, t); }

#pragma mark - NSUserDefaults

static id (*orig_obj)(id, SEL, NSString*);
static id hook_obj(id self, SEL _cmd, NSString *k) {
    if (!k) return nil;
    NSString *l = [k lowercaseString];
    if ([l containsString:@"iap"]||[l containsString:@"purchase"]||[l containsString:@"unlock"]||
        [l containsString:@"premium"]||[l containsString:@"vip"]||[l containsString:@"pro"]||
        [l containsString:@"buy"]||[l containsString:@"paid"]||[l containsString:@"member"]||
        [l containsString:@"subscribe"]||[l containsString:@"coin"]||[l containsString:@"gem"]||
        [l containsString:@"diamond"]||[l containsString:@"gold"]||[l containsString:@"cash"]) return @"1";
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

#pragma mark - Chặn API Verify Receipt

static void hookURLProtocol(void) {
    Class URLP = NSClassFromString(@"NSURLProtocol");
    if (!URLP) return;
    
    // Hook NSURLSession
    Class session = [NSURLSession class];
    SEL sel = @selector(dataTaskWithRequest:completionHandler:);
    Method m = class_getInstanceMethod(session, sel);
    if (m) {
        IMP old = method_getImplementation(m);
        IMP new = imp_implementationWithBlock(^(id self, id request, id handler) {
            NSURL *url = [request valueForKey:@"URL"];
            NSString *str = url.absoluteString.lowercaseString;
            
            if ([str containsString:@"verifyreceipt"]||[str containsString:@"iap"]||
                [str containsString:@"purchase"]||[str containsString:@"buy"]||
                [str containsString:@"payment"]||[str containsString:@"order"]||
                [str containsString:@"unlock"]||[str containsString:@"premium"]||
                [str containsString:@"vip/check"]||[str containsString:@"subscription/check"]) {
                
                NSDictionary *fake = @{@"status":@0,@"code":@200,@"success":@YES,
                    @"data":@{@"valid":@YES,@"purchased":@YES,@"unlocked":@YES,@"premium":@YES,@"vip":@YES}};
                NSData *data = [NSJSONSerialization dataWithJSONObject:fake options:0 error:nil];
                NSHTTPURLResponse *resp = [[NSHTTPURLResponse alloc] initWithURL:url statusCode:200 HTTPVersion:@"HTTP/1.1" headerFields:@{@"Content-Type":@"application/json"}];
                if (handler) ((void(^)(NSData*,NSURLResponse*,NSError*))handler)(data, resp, nil);
                return (id)nil;
            }
            return ((id(*)(id,SEL,id,id))old)(self, sel, request, handler);
        });
        method_setImplementation(m, new);
    }
}

#pragma mark - Keychain

static void hookKeychain(void) {
    Class kc = NSClassFromString(@"SFHFKeychainUtils");
    if (kc) {
        SEL sel = @selector(getPasswordForUsername:andServiceName:error:);
        Method m = class_getClassMethod(kc, sel);
        if (m) {
            IMP old = method_getImplementation(m);
            IMP new = imp_implementationWithBlock(^(id self, id user, id service, id *err) {
                NSString *s = [service lowercaseString];
                if ([s containsString:@"receipt"]||[s containsString:@"purchase"]||[s containsString:@"iap"]) {
                    return @"fake_receipt_data";
                }
                return ((id(*)(id,SEL,id,id,id*))old)(self, sel, user, service, err);
            });
            method_setImplementation(m, new);
        }
    }
}

#pragma mark - Runtime Hook All Classes

static void hookAllClasses(void) {
    unsigned int count;
    Class *classes = objc_copyClassList(&count);
    const char *sels[] = {
        "isPurchased","isUnlocked","isPremium","hasPurchased","isIAPPurchased",
        "isProductPurchased","isItemUnlocked","isVIP","isVip","isPro","hasVIP",
        "hasPremium","hasSubscription","isSubscribed","isMember","isFeatureUnlocked",
        "isFullVersion","isPaidUser","isPremiumUser","hasValidSubscription",
        "isVIPActive","isVIPValid","canUseVIPFeature","hasVIPPermission",
        "hasPurchasedProduct","isProductOwned","isItemOwned","isContentUnlocked",
        NULL
    };
    for (unsigned int i = 0; i < count; i++) {
        for (int j = 0; sels[j]; j++) {
            SEL s = sel_registerName(sels[j]);
            Method m = class_getInstanceMethod(classes[i], s);
            if (m) method_setImplementation(m, imp_implementationWithBlock(^BOOL(id self, SEL _cmd){return YES;}));
            m = class_getClassMethod(classes[i], s);
            if (m) method_setImplementation(m, imp_implementationWithBlock(^BOOL(id self, SEL _cmd){return YES;}));
        }
    }
    free(classes);
}

#pragma mark - Constructor

__attribute__((constructor))
static void init(void) {
    @autoreleasepool {
        // SKPaymentQueue
        Class q = [SKPaymentQueue class];
        Method m1 = class_getInstanceMethod(q, @selector(addPayment:));
        if(m1){orig_addPayment=(void*)method_getImplementation(m1);method_setImplementation(m1,(IMP)hook_addPayment);}
        Method m2 = class_getInstanceMethod(q, @selector(finishTransaction:));
        if(m2){orig_finish=(void*)method_getImplementation(m2);method_setImplementation(m2,(IMP)hook_finish);}
        
        // NSUserDefaults
        Class u = [NSUserDefaults class];
        Method m3 = class_getInstanceMethod(u, @selector(objectForKey:));
        if(m3){orig_obj=(void*)method_getImplementation(m3);method_setImplementation(m3,(IMP)hook_obj);}
        Method m4 = class_getInstanceMethod(u, @selector(boolForKey:));
        if(m4){orig_bool=(void*)method_getImplementation(m4);method_setImplementation(m4,(IMP)hook_bool);}
        Method m5 = class_getInstanceMethod(u, @selector(stringForKey:));
        if(m5) method_setImplementation(m5, (IMP)hook_obj);
        Method m6 = class_getInstanceMethod(u, @selector(valueForKey:));
        if(m6) method_setImplementation(m6, (IMP)hook_obj);
        Method m7 = class_getInstanceMethod(u, @selector(dictionaryForKey:));
        if(m7) method_setImplementation(m7, (IMP)hook_obj);
        Method m8 = class_getInstanceMethod(u, @selector(integerForKey:));
        if(m8) method_setImplementation(m8, (IMP)hook_obj);
        
        // Anti detect
        Class dbg = NSClassFromString(@"NSDebugger");
        if (dbg) {
            Method m9 = class_getClassMethod(dbg, @selector(isDebuggerAttached));
            if(m9) method_setImplementation(m9, (IMP)fake_debugger);
        }
        
        // API intercept
        hookURLProtocol();
        hookKeychain();
        
        // All classes
        hookAllClasses();
        
        NSLog(@"[IAP_GOD_PRO] ✓ ALL IAP BYPASSED + API FAKED");
    }
}
