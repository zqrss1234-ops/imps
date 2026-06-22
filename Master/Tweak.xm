#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

#define kYallaBundle @"com.yalla.yallalite"

static int kMsVals[] = {50, 25, 10, 5, 1};
static int s_sel = -1;
static int s_msIdx = 2;
static BOOL s_on = NO;
static BOOL s_cxx = NO;
static BOOL s_lite = NO;
static UIView *s_panel;
static UIView *s_passView;
static UITextField *s_passField;
static UILabel *s_st, *s_msL, *s_cxxL, *s_liteL;
static NSMutableArray *s_nums;
static BOOL s_visible = YES;

static UILabel *makeLabel(CGFloat x, CGFloat y, CGFloat w, CGFloat h, NSString *t) {
    UILabel *lb = [[UILabel alloc] initWithFrame:CGRectMake(x, y, w, h)];
    lb.text = t;
    lb.textColor = [UIColor whiteColor];
    lb.font = [UIFont boldSystemFontOfSize:11];
    lb.textAlignment = NSTextAlignmentCenter;
    lb.userInteractionEnabled = NO;
    return lb;
}

@interface _YM : NSObject @end
@implementation _YM
+ (void)num:(UIButton *)b {
    if (s_on) return;
    int idx = (int)b.tag;
    s_sel = idx;
    for (UIButton *nb in s_nums) nb.selected = (nb.tag == idx);
    NSString *cmd = [NSString stringWithFormat:@"com.yalla.liteagent.cmd.select.%d", idx];
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge CFStringRef)cmd, NULL, NULL, YES);
}
+ (void)onT {
    s_on = !s_on;
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
    [s_passView removeFromSuperview];
    s_passView = nil;
    [self buildUI];
}
+ (void)buildUI {
    UIWindow *kw = [[UIApplication sharedApplication] keyWindow];
    if (!kw) return;
    UIView *cv = kw.rootViewController.view;
    if (!cv) return;

    s_panel = [[UIView alloc] initWithFrame:CGRectMake(20, 140, 320, 200)];
    s_panel.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.92];
    s_panel.layer.cornerRadius = 18;
    s_panel.layer.borderWidth = 2;
    s_panel.layer.borderColor = [UIColor blackColor].CGColor;

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(10, 8, 120, 18)];
    title.text = @"YallaMaster";
    title.textColor = [UIColor whiteColor];
    title.font = [UIFont boldSystemFontOfSize:13];
    [s_panel addSubview:title];

    UILabel *sub = [[UILabel alloc] initWithFrame:CGRectMake(130, 8, 180, 18)];
    sub.textColor = [UIColor lightGrayColor];
    sub.font = [UIFont systemFontOfSize:10];
    sub.textAlignment = NSTextAlignmentRight;
    [s_panel addSubview:sub];

    s_nums = [NSMutableArray array];
    for (int i = 1; i <= 10; i++) {
        int col = (i - 1) % 5;
        int row = (i - 1) / 5;
        UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
        b.frame = CGRectMake(10 + col * 60, 30 + row * 30, 50, 24);
        [b setTitle:[@(i) stringValue] forState:UIControlStateNormal];
        [b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        [b setTitleColor:[UIColor blackColor] forState:UIControlStateSelected];
        b.backgroundColor = [UIColor darkGrayColor];
        b.layer.cornerRadius = 6;
        b.layer.borderWidth = 1;
        b.layer.borderColor = [UIColor grayColor].CGColor;
        b.titleLabel.font = [UIFont boldSystemFontOfSize:12];
        b.tag = i;
        [b addTarget:self action:@selector(num:) forControlEvents:UIControlEventTouchUpInside];
        [s_panel addSubview:b];
        [s_nums addObject:b];
    }

    int y = 94;
    int w = 52;
    UIButton *onBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    onBtn.frame = CGRectMake(10, y, w, 28);
    [onBtn setTitle:@"ON" forState:UIControlStateNormal];
    [onBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    onBtn.backgroundColor = [UIColor colorWithRed:0.2 green:0.5 blue:0.2 alpha:1];
    onBtn.layer.cornerRadius = 8;
    [onBtn addTarget:self action:@selector(onT) forControlEvents:UIControlEventTouchUpInside];
    [s_panel addSubview:onBtn];

    s_msL = makeLabel(72, y, w, 28, @"10ms");
    s_msL.tag = 101;
    [s_panel addSubview:s_msL];
    UIButton *msBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    msBtn.frame = CGRectMake(72, y, w, 28);
    msBtn.backgroundColor = [UIColor clearColor];
    [msBtn addTarget:self action:@selector(msT) forControlEvents:UIControlEventTouchUpInside];
    [s_panel addSubview:msBtn];

    s_cxxL = makeLabel(134, y, w, 28, @"cxx");
    s_cxxL.tag = 102;
    [s_panel addSubview:s_cxxL];
    UIButton *cxxBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    cxxBtn.frame = CGRectMake(134, y, w, 28);
    cxxBtn.backgroundColor = [UIColor clearColor];
    [cxxBtn addTarget:self action:@selector(cxxT) forControlEvents:UIControlEventTouchUpInside];
    [s_panel addSubview:cxxBtn];

    s_liteL = makeLabel(196, y, w, 28, @"LiTE");
    s_liteL.tag = 103;
    [s_panel addSubview:s_liteL];
    UIButton *liteBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    liteBtn.frame = CGRectMake(196, y, w, 28);
    liteBtn.backgroundColor = [UIColor clearColor];
    [liteBtn addTarget:self action:@selector(liteT) forControlEvents:UIControlEventTouchUpInside];
    [s_panel addSubview:liteBtn];

    UIButton *hideBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    hideBtn.frame = CGRectMake(258, y, w, 28);
    [hideBtn setTitle:@"Hide" forState:UIControlStateNormal];
    [hideBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    hideBtn.backgroundColor = [UIColor darkGrayColor];
    hideBtn.layer.cornerRadius = 8;
    [hideBtn addTarget:self action:@selector(hideT) forControlEvents:UIControlEventTouchUpInside];
    [s_panel addSubview:hideBtn];

    s_st = [[UILabel alloc] initWithFrame:CGRectMake(10, 130, 300, 18)];
    s_st.textColor = [UIColor lightGrayColor];
    s_st.font = [UIFont systemFontOfSize:9];
    s_st.textAlignment = NSTextAlignmentRight;
    [s_panel addSubview:s_st];

    [cv addSubview:s_panel];
}
+ (void)showPass {
    UIWindow *kw = [[UIApplication sharedApplication] keyWindow];
    if (!kw) return;
    UIView *cv = kw.rootViewController.view;
    if (!cv) return;

    s_passView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, [UIScreen mainScreen].bounds.size.width, [UIScreen mainScreen].bounds.size.height)];
    s_passView.backgroundColor = [UIColor colorWithWhite:0 alpha:0.85];
    s_passView.userInteractionEnabled = YES;

    UIView *box = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 200, 130)];
    box.center = CGPointMake(s_passView.center.x, s_passView.center.y - 60);
    box.backgroundColor = [UIColor colorWithWhite:0.12 alpha:0.95];
    box.layer.cornerRadius = 16;
    box.layer.borderWidth = 2;
    box.layer.borderColor = [UIColor blackColor].CGColor;

    UILabel *pl = [[UILabel alloc] initWithFrame:CGRectMake(0, 16, 200, 20)];
    pl.text = @"Enter Passcode";
    pl.textColor = [UIColor whiteColor];
    pl.font = [UIFont boldSystemFontOfSize:14];
    pl.textAlignment = NSTextAlignmentCenter;
    [box addSubview:pl];

    s_passField = [[UITextField alloc] initWithFrame:CGRectMake(30, 44, 140, 30)];
    s_passField.placeholder = @"***";
    s_passField.textAlignment = NSTextAlignmentCenter;
    s_passField.keyboardType = UIKeyboardTypeNumberPad;
    s_passField.secureTextEntry = YES;
    s_passField.textColor = [UIColor whiteColor];
    s_passField.backgroundColor = [UIColor colorWithWhite:0.2 alpha:1];
    s_passField.layer.cornerRadius = 8;
    [box addSubview:s_passField];

    UIButton *psBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    psBtn.frame = CGRectMake(40, 84, 120, 28);
    [psBtn setTitle:@"Submit" forState:UIControlStateNormal];
    [psBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    psBtn.backgroundColor = [UIColor colorWithRed:0.2 green:0.4 blue:0.7 alpha:1];
    psBtn.layer.cornerRadius = 8;
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
