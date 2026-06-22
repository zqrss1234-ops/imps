#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

#define kYallaBundle @"com.yalla.yallalite"

static const int kMsVals[] = {50, 25, 10, 5, 1};
static int s_sel = -1;
static int s_msIdx = 0;
static BOOL s_on = NO;
static BOOL s_cxx = NO;
static BOOL s_lite = NO;
static UIView *s_panel;
static UIView *s_passView;
static UITextField *s_passField;
static UILabel *s_st, *s_msL, *s_cxxL, *s_liteL, *s_selL;
static NSMutableArray *s_nums;
static BOOL s_visible = YES;

static UILabel *mkLab(CGFloat x, CGFloat y, CGFloat w, CGFloat h, NSString *t, CGFloat fs) {
    UILabel *lb = [[UILabel alloc] initWithFrame:CGRectMake(x, y, w, h)];
    lb.text = t;
    lb.textColor = [UIColor whiteColor];
    lb.font = [UIFont boldSystemFontOfSize:fs];
    lb.textAlignment = NSTextAlignmentCenter;
    lb.userInteractionEnabled = NO;
    return lb;
}
static UIView *sep(CGFloat x, CGFloat y, CGFloat w) {
    UIView *v = [[UIView alloc] initWithFrame:CGRectMake(x, y, w, 1)];
    v.backgroundColor = [UIColor colorWithWhite:0.3 alpha:0.6];
    v.userInteractionEnabled = NO;
    return v;
}

@interface _YM : NSObject @end
@implementation _YM
+ (void)num:(UIButton *)b {
    if (s_on) return;
    int idx = (int)b.tag;
    s_sel = idx;
    for (UIButton *nb in s_nums) nb.selected = (nb.tag == idx);
    s_selL.text = [NSString stringWithFormat:@"Slot %d selected", idx];
    NSString *cmd = [NSString stringWithFormat:@"com.yalla.liteagent.cmd.select.%d", idx];
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge CFStringRef)cmd, NULL, NULL, YES);
}
+ (void)onT {
    s_on = !s_on;
    s_st.text = s_on ? @"ON" : @"OFF";
    for (long i = 1; i <= 10; i++) {
        NSString *cmd = s_on
            ? [NSString stringWithFormat:@"com.yalla.liteagent.cmd.micon.%ld", i]
            : [NSString stringWithFormat:@"com.yalla.liteagent.cmd.micoff.%ld", i];
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge CFStringRef)cmd, NULL, NULL, YES);
    }
}
+ (void)msT {
    s_msIdx = s_msIdx >= 4 ? 0 : s_msIdx + 1;
    s_msL.text = [NSString stringWithFormat:@"%dms", kMsVals[s_msIdx]];
    NSString *cmd = [NSString stringWithFormat:@"com.yalla.liteagent.cmd.ms.%d", kMsVals[s_msIdx]];
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge CFStringRef)cmd, NULL, NULL, YES);
}
+ (void)cxxT {
    s_cxx = !s_cxx;
    s_cxxL.textColor = s_cxx ? [UIColor yellowColor] : [UIColor whiteColor];
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR("com.yalla.liteagent.cmd.cxx"), NULL, NULL, YES);
}
+ (void)liteT {
    s_lite = !s_lite;
    s_liteL.textColor = s_lite ? [UIColor yellowColor] : [UIColor whiteColor];
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR("com.yalla.liteagent.cmd.lite"), NULL, NULL, YES);
}
+ (void)hideT {
    s_visible = !s_visible;
    s_panel.hidden = !s_visible;
}
+ (void)submitPass {
    NSString *code = s_passField.text ?: @"";
    if (![code isEqualToString:@"515"]) {
        UIColor *orig = s_passField.backgroundColor;
        s_passField.backgroundColor = [UIColor colorWithRed:1 green:0.2 blue:0.2 alpha:0.5];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.25 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            s_passField.backgroundColor = orig;
        });
        s_passField.text = @"";
        return;
    }
    [s_passField resignFirstResponder];
    s_passField = nil;
    [s_passView removeFromSuperview];
    s_passView = nil;
    [self buildUI];
}
+ (void)buildUI {
    UIWindow *kw = [[UIApplication sharedApplication] keyWindow];
    if (!kw) return;
    UIView *cv = kw.rootViewController.view;
    if (!cv) return;

    s_panel = [[UIView alloc] initWithFrame:CGRectMake(16, 130, 348, 188)];
    s_panel.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.94];
    s_panel.layer.cornerRadius = 18;
    s_panel.layer.borderWidth = 2;
    s_panel.layer.borderColor = [UIColor blackColor].CGColor;

    // Title
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(14, 8, 140, 20)];
    title.text = @"YallaMaster";
    title.textColor = [UIColor whiteColor];
    title.font = [UIFont boldSystemFontOfSize:15];
    [s_panel addSubview:title];

    s_st = [[UILabel alloc] initWithFrame:CGRectMake(160, 8, 178, 20)];
    s_st.textColor = [UIColor colorWithRed:0.4 green:0.8 blue:0.4 alpha:1];
    s_st.font = [UIFont systemFontOfSize:12];
    s_st.textAlignment = NSTextAlignmentRight;
    s_st.text = @"Ready";
    [s_panel addSubview:s_st];

    [s_panel addSubview:sep(10, 30, 328)];

    // Slots label
    UILabel *sl = [[UILabel alloc] initWithFrame:CGRectMake(14, 33, 100, 16)];
    sl.text = @"Slots";
    sl.textColor = [UIColor colorWithWhite:0.7 alpha:1];
    sl.font = [UIFont systemFontOfSize:10];
    [s_panel addSubview:sl];

    // Number buttons 1-10 (2 rows, 5 cols)
    s_nums = [NSMutableArray array];
    for (int i = 1; i <= 10; i++) {
        int col = (i - 1) % 5;
        int row = (i - 1) / 5;
        UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
        b.frame = CGRectMake(14 + col * 64, 52 + row * 30, 56, 24);
        [b setTitle:[@(i) stringValue] forState:UIControlStateNormal];
        [b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        [b setTitleColor:[UIColor blackColor] forState:UIControlStateSelected];
        b.backgroundColor = [UIColor darkGrayColor];
        b.layer.cornerRadius = 6;
        b.layer.borderWidth = 1.5;
        b.layer.borderColor = [UIColor grayColor].CGColor;
        b.titleLabel.font = [UIFont boldSystemFontOfSize:13];
        b.tag = i;
        [b addTarget:self action:@selector(num:) forControlEvents:UIControlEventTouchUpInside];
        [s_panel addSubview:b];
        [s_nums addObject:b];
    }

    [s_panel addSubview:sep(10, 112, 328)];

    // Controls label
    UILabel *cl = [[UILabel alloc] initWithFrame:CGRectMake(14, 114, 100, 16)];
    cl.text = @"Controls";
    cl.textColor = [UIColor colorWithWhite:0.7 alpha:1];
    cl.font = [UIFont systemFontOfSize:10];
    [s_panel addSubview:cl];

    int yb = 132;
    int bw = 58;

    UIButton *onBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    onBtn.frame = CGRectMake(14, yb, bw, 28);
    [onBtn setTitle:@"ON" forState:UIControlStateNormal];
    [onBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    onBtn.backgroundColor = [UIColor colorWithRed:0.2 green:0.5 blue:0.2 alpha:1];
    onBtn.layer.cornerRadius = 8;
    onBtn.layer.borderWidth = 1;
    onBtn.layer.borderColor = [UIColor colorWithRed:0.3 green:0.7 blue:0.3 alpha:0.8].CGColor;
    [onBtn addTarget:self action:@selector(onT) forControlEvents:UIControlEventTouchUpInside];
    [s_panel addSubview:onBtn];

    s_msL = mkLab(80, yb, bw, 28, @"50ms", 12);
    s_msL.layer.borderWidth = 1;
    s_msL.layer.borderColor = [UIColor colorWithWhite:0.3 alpha:0.6].CGColor;
    s_msL.layer.cornerRadius = 8;
    s_msL.tag = 101;
    [s_panel addSubview:s_msL];
    UIButton *msBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    msBtn.frame = CGRectMake(80, yb, bw, 28);
    msBtn.backgroundColor = [UIColor clearColor];
    [msBtn addTarget:self action:@selector(msT) forControlEvents:UIControlEventTouchUpInside];
    [s_panel addSubview:msBtn];

    s_cxxL = mkLab(146, yb, bw, 28, @"cxx", 12);
    s_cxxL.layer.borderWidth = 1;
    s_cxxL.layer.borderColor = [UIColor colorWithWhite:0.3 alpha:0.6].CGColor;
    s_cxxL.layer.cornerRadius = 8;
    s_cxxL.tag = 102;
    [s_panel addSubview:s_cxxL];
    UIButton *cxxBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    cxxBtn.frame = CGRectMake(146, yb, bw, 28);
    cxxBtn.backgroundColor = [UIColor clearColor];
    [cxxBtn addTarget:self action:@selector(cxxT) forControlEvents:UIControlEventTouchUpInside];
    [s_panel addSubview:cxxBtn];

    s_liteL = mkLab(212, yb, bw, 28, @"LiTE", 12);
    s_liteL.layer.borderWidth = 1;
    s_liteL.layer.borderColor = [UIColor colorWithWhite:0.3 alpha:0.6].CGColor;
    s_liteL.layer.cornerRadius = 8;
    s_liteL.tag = 103;
    [s_panel addSubview:s_liteL];
    UIButton *liteBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    liteBtn.frame = CGRectMake(212, yb, bw, 28);
    liteBtn.backgroundColor = [UIColor clearColor];
    [liteBtn addTarget:self action:@selector(liteT) forControlEvents:UIControlEventTouchUpInside];
    [s_panel addSubview:liteBtn];

    UIButton *hideBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    hideBtn.frame = CGRectMake(278, yb, bw, 28);
    [hideBtn setTitle:@"Hide" forState:UIControlStateNormal];
    [hideBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    hideBtn.backgroundColor = [UIColor darkGrayColor];
    hideBtn.layer.cornerRadius = 8;
    hideBtn.layer.borderWidth = 1;
    hideBtn.layer.borderColor = [UIColor lightGrayColor].CGColor;
    [hideBtn addTarget:self action:@selector(hideT) forControlEvents:UIControlEventTouchUpInside];
    [s_panel addSubview:hideBtn];

    // Selected slot indicator
    s_selL = [[UILabel alloc] initWithFrame:CGRectMake(14, 166, 324, 16)];
    s_selL.textColor = [UIColor colorWithWhite:0.6 alpha:1];
    s_selL.font = [UIFont systemFontOfSize:10];
    s_selL.textAlignment = NSTextAlignmentCenter;
    s_selL.text = @"No slot selected";
    [s_panel addSubview:s_selL];

    [cv addSubview:s_panel];
}
+ (void)showPass {
    UIWindow *kw = [[UIApplication sharedApplication] keyWindow];
    if (!kw) return;
    UIView *cv = kw.rootViewController.view;
    if (!cv) return;

    s_passView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, [UIScreen mainScreen].bounds.size.width, [UIScreen mainScreen].bounds.size.height)];
    s_passView.backgroundColor = [UIColor colorWithWhite:0 alpha:0.88];
    s_passView.userInteractionEnabled = YES;

    UIView *box = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 220, 140)];
    box.center = CGPointMake(s_passView.center.x, s_passView.center.y - 60);
    box.backgroundColor = [UIColor colorWithWhite:0.12 alpha:0.95];
    box.layer.cornerRadius = 18;
    box.layer.borderWidth = 2;
    box.layer.borderColor = [UIColor blackColor].CGColor;

    UILabel *pl = [[UILabel alloc] initWithFrame:CGRectMake(0, 18, 220, 20)];
    pl.text = @"YallaMaster Passcode";
    pl.textColor = [UIColor whiteColor];
    pl.font = [UIFont boldSystemFontOfSize:14];
    pl.textAlignment = NSTextAlignmentCenter;
    [box addSubview:pl];

    UILabel *inst = [[UILabel alloc] initWithFrame:CGRectMake(0, 40, 220, 16)];
    inst.text = @"Enter code to continue";
    inst.textColor = [UIColor colorWithWhite:0.6 alpha:1];
    inst.font = [UIFont systemFontOfSize:11];
    inst.textAlignment = NSTextAlignmentCenter;
    [box addSubview:inst];

    s_passField = [[UITextField alloc] initWithFrame:CGRectMake(40, 62, 140, 30)];
    s_passField.placeholder = @"***";
    s_passField.textAlignment = NSTextAlignmentCenter;
    s_passField.keyboardType = UIKeyboardTypeNumberPad;
    s_passField.secureTextEntry = YES;
    s_passField.textColor = [UIColor whiteColor];
    s_passField.backgroundColor = [UIColor colorWithWhite:0.2 alpha:1];
    s_passField.layer.cornerRadius = 8;
    s_passField.layer.borderWidth = 1;
    s_passField.layer.borderColor = [UIColor colorWithWhite:0.4 alpha:1].CGColor;
    [box addSubview:s_passField];

    UIButton *psBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    psBtn.frame = CGRectMake(50, 100, 120, 28);
    [psBtn setTitle:@"Submit" forState:UIControlStateNormal];
    [psBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    psBtn.backgroundColor = [UIColor colorWithRed:0.2 green:0.4 blue:0.7 alpha:1];
    psBtn.layer.cornerRadius = 10;
    [psBtn addTarget:self action:@selector(submitPass) forControlEvents:UIControlEventTouchUpInside];
    [box addSubview:psBtn];

    [s_passView addSubview:box];
    [cv addSubview:s_passView];
    [s_passField becomeFirstResponder];
}
@end

__attribute__((constructor)) static void init() {
    @autoreleasepool {
        NSString *bid = [[NSBundle mainBundle] bundleIdentifier];
        if (![bid isEqualToString:kYallaBundle]) return;
        dispatch_async(dispatch_get_main_queue(), ^{
#ifdef YM_DIRECT
            [_YM buildUI];
#else
            [_YM showPass];
#endif
        });
    }
}
