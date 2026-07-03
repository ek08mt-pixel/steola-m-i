#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <StoreKit/StoreKit.h>
#import <UIKit/UIKit.h>
#import <Security/Security.h>

#pragma mark - Fake Transaction

@interface FakeSKPaymentTransaction : NSObject
@property (nonatomic, copy) NSString *productIdentifier;
@property (nonatomic, copy) NSString *transactionIdentifier;
@property (nonatomic, copy) NSDate *transactionDate;
@property (nonatomic, assign) NSInteger transactionState;
@property (nonatomic, strong) NSError *error;
@property (nonatomic, strong) NSData *transactionReceipt;
@property (nonatomic, strong) SKPayment *payment;
@property (nonatomic, strong) id originalTransaction;
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

#pragma mark - SKPaymentQueue Hooks

static void (*orig_addPayment)(id, SEL, SKPayment*);
static void hook_addPayment(id self, SEL _cmd, SKPayment *payment) {
    FakeSKPaymentTransaction *fake = [[FakeSKPaymentTransaction alloc] init];
    fake.productIdentifier = payment.productIdentifier;
    fake.payment = payment;
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.15 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        NSArray *obs = [self valueForKey:@"transactionObservers"];
        for (id o in obs) {
            if ([o respondsToSelector:@selector(paymentQueue:updatedTransactions:)])
                [o paymentQueue:self updatedTransactions:@[fake]];
        }
    });
}
static void (*orig_finishTransaction)(id, SEL, id);
static void hook_finishTransaction(id self, SEL _cmd, id t) {
    orig_finishTransaction(self, _cmd, t);
}
static id (*orig_transactions)(id, SEL);
static id hook_transactions(id self, SEL _cmd) { return @[]; }

#pragma mark - SKProductsRequest Hooks

static void (*orig_didReceiveResponse)(id, SEL, id, id);
static void hook_didReceiveResponse(id self, SEL _cmd, id req, id resp) {
    for (id p in [resp valueForKey:@"products"]) {
        @try {
            [p setValue:@(0.00) forKey:@"price"];
            [p setValue:@"Free" forKey:@"priceString"];
            [p setValue:[NSLocale localeWithLocaleIdentifier:@"en_US"] forKey:@"priceLocale"];
        } @catch (NSException *e) {}
    }
    orig_didReceiveResponse(self, _cmd, req, resp);
}

static void (*orig_didFail)(id, SEL, id, id);
static void hook_didFail(id self, SEL _cmd, id req, id err) {
    return;
}

static void (*orig_requestDidFinish)(id, SEL, id);
static void hook_requestDidFinish(id self, SEL _cmd, id req) {
    orig_requestDidFinish(self, _cmd, req);
}

#pragma mark - NSUserDefaults

static id (*orig_obj)(id, SEL, NSString*);
static id hook_obj(id self, SEL _cmd, NSString *k) {
    if (!k) return nil;
    NSString *l = [k lowercaseString];
    if ([l containsString:@"iap"]||[l containsString:@"purchase"]||[l containsString:@"unlock"]||
        [l containsString:@"premium"]||[l containsString:@"vip"]||[l containsString:@"pro"]||
        [l containsString:@"buy"]||[l containsString:@"paid"]||[l containsString:@"member"]||
        [l containsString:@"subscribe"]||[l containsString:@"coin"]||[l containsString:@"gem"]||
        [l containsString:@"diamond"]||[l containsString:@"gold"]||[l containsString:@"cash"]||
        [l containsString:@"removeads"]||[l containsString:@"noads"]||[l containsString:@"adfree"]||
        [l containsString:@"fullversion"]||[l containsString:@"full_version"])
        return @"1";
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
        [l containsString:@"subscribe"]||[l containsString:@"removeads"]||[l containsString:@"noads"]||
        [l containsString:@"fullversion"]) return YES;
    return orig_bool ? orig_bool(self, _cmd, k) : NO;
}

#pragma mark - Keychain Hook

static OSStatus (*orig_SecItemCopyMatching)(CFDictionaryRef, CFTypeRef*);
static OSStatus hook_SecItemCopyMatching(CFDictionaryRef query, CFTypeRef *result) {
    OSStatus ret = orig_SecItemCopyMatching ? orig_SecItemCopyMatching(query, result) : errSecItemNotFound;
    if (ret == errSecItemNotFound && result) {
        *result = (__bridge CFTypeRef)[NSData dataWithBytes:"receipt" length:7];
        return errSecSuccess;
    }
    return ret;
}

#pragma mark - NSURLSession Hook

static id (*orig_dataTask)(id, SEL, id, id);
static id hook_dataTask(id self, SEL _cmd, id request, id handler) {
    NSURL *url = [request valueForKey:@"URL"];
    NSString *lower = [[url absoluteString] lowercaseString];
    
    if ([lower containsString:@"verifyreceipt"]||[lower containsString:@"validate"]||
        [lower containsString:@"iap"]||[lower containsString:@"purchase"]||
        [lower containsString:@"buy"]||[lower containsString:@"payment"]||
        [lower containsString:@"order"]||[lower containsString:@"unlock"]||
        [lower containsString:@"premium"]||[lower containsString:@"vip"]||
        [lower containsString:@"subscription"]||[lower containsString:@"restore"]) {
        
        NSDictionary *fake = @{
            @"status":@0,@"code":@200,@"success":@YES,
            @"receipt":@{@"in_app":@[]},
            @"latest_receipt_info":@[],
            @"pending_renewal_info":@[]
        };
        NSData *d = [NSJSONSerialization dataWithJSONObject:fake options:0 error:nil];
        NSHTTPURLResponse *r = [[NSHTTPURLResponse alloc] initWithURL:url statusCode:200 HTTPVersion:@"HTTP/1.1" headerFields:@{@"Content-Type":@"application/json"}];
        if (handler) ((void(^)(NSData*,NSURLResponse*,NSError*))handler)(d, r, nil);
        return nil;
    }
    return orig_dataTask ? orig_dataTask(self, _cmd, request, handler) : nil;
}

#pragma mark - NSURLConnection Hook

static id (*orig_sendSync)(id, SEL, id, id*, id*);
static id hook_sendSync(id self, SEL _cmd, id req, id *resp, id *err) {
    NSURL *url = [req valueForKey:@"URL"];
    NSString *lower = [[url absoluteString] lowercaseString];
    if ([lower containsString:@"verifyreceipt"]||[lower containsString:@"iap"]||[lower containsString:@"purchase"]) {
        NSDictionary *fake = @{@"status":@0,@"success":@YES};
        NSData *d = [NSJSONSerialization dataWithJSONObject:fake options:0 error:nil];
        if (resp) *resp = [[NSHTTPURLResponse alloc] initWithURL:url statusCode:200 HTTPVersion:@"HTTP/1.1" headerFields:@{@"Content-Type":@"application/json"}];
        return d;
    }
    return orig_sendSync ? orig_sendSync(self, _cmd, req, resp, err) : nil;
}

#pragma mark - Runtime Hook

static void hookAllClasses(void) {
    unsigned int count;
    Class *classes = objc_copyClassList(&count);
    const char *sels[] = {
        "isPurchased","isUnlocked","isPremium","hasPurchased","isIAPPurchased",
        "isProductPurchased","isItemUnlocked","isVIP","isVip","isPro","hasVIP",
        "hasPremium","hasSubscription","isSubscribed","isMember","isFeatureUnlocked",
        "isFullVersion","isPaidUser","isPremiumUser","hasValidSubscription",
        "isVIPActive","isVIPValid","canUseVIPFeature","hasVIPPermission",
        "isNoAds","isAdFree","hasRemoveAds","isUnlimited","isFullGame",
        "hasBought","didPurchase","isPurchasing","purchaseCompleted",
        NULL
    };
    for (unsigned int i = 0; i < count; i++) {
        Class cls = classes[i];
        for (int j = 0; sels[j]; j++) {
            SEL s = sel_registerName(sels[j]);
            Method m = class_getInstanceMethod(cls, s);
            if (m) method_setImplementation(m, imp_implementationWithBlock(^BOOL(id _s, SEL _c){return YES;}));
            m = class_getClassMethod(cls, s);
            if (m) method_setImplementation(m, imp_implementationWithBlock(^BOOL(id _s, SEL _c){return YES;}));
        }
    }
    free(classes);
}

#pragma mark - ANTI-DETECT: Che giấu dylib

static void antiDetect(void) {
    // Hook _dyld_image_count
    // Hook sysctl để che process flags
    Class dbg = NSClassFromString(@"NSDebugger");
    if (dbg) {
        SEL s = sel_registerName("isDebuggerAttached");
        Method m = class_getClassMethod(dbg, s);
        if (m) method_setImplementation(m, imp_implementationWithBlock(^BOOL(id _s, SEL _c){return NO;}));
    }
    
    // Xóa environment variable nghi ngờ
    unsetenv("DYLD_INSERT_LIBRARIES");
    unsetenv("CYDIA");
    unsetenv("SUBSTRATE");
}

#pragma mark - IN-APP MENU (by emmewchamchi)

static BOOL masterSwitch = YES;

@interface IAPGodMenu : UIViewController
@end

@implementation IAPGodMenu

- (void)viewDidLoad {
    [super viewDidLoad];
    
    CGFloat w = 300, h = 500;
    self.view.frame = CGRectMake(0, 0, w, h);
    self.view.backgroundColor = [UIColor colorWithRed:0.05 green:0.05 blue:0.15 alpha:0.97];
    self.view.layer.cornerRadius = 20;
    self.view.layer.borderWidth = 2;
    self.view.layer.borderColor = [UIColor cyanColor].CGColor;
    self.view.clipsToBounds = YES;
    
    // Background glow effect
    CAGradientLayer *gradient = [CAGradientLayer layer];
    gradient.frame = self.view.bounds;
    gradient.colors = @[(id)[UIColor colorWithRed:0 green:0.8 blue:0.8 alpha:0.3].CGColor, (id)[UIColor clearColor].CGColor];
    gradient.locations = @[@0.0, @0.3];
    [self.view.layer insertSublayer:gradient atIndex:0];
    
    // Title
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(20, 20, w-40, 35)];
    title.text = @"⚡ IAP GOD PRO ⚡";
    title.textColor = [UIColor cyanColor];
    title.textAlignment = NSTextAlignmentCenter;
    title.font = [UIFont boldSystemFontOfSize:24];
    [self.view addSubview:title];
    
    // Credit
    UILabel *credit = [[UILabel alloc] initWithFrame:CGRectMake(20, 53, w-40, 20)];
    credit.text = @"by emmewchamchi";
    credit.textColor = [UIColor colorWithRed:1.0 green:0.5 blue:0.0 alpha:1.0];
    credit.textAlignment = NSTextAlignmentCenter;
    credit.font = [UIFont italicSystemFontOfSize:13];
    [self.view addSubview:credit];
    
    // Separator line
    UIView *line = [[UIView alloc] initWithFrame:CGRectMake(30, 78, w-60, 1)];
    line.backgroundColor = [UIColor colorWithWhite:0.3 alpha:1.0];
    [self.view addSubview:line];
    
    // Status
    UILabel *status = [[UILabel alloc] initWithFrame:CGRectMake(20, 88, w-40, 25)];
    status.text = masterSwitch ? @"🟢 STATUS: ACTIVE" : @"🔴 STATUS: DISABLED";
    status.textColor = masterSwitch ? [UIColor greenColor] : [UIColor redColor];
    status.textAlignment = NSTextAlignmentCenter;
    status.font = [UIFont boldSystemFontOfSize:15];
    status.tag = 999;
    [self.view addSubview:status];
    
    // Feature list
    NSArray *features = @[
        @"✅ IAP Bypass",
        @"🌐 API Fake",
        @"💾 UserDefaults Hook",
        @"🔑 Keychain Fake",
        @"🛡 Anti-Detect",
        @"🔓 Unlock All"
    ];
    
    for (int i = 0; i < features.count; i++) {
        UILabel *feat = [[UILabel alloc] initWithFrame:CGRectMake(25, 125 + i * 38, w-50, 30)];
        feat.text = features[i];
        feat.textColor = [UIColor whiteColor];
        feat.font = [UIFont systemFontOfSize:15];
        [self.view addSubview:feat];
    }
    
    // Toggle button
    UIButton *toggle = [UIButton buttonWithType:UIButtonTypeSystem];
    toggle.frame = CGRectMake(50, 370, w-100, 45);
    [toggle setTitle:@"🔄 BẬT / TẮT" forState:UIControlStateNormal];
    [toggle setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    toggle.titleLabel.font = [UIFont boldSystemFontOfSize:17];
    toggle.backgroundColor = [UIColor yellowColor];
    toggle.layer.cornerRadius = 12;
    [toggle addTarget:self action:@selector(toggleAll) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:toggle];
    
    // Close button
    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    close.frame = CGRectMake(50, 430, w-100, 40);
    [close setTitle:@"✕ ĐÓNG" forState:UIControlStateNormal];
    [close setTitleColor:[UIColor redColor] forState:UIControlStateNormal];
    close.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    [close addTarget:self action:@selector(closeMenu) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:close];
}

- (void)toggleAll {
    masterSwitch = !masterSwitch;
    UILabel *st = [self.view viewWithTag:999];
    st.text = masterSwitch ? @"🟢 STATUS: ACTIVE" : @"🔴 STATUS: DISABLED";
    st.textColor = masterSwitch ? [UIColor greenColor] : [UIColor redColor];
}

- (void)closeMenu {
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end

static void showMenu(void) {
    if (!masterSwitch) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *window = nil;
        for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive) {
                window = scene.windows.firstObject;
                break;
            }
        }
        if (!window) window = [UIApplication sharedApplication].windows.firstObject;
        
        IAPGodMenu *menu = [[IAPGodMenu alloc] init];
        menu.modalPresentationStyle = UIModalPresentationOverFullScreen;
        menu.view.center = window.center;
        [window.rootViewController presentViewController:menu animated:YES completion:nil];
    });
}

#pragma mark - Gesture Handler

static void (*orig_touchesEnded)(id, SEL, NSSet*, UIEvent*);
static void hook_touchesEnded(UIWindow *self, SEL _cmd, NSSet *touches, UIEvent *event) {
    if (touches.count >= 3) {
        UITouch *touch = touches.anyObject;
        if (touch.tapCount >= 2) {
            showMenu();
            return;
        }
    }
    if (orig_touchesEnded) orig_touchesEnded(self, _cmd, touches, event);
}

#pragma mark - Constructor

__attribute__((constructor))
static void IAPGodProInit(void) {
    @autoreleasepool {
        antiDetect();
        
        Class skq = [SKPaymentQueue class];
        Method m1 = class_getInstanceMethod(skq, @selector(addPayment:));
        if(m1){orig_addPayment=(void*)method_getImplementation(m1);method_setImplementation(m1,(IMP)hook_addPayment);}
        Method m2 = class_getInstanceMethod(skq, @selector(finishTransaction:));
        if(m2){orig_finishTransaction=(void*)method_getImplementation(m2);method_setImplementation(m2,(IMP)hook_finishTransaction);}
        Method m3 = class_getInstanceMethod(skq, @selector(transactions));
        if(m3){orig_transactions=(void*)method_getImplementation(m3);method_setImplementation(m3,(IMP)hook_transactions);}
        
        Class pr = [SKProductsRequest class];
        Method m4 = class_getInstanceMethod(pr, NSSelectorFromString(@"productsRequest:didReceiveResponse:"));
        if(m4){orig_didReceiveResponse=(void*)method_getImplementation(m4);method_setImplementation(m4,(IMP)hook_didReceiveResponse);}
        
        Class ud = [NSUserDefaults class];
        Method m5 = class_getInstanceMethod(ud, @selector(objectForKey:));
        if(m5){orig_obj=(void*)method_getImplementation(m5);method_setImplementation(m5,(IMP)hook_obj);}
        Method m6 = class_getInstanceMethod(ud, @selector(boolForKey:));
        if(m6){orig_bool=(void*)method_getImplementation(m6);method_setImplementation(m6,(IMP)hook_bool);}
        Method m7 = class_getInstanceMethod(ud, @selector(stringForKey:));
        if(m7) method_setImplementation(m7,(IMP)hook_obj);
        Method m8 = class_getInstanceMethod(ud, @selector(valueForKey:));
        if(m8) method_setImplementation(m8,(IMP)hook_obj);
        Method m9 = class_getInstanceMethod(ud, @selector(dictionaryForKey:));
        if(m9) method_setImplementation(m9,(IMP)hook_obj);
        Method m10 = class_getInstanceMethod(ud, @selector(integerForKey:));
        if(m10) method_setImplementation(m10,(IMP)hook_obj);
        Method m11 = class_getInstanceMethod(ud, @selector(arrayForKey:));
        if(m11) method_setImplementation(m11,(IMP)hook_obj);
        
        Class session = [NSURLSession class];
        Method m12 = class_getInstanceMethod(session, @selector(dataTaskWithRequest:completionHandler:));
        if(m12){orig_dataTask=(void*)method_getImplementation(m12);method_setImplementation(m12,(IMP)hook_dataTask);}
        
        Class conn = [NSURLConnection class];
        Method m13 = class_getClassMethod(conn, @selector(sendSynchronousRequest:returningResponse:error:));
        if(m13){orig_sendSync=(void*)method_getImplementation(m13);method_setImplementation(m13,(IMP)hook_sendSync);}
        
        Class win = [UIWindow class];
        Method m14 = class_getInstanceMethod(win, @selector(touchesEnded:withEvent:));
        if(m14){orig_touchesEnded=(void*)method_getImplementation(m14);method_setImplementation(m14,(IMP)hook_touchesEnded);}
        
        hookAllClasses();
        
        NSLog(@"[IAP_GOD_PRO] ⚡ by emmewchamchi - ALL IAP BYPASSED");
    }
}
