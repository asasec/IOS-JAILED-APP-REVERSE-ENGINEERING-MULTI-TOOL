#import <UIKit/UIKit.h>
#import <dispatch/dispatch.h>

#import "../../Imgui/Gui/AsasecImgui.h"
#import "../../GuiAlert/GuiAlert.h"
#include "../../Imgui/imgui.h"

#pragma mark - ASASEC GUI Registration API

extern void ASASECGuiSwitch(const char *category,
                            const char *title,
                            bool *valuePointer,
                            void (*callback)(bool));

extern void ASASECGuiButton(const char *category,
                            const char *title,
                            void (*callback)(void));

#pragma mark - COMBAT & SETTINGS CALLBACKS

static bool gSwitch1Val = false;
static void Switch1Toggled(bool isOn) {
    if (isOn) {
        [GuiAlert SaniyeliUyariBaslik:@"Combat" mesaj:@"Switch 1 Aktifleştirildi" saniye:2.0];
    }
}

static bool gSwitch2Val = false;
static void Switch2Toggled(bool isOn) {
    if (isOn) {
        [GuiAlert BilgiAktarBaslik:@"God Mode" mesaj:@"Ölümsüzlük modu başarıyla açıldı!"];
    }
}

static void Button1Clicked(void) {
    [GuiAlert SonUyariYapi:@"Test Butonu 1" devamEt:^{
        [GuiAlert SaniyeliUyariBaslik:@"Başarılı" mesaj:@"İşlem Onaylandı" saniye:2.0];
    } iptalEt:^{
        // İptal
    }];
}

static void Button2Clicked(void) {
    [GuiAlert DinleyiciMenuBaslik:@"Combat Dinleyicileri"];
}

#pragma mark - Menüyü Dışarıya Açan Başlatıcı Fonksiyon

void StartAsasecMenu(void) {
    
    /*
     * COMBAT
     */
    ASASECGuiSwitch("Combat", "Switch 1", &gSwitch1Val, Switch1Toggled);
    ASASECGuiSwitch("Combat", "Switch 2 (God Mode)", &gSwitch2Val, Switch2Toggled);
    ASASECGuiButton("Combat", "Test Butonu 1", Button1Clicked);
    ASASECGuiButton("Combat", "Test Butonu 2", Button2Clicked);

    // Alert ekranı kaldırıldı, doğrudan ImGui arayüzü başlatılıyor:
    ASASECImGuiStart();
}
