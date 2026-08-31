#import <UIKit/UIKit.h>

extern void StartAsasecMenu(void);

%ctor {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        StartAsasecMenu();
        NSLog(@"[ASASEC] UI direkt olarak başlatıldı!");
    });
}
