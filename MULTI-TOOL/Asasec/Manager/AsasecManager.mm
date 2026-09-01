#import <UIKit/UIKit.h>
#import <dispatch/dispatch.h>

#import "../../Imgui/Ui/AsasecUi.h"
#import "../../GuiAlert/GuiAlert.h"
#include "../../Imgui/imgui.h"

#pragma mark - COMBAT & SETTINGS CALLBACKS

static bool gSwitch1Val = false;
static void Switch1Toggled(bool isOn) {
    if (isOn) {
        [GuiAlert SonUyariYapi:@"Test Switch 1" devamEt:^{
            [GuiAlert SaniyeliUyariBaslik:@"Başarılı" mesaj:@"İşlem Onaylandı" saniye:2.0];
        } iptalEt:^{
           // İptal
        }];
    }
}

static bool gSwitch2Val = false;
static void Switch2Toggled(bool isOn) {
    if (isOn) {
        [GuiAlert SonUyariYapi:@"Test Switch 2" devamEt:^{
            [GuiAlert SaniyeliUyariBaslik:@"Başarılı" mesaj:@"İşlem Onaylandı" saniye:2.0];
        } iptalEt:^{
            // İptal
        }];
    }
}

static bool gCheckboxVal = false;
static void CheckboxToggled(bool isChecked) {
    if (isChecked) {
        [GuiAlert SaniyeliUyariBaslik:@"Başarılı" mesaj:@"Checkbox Aktif Edildi" saniye:2.0];
    }
}

static float gSliderVal = 50.0f;
static void SliderChanged(float value) {
    // Slider değer değişimi callback fonksiyonu
}

static void Button1Clicked(void) {
    [GuiAlert SonUyariYapi:@"Test Butonu 1" devamEt:^{
        [GuiAlert SaniyeliUyariBaslik:@"Başarılı" mesaj:@"İşlem Onaylandı" saniye:2.0];
    } iptalEt:^{
        // İptal
    }];
}

static void Button2Clicked(void) {
    [GuiAlert SonUyariYapi:@"Test Butonu 2" devamEt:^{
        [GuiAlert SaniyeliUyariBaslik:@"Başarılı" mesaj:@"İşlem Onaylandı" saniye:2.0];
    } iptalEt:^{
        // İptal
    }];
}

#pragma mark - Menüyü Dışarıya Açan Başlatıcı Fonksiyon

void StartAsasecMenu(void) {
    
    /*
     * COMBAT & SETTINGS
     */
    ASASECUiSwitch("Switch Deneme", "Switch 1", &gSwitch1Val, Switch1Toggled);
    ASASECUiSwitch("Switch Deneme", "Switch 2 (God Mode)", &gSwitch2Val, Switch2Toggled);
    
    ASASECUiCheckbox("Diğer Özellikler", "Test Checkbox", &gCheckboxVal, CheckboxToggled);
    ASASECUiSlider("Diğer Özellikler", "Test Slider", &gSliderVal, 0.0f, 100.0f, SliderChanged);

    ASASECUiButton("Buton Deneme", "Test Butonu 1", Button1Clicked);
    ASASECUiButton("Buton Deneme", "Test Butonu 2", Button2Clicked);

    // ImGui arayüzü başlatılıyor:
    ASASECImGuiStart();
}
