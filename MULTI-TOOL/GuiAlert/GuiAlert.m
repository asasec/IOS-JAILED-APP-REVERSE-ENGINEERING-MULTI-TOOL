#import "GuiAlert.h"

@implementation GuiAlert

static UIWindow *activeWindow = nil;

+ (UIViewController *)topController {
    UIWindow *window = nil;
    if (@available(iOS 13.0, *)) {
        for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive) {
                for (UIWindow *w in scene.windows) {
                    if (w.isKeyWindow) {
                        window = w;
                        break;
                    }
                }
            }
        }
    }
    if (!window) {
        if (@available(iOS 13.0, *)) {
            for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
                if (scene.activationState == UISceneActivationStateForegroundActive) {
                    window = scene.windows.firstObject;
                    break;
                }
            }
        }
    }
    
    UIViewController *topController = window.rootViewController;
    while (topController.presentedViewController) {
        topController = topController.presentedViewController;
    }
    return topController;
}

+ (void)BilgiAktarBaslik:(NSString *)baslik mesaj:(NSString *)mesaj {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *topVC = [self topController];
        if (!topVC) return;
        
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:baslik
                                                                    message:mesaj
                                                             preferredStyle:UIAlertControllerStyleAlert];
        
        UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"Tamam"
                                                          style:UIAlertActionStyleDefault
                                                        handler:nil];
        [alert addAction:okAction];
        [topVC presentViewController:alert animated:YES completion:nil];
    });
}

+ (void)BaslangicEkraniWithFlexGui:(void (^)(void))flexGui
                         dinleyici:(void (^)(void))dinleyici
                      storeKitHook:(void (^)(void))storeKitHook
                             kapat:(void (^)(void))kapat {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *topVC = [self topController];
        if (!topVC) return;
        
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"@asasecmod"
                                                                    message:nil
                                                             preferredStyle:UIAlertControllerStyleAlert];
        
        UIAlertAction *flexAction = [UIAlertAction actionWithTitle:@"FLEX Arayüzünü Aç"
                                                             style:UIAlertActionStyleDefault
                                                           handler:^(UIAlertAction * _Nonnull action) {
            if (flexGui) flexGui();
        }];
        
        UIAlertAction *dinleyiciAction = [UIAlertAction actionWithTitle:@"Dinleyici Menüsü"
                                                                  style:UIAlertActionStyleDefault
                                                                handler:^(UIAlertAction * _Nonnull action) {
            if (dinleyici) dinleyici();
        }];
        
        UIAlertAction *storeKitAction = [UIAlertAction actionWithTitle:@"StoreKit-1 Satın Almaları Yamala"
                                                                 style:UIAlertActionStyleDefault
                                                               handler:^(UIAlertAction * _Nonnull action) {
            if (storeKitHook) storeKitHook();
        }];
        
        UIAlertAction *kapatAction = [UIAlertAction actionWithTitle:@"Menüyü Kapat"
                                                              style:UIAlertActionStyleCancel
                                                            handler:^(UIAlertAction * _Nonnull action) {
            if (kapat) kapat();
        }];
        
        [alert addAction:flexAction];
        [alert addAction:dinleyiciAction];
        [alert addAction:storeKitAction];
        [alert addAction:kapatAction];
        
        [topVC presentViewController:alert animated:YES completion:nil];
    });
}

+ (void)OyunaOzelModlu:(void (^)(void))modlu
                modsuz:(void (^)(void))modsuz
                mesaj:(NSString *)mesaj {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *topVC = [self topController];
        if (!topVC) return;
        
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"@asasecmod"
                                                                    message:mesaj
                                                             preferredStyle:UIAlertControllerStyleAlert];
        
        [alert addAction:[UIAlertAction actionWithTitle:@"Modu Yamala ve Giriş Yap" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            if (modlu) modlu();
        }]];
        
        [alert addAction:[UIAlertAction actionWithTitle:@"Modsuz Giriş Yap" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            if (modsuz) modsuz();
        }]];
        
        [topVC presentViewController:alert animated:YES completion:nil];
    });
}

+ (void)SonUyariYapi:(NSString *)yapi
            devamEt:(void (^)(void))devamEt
           iptalEt:(void (^)(void))iptalEt {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *topVC = [self topController];
        if (!topVC) return;
        
        NSString *mesaj = [NSString stringWithFormat:@"Emin Misin?\nDevam Etmek İstediğin Yapı: %@", yapi];
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"@asasecmod"
                                                                    message:mesaj
                                                             preferredStyle:UIAlertControllerStyleAlert];
        
        [alert addAction:[UIAlertAction actionWithTitle:@"Devam Et" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            if (devamEt) devamEt();
        }]];
        
        [alert addAction:[UIAlertAction actionWithTitle:@"Vazgeç" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            if (iptalEt) iptalEt();
        }]];
        
        [topVC presentViewController:alert animated:YES completion:nil];
    });
}

+ (void)dismiss {
    if (activeWindow) {
        activeWindow.hidden = YES;
        activeWindow = nil;
    }
}

+ (void)SaniyeliUyariBaslik:(NSString *)baslik
                     mesaj:(NSString *)mesaj
                    saniye:(NSTimeInterval)saniye {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self dismiss];
        
        UIWindowScene *targetScene = nil;
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]] && scene.activationState == UISceneActivationStateForegroundActive) {
                targetScene = (UIWindowScene *)scene;
                break;
            }
        }
        
        UIWindow *window = nil;
        if (targetScene) {
            window = [[UIWindow alloc] initWithWindowScene:targetScene];
        } else {
            // Fallback for edge cases: use the first available connected scene's screen bounds if possible
            UIScene *firstScene = [UIApplication sharedApplication].connectedScenes.anyObject;
            if ([firstScene isKindOfClass:[UIWindowScene class]]) {
                window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)firstScene];
            } else {
                window = [[UIWindow alloc] init];
            }
        }
        
        window.windowLevel = UIWindowLevelAlert + 1;
        window.hidden = NO;
        
        UIViewController *viewController = [[UIViewController alloc] init];
        viewController.view.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.4];
        
        UIView *alertBox = [[UIView alloc] init];
        alertBox.backgroundColor = [[UIColor systemBackgroundColor] colorWithAlphaComponent:0.95];
        alertBox.layer.cornerRadius = 14;
        alertBox.layer.shadowColor = [UIColor blackColor].CGColor;
        alertBox.layer.shadowOpacity = 0.2;
        alertBox.layer.shadowOffset = CGSizeMake(0, 4);
        alertBox.layer.shadowRadius = 10;
        alertBox.translatesAutoresizingMaskIntoConstraints = NO;
        
        UILabel *titleLabel = [[UILabel alloc] init];
        titleLabel.text = baslik;
        titleLabel.numberOfLines = 0;
        titleLabel.textAlignment = NSTextAlignmentCenter;
        titleLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightBold];
        titleLabel.textColor = [UIColor labelColor];
        titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        
        UILabel *messageLabel = [[UILabel alloc] init];
        messageLabel.text = mesaj;
        messageLabel.numberOfLines = 0;
        messageLabel.textAlignment = NSTextAlignmentCenter;
        messageLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightRegular];
        messageLabel.textColor = [UIColor secondaryLabelColor];
        messageLabel.translatesAutoresizingMaskIntoConstraints = NO;
        
        [alertBox addSubview:titleLabel];
        [alertBox addSubview:messageLabel];
        [viewController.view addSubview:alertBox];
        window.rootViewController = viewController;
        
        [NSLayoutConstraint activateConstraints:@[
            [alertBox.centerXAnchor constraintEqualToAnchor:viewController.view.centerXAnchor],
            [alertBox.centerYAnchor constraintEqualToAnchor:viewController.view.centerYAnchor],
            [alertBox.widthAnchor constraintGreaterThanOrEqualToConstant:240],
            [alertBox.widthAnchor constraintLessThanOrEqualToConstant:320],
            
            [titleLabel.topAnchor constraintEqualToAnchor:alertBox.topAnchor constant:20],
            [titleLabel.leadingAnchor constraintEqualToAnchor:alertBox.leadingAnchor constant:20],
            [titleLabel.trailingAnchor constraintEqualToAnchor:alertBox.trailingAnchor constant:-20],
            
            [messageLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:8],
            [messageLabel.bottomAnchor constraintEqualToAnchor:alertBox.bottomAnchor constant:-20],
            [messageLabel.leadingAnchor constraintEqualToAnchor:alertBox.leadingAnchor constant:20],
            [messageLabel.trailingAnchor constraintEqualToAnchor:alertBox.trailingAnchor constant:-20]
        ]];
        
        activeWindow = window;
        
        if (saniye > 0) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(saniye * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self dismiss];
            });
        }
    });
}

@end
