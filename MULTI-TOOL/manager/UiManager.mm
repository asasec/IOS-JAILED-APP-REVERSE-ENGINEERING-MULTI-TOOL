#import <UIKit/UIKit.h>
#import <dispatch/dispatch.h>

#import "../ui/AsasecUi.h"
#import "../guialert/GuiAlert.h"
#include "../imgui/imgui.h"

#pragma mark - ASASEC GUI Registration API (Extern Declarations)

extern void ASASECUiSwitch(const char *category,
                            const char *title,
                            bool *valuePointer,
                            void (*callback)(bool));

extern void ASASECUiButton(const char *category,
                            const char *title,
                            void (*callback)(void));

extern void ASASECUiSlider(const char *category,
                            const char *title,
                            float *valuePointer,
                            float minVal,
                            float maxVal,
                            void (*callback)(float));

extern void ASASECUiCheckbox(const char *category,
                              const char *title,
                              bool *valuePointer,
                              void (*callback)(bool));

#pragma mark - COMBAT & SETTINGS CALLBACKS

static bool gSwitchVal = false;
static void SwitchToggled(bool isOn) {
    if (isOn) {
        [GuiAlert SonUyariYapi:@"Test Switch" devamEt:^{
            [GuiAlert SaniyeliUyariBaslik:@"Başarılı" mesaj:@"Switch Açıldı" saniye:2.0];
        } iptalEt:^{
           // İptal
        }];
    } else {
        [GuiAlert SaniyeliUyariBaslik:@"Bilgi" mesaj:@"Switch Kapatıldı" saniye:2.0];
    }
}

static bool gSwitch1Val = false;
static void Switch1Toggled(bool isOn) {
    if (isOn) {
        [GuiAlert SonUyariYapi:@"Test Switch 1" devamEt:^{
            [GuiAlert SaniyeliUyariBaslik:@"Başarılı" mesaj:@"Switch 1 Açıldı" saniye:2.0];
        } iptalEt:^{
           // İptal
        }];
    } else {
        [GuiAlert SaniyeliUyariBaslik:@"Bilgi" mesaj:@"Switch 1 Kapatıldı" saniye:2.0];
    }
}

static bool gSwitch2Val = false;
static void Switch2Toggled(bool isOn) {
    if (isOn) {
        [GuiAlert SonUyariYapi:@"Test Switch 2 (God Mode)" devamEt:^{
            [GuiAlert SaniyeliUyariBaslik:@"Başarılı" mesaj:@"Switch 2 Açıldı" saniye:2.0];
        } iptalEt:^{
            // İptal
        }];
    } else {
        [GuiAlert SaniyeliUyariBaslik:@"Bilgi" mesaj:@"Switch 2 Kapatıldı" saniye:2.0];
    }
}

static bool gCheckboxVal = false;
static void CheckboxToggled(bool isChecked) {
    if (isChecked) {
        [GuiAlert SaniyeliUyariBaslik:@"Başarılı" mesaj:@"Checkbox Aktif Edildi" saniye:2.0];
    } else {
        [GuiAlert SaniyeliUyariBaslik:@"Bilgi" mesaj:@"Checkbox Kapatıldı" saniye:2.0];
    }
}

static bool gCheckbox1Val = false;
static void Checkbox1Toggled(bool isChecked) {
    if (isChecked) {
        [GuiAlert SaniyeliUyariBaslik:@"Başarılı" mesaj:@"Checkbox 1 Aktif Edildi" saniye:2.0];
    } else {
        [GuiAlert SaniyeliUyariBaslik:@"Bilgi" mesaj:@"Checkbox 1 Kapatıldı" saniye:2.0];
    }
}

static bool gCheckbox2Val = false;
static void Checkbox2Toggled(bool isChecked) {
    if (isChecked) {
        [GuiAlert SaniyeliUyariBaslik:@"Başarılı" mesaj:@"Checkbox 2 Aktif Edildi" saniye:2.0];
    } else {
        [GuiAlert SaniyeliUyariBaslik:@"Bilgi" mesaj:@"Checkbox 2 Kapatıldı" saniye:2.0];
    }
}

static float gSliderVal = 75.0f;
static void SliderChanged(float value) {
    // Slider değer değişimi callback fonksiyonu
}

static float gSlider1Val = 50.0f;
static void Slider1Changed(float value) {
    // Slider değer değişimi callback fonksiyonu
}

static float gSlider2Val = 100.0f;
static void Slider2Changed(float value) {
    // Slider değer değişimi callback fonksiyonu
}

static void ButtonClicked(void) {
    [GuiAlert SonUyariYapi:@"Test Butonu" devamEt:^{
        [GuiAlert SaniyeliUyariBaslik:@"Başarılı" mesaj:@"İşlem Onaylandı" saniye:2.0];
    } iptalEt:^{
        // İptal
    }];
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

    ASASECUiSwitch("Full", "Switch", &gSwitchVal, SwitchToggled);
    ASASECUiSlider("Full", "Slider", &gSliderVal, 0.0f, 100.0f, SliderChanged);
    ASASECUiCheckbox("Full", "Checkbox", &gCheckboxVal, CheckboxToggled);
    ASASECUiButton("Full", "Buton", ButtonClicked);
    
    ASASECUiSwitch("Switch", "Switch 1", &gSwitch1Val, Switch1Toggled);
    ASASECUiSwitch("Switch", "Switch 2 (God Mode)", &gSwitch2Val, Switch2Toggled);
    
    ASASECUiSlider("Slider", "Slider 1", &gSlider1Val, 0.0f, 50.0f, Slider1Changed);
    ASASECUiSlider("Slider", "Slider 2", &gSlider2Val, 50.0f, 100.0f, Slider2Changed);

    ASASECUiCheckbox("CheckBox", "Checkbox 1", &gCheckbox1Val, Checkbox1Toggled);
    ASASECUiCheckbox("CheckBox", "Checkbox 2", &gCheckbox2Val, Checkbox2Toggled);

    ASASECUiButton("Buton", "Buton 1", Button1Clicked);
    ASASECUiButton("Buton", "Buton 2", Button2Clicked);

    ASASECUiStart();
}
