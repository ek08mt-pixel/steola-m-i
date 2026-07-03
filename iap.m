#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <StoreKit/StoreKit.h>
#import <UIKit/UIKit.h>

#pragma mark - Fake Transaction

@interface FakeSKPaymentTransaction : NSObject
@property (nonatomic, copy) NSString *productIdentifier;
@property (nonatomic, copy) NSString *transactionIdentifier;
@property (nonatomic, copy) NSDate *transactionDate;
@property (nonatomic, assign) NSInteger transactionState;
@property (nonatomic, strong) NSData *transactionReceipt;
@property (nonatomic, strong) SKPayment *payment;
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
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        for (id obs in [self valueForKey:@"transactionObservers"]) {
            if ([obs respondsToSelector:@selector(paymentQueue:updatedTransactions:)])
                [obs paymentQueue:self updatedTransactions:@[fake]];
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
        [l containsString:@"subscribe"]||[l containsString:@"removeads"]||[l containsString:@"noads"]||
        [l containsString:@"fullversion"]) return @"1";
    if ([l containsString:@"expire"]) return @(4102444800);
    if ([l containsString:@"level"]) return @"999";
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

#pragma mark - NSURLSession

static id (*orig_dataTask)(id, SEL, id, id);
static id hook_dataTask(id self, SEL _cmd, id request, id handler) {
    NSURL *url = [request valueForKey:@"URL"];
    NSString *lower = [[url absoluteString] lowercaseString];
    if ([lower containsString:@"verifyreceipt"]||[lower containsString:@"iap"]||
        [lower containsString:@"purchase"]||[lower containsString:@"buy"]||
        [lower containsString:@"premium"]||[lower containsString:@"vip"]||
        [lower containsString:@"subscription"]) {
        NSDictionary *fake = @{@"status":@0,@"code":@200,@"success":@YES};
        NSData *d = [NSJSONSerialization dataWithJSONObject:fake options:0 error:nil];
        NSHTTPURLResponse *r = [[NSHTTPURLResponse alloc] initWithURL:url statusCode:200 HTTPVersion:@"HTTP/1.1" headerFields:@{@"Content-Type":@"application/json"}];
        if (handler) ((void(^)(NSData*,NSURLResponse*,NSError*))handler)(d, r, nil);
        return nil;
    }
    return orig_dataTask ? orig_dataTask(self, _cmd, request, handler) : nil;
}

#pragma mark - IN-APP MENU (by emmewchamchi)

static BOOL menuOn = YES;

@interface IAPGodMenu : UIViewController
@end

@implementation IAPGodMenu
- (void)viewDidLoad {
    [super viewDidLoad];
    CGFloat w = 290, h = 420;
    self.view.frame = CGRectMake(0, 0, w, h);
    self.view.backgroundColor = [UIColor colorWithRed:0.05 green:0.05 blue:0.15 alpha:0.97];
    self.view.layer.cornerRadius = 20;
    self.view.layer.borderWidth = 2;
    self.view.layer.borderColor = [UIColor cyanColor].CGColor;
    self.view.clipsToBounds = YES;
    
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(20, 25, w-40, 35)];
    title.text = @"⚡ IAP GOD PRO ⚡";
    title.textColor = [UIColor cyanColor];
    title.textAlignment = NSTextAlignmentCenter;
    title.font = [UIFont boldSystemFontOfSize:23];
    [self.view addSubview:title];
    
    UILabel *credit = [[UILabel alloc] initWithFrame:CGRectMake(20, 55, w-40, 20)];
    credit.text = @"by emmewchamchi";
    credit.textColor = [UIColor orangeColor];
    credit.textAlignment = NSTextAlignmentCenter;
    credit.font = [UIFont italicSystemFontOfSize:13];
    [self.view addSubview:credit];
    
    UIView *line = [[UIView alloc] initWithFrame:CGRectMake(30, 80, w-60, 1)];
    line.backgroundColor = [UIColor colorWithWhite:0.3 alpha:1.0];
    [self.view addSubview:line];
    
    UILabel *status = [[UILabel alloc] initWithFrame:CGRectMake(20, 90, w-40, 25)];
    status.text = menuOn ? @"🟢 ACTIVE" : @"🔴 DISABLED";
    status.textColor = menuOn ? [UIColor greenColor] : [UIColor redColor];
    status.textAlignment = NSTextAlignmentCenter;
    status.font = [UIFont boldSystemFontOfSize:15];
    status.tag = 999;
    [self.view addSubview:status];
    
    NSArray *feats = @[@"✅ IAP Bypass",@"🌐 API Fake",@"💾 UserDefaults",@"🛡 Anti-Detect"];
    for (int i = 0; i < feats.count; i++) {
        UILabel *f = [[UILabel alloc] initWithFrame:CGRectMake(30, 125 + i * 40, w-60, 30)];
        f.text = feats[i];
        f.textColor = [UIColor whiteColor];
        f.font = [UIFont systemFontOfSize:15];
        [self.view addSubview:f];
    }
    
    UIButton *toggle = [UIButton buttonWithType:UIButtonTypeSystem];
    toggle.frame = CGRectMake(50, 300, w-100, 45);
    [toggle setTitle:@"🔄 BẬT / TẮT" forState:UIControlStateNormal];
    [toggle setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    toggle.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    toggle.backgroundColor = [UIColor yellowColor];
    toggle.layer.cornerRadius = 12;
    [toggle addTarget:self action:@selector(toggle) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:toggle];
    
    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    close.frame = CGRectMake(50, 358, w-100, 40);
    [close setTitle:@"✕ ĐÓNG" forState:UIControlStateNormal];
    [close setTitleColor:[UIColor redColor] forState:UIControlStateNormal];
    [close addTarget:self action:@selector(closeMenu) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:close];
}
- (void)toggle {
    menuOn = !menuOn;
    UILabel *s = [self.view viewWithTag:999];
    s.text = menuOn ? @"🟢 ACTIVE" : @"🔴 DISABLED";
    s.textColor = menuOn ? [UIColor greenColor] : [UIColor redColor];
}
- (void)closeMenu {
    [self dismissViewControllerAnimated:YES completion:nil];
}
@end

static void showMenu(void) {
    if (!menuOn) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *w = nil;
        for (UIWindowScene *sc in [UIApplication sharedApplication].connectedScenes) {
            if (sc.activationState == UISceneActivationStateForegroundActive) {
                w = sc.windows.firstObject;
                break;
            }
        }
        if (!w) w = [UIApplication sharedApplication].windows.firstObject;
        IAPGodMenu *m = [[IAPGodMenu alloc] init];
        m.modalPresentationStyle = UIModalPresentationOverFullScreen;
        m.view.center = w.center;
        [w.rootViewController presentViewController:m animated:YES completion:nil];
    });
}

#pragma mark - Gesture

static void (*orig_touchesEnded)(id, SEL, NSSet*, UIEvent*);
static void hook_touchesEnded(UIWindow *self, SEL _cmd, NSSet *touches, UIEvent *event) {
    if (touches.count >= 3) {
        UITouch *t = touches.anyObject;
        if (t.tapCount >= 2) { showMenu(); return; }
    }
    if (orig_touchesEnded) orig_touchesEnded(self, _cmd, touches, event);
}

#pragma mark - Constructor (NHẸ - chỉ hook essential)

__attribute__((constructor))
static void init(void) {
    @autoreleasepool {
        Class skq = [SKPaymentQueue class];
        Method m1 = class_getInstanceMethod(skq, @selector(addPayment:));
        if(m1){orig_addPayment=(void*)method_getImplementation(m1);method_setImplementation(m1,(IMP)hook_addPayment);}
        Method m2 = class_getInstanceMethod(skq, @selector(finishTransaction:));
        if(m2){orig_finish=(void*)method_getImplementation(m2);method_setImplementation(m2,(IMP)hook_finish);}
        
        Class ud = [NSUserDefaults class];
        Method m3 = class_getInstanceMethod(ud, @selector(objectForKey:));
        if(m3){orig_obj=(void*)method_getImplementation(m3);method_setImplementation(m3,(IMP)hook_obj);}
        Method m4 = class_getInstanceMethod(ud, @selector(boolForKey:));
        if(m4){orig_bool=(void*)method_getImplementation(m4);method_setImplementation(m4,(IMP)hook_bool);}
        Method m5 = class_getInstanceMethod(ud, @selector(stringForKey:));
        if(m5) method_setImplementation(m5,(IMP)hook_obj);
        Method m6 = class_getInstanceMethod(ud, @selector(valueForKey:));
        if(m6) method_setImplementation(m6,(IMP)hook_obj);
        
        Class sess = [NSURLSession class];
        Method m7 = class_getInstanceMethod(sess, @selector(dataTaskWithRequest:completionHandler:));
        if(m7){orig_dataTask=(void*)method_getImplementation(m7);method_setImplementation(m7,(IMP)hook_dataTask);}
        
        Class win = [UIWindow class];
        Method m8 = class_getInstanceMethod(win, @selector(touchesEnded:withEvent:));
        if(m8){orig_touchesEnded=(void*)method_getImplementation(m8);method_setImplementation(m8,(IMP)hook_touchesEnded);}
        
        NSLog(@"[IAP_GOD_PRO] ⚡ by emmewchamchi - LOADED");
    }
}
