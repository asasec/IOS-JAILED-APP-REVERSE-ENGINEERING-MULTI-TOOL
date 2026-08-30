#import <UIKit/UIKit.h>
#import <dispatch/dispatch.h>

#import "../Imgui/Gui/AsasecImgui.h"
#include "../Imgui/imgui.h"

// Dışarıdan gelen kayıt fonksiyonlarının prototipleri
extern void ASASECRegisterFeature(const char *category, const char *title, bool *valuePointer, void (*callback)(bool));
extern void ASASECRegisterButton(const char *category, const char *title, void (*callback)(void));

// --- COMBAT KATEGORİSİ DEĞİŞKENLERİ VE FONKSİYONLARI ---
static bool gSwitch1Val = false;
void Switch1Toggled(bool isOn) {
    if (isOn) {
        NSLog(@"Switch 1 Açıldı");
    } else {
        NSLog(@"Switch 1 Kapatıldı");
    }
}

static bool gSwitch2Val = false;
void Switch2Toggled(bool isOn) {
    if (isOn) {
        NSLog(@"Switch 2 Açıldı (Örn: God Mode)");
    } else {
        NSLog(@"Switch 2 Kapatıldı");
    }
}

void Button1Clicked(void) {
    NSLog(@"Test Butonu 1'e tıklandı!");
}

void Button2Clicked(void) {
    NSLog(@"Test Butonu 2'ye tıklandı!");
}


// --- SETTINGS KATEGORİSİ DEĞİŞKENLERİ VE FONKSİYONLARI ---
static bool gSettingsSwitch1Val = true;
void SettingsSwitch1Toggled(bool isOn) {
    if (isOn) {
        NSLog(@"Karanlık Mod / FPS Göstergesi Açıldı");
    } else {
        NSLog(@"Kapatıldı");
    }
}

static bool gSettingsSwitch2Val = false;
void SettingsSwitch2Toggled(bool isOn) {
    if (isOn) {
        NSLog(@"Bildirimler Açıldı");
    } else {
        NSLog(@"Bildirimler Kapatıldı");
    }
}

void SettingsButton1Clicked(void) {
    NSLog(@"Ayarları Sıfırla butonuna tıklandı!");
}

void SettingsButton2Clicked(void) {
    NSLog(@"Önbelleği Temizle butonuna tıklandı!");
}


// Otomatik Kayıt Yapısı
__attribute__((constructor)) void RegisterItems() {
    // Combat Kategorisi Öğeleri
    ASASECRegisterFeature("Combat", "Swicht 1", &gSwitch1Val, Switch1Toggled);
    ASASECRegisterFeature("Combat", "Swicht 2 (God Mode)", &gSwitch2Val, Switch2Toggled);
    ASASECRegisterButton("Combat", "Test Butonu 1", Button1Clicked);
    ASASECRegisterButton("Combat", "Test Butonu 2", Button2Clicked);
    
    // Settings Kategorisi Öğeleri
    ASASECRegisterFeature("Settings", "FPS Göstergesi", &gSettingsSwitch1Val, SettingsSwitch1Toggled);
    ASASECRegisterFeature("Settings", "Bildirim Sesleri", &gSettingsSwitch2Val, SettingsSwitch2Toggled);
    ASASECRegisterButton("Settings", "Ayarları Sıfırla", SettingsButton1Clicked);
    ASASECRegisterButton("Settings", "Önbelleği Temizle", SettingsButton2Clicked);
}

// Menüyü Başlatan Constructor
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
