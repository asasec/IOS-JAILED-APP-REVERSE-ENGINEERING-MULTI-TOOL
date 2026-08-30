#import <UIKit/UIKit.h>
#import <dispatch/dispatch.h>

#import "../Imgui/Gui/AsasecImgui.h"
#include "../Imgui/imgui.h"

// Dışarıdan gelen kayıt fonksiyonlarının prototipleri
extern void ASASECRegisterFeature(const char *category, const char *title, bool *valuePointer, void (*callback)(bool));
extern void ASASECRegisterButton(const char *category, const char *title, void (*callback)(void));

// 1. Switch Değişkeni ve İşlemi
static bool gSwitch1Val = false;
void Switch1Toggled(bool isOn) {
    if (isOn) {
        NSLog(@"Switch 1 Açıldı");
    } else {
        NSLog(@"Switch 1 Kapatıldı");
    }
}

// 2. Buton Tıklanma İşlemi
void Button1Clicked(void) {
    NSLog(@"Butona tıklandı!");
}

// 3. Otomatik Kayıt Yapısı
__attribute__((constructor)) void RegisterItems() {
    // Combat kategorisinin altına Switch ekler
    ASASECRegisterFeature("Combat", "Swicht 1", &gSwitch1Val, Switch1Toggled);
    
    // Combat kategorisinin altına Buton ekler
    ASASECRegisterButton("Combat", "Test Butonu", Button1Clicked);
}

// 4. Menüyü Başlatan Constructor
%ctor
{
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIWindow *mainWindow = nil;
        for (UIWindow *window in [UIApplication sharedApplication].windows) {
            if (window.isKeyWindow) {
                mainWindow = window;
                break;
            }
        }
        
        if (mainWindow) {
            ASASECImGuiStart();
        } else {
            ASASECImGuiStart();
        }
    });
}
