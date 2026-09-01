#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface GuiAlert : NSObject

+ (void)BilgiAktarBaslik:(NSString *)baslik mesaj:(NSString *)mesaj;

+ (void)BaslangicEkraniWithFlexGui:(void (^)(void))flexGui
                         dinleyici:(void (^)(void))dinleyici
                      storeKitHook:(void (^)(void))storeKitHook
                             kapat:(void (^)(void))kapat;

+ (void)OyunaOzelModlu:(void (^)(void))modlu
                modsuz:(void (^)(void))modsuz
                mesaj:(NSString *)mesaj;

+ (void)SonUyariYapi:(NSString *)yapi
            devamEt:(void (^)(void))devamEt
           iptalEt:(void (^)(void))iptalEt;

+ (void)SaniyeliUyariBaslik:(NSString *)baslik
                     mesaj:(NSString *)mesaj
                    saniye:(NSTimeInterval)saniye;

@end

NS_ASSUME_NONNULL_END
