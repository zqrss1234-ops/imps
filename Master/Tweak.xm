#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <QuartzCore/QuartzCore.h>

#define YM_TRY(op) @try { op; } @catch (NSException *e) { NSLog(@"[YallaMaster] %@", e); }

static UIWindow *ym_keyWindow(void) {
    UIWindow *kw = [UIApplication sharedApplication].keyWindow;
    if (kw) return kw;
    if (@available(iOS 13, *)) {
        for (UIScene *s in [UIApplication sharedApplication].connectedScenes) {
            if ([s isKindOfClass:[UIWindowScene class]]) {
                for (UIWindow *w in [(UIWindowScene *)s windows]) {
                    if (w.isKeyWindow) return w;
                }
            }
        }
    }
    return nil;
}

static NSString *const kYalla = @"com.yalla.yallalite";

static int const kMsVals[5] = {50, 25, 10, 5, 1};
static NSString *const kNameList[8] = {
    @"Abdulilah", @"Lahlouh", @"Charo", @"Abu Mutab",
    @"Saeed", @"Al-Kaed", @"Al-Shammarah", @"Al-Habbas"
};

@interface YallaState : NSObject
@property (nonatomic, assign) int selectedIdx;
@property (nonatomic, assign) int msIdx;
@property (nonatomic, assign) BOOL isActive;
@property (nonatomic, assign) BOOL cxxOn;
@property (nonatomic, assign) BOOL liteOn;
+ (instancetype)s;
- (int)ms;
@end
@implementation YallaState
+ (instancetype)s {
    static YallaState *x;
    static dispatch_once_t t;
    dispatch_once(&t, ^{ x = [[self alloc] init]; });
    return x;
}
- (instancetype)init {
    if ((self = [super init])) {
        _selectedIdx = -1;
        _msIdx = 2;
    }
    return self;
}
- (int)ms { return kMsVals[self.msIdx]; }
@end

@interface TapReg : NSObject
@property (nonatomic, strong) NSMutableDictionary *taps;
@property (nonatomic, strong) NSLock *lock;
+ (instancetype)shared;
- (int)cnt;
@end
@implementation TapReg
+ (instancetype)shared {
    static TapReg *x;
    static dispatch_once_t t;
    dispatch_once(&t, ^{ x = [[self alloc] init]; });
    return x;
}
- (instancetype)init {
    if ((self = [super init])) {
        _taps = [NSMutableDictionary dictionary];
        _lock = [[NSLock alloc] init];
    }
    return self;
}
- (int)cnt {
    [_lock lock];
    int c = (int)_taps.count;
    [_lock unlock];
    return c;
}
- (void)recv:(NSString *)u {
    [_lock lock];
    _taps[u] = @([[NSDate date] timeIntervalSince1970]);
    [_lock unlock];
}
- (void)prune {
    [_lock lock];
    double now = [[NSDate date] timeIntervalSince1970];
    NSMutableArray *stale = [NSMutableArray array];
    [_taps enumerateKeysAndObjectsUsingBlock:^(id k, NSNumber *v, BOOL *s) {
        if (now - v.doubleValue > 12) [stale addObject:k];
    }];
    [_taps removeObjectsForKeys:stale];
    [_lock unlock];
}
@end

static const char *kTapPrefix = "com.yalla.liteagent.cmd.";

@interface Notifier : NSObject
- (void)post:(NSString *)n;
- (void)postMic:(long)s;
- (void)postRun:(BOOL)o;
@end
@implementation Notifier
- (void)post:(NSString *)name {
    NSString *full = [NSString stringWithFormat:@"%s%@", kTapPrefix, name];
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                          (__bridge CFStringRef)full, NULL, NULL, true);
}
- (void)postMic:(long)s { [self post:[NSString stringWithFormat:@"mic.%ld", s]]; }
- (void)postRun:(BOOL)o { [self post:o ? @"run.on" : @"run.off"]; }
@end

@interface YallaUI : NSObject
@property (nonatomic, strong) UIView *panel;
@property (nonatomic, strong) UIView *dot;
@property (nonatomic, strong) NSMutableArray *numBtns;
@property (nonatomic, strong) UIButton *onB, *msB, *cxxB, *liteB, *hideB;
@property (nonatomic, strong) UILabel *st;
@property (nonatomic, strong) Notifier *n;
- (void)build;
@end

@implementation YallaUI {
    NSTimer *_t;
    UIView *_pv;
}

- (instancetype)init {
    if ((self = [super init])) {
        _n = [[Notifier alloc] init];
        _numBtns = [NSMutableArray array];
#ifndef YM_DIRECT
        [self showPass];
#else
        dispatch_async(dispatch_get_main_queue(), ^{ [self build]; });
#endif
    }
    return self;
}

- (void)showPass {
    UIWindow *kw = ym_keyWindow();
    if (!kw) return;
    _pv = [[UIView alloc] initWithFrame:kw.bounds];
    _pv.backgroundColor = [UIColor colorWithWhite:0 alpha:0.85];
    _pv.userInteractionEnabled = YES;

    UIView *box = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 220, 160)];
    box.center = CGPointMake(kw.bounds.size.width/2, kw.bounds.size.height/2);
    box.backgroundColor = [UIColor blackColor];
    box.layer.cornerRadius = 16;

    UILabel *tt = [[UILabel alloc] initWithFrame:CGRectMake(0, 16, 220, 30)];
    tt.text = @"Abdulilah";
    tt.textColor = [UIColor whiteColor];
    tt.font = [UIFont boldSystemFontOfSize:14];
    tt.textAlignment = NSTextAlignmentCenter;
    [box addSubview:tt];

    UITextField *tf = [[UITextField alloc] initWithFrame:CGRectMake(30, 54, 160, 34)];
    tf.placeholder = @"515";
    tf.textAlignment = NSTextAlignmentCenter;
    tf.keyboardType = UIKeyboardTypeNumberPad;
    tf.secureTextEntry = YES;
    tf.textColor = [UIColor whiteColor];
    tf.font = [UIFont boldSystemFontOfSize:18];
    tf.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.9];
    tf.layer.cornerRadius = 8;
    [box addSubview:tf];

    UIButton *un = [UIButton buttonWithType:UIButtonTypeCustom];
    un.frame = CGRectMake(30, 102, 160, 36);
    [un setTitle:@"Unlock" forState:UIControlStateNormal];
    [un setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    un.backgroundColor = [UIColor colorWithRed:0.1 green:0.1 blue:0.5 alpha:0.9];
    un.layer.cornerRadius = 8;
    un.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    un.tag = 1;
    [un addTarget:self action:@selector(submit:) forControlEvents:UIControlEventTouchUpInside];
    [box addSubview:un];

    [_pv addSubview:box];
    [kw addSubview:_pv];
    [kw bringSubviewToFront:_pv];
    [tf becomeFirstResponder];
}

- (void)submit:(UIButton *)s {
    UITextField *tf = (UITextField *)s.superview.subviews[1];
    NSString *code = tf.text ?: @"";
    if (![code isEqualToString:@"515"]) {
        CABasicAnimation *sh = [CABasicAnimation animationWithKeyPath:@"position"];
        sh.duration = 0.06;
        sh.repeatCount = 3;
        sh.autoreverses = YES;
        sh.fromValue = [NSValue valueWithCGPoint:CGPointMake(s.superview.center.x - 8, s.superview.center.y)];
        sh.toValue = [NSValue valueWithCGPoint:CGPointMake(s.superview.center.x + 8, s.superview.center.y)];
        [s.superview.layer addAnimation:sh forKey:@"sh"];
        tf.text = @"";
        return;
    }
    [tf resignFirstResponder];
    [_pv removeFromSuperview];
    _pv = nil;
    dispatch_async(dispatch_get_main_queue(), ^{
        [self build];
    });
}

- (void)build {
    UIWindow *kw = ym_keyWindow();
    if (!kw) return;
    CGFloat rw = MIN(kw.bounds.size.width - 20, 350);

    self.panel = [[UIView alloc] initWithFrame:CGRectMake((kw.bounds.size.width - rw)/2, (kw.bounds.size.height - 142)/2 - 40, rw, 142)];
    self.panel.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.92];
    self.panel.layer.cornerRadius = 18;
    self.panel.layer.borderWidth = 2;
    self.panel.layer.borderColor = [UIColor blackColor].CGColor;
    self.panel.clipsToBounds = YES;

    UIView *nr = [[UIView alloc] initWithFrame:CGRectMake(0, 0, rw, 38)];
    for (int i = 0; i < 8; i++) {
        int col = i % 4, row = i / 4;
        UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(10 + col * ((rw-40)/4 + 5), 6 + row * 16, (rw-40)/4, 14)];
        l.text = kNameList[i];
        l.textColor = [UIColor colorWithWhite:0.9 alpha:1];
        l.font = [UIFont boldSystemFontOfSize:9];
        l.adjustsFontSizeToFitWidth = YES;
        l.minimumScaleFactor = 0.6;
        [nr addSubview:l];
    }
    [self.panel addSubview:nr];

    UIView *s1 = [[UIView alloc] initWithFrame:CGRectMake(0, 38, rw, 1)];
    s1.backgroundColor = [UIColor colorWithRed:0.1 green:0.1 blue:0.1 alpha:0.5];
    [self.panel addSubview:s1];

    UIView *numRow = [[UIView alloc] initWithFrame:CGRectMake(0, 42, rw, 40)];
    CGFloat bw = 26, gap = 4;
    CGFloat sx = (rw - (bw * 10 + gap * 9)) / 2;
    for (int i = 0; i < 10; i++) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
        b.frame = CGRectMake(sx + i * (bw + gap), 5, bw, 30);
        b.layer.cornerRadius = 7;
        b.backgroundColor = [UIColor blackColor];
        b.layer.borderWidth = 1.5;
        b.layer.borderColor = [UIColor colorWithRed:0.15 green:0.15 blue:0.15 alpha:0.6].CGColor;
        b.titleLabel.font = [UIFont boldSystemFontOfSize:13];
        [b setTitle:@(i+1).stringValue forState:UIControlStateNormal];
        [b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        b.tag = i;
        [b addTarget:self action:@selector(tapNum:) forControlEvents:UIControlEventTouchUpInside];
        [numRow addSubview:b];
        [self.numBtns addObject:b];
    }
    [self.panel addSubview:numRow];

    UIView *s2 = [[UIView alloc] initWithFrame:CGRectMake(0, 82, rw, 1.5)];
    s2.backgroundColor = [UIColor colorWithRed:0.1 green:0.1 blue:0.1 alpha:0.5];
    [self.panel addSubview:s2];

    NSArray *cids = @[@"hide", @"lite", @"cxx", @"ms", @"on"];
    CGFloat cw = (rw - 24) / 5;
    for (int i = 0; i < 5; i++) {
        NSString *cid = cids[i];
        UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
        b.frame = CGRectMake(10 + (4 - i) * (cw + 2), 87, cw, 30);
        b.layer.cornerRadius = 8;
        b.titleLabel.font = [UIFont boldSystemFontOfSize:10];
        b.layer.borderWidth = 1;
        b.backgroundColor = [UIColor blackColor];
        b.layer.borderColor = [UIColor colorWithRed:0.15 green:0.15 blue:0.15 alpha:0.6].CGColor;
        [b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        if ([cid isEqualToString:@"on"]) {
            [b setTitle:@"ON" forState:UIControlStateNormal];
            [b addTarget:self action:@selector(tapOn) forControlEvents:UIControlEventTouchUpInside];
            self.onB = b;
        } else if ([cid isEqualToString:@"ms"]) {
            [b setTitle:@"ms:10" forState:UIControlStateNormal];
            [b addTarget:self action:@selector(tapMs) forControlEvents:UIControlEventTouchUpInside];
            self.msB = b;
        } else if ([cid isEqualToString:@"cxx"]) {
            [b setTitle:@"cxx" forState:UIControlStateNormal];
            [b addTarget:self action:@selector(tapCxx) forControlEvents:UIControlEventTouchUpInside];
            self.cxxB = b;
        } else if ([cid isEqualToString:@"lite"]) {
            [b setTitle:@"LiTE" forState:UIControlStateNormal];
            [b addTarget:self action:@selector(tapLite) forControlEvents:UIControlEventTouchUpInside];
            self.liteB = b;
        } else if ([cid isEqualToString:@"hide"]) {
            [b setTitle:@"Hide" forState:UIControlStateNormal];
            [b addTarget:self action:@selector(tapHide) forControlEvents:UIControlEventTouchUpInside];
            self.hideB = b;
        }
        [self.panel addSubview:b];
    }

    self.st = [[UILabel alloc] initWithFrame:CGRectMake(0, 120, rw, 16)];
    self.st.textAlignment = NSTextAlignmentCenter;
    self.st.textColor = [UIColor whiteColor];
    self.st.font = [UIFont systemFontOfSize:9];
    [self upd];
    [self.panel addSubview:self.st];

    [kw addSubview:self.panel];
    [kw bringSubviewToFront:self.panel];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(pan:)];
    pan.cancelsTouchesInView = NO;
    pan.delaysTouchesBegan = NO;
    pan.delaysTouchesEnded = NO;
    [self.panel addGestureRecognizer:pan];

    self.dot = [[UIView alloc] initWithFrame:CGRectMake(kw.bounds.size.width - 80, kw.bounds.size.height/2 - 25, 48, 48)];
    self.dot.backgroundColor = [UIColor blackColor];
    self.dot.layer.cornerRadius = 24;
    self.dot.layer.borderWidth = 2.5;
    self.dot.layer.borderColor = [UIColor blackColor].CGColor;
    self.dot.hidden = YES;
    self.dot.userInteractionEnabled = YES;
    UILabel *cl = [[UILabel alloc] initWithFrame:self.dot.bounds];
    cl.text = @"515";
    cl.textColor = [UIColor colorWithWhite:1 alpha:0.7];
    cl.font = [UIFont boldSystemFontOfSize:13];
    cl.textAlignment = NSTextAlignmentCenter;
    [self.dot addSubview:cl];
    [self.dot addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(showP)]];
    UIPanGestureRecognizer *cp = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(pan:)];
    cp.cancelsTouchesInView = NO;
    cp.delaysTouchesBegan = NO;
    cp.delaysTouchesEnded = NO;
    [self.dot addGestureRecognizer:cp];
    [kw addSubview:self.dot];

    _t = [NSTimer scheduledTimerWithTimeInterval:2.0 repeats:YES block:^(NSTimer *t) {
        [self upd];
    }];
}

- (void)tapNum:(UIButton *)s {
    YallaState *st = [YallaState s];
    if (st.isActive) return;
    int idx = (int)s.tag;
    for (UIButton *b in self.numBtns) {
        b.backgroundColor = [UIColor blackColor];
        b.layer.borderColor = [UIColor colorWithRed:0.15 green:0.15 blue:0.15 alpha:0.6].CGColor;
        [b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    }
    if (st.selectedIdx == idx) {
        st.selectedIdx = -1;
        return;
    }
    st.selectedIdx = idx;
    s.backgroundColor = [UIColor colorWithRed:0 green:0.16 blue:0.04 alpha:0.7];
    s.layer.borderColor = [UIColor colorWithRed:0 green:0.8 blue:0.27 alpha:0.8].CGColor;
    [s setTitleColor:[UIColor colorWithRed:0 green:1 blue:0.33 alpha:0.9] forState:UIControlStateNormal];
    [self.n postMic:st.selectedIdx+1];
    [self upd];
}

- (void)tapOn {
    YallaState *st = [YallaState s];
    if (st.selectedIdx < 0) return;
    st.isActive = !st.isActive;
    [self.onB setTitle:st.isActive ? @"OFF" : @"ON" forState:UIControlStateNormal];
    self.onB.backgroundColor = st.isActive ? [UIColor colorWithRed:0.6 green:0.1 blue:0.1 alpha:0.9] : [UIColor blackColor];
    self.onB.layer.borderColor = st.isActive ? [UIColor colorWithRed:1 green:0.2 blue:0.2 alpha:0.9].CGColor : [UIColor colorWithRed:0.15 green:0.15 blue:0.15 alpha:0.6].CGColor;
    [self.n postMic:st.selectedIdx+1];
    [self.n postRun:st.isActive];
}

- (void)tapMs {
    YallaState *st = [YallaState s];
    st.msIdx = (st.msIdx + 1) % 5;
    [self.msB setTitle:[NSString stringWithFormat:@"ms:%d", [st ms]] forState:UIControlStateNormal];
    [self upd];
}

- (void)tapCxx {
    YallaState *st = [YallaState s];
    st.cxxOn = !st.cxxOn;
    self.cxxB.backgroundColor = st.cxxOn ? [UIColor colorWithRed:0.6 green:0.1 blue:0.6 alpha:0.9] : [UIColor blackColor];
    self.cxxB.layer.borderColor = st.cxxOn ? [UIColor colorWithRed:1 green:0.2 blue:1 alpha:0.9].CGColor : [UIColor colorWithRed:0.15 green:0.15 blue:0.15 alpha:0.6].CGColor;
    [self upd];
}

- (void)tapLite {
    YallaState *st = [YallaState s];
    st.liteOn = !st.liteOn;
    self.liteB.backgroundColor = st.liteOn ? [UIColor colorWithRed:0.1 green:0.1 blue:0.6 alpha:0.9] : [UIColor blackColor];
    self.liteB.layer.borderColor = st.liteOn ? [UIColor colorWithRed:0.2 green:0.2 blue:1 alpha:0.9].CGColor : [UIColor colorWithRed:0.15 green:0.15 blue:0.15 alpha:0.6].CGColor;
    [self upd];
}

- (void)tapHide { self.panel.hidden = YES; self.dot.hidden = NO; }
- (void)showP { self.panel.hidden = NO; self.dot.hidden = YES; }

- (void)pan:(UIPanGestureRecognizer *)g {
    UIView *v = g.view;
    if (g.state == 1) {
        objc_setAssociatedObject(g, _cmd, [NSValue valueWithCGPoint:v.center], 1);
    } else if (g.state == 2) {
        NSValue *val = objc_getAssociatedObject(g, _cmd);
        if (val) {
            CGPoint s = [val CGPointValue];
            CGPoint t = [g translationInView:v.superview];
            v.center = CGPointMake(s.x + t.x, s.y + t.y);
        }
    }
}

- (void)upd {
    YallaState *st = [YallaState s];
    int cnt = [[TapReg shared] cnt];
    NSString *slot = st.selectedIdx >= 0 ? [NSString stringWithFormat:@"Slot %d", st.selectedIdx+1] : @"None";
    self.st.text = [NSString stringWithFormat:@"%@ | ms:%d %@%@ (%d)", slot, [st ms], st.liteOn ? @"LiTE✓" : @"", st.cxxOn ? @" cxx✓" : @"", cnt];
}

@end

static YallaUI *gUI;

__attribute__((constructor)) static void init() {
    @autoreleasepool {
        if (![[[NSBundle mainBundle] bundleIdentifier] isEqualToString:kYalla]) return;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (gUI || !ym_keyWindow()) return;
            gUI = [[YallaUI alloc] init];
        });
    }
}
