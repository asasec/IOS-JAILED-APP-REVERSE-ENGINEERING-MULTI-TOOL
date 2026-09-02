#import <UIKit/UIKit.h>
#import <dispatch/dispatch.h>

#import "../ASASECUI/ui/AsasecUi.h"
#import "../ASASECUI/guialert/GuiAlert.h"
#include "../ASASECUI/imgui/imgui.h"

#pragma mark - API

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

#pragma mark - İşlemler


static void ButonBas(void) {
    // Çağır
}

#pragma mark - Menüyü Dışarıya Açan Başlatıcı Fonksiyon

void StartAsasecMenu(void) {

    ASASECUiButton("SANDBOX", "Browser", ButonBas);

    ASASECUiStart();
}
