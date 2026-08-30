#import <UIKit/UIKit.h>
#import <dispatch/dispatch.h>

#import "../Imgui/Gui/AsasecImgui.h"
#include "../Imgui/imgui.h"

#pragma mark - ASASEC GUI Registration API

extern void ASASECGuiSwitch(const char *category,
                            const char *title,
                            bool *valuePointer,
                            void (*callback)(bool));

extern void ASASECGuiButton(const char *category,
                            const char *title,
                            void (*callback)(void));

#pragma mark - COMBAT

static bool gSwitch1Val = false;

static void Switch1Toggled(bool isOn) {
    if (isOn) {
        NSLog(@"[ASASEC] Switch 1 Açıldı");
    } else {
        NSLog(@"[ASASEC] Switch 1 Kapatıldı");
    }
}

static bool gSwitch2Val = false;

static void Switch2Toggled(bool isOn) {
    if (isOn) {
        NSLog(@"[ASASEC] Switch 2 (God Mode) Açıldı");
    } else {
        NSLog(@"[ASASEC] Switch 2 (God Mode) Kapatıldı");
    }
}

static void Button1Clicked(void) {
    NSLog(@"[ASASEC] Test Butonu 1'e tıklandı!");
}

static void Button2Clicked(void) {
    NSLog(@"[ASASEC] Test Butonu 2'ye tıklandı!");
}

#pragma mark - SETTINGS

static bool gSettingsSwitch1Val = true;

static void SettingsSwitch1Toggled(bool isOn) {
    if (isOn) {
        NSLog(@"[ASASEC] FPS Göstergesi Açıldı");
    } else {
        NSLog(@"[ASASEC] FPS Göstergesi Kapatıldı");
    }
}

static bool gSettingsSwitch2Val = false;

static void SettingsSwitch2Toggled(bool isOn) {
    if (isOn) {
        NSLog(@"[ASASEC] Bildirim Sesleri Açıldı");
    } else {
        NSLog(@"[ASASEC] Bildirim Sesleri Kapatıldı");
    }
}

static void SettingsButton1Clicked(void) {
    NSLog(@"[ASASEC] Ayarları Sıfırla butonuna tıklandı!");
}

static void SettingsButton2Clicked(void) {
    NSLog(@"[ASASEC] Önbelleği Temizle butonuna tıklandı!");
}

#pragma mark - GUI Registration

__attribute__((constructor))
static void RegisterItems(void) {

    /*
     * COMBAT
     */

    ASASECGuiSwitch(
        "Combat",
        "Switch 1",
        &gSwitch1Val,
        Switch1Toggled
    );

    ASASECGuiSwitch(
        "Combat",
        "Switch 2 (God Mode)",
        &gSwitch2Val,
        Switch2Toggled
    );

    ASASECGuiButton(
        "Combat",
        "Test Butonu 1",
        Button1Clicked
    );

    ASASECGuiButton(
        "Combat",
        "Test Butonu 2",
        Button2Clicked
    );


    /*
     * SETTINGS
     */

    ASASECGuiSwitch(
        "Settings",
        "FPS Göstergesi",
        &gSettingsSwitch1Val,
        SettingsSwitch1Toggled
    );

    ASASECGuiSwitch(
        "Settings",
        "Bildirim Sesleri",
        &gSettingsSwitch2Val,
        SettingsSwitch2Toggled
    );

    ASASECGuiButton(
        "Settings",
        "Ayarları Sıfırla",
        SettingsButton1Clicked
    );

    ASASECGuiButton(
        "Settings",
        "Önbelleği Temizle",
        SettingsButton2Clicked
    );
}

#pragma mark - ASASEC MENU START

%ctor
{
    dispatch_after(
        dispatch_time(
            DISPATCH_TIME_NOW,
            (int64_t)(5.0 * NSEC_PER_SEC)
        ),
        dispatch_get_main_queue(),
        ^{
            ASASECImGuiStart();
        }
    );
}
