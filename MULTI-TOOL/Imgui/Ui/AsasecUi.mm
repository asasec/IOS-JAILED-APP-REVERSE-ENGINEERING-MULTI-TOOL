#import "AsasecUi.h"

#import <UIKit/UIKit.h>
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import <QuartzCore/QuartzCore.h>
#import <dispatch/dispatch.h>
#import <math.h>
#import <string.h>

#define IMGUI_DEFINE_MATH_OPERATORS
#include "../imgui.h"
#include "../imgui_internal.h"
#include "../Backends/imgui_impl_metal.h"

#pragma mark - External Feature Registration

typedef enum {
    ASASECFeatureTypeSwitch = 0,
    ASASECFeatureTypeButton = 1,
    ASASECFeatureTypeSlider = 2,
    ASASECFeatureTypeCheckbox = 3
} ASASECFeatureType;

typedef void (*ASASECSwitchCallback)(bool isOn);
typedef void (*ASASECButtonCallback)(void);
typedef void (*ASASECSliderCallback)(float value);
typedef void (*ASASECCheckboxCallback)(bool isChecked);

typedef struct {
    ASASECFeatureType type;
    const char *category;
    const char *title;
    bool *valuePointer;
    float *floatValuePointer;
    float sliderMin;
    float sliderMax;
    ASASECSwitchCallback switchCallback;
    ASASECButtonCallback buttonCallback;
    ASASECSliderCallback sliderCallback;
    ASASECCheckboxCallback checkboxCallback;
} ASASECCustomFeature;

#define MAX_CUSTOM_FEATURES 128

static ASASECCustomFeature gRegisteredFeatures[MAX_CUSTOM_FEATURES];
static int gRegisteredFeatureCount = 0;

void ASASECUiSwitch(const char *category,
                    const char *title,
                    bool *valuePointer,
                    ASASECSwitchCallback callback)
{
    if (!category || !title || !valuePointer)
        return;

    if (gRegisteredFeatureCount >= MAX_CUSTOM_FEATURES)
        return;

    ASASECCustomFeature *feature =
        &gRegisteredFeatures[gRegisteredFeatureCount++];

    feature->type = ASASECFeatureTypeSwitch;
    feature->category = category;
    feature->title = title;
    feature->valuePointer = valuePointer;
    feature->switchCallback = callback;
    feature->buttonCallback = NULL;
}

void ASASECUiButton(const char *category,
                    const char *title,
                    ASASECButtonCallback callback)
{
    if (!category || !title)
        return;

    if (gRegisteredFeatureCount >= MAX_CUSTOM_FEATURES)
        return;

    ASASECCustomFeature *feature =
        &gRegisteredFeatures[gRegisteredFeatureCount++];

    feature->type = ASASECFeatureTypeButton;
    feature->category = category;
    feature->title = title;
    feature->valuePointer = NULL;
    feature->switchCallback = NULL;
    feature->buttonCallback = callback;
}

void ASASECUiSlider(const char *category,
                    const char *title,
                    float *valuePointer,
                    float minVal,
                    float maxVal,
                    ASASECSliderCallback callback)
{
    if (!category || !title || !valuePointer)
        return;

    if (gRegisteredFeatureCount >= MAX_CUSTOM_FEATURES)
        return;

    ASASECCustomFeature *feature =
        &gRegisteredFeatures[gRegisteredFeatureCount++];

    feature->type = ASASECFeatureTypeSlider;
    feature->category = category;
    feature->title = title;
    feature->floatValuePointer = valuePointer;
    feature->sliderMin = minVal;
    feature->sliderMax = maxVal;
    feature->sliderCallback = callback;
}

void ASASECUiCheckbox(const char *category,
                      const char *title,
                      bool *valuePointer,
                      ASASECCheckboxCallback callback)
{
    if (!category || !title || !valuePointer)
        return;

    if (gRegisteredFeatureCount >= MAX_CUSTOM_FEATURES)
        return;

    ASASECCustomFeature *feature =
        &gRegisteredFeatures[gRegisteredFeatureCount++];

    feature->type = ASASECFeatureTypeCheckbox;
    feature->category = category;
    feature->title = title;
    feature->valuePointer = valuePointer;
    feature->checkboxCallback = callback;
}

static int ASASECGetUniqueCategories(const char *categoriesOut[],
                                     int maxCategories)
{
    int count = 0;

    for (int i = 0;
         i < gRegisteredFeatureCount;
         i++) {

        const char *category =
            gRegisteredFeatures[i].category;

        if (!category)
            continue;

        bool exists = false;

        for (int j = 0;
             j < count;
             j++) {

            if (strcmp(
                    categoriesOut[j],
                    category
                ) == 0) {

                exists = true;
                break;
            }
        }

        if (!exists &&
            count < maxCategories) {

            categoriesOut[count++] =
                category;
        }
    }

    return count;
}

#pragma mark - Global State

static MTKView *gImGuiView = nil;
static id gMetalDevice = nil;
static id gCommandQueue = nil;

static BOOL gInitialized = NO;
static BOOL gStarting = NO;
static BOOL gMetalBackendInitialized = NO;

static BOOL gMenuVisible = YES;
static BOOL gMenuCollapsed = NO;

static BOOL gCategoriesVisible = YES;
static float gCategoriesAnimation = 1.0f;

static ImVec2 gMenuPosition =
    ImVec2(25.0f, 75.0f);

static ImVec2 gMenuSize =
    ImVec2(560.0f, 390.0f);

static const float kMenuMinWidth = 320.0f;
static const float kMenuMaxWidth = 760.0f;

static const float kMenuMinHeight = 260.0f;
static const float kMenuMaxHeight = 620.0f;

static const float kHeaderHeight = 56.0f;
static const float kResizeSize = 58.0f;

static const float kSidebarWidth = 145.0f;

static const float kSidebarAnimationSpeed = 15.0f;

static const float kClosedCategoryArrowY = 7.0f;
static const float kClosedCategoryArrowWidth = 34.0f;
static const float kClosedCategoryArrowHeight = 32.0f;

static const float kClosedCategoryTitleY = 11.0f;
static const float kClosedCategoryHeaderLineY = 49.0f;
static const float kClosedCategoryContentStartY = 58.0f;

static int gSelectedPage = 0;
static int gPreviousPage = 0;

static BOOL gDraggingMenu = NO;
static BOOL gResizingMenu = NO;
static BOOL gContentDragging = NO;

static BOOL gOpenCategoriesTouchCandidate = NO;

static CGPoint gDragStartPoint = CGPointZero;
static CGPoint gResizeStartPoint = CGPointZero;

static ImVec2 gDragStartPosition =
    ImVec2(25.0f, 75.0f);

static ImVec2 gResizeStartSize =
    ImVec2(560.0f, 390.0f);

static float gPendingContentScrollY = 0.0f;
static float gContentScrollVelocity = 0.0f;

static BOOL gContentHasMoved = NO;
static BOOL gContentTouchCandidate = NO;

static CGPoint gContentStartPoint = CGPointZero;
static CGPoint gContentLastPoint = CGPointZero;

static float gPageAnimation = 1.0f;
static float gPageSlide = 0.0f;

#pragma mark - Animations Structures

typedef struct {
    const char *label;
    float pulse;
} ASASECButtonAnimation;

static ASASECButtonAnimation gButtonAnimations[128];
static int gButtonAnimationCount = 0;

static ASASECButtonAnimation *
ASASECGetButtonAnimation(const char *label)
{
    if (!label)
        return NULL;

    for (int i = 0;
         i < gButtonAnimationCount;
         i++) {

        if (gButtonAnimations[i].label &&
            strcmp(
                gButtonAnimations[i].label,
                label
            ) == 0) {

            return &gButtonAnimations[i];
        }
    }

    if (gButtonAnimationCount >= 128)
        return NULL;

    int index =
        gButtonAnimationCount++;

    gButtonAnimations[index].label =
        label;

    gButtonAnimations[index].pulse =
        0.0f;

    return &gButtonAnimations[index];
}

typedef struct {
    const char *label;
    float progress;
    float pulse;
} ASASECSwitchAnimation;

static ASASECSwitchAnimation gSwitchAnimations[128];
static int gSwitchAnimationCount = 0;

static ASASECSwitchAnimation *
ASASECGetSwitchAnimationData(const char *label)
{
    if (!label)
        return NULL;

    for (int i = 0;
         i < gSwitchAnimationCount;
         i++) {

        if (gSwitchAnimations[i].label &&
            strcmp(
                gSwitchAnimations[i].label,
                label
            ) == 0) {

            return &gSwitchAnimations[i];
        }
    }

    if (gSwitchAnimationCount >= 128)
        return NULL;

    int index =
        gSwitchAnimationCount++;

    gSwitchAnimations[index].label =
        label;

    gSwitchAnimations[index].progress =
        0.0f;

    gSwitchAnimations[index].pulse =
        0.0f;

    return &gSwitchAnimations[index];
}

#pragma mark - Helpers

static float ASASECClampFloat(float value,
                              float minValue,
                              float maxValue)
{
    if (value < minValue)
        return minValue;

    if (value > maxValue)
        return maxValue;

    return value;
}

static float ASASECEase(float current,
                        float target,
                        float speed,
                        float dt)
{
    if (dt <= 0.0f)
        dt = 1.0f / 60.0f;

    if (dt > 0.1f)
        dt = 0.1f;

    if (speed <= 0.0f)
        return target;

    float factor =
        1.0f - expf(-speed * dt);

    return current +
           (target - current) * factor;
}

static float ASASECGetAnimatedSidebarWidth(void)
{
    return kSidebarWidth *
           ASASECClampFloat(
               gCategoriesAnimation,
               0.0f,
               1.0f
           );
}

static ImU32 ASASECColor(float r,
                         float g,
                         float b,
                         float a)
{
    return ImGui::ColorConvertFloat4ToU32(
        ImVec4(r, g, b, a)
    );
}

static UIWindow *ASASECFindActiveWindow(void)
{
    UIApplication *application =
        UIApplication.sharedApplication;

    if (!application)
        return nil;

    for (UIScene *scene in
         application.connectedScenes) {

        if (![scene isKindOfClass:
              [UIWindowScene class]])
            continue;

        UIWindowScene *windowScene =
            (UIWindowScene *)scene;

        if (windowScene.activationState !=
            UISceneActivationStateForegroundActive)
            continue;

        for (UIWindow *window in
             windowScene.windows) {

            if (!window ||
                window.hidden ||
                window.alpha <= 0.0)
                continue;

            if (window.isKeyWindow)
                return window;
        }
    }

    for (UIScene *scene in
         application.connectedScenes) {

        if (![scene isKindOfClass:
              [UIWindowScene class]])
            continue;

        UIWindowScene *windowScene =
            (UIWindowScene *)scene;

        if (windowScene.activationState !=
            UISceneActivationStateForegroundActive)
            continue;

        for (UIWindow *window in
             windowScene.windows) {

            if (!window ||
                window.hidden ||
                window.alpha <= 0.0)
                continue;

            return window;
        }
    }

    return nil;
}

static void ASASECClampMenuToScreen(UIWindow *window)
{
    if (!window)
        return;

    CGSize size =
        window.bounds.size;

    const float margin = 12.0f;

    float maxAllowedWidth =
        (float)size.width -
        margin * 2.0f;

    float targetMaxWidth =
        MIN(
            kMenuMaxWidth,
            maxAllowedWidth
        );

    if (targetMaxWidth <
        kMenuMinWidth) {

        targetMaxWidth =
            kMenuMinWidth;
    }

    float maxAllowedHeight =
        (float)size.height -
        margin * 2.0f;

    float targetMaxHeight =
        MIN(
            kMenuMaxHeight,
            maxAllowedHeight
        );

    if (targetMaxHeight <
        kMenuMinHeight) {

        targetMaxHeight =
            kMenuMinHeight;
    }

    gMenuSize.x =
        ASASECClampFloat(
            gMenuSize.x,
            kMenuMinWidth,
            targetMaxWidth
        );

    gMenuSize.y =
        gMenuCollapsed
        ? kHeaderHeight
        : ASASECClampFloat(
            gMenuSize.y,
            kMenuMinHeight,
            targetMaxHeight
        );

    float maxX =
        (float)size.width -
        gMenuSize.x -
        margin;

    float maxY =
        (float)size.height -
        gMenuSize.y -
        margin;

    if (maxX < margin)
        maxX = margin;

    if (maxY < margin)
        maxY = margin;

    gMenuPosition.x =
        ASASECClampFloat(
            gMenuPosition.x,
            margin,
            maxX
        );

    gMenuPosition.y =
        ASASECClampFloat(
            gMenuPosition.y,
            margin,
            maxY
        );
}

#pragma mark - Modern Switch (Yüksek Dokunma Eşiği ile)

static bool ASASECModernSwitch(const char *label,
                               bool *value)
{
    if (!label || !value)
        return false;

    ImGui::PushID(label);

    const float switchWidth = 48.0f;
    const float switchHeight = 26.0f;
    const float rowHeight = 64.0f;

    float available =
        ImGui::GetContentRegionAvail().x;

    if (available < 150.0f)
        available = 150.0f;

    bool clicked =
        ImGui::InvisibleButton(
            "##switch",
            ImVec2(
                available,
                rowHeight
            )
        );

    if (clicked && !ImGui::IsMouseDragging(0, 8.0f)) {
        *value = !(*value);
    } else {
        clicked = false;
    }

    ImVec2 itemMin =
        ImGui::GetItemRectMin();

    ImVec2 itemMax =
        ImGui::GetItemRectMax();

    ImDrawList *draw =
        ImGui::GetWindowDrawList();

    ASASECSwitchAnimation *animation =
        ASASECGetSwitchAnimationData(label);

    if (clicked && animation) {
        animation->pulse = 1.0f;
    }

    bool hovered =
        ImGui::IsItemHovered();

    float dt =
        ImGui::GetIO().DeltaTime;

    if (dt <= 0.0f ||
        dt > 0.1f) {

        dt = 1.0f / 60.0f;
    }

    float progress =
        animation
        ? animation->progress
        : (*value ? 1.0f : 0.0f);

    float target =
        *value ? 1.0f : 0.0f;

    progress =
        ASASECEase(
            progress,
            target,
            16.0f,
            dt
        );

    if (animation) {

        animation->progress =
            progress;

        animation->pulse =
            ASASECEase(
                animation->pulse,
                0.0f,
                12.0f,
                dt
            );
    }

    float pulse =
        animation
        ? animation->pulse
        : 0.0f;

    ImU32 cardBackground =
        hovered
        ? ASASECColor(
            0.075f,
            0.100f,
            0.145f,
            0.99f
        )
        : ASASECColor(
            0.045f,
            0.060f,
            0.088f,
            0.98f
        );

    ImU32 cardBorder =
        hovered
        ? ASASECColor(
            0.18f,
            0.30f,
            0.46f,
            0.90f
        )
        : ASASECColor(
            0.10f,
            0.15f,
            0.22f,
            0.80f
        );

    if (draw) {

        draw->AddRectFilled(
            itemMin,
            itemMax,
            cardBackground,
            14.0f
        );

        draw->AddRect(
            ImVec2(
                itemMin.x + 0.5f,
                itemMin.y + 0.5f
            ),
            ImVec2(
                itemMax.x - 0.5f,
                itemMax.y - 0.5f
            ),
            cardBorder,
            14.0f,
            0,
            1.0f
        );

        float switchX =
            itemMax.x -
            switchWidth -
            15.0f;

        float switchY =
            itemMin.y +
            (rowHeight -
             switchHeight) *
            0.5f;

        ImVec2 switchMin =
            ImVec2(
                switchX,
                switchY
            );

        ImVec2 switchMax =
            ImVec2(
                switchX + switchWidth,
                switchY + switchHeight
            );

        float bgR =
            0.075f +
            (0.18f - 0.075f) *
            progress;

        float bgG =
            0.115f +
            (0.52f - 0.115f) *
            progress;

        float bgB =
            0.19f +
            (0.95f - 0.19f) *
            progress;

        if (hovered) {

            bgR += 0.02f;
            bgG += 0.02f;
            bgB += 0.02f;
        }

        draw->AddRectFilled(
            switchMin,
            switchMax,
            ASASECColor(
                bgR,
                bgG,
                bgB,
                1.0f
            ),
            switchHeight * 0.5f
        );

        draw->AddRect(
            switchMin,
            switchMax,
            ASASECColor(
                0.25f +
                0.22f * progress,
                0.33f +
                0.31f * progress,
                0.47f +
                0.39f * progress,
                0.90f
            ),
            switchHeight * 0.5f,
            0,
            1.0f
        );

        float offX =
            switchMin.x + 13.0f;

        float onX =
            switchMax.x - 13.0f;

        float knobX =
            offX +
            (onX - offX) *
            progress;

        float knobY =
            switchMin.y +
            switchHeight * 0.5f;

        float knobRadius =
            9.0f +
            pulse * 1.2f;

        if (pulse > 0.01f) {

            draw->AddCircle(
                ImVec2(
                    knobX,
                    knobY
                ),
                12.0f +
                pulse * 3.0f,
                ASASECColor(
                    0.30f,
                    0.68f,
                    1.0f,
                    pulse * 0.30f
                ),
                24,
                1.6f
            );
        }

        draw->AddCircleFilled(
            ImVec2(
                knobX,
                knobY + 1.0f
            ),
            knobRadius + 0.8f,
            ASASECColor(
                0.0f,
                0.0f,
                0.0f,
                0.28f
            )
        );

        draw->AddCircleFilled(
            ImVec2(
                knobX,
                knobY
            ),
            knobRadius,
            ASASECColor(
                0.96f,
                0.98f,
                1.0f,
                1.0f
            )
        );
    }

    ImGui::SetCursorScreenPos(
        ImVec2(
            itemMin.x + 15.0f,
            itemMin.y + 13.0f
        )
    );

    ImGui::TextColored(
        ImVec4(
            0.92f,
            0.95f,
            1.0f,
            1.0f
        ),
        "%s",
        label
    );

    ImGui::SetCursorScreenPos(
        ImVec2(
            itemMin.x + 15.0f,
            itemMin.y + 35.0f
        )
    );

    ImGui::TextColored(
        ImVec4(
            0.39f,
            0.45f,
            0.54f,
            1.0f
        ),
        "%s",
        *value
        ? "Enabled"
        : "Disabled"
    );

    ImGui::PopID();

    return clicked;
}

#pragma mark - Modern Button

static bool ASASECModernButton(const char *label)
{
    if (!label)
        return false;

    ImGui::PushID(label);

    float available =
        ImGui::GetContentRegionAvail().x;

    if (available < 150.0f)
        available = 150.0f;

    const float height = 64.0f;

    bool pressed =
        ImGui::InvisibleButton(
            "##button",
            ImVec2(
                available,
                height
            )
        );

    if (pressed && ImGui::IsMouseDragging(0, 10.0f)) {
        pressed = false;
    }

    ImVec2 min =
        ImGui::GetItemRectMin();

    ImVec2 max =
        ImGui::GetItemRectMax();

    bool hovered =
        ImGui::IsItemHovered();

    ASASECButtonAnimation *animation =
        ASASECGetButtonAnimation(label);

    if (pressed && animation)
        animation->pulse = 1.0f;

    float dt =
        ImGui::GetIO().DeltaTime;

    if (dt <= 0.0f ||
        dt > 0.1f) {

        dt = 1.0f / 60.0f;
    }

    float pulse =
        animation
        ? animation->pulse
        : 0.0f;

    if (animation) {

        animation->pulse =
            ASASECEase(
                animation->pulse,
                0.0f,
                9.0f,
                dt
            );

        pulse =
            animation->pulse;
    }

    ImDrawList *draw =
        ImGui::GetWindowDrawList();

    if (draw) {

        float baseR = 0.045f;
        float baseG = 0.065f;
        float baseB = 0.105f;

        if (hovered) {

            baseR += 0.025f;
            baseG += 0.035f;
            baseB += 0.055f;
        }

        float pulseBoost =
            pulse * 0.13f;

        ImU32 background =
            ASASECColor(
                baseR,
                baseG + pulseBoost,
                baseB +
                pulseBoost * 1.5f,
                1.0f
            );

        ImU32 border =
            ASASECColor(
                0.12f +
                pulse * 0.20f,
                0.19f +
                pulse * 0.35f,
                0.30f +
                pulse * 0.60f,
                0.90f
            );

        draw->AddRectFilled(
            min,
            max,
            background,
            13.0f
        );

        draw->AddRect(
            ImVec2(
                min.x + 0.5f,
                min.y + 0.5f
            ),
            ImVec2(
                max.x - 0.5f,
                max.y - 0.5f
            ),
            border,
            13.0f,
            0,
            1.0f
        );

        if (pulse > 0.01f) {

            draw->AddRect(
                ImVec2(
                    min.x + 1.0f,
                    min.y + 1.0f
                ),
                ImVec2(
                    max.x - 1.0f,
                    max.y - 1.0f
                ),
                ASASECColor(
                    0.22f,
                    0.62f,
                    1.0f,
                    pulse * 0.55f
                ),
                13.0f,
                0,
                2.0f
            );
        }
    }

    ImVec2 textSize =
        ImGui::CalcTextSize(label);

    ImVec2 textPos =
        ImVec2(
            min.x +
            (available -
             textSize.x) * 0.5f,
            min.y +
            (height -
             textSize.y) * 0.5f
        );

    ImGui::SetCursorScreenPos(
        textPos
    );

    ImGui::TextColored(
        ImVec4(
            hovered ? 0.90f : 0.82f,
            hovered ? 0.96f : 0.88f,
            1.0f,
            1.0f
        ),
        "%s",
        label
    );

    ImGui::PopID();

    return pressed;
}

#pragma mark - Geliştirilmiş ve Animasyonlu Modern Bileşenler (Slider, Checkbox)

static bool ASASECModernSlider(const char *label, float *value, float minVal, float maxVal)
{
    if (!label || !value) return false;

    ImGui::PushID(label);

    float available = ImGui::GetContentRegionAvail().x;
    if (available < 150.0f) available = 150.0f;

    const float rowHeight = 64.0f;
    bool modified = false;

    ImGui::InvisibleButton("##slider_area", ImVec2(available, rowHeight));
    bool active = ImGui::IsItemActive();

    ImVec2 itemMin = ImGui::GetItemRectMin();
    ImVec2 itemMax = ImGui::GetItemRectMax();
    ImDrawList *draw = ImGui::GetWindowDrawList();

    static float sliderAnimValues[128] = {0};
    int currentSliderIdx = 0;
    static const char *sliderLabels[128] = {NULL};
    bool foundSlider = false;
    for (int i = 0; i < 128; i++) {
        if (sliderLabels[i] == label) {
            currentSliderIdx = i;
            foundSlider = true;
            break;
        }
        if (sliderLabels[i] == NULL) {
            sliderLabels[i] = label;
            currentSliderIdx = i;
            foundSlider = true;
            break;
        }
    }
    if (!foundSlider) currentSliderIdx = 0;

    float dtSlider = ImGui::GetIO().DeltaTime;
    if (dtSlider <= 0.0f || dtSlider > 0.1f) dtSlider = 1.0f / 60.0f;

    float targetNormalized = (*value - minVal) / (maxVal - minVal);
    targetNormalized = ASASECClampFloat(targetNormalized, 0.0f, 1.0f);

    sliderAnimValues[currentSliderIdx] = ASASECEase(sliderAnimValues[currentSliderIdx], targetNormalized, 18.0f, dtSlider);
    float animatedNormalized = sliderAnimValues[currentSliderIdx];

    if (active) {
        ImVec2 mouseDelta = ImGui::GetIO().MouseDelta;
        if (fabsf(mouseDelta.x) > 0.5f || ImGui::IsMouseDragging(0, 4.0f)) {
            float sliderWidth = available - 30.0f;
            float currentMouseX = ImGui::GetIO().MousePos.x;
            float barStartX = itemMin.x + 15.0f;
            
            float ratio = (currentMouseX - barStartX) / sliderWidth;
            ratio = ASASECClampFloat(ratio, 0.0f, 1.0f);
            
            float newValue = minVal + ratio * (maxVal - minVal);
            if (*value != newValue) {
                *value = newValue;
                modified = true;
            }
        }
    }

    if (draw) {
        draw->AddRectFilled(itemMin, itemMax, ASASECColor(0.045f, 0.060f, 0.088f, 0.98f), 14.0f);
        draw->AddRect(ImVec2(itemMin.x + 0.5f, itemMin.y + 0.5f), ImVec2(itemMax.x - 0.5f, itemMax.y - 0.5f), ASASECColor(0.10f, 0.15f, 0.22f, 0.80f), 14.0f, 0, 1.0f);

        float barY = itemMin.y + 44.0f;
        float barStartX = itemMin.x + 15.0f;
        float barEndX = itemMax.x - 15.0f;
        float barWidth = barEndX - barStartX;
        float fillWidth = barWidth * animatedNormalized;

        draw->AddRectFilled(ImVec2(barStartX, barY - 3.5f), ImVec2(barEndX, barY + 3.5f), ASASECColor(0.08f, 0.12f, 0.18f, 1.0f), 3.5f);
        draw->AddRectFilled(ImVec2(barStartX, barY - 3.5f), ImVec2(barStartX + fillWidth, barY + 3.5f), ASASECColor(0.22f, 0.56f, 1.0f, 1.0f), 3.5f);

        float knobX = barStartX + fillWidth;
        draw->AddCircleFilled(ImVec2(knobX, barY), 9.0f, ASASECColor(0.96f, 0.98f, 1.0f, 1.0f), 24);
        draw->AddCircle(ImVec2(knobX, barY), 9.0f, ASASECColor(0.30f, 0.68f, 1.0f, 0.9f), 24, 1.5f);
    }

    ImGui::SetCursorScreenPos(ImVec2(itemMin.x + 15.0f, itemMin.y + 13.0f));
    ImGui::TextColored(ImVec4(0.92f, 0.95f, 1.0f, 1.0f), "%s", label);

    char valStr[32];
    snprintf(valStr, sizeof(valStr), "%.1f", *value);
    ImVec2 valSize = ImGui::CalcTextSize(valStr);

    ImGui::SetCursorScreenPos(ImVec2(itemMax.x - 15.0f - valSize.x, itemMin.y + 13.0f));
    ImGui::TextColored(ImVec4(0.30f, 0.68f, 1.0f, 1.0f), "%s", valStr);

    ImGui::PopID();
    return modified;
}

static bool ASASECModernCheckbox(const char *label, bool *value)
{
    if (!label || !value) return false;

    ImGui::PushID(label);

    float available = ImGui::GetContentRegionAvail().x;
    if (available < 150.0f) available = 150.0f;

    const float rowHeight = 64.0f;

    bool clicked = ImGui::InvisibleButton("##checkbox", ImVec2(available, rowHeight));
    
    if (clicked && !ImGui::IsMouseDragging(0, 8.0f)) {
        *value = !(*value);
    } else {
        clicked = false;
    }

    ImVec2 itemMin = ImGui::GetItemRectMin();
    ImVec2 itemMax = ImGui::GetItemRectMax();
    ImDrawList *draw = ImGui::GetWindowDrawList();
    bool isItemHovered = ImGui::IsItemHovered();

    float dtCheck = ImGui::GetIO().DeltaTime;
    if (dtCheck <= 0.0f || dtCheck > 0.1f) dtCheck = 1.0f / 60.0f;

    static float checkAnimProgress[128] = {0};
    static const char *checkLabels[128] = {NULL};
    int currentCheckIdx = 0;
    bool foundCheck = false;
    for (int i = 0; i < 128; i++) {
        if (checkLabels[i] == label) {
            currentCheckIdx = i;
            foundCheck = true;
            break;
        }
        if (checkLabels[i] == NULL) {
            checkLabels[i] = label;
            currentCheckIdx = i;
            foundCheck = true;
            break;
        }
    }
    if (!foundCheck) currentCheckIdx = 0;

    float targetCheckAnim = *value ? 1.0f : 0.0f;
    checkAnimProgress[currentCheckIdx] = ASASECEase(checkAnimProgress[currentCheckIdx], targetCheckAnim, 16.0f, dtCheck);
    float animProgressVal = checkAnimProgress[currentCheckIdx];

    if (draw) {
        draw->AddRectFilled(itemMin, itemMax, isItemHovered ? ASASECColor(0.075f, 0.100f, 0.145f, 0.99f) : ASASECColor(0.045f, 0.060f, 0.088f, 0.98f), 14.0f);
        draw->AddRect(ImVec2(itemMin.x + 0.5f, itemMin.y + 0.5f), ImVec2(itemMax.x - 0.5f, itemMax.y - 0.5f), ASASECColor(0.10f, 0.15f, 0.22f, 0.80f), 14.0f, 0, 1.0f);

        float boxSize = 24.0f;
        float boxX = itemMax.x - boxSize - 20.0f;
        float boxY = itemMin.y + (rowHeight - boxSize) * 0.5f;

        ImVec2 boxMin(boxX, boxY);
        ImVec2 boxMax(boxX + boxSize, boxY + boxSize);

        float cR = 0.08f + (0.22f - 0.08f) * animProgressVal;
        float cG = 0.12f + (0.56f - 0.12f) * animProgressVal;
        float cB = 0.18f + (1.00f - 0.18f) * animProgressVal;

        draw->AddRectFilled(boxMin, boxMax, ASASECColor(cR, cG, cB, 1.0f), 6.0f);
        draw->AddRect(boxMin, boxMax, ASASECColor(0.30f, 0.68f, 1.0f, 0.9f), 6.0f, 0, 1.0f);

        if (animProgressVal > 0.05f) {
            ImU32 markColor = ASASECColor(1.0f, 1.0f, 1.0f, animProgressVal);
            draw->AddLine(ImVec2(boxMin.x + 6.0f, boxMin.y + 12.0f), ImVec2(boxMin.x + 10.0f, boxMin.y + 16.0f), markColor, 2.0f);
            draw->AddLine(ImVec2(boxMin.x + 10.0f, boxMin.y + 16.0f), ImVec2(boxMin.x + 18.0f, boxMin.y + 8.0f), markColor, 2.0f);
        }
    }

    ImGui::SetCursorScreenPos(ImVec2(itemMin.x + 15.0f, itemMin.y + 20.0f));
    ImGui::TextColored(ImVec4(0.92f, 0.95f, 1.0f, 1.0f), "%s", label);

    ImGui::PopID();
    return clicked;
}

#pragma mark - ImGui View

@interface ASASECImGuiView : MTKView
@end

@implementation ASASECImGuiView

- (BOOL)pointInsideMenu:(CGPoint)point
{
    if (!gMenuVisible)
        return NO;

    float height =
        gMenuCollapsed
        ? kHeaderHeight
        : gMenuSize.y;

    return
        point.x >= gMenuPosition.x &&
        point.x <=
        gMenuPosition.x +
        gMenuSize.x &&
        point.y >= gMenuPosition.y &&
        point.y <=
        gMenuPosition.y +
        height;
}

- (BOOL)pointInsideOpenCategoriesButton:(CGPoint)point
{
    if (!gMenuVisible ||
        gMenuCollapsed ||
        gCategoriesVisible)
        return NO;

    float contentRootY =
        gMenuPosition.y +
        kHeaderHeight;

    float x1 =
        gMenuPosition.x +
        5.0f;

    float y1 =
        contentRootY +
        kClosedCategoryArrowY -
        4.0f;

    float x2 =
        x1 +
        kClosedCategoryArrowWidth +
        8.0f;

    float y2 =
        y1 +
        kClosedCategoryArrowHeight +
        8.0f;

    return
        point.x >= x1 &&
        point.x <= x2 &&
        point.y >= y1 &&
        point.y <= y2;
}

- (UIView *)hitTest:(CGPoint)point
           withEvent:(UIEvent *)event
{
    if (!gInitialized ||
        !gMenuVisible)
        return nil;

    if ([self pointInsideMenu:point])
        return self;

    return nil;
}

- (void)updateIOWithTouchEvent:(UIEvent *)event
{
    if (!gInitialized || !event)
        return;

    ImGuiContext *ctx =
        ImGui::GetCurrentContext();

    if (!ctx)
        return;

    ImGuiIO &io =
        ImGui::GetIO();

    UITouch *touch =
        event.allTouches.anyObject;

    if (!touch)
        return;

    CGPoint point =
        [touch locationInView:self];

    io.MousePos =
        ImVec2(
            (float)point.x,
            (float)point.y
        );

    BOOL touching = NO;

    for (UITouch *currentTouch
         in event.allTouches) {

        if (!currentTouch)
            continue;

        if (currentTouch.phase !=
            UITouchPhaseEnded &&
            currentTouch.phase !=
            UITouchPhaseCancelled) {

            touching = YES;
            break;
        }
    }

    io.MouseDown[0] =
        touching;
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches
           withEvent:(UIEvent *)event
{
    if (!gInitialized)
        return;

    [self updateIOWithTouchEvent:event];

    UITouch *touch =
        touches.anyObject;

    if (!touch)
        return;

    CGPoint point =
        [touch locationInView:self];

    if (!gMenuVisible)
        return;

    if ([self pointInsideOpenCategoriesButton:point]) {

        gOpenCategoriesTouchCandidate =
            YES;

        gDraggingMenu = NO;
        gResizingMenu = NO;
        gContentDragging = NO;
        gContentTouchCandidate = NO;
        gContentHasMoved = NO;

        gPendingContentScrollY =
            0.0f;

        gContentScrollVelocity =
            0.0f;

        ImGuiContext *ctx =
            ImGui::GetCurrentContext();

        if (ctx) {

            ImGui::GetIO().MouseDown[0] =
                false;
        }

        return;
    }

    gOpenCategoriesTouchCandidate =
        NO;

    if (!gMenuCollapsed) {

        float resizeX =
            gMenuPosition.x +
            gMenuSize.x -
            kResizeSize;

        float resizeY =
            gMenuPosition.y +
            gMenuSize.y -
            kResizeSize;

        if (point.x >= resizeX &&
            point.y >= resizeY &&
            point.x <=
            gMenuPosition.x +
            gMenuSize.x &&
            point.y <=
            gMenuPosition.y +
            gMenuSize.y) {

            gResizingMenu = YES;

            gResizeStartPoint =
                point;

            gResizeStartSize =
                gMenuSize;

            ImGui::GetIO().MouseDown[0] =
                false;

            return;
        }
    }

    float dragAreaRight =
        gMenuPosition.x +
        gMenuSize.x -
        115.0f;

    if (point.y >= gMenuPosition.y &&
        point.y <=
        gMenuPosition.y +
        kHeaderHeight &&
        point.x >= gMenuPosition.x &&
        point.x <= dragAreaRight) {

        gDraggingMenu = YES;

        gDragStartPoint =
            point;

        gDragStartPosition =
            gMenuPosition;

        ImGui::GetIO().MouseDown[0] =
            false;

        return;
    }

    if (!gMenuCollapsed) {

        float animatedSidebarWidth =
            ASASECGetAnimatedSidebarWidth();

        float contentStartX =
            gMenuPosition.x +
            animatedSidebarWidth;

        float contentStartY =
            gMenuPosition.y +
            kHeaderHeight;

        float contentEndX =
            gMenuPosition.x +
            gMenuSize.x;

        float contentEndY =
            gMenuPosition.y +
            gMenuSize.y;

        if (point.x >= contentStartX &&
            point.x <= contentEndX &&
            point.y >= contentStartY &&
            point.y <= contentEndY) {

            gContentTouchCandidate =
                YES;

            gContentHasMoved =
                NO;

            gContentStartPoint =
                point;

            gContentLastPoint =
                point;

            gContentDragging =
                NO;

            gContentScrollVelocity =
                0.0f;
        }
    }
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches
           withEvent:(UIEvent *)event
{
    if (!gInitialized)
        return;

    [self updateIOWithTouchEvent:event];

    UITouch *touch =
        touches.anyObject;

    if (!touch)
        return;

    CGPoint point =
        [touch locationInView:self];

    if (gOpenCategoriesTouchCandidate) {

        ImGui::GetIO().MouseDown[0] =
            false;

        return;
    }

    if (gResizingMenu) {

        float deltaX =
            point.x -
            gResizeStartPoint.x;

        float deltaY =
            point.y -
            gResizeStartPoint.y;

        UIWindow *window =
            self.window;

        CGSize screenSize =
            window
            ? window.bounds.size
            : CGSizeMake(800, 600);

        float maxAllowedWidth =
            screenSize.width -
            24.0f -
            gMenuPosition.x;

        float maxAllowedHeight =
            screenSize.height -
            24.0f -
            gMenuPosition.y;

        float maxWidth =
            MIN(
                kMenuMaxWidth,
                maxAllowedWidth
            );

        float maxHeight =
            MIN(
                kMenuMaxHeight,
                maxAllowedHeight
            );

        gMenuSize.x =
            ASASECClampFloat(
                gResizeStartSize.x +
                deltaX,
                kMenuMinWidth,
                maxWidth
            );

        gMenuSize.y =
            ASASECClampFloat(
                gResizeStartSize.y +
                deltaY,
                kMenuMinHeight,
                maxHeight
            );

        if (window)
            ASASECClampMenuToScreen(
                window
            );

        ImGui::GetIO().MouseDown[0] =
            false;

        return;
    }

    if (gDraggingMenu) {

        float deltaX =
            point.x -
            gDragStartPoint.x;

        float deltaY =
            point.y -
            gDragStartPoint.y;

        gMenuPosition.x =
            gDragStartPosition.x +
            deltaX;

        gMenuPosition.y =
            gDragStartPosition.y +
            deltaY;

        UIWindow *window =
            self.window;

        if (window)
            ASASECClampMenuToScreen(
                window
            );

        ImGui::GetIO().MouseDown[0] =
            false;

        return;
    }

    if (gContentTouchCandidate) {

        float moveX =
            point.x -
            gContentStartPoint.x;

        float moveY =
            point.y -
            gContentStartPoint.y;

        if (!gContentDragging &&
            (fabsf(moveX) > 12.0f ||
             fabsf(moveY) > 12.0f)) {

            gContentDragging =
                YES;

            gContentHasMoved =
                YES;
        }

        if (gContentDragging) {

            float deltaY =
                point.y -
                gContentLastPoint.y;

            gPendingContentScrollY -=
                deltaY;

            gContentScrollVelocity =
                -deltaY * 0.6f;

            gContentLastPoint =
                point;

            ImGui::GetIO().MouseDown[0] =
                false;
        }
    }
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches
           withEvent:(UIEvent *)event
{
    if (!gInitialized)
        return;

    [self updateIOWithTouchEvent:event];

    if (gOpenCategoriesTouchCandidate) {

        gOpenCategoriesTouchCandidate =
            NO;

        gCategoriesVisible =
            YES;

        gContentDragging =
            NO;

        gContentTouchCandidate =
            NO;

        gContentHasMoved =
            NO;

        gPendingContentScrollY =
            0.0f;

        gContentScrollVelocity =
            0.0f;

        ImGuiContext *ctx =
            ImGui::GetCurrentContext();

        if (ctx) {

            ImGui::GetIO().MouseDown[0] =
                false;
        }

        return;
    }

    ImGuiContext *ctx =
        ImGui::GetCurrentContext();

    if (ctx)
        ImGui::GetIO().MouseDown[0] =
            false;

    gDraggingMenu = NO;
    gResizingMenu = NO;
    gContentDragging = NO;
    gContentTouchCandidate = NO;
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches
               withEvent:(UIEvent *)event
{
    if (!gInitialized)
        return;

    [self updateIOWithTouchEvent:event];

    ImGuiContext *ctx =
        ImGui::GetCurrentContext();

    if (ctx)
        ImGui::GetIO().MouseDown[0] =
            false;

    gOpenCategoriesTouchCandidate =
        NO;

    gDraggingMenu = NO;
    gResizingMenu = NO;
    gContentDragging = NO;
    gContentTouchCandidate = NO;
}

@end

#pragma mark - Style

static void ASASECApplyStyle(void)
{
    if (!ImGui::GetCurrentContext())
        return;

    ImGuiStyle &style =
        ImGui::GetStyle();

    style.WindowPadding =
        ImVec2(10.0f, 10.0f);

    style.FramePadding =
        ImVec2(11.0f, 8.0f);

    style.ItemSpacing =
        ImVec2(9.0f, 10.0f);

    style.ItemInnerSpacing =
        ImVec2(7.0f, 6.0f);

    style.ScrollbarSize =
        1.0f;

    style.GrabMinSize =
        15.0f;

    style.WindowRounding =
        22.0f;

    style.ChildRounding =
        15.0f;

    style.FrameRounding =
        12.0f;

    style.PopupRounding =
        13.0f;

    style.ScrollbarRounding =
        8.0f;

    style.GrabRounding =
        8.0f;

    style.TabRounding =
        10.0f;

    style.WindowBorderSize =
        0.0f;

    style.ChildBorderSize =
        1.0f;

    style.FrameBorderSize =
        0.0f;

    style.IndentSpacing =
        20.0f;

    ImVec4 *c =
        style.Colors;

    c[ImGuiCol_Text] =
        ImVec4(
            0.94f,
            0.97f,
            1.0f,
            1.0f
        );

    c[ImGuiCol_TextDisabled] =
        ImVec4(
            0.40f,
            0.45f,
            0.54f,
            1.0f
        );

    c[ImGuiCol_WindowBg] =
        ImVec4(
            0.016f,
            0.022f,
            0.035f,
            0.985f
        );

    c[ImGuiCol_ChildBg] =
        ImVec4(
            0.035f,
            0.047f,
            0.068f,
            0.98f
        );

    c[ImGuiCol_Border] =
        ImVec4(
            0.13f,
            0.18f,
            0.26f,
            0.78f
        );

    c[ImGuiCol_FrameBg] =
        ImVec4(
            0.055f,
            0.071f,
            0.102f,
            1.0f
        );

    c[ImGuiCol_FrameBgHovered] =
        ImVec4(
            0.090f,
            0.120f,
            0.175f,
            1.0f
        );

    c[ImGuiCol_FrameBgActive] =
        ImVec4(
            0.12f,
            0.18f,
            0.27f,
            1.0f
        );

    c[ImGuiCol_Button] =
        ImVec4(
            0.055f,
            0.075f,
            0.115f,
            1.0f
        );

    c[ImGuiCol_ButtonHovered] =
        ImVec4(
            0.10f,
            0.15f,
            0.23f,
            1.0f
        );

    c[ImGuiCol_ButtonActive] =
        ImVec4(
            0.14f,
            0.24f,
            0.39f,
            1.0f
        );

    c[ImGuiCol_CheckMark] =
        ImVec4(
            0.30f,
            0.68f,
            1.0f,
            1.0f
        );

    c[ImGuiCol_SliderGrab] =
        ImVec4(
            0.22f,
            0.56f,
            1.0f,
            1.0f
        );

    c[ImGuiCol_SliderGrabActive] =
        ImVec4(
            0.38f,
            0.70f,
            1.0f,
            1.0f
        );

    c[ImGuiCol_Header] =
        ImVec4(
            0.10f,
            0.17f,
            0.27f,
            1.0f
        );

    c[ImGuiCol_HeaderHovered] =
        ImVec4(
            0.14f,
            0.23f,
            0.36f,
            1.0f
        );

    c[ImGuiCol_HeaderActive] =
        ImVec4(
            0.17f,
            0.30f,
            0.47f,
            1.0f
        );

    c[ImGuiCol_Separator] =
        ImVec4(
            0.13f,
            0.17f,
            0.23f,
            0.80f
        );
}

#pragma mark - Renderer

@interface ASASECImGuiRenderer : NSObject <MTKViewDelegate>
@end

static ASASECImGuiRenderer *gRenderer = nil;

@implementation ASASECImGuiRenderer

- (void)mtkView:(MTKView *)view
drawableSizeWillChange:(CGSize)size
{
    if (!gInitialized || !view)
        return;

    ImGuiContext *ctx =
        ImGui::GetCurrentContext();

    if (!ctx)
        return;

    ImGuiIO &io =
        ImGui::GetIO();

    io.DisplaySize =
        ImVec2(
            (float)view.bounds.size.width,
            (float)view.bounds.size.height
        );

    CGFloat scale =
        view.contentScaleFactor;

    if (scale <= 0.0)
        scale = 1.0;

    io.DisplayFramebufferScale =
        ImVec2(
            (float)scale,
            (float)scale
        );

    UIWindow *window =
        view.window;

    if (window)
        ASASECClampMenuToScreen(
            window
        );
}

- (void)drawInMTKView:(MTKView *)view
{
    if (!gInitialized ||
        !view ||
        !gMetalDevice ||
        !gCommandQueue ||
        !gMetalBackendInitialized)
        return;

    ImGuiContext *ctx =
        ImGui::GetCurrentContext();

    if (!ctx)
        return;

    MTLRenderPassDescriptor *pass =
        view.currentRenderPassDescriptor;

    if (!pass)
        return;

    id drawable =
        view.currentDrawable;

    if (!drawable)
        return;

    id<MTLCommandBuffer> commandBuffer =
        [gCommandQueue commandBuffer];

    if (!commandBuffer)
        return;

    ImGui_ImplMetal_NewFrame(pass);

    ImGuiIO &io =
        ImGui::GetIO();

    io.DisplaySize =
        ImVec2(
            (float)view.bounds.size.width,
            (float)view.bounds.size.height
        );

    CGFloat scale =
        view.contentScaleFactor;

    if (scale <= 0.0)
        scale = 1.0;

    io.DisplayFramebufferScale =
        ImVec2(
            (float)scale,
            (float)scale
        );

    float fps =
        (float)view.preferredFramesPerSecond;

    if (fps < 1.0f)
        fps = 60.0f;

    io.DeltaTime =
        1.0f / fps;

    if (io.DeltaTime <= 0.0f ||
        io.DeltaTime > 0.1f) {

        io.DeltaTime =
            1.0f / 60.0f;
    }

    ImGui::NewFrame();

    float dt =
        io.DeltaTime;

    float categoriesTarget =
        gCategoriesVisible
        ? 1.0f
        : 0.0f;

    gCategoriesAnimation =
        ASASECEase(
            gCategoriesAnimation,
            categoriesTarget,
            kSidebarAnimationSpeed,
            dt
        );

    if (fabsf(
            gCategoriesAnimation -
            categoriesTarget
        ) < 0.001f) {

        gCategoriesAnimation =
            categoriesTarget;
    }

    if (gSelectedPage !=
        gPreviousPage) {

        gPreviousPage =
            gSelectedPage;

        gPageAnimation =
            0.0f;

        gPageSlide =
            16.0f;
    }

    gPageAnimation =
        ASASECEase(
            gPageAnimation,
            1.0f,
            14.0f,
            dt
        );

    gPageSlide =
        ASASECEase(
            gPageSlide,
            0.0f,
            14.0f,
            dt
        );

    if (!gContentDragging &&
        fabsf(gContentScrollVelocity) >
        0.01f) {

        gPendingContentScrollY +=
            gContentScrollVelocity;

        gContentScrollVelocity *=
            expf(-7.0f * dt);

        if (fabsf(
                gContentScrollVelocity
            ) < 0.01f) {

            gContentScrollVelocity =
                0.0f;
        }
    }

    if (gMenuVisible) {

        UIWindow *win =
            view.window;

        if (win)
            ASASECClampMenuToScreen(
                win
            );

        float animatedSidebarWidth =
            ASASECGetAnimatedSidebarWidth();

        ImVec2 actualWindowSize =
            ImVec2(
                gMenuSize.x,
                gMenuCollapsed
                ? kHeaderHeight
                : gMenuSize.y
            );

        ImGui::SetNextWindowPos(
            gMenuPosition,
            ImGuiCond_Always
        );

        ImGui::SetNextWindowSize(
            actualWindowSize,
            ImGuiCond_Always
        );

        ImGuiWindowFlags flags =
            ImGuiWindowFlags_NoTitleBar |
            ImGuiWindowFlags_NoResize |
            ImGuiWindowFlags_NoCollapse |
            ImGuiWindowFlags_NoSavedSettings |
            ImGuiWindowFlags_NoScrollbar;

        ImGui::PushStyleVar(
            ImGuiStyleVar_WindowPadding,
            ImVec2(0.0f, 0.0f)
        );

        ImGui::PushStyleVar(
            ImGuiStyleVar_WindowRounding,
            22.0f
        );

        ImGui::PushStyleColor(
            ImGuiCol_WindowBg,
            ImVec4(
                0.016f,
                0.022f,
                0.035f,
                0.985f
            )
        );

        bool windowOpened =
            ImGui::Begin(
                "##ASASEC_WINDOW",
                NULL,
                flags
            );

        if (windowOpened) {

            ImVec2 windowPos =
                ImGui::GetWindowPos();

            ImVec2 windowSize =
                ImGui::GetWindowSize();

            ImVec2 windowEnd =
                ImVec2(
                    windowPos.x +
                    windowSize.x,
                    windowPos.y +
                    windowSize.y
                );

            ImDrawList *draw =
                ImGui::GetWindowDrawList();

            if (draw) {

                draw->AddRectFilled(
                    windowPos,
                    windowEnd,
                    IM_COL32(
                        5,
                        8,
                        15,
                        253
                    ),
                    22.0f
                );

                draw->AddRect(
                    ImVec2(
                        windowPos.x + 0.5f,
                        windowPos.y + 0.5f
                    ),
                    ImVec2(
                        windowEnd.x - 0.5f,
                        windowEnd.y - 0.5f
                    ),
                    IM_COL32(
                        44,
                        61,
                        86,
                        220
                    ),
                    22.0f,
                    0,
                    1.0f
                );

                draw->AddRectFilled(
                    ImVec2(
                        windowPos.x + 1.0f,
                        windowPos.y + 1.0f
                    ),
                    ImVec2(
                        windowEnd.x - 1.0f,
                        windowPos.y +
                        kHeaderHeight
                    ),
                    IM_COL32(
                        9,
                        14,
                        24,
                        255
                    ),
                    21.0f,
                    ImDrawFlags_RoundCornersTop
                );

                draw->AddLine(
                    ImVec2(
                        windowPos.x + 18.0f,
                        windowPos.y +
                        kHeaderHeight
                    ),
                    ImVec2(
                        windowEnd.x - 18.0f,
                        windowPos.y +
                        kHeaderHeight
                    ),
                    IM_COL32(
                        36,
                        48,
                        67,
                        220
                    ),
                    1.0f
                );

                draw->AddLine(
                    ImVec2(
                        windowPos.x + 20.0f,
                        windowPos.y +
                        kHeaderHeight - 1.0f
                    ),
                    ImVec2(
                        windowPos.x + 105.0f,
                        windowPos.y +
                        kHeaderHeight - 1.0f
                    ),
                    IM_COL32(
                        64,
                        145,
                        245,
                        180
                    ),
                    2.0f
                );

                draw->AddLine(
                    ImVec2(
                        windowPos.x + 25.0f,
                        windowPos.y + 1.0f
                    ),
                    ImVec2(
                        windowEnd.x - 25.0f,
                        windowPos.y + 1.0f
                    ),
                    IM_COL32(
                        74,
                        94,
                        124,
                        90
                    ),
                    1.0f
                );
            }

            const char *uniqueCategories[32];

            int uniqueCategoryCount =
                ASASECGetUniqueCategories(
                    uniqueCategories,
                    32
                );

            if (uniqueCategoryCount <= 0) {

                gSelectedPage = 0;
                gPreviousPage = 0;

            } else if (gSelectedPage >=
                       uniqueCategoryCount) {

                gSelectedPage =
                    0;
            }

            const char *currentCategoryName =
                (
                    uniqueCategoryCount > 0 &&
                    gSelectedPage <
                    uniqueCategoryCount
                )
                ? uniqueCategories[
                    gSelectedPage
                ]
                : "General";

            if (!gMenuCollapsed &&
                gMenuVisible) {

                if (draw &&
                    animatedSidebarWidth > 0.01f) {

                    draw->AddRectFilled(
                        ImVec2(
                            windowPos.x,
                            windowPos.y +
                            kHeaderHeight
                        ),
                        ImVec2(
                            windowPos.x +
                            animatedSidebarWidth,
                            windowEnd.y
                        ),
                        IM_COL32(
                            7,
                            12,
                            22,
                            255
                        ),
                        0.0f
                    );

                    draw->PushClipRect(
                        ImVec2(
                            windowPos.x,
                            windowPos.y +
                            kHeaderHeight
                        ),
                        ImVec2(
                            windowPos.x +
                            animatedSidebarWidth,
                            windowEnd.y
                        ),
                        true
                    );

                    if (animatedSidebarWidth >
                        1.0f) {

                        draw->AddRectFilled(
                            ImVec2(
                                windowPos.x,
                                windowEnd.y -
                                22.0f
                            ),
                            ImVec2(
                                windowPos.x +
                                animatedSidebarWidth,
                                windowEnd.y
                            ),
                            IM_COL32(
                                7,
                                12,
                                22,
                                255
                            ),
                            20.0f,
                            ImDrawFlags_RoundCornersBottomLeft
                        );
                    }

                    if (animatedSidebarWidth >
                        1.0f) {

                        draw->AddLine(
                            ImVec2(
                                windowPos.x +
                                animatedSidebarWidth -
                                1.0f,
                                windowPos.y +
                                72.0f
                            ),
                            ImVec2(
                                windowPos.x +
                                animatedSidebarWidth -
                                1.0f,
                                windowEnd.y -
                                22.0f
                            ),
                            IM_COL32(
                                53,
                                69,
                                94,
                                120
                            ),
                            1.0f
                        );
                    }
                }

                if (gCategoriesAnimation >
                    0.001f) {

                    ImGui::SetCursorPos(
                        ImVec2(
                            18.0f,
                            66.0f
                        )
                    );

                    ImGui::TextColored(
                        ImVec4(
                            0.30f,
                            0.36f,
                            0.45f,
                            1.0f
                        ),
                        "KATEGORİLER"
                    );

                    for (int i = 0;
                         i < uniqueCategoryCount;
                         i++) {

                        bool active =
                            gSelectedPage == i;

                        float itemY =
                            102.0f +
                            i * 52.0f;

                        if (active && draw) {

                            draw->AddRectFilled(
                                ImVec2(
                                    windowPos.x + 8.0f,
                                    windowPos.y +
                                    itemY
                                ),
                                ImVec2(
                                    windowPos.x +
                                    kSidebarWidth -
                                    8.0f,
                                    windowPos.y +
                                    itemY +
                                    43.0f
                                ),
                                IM_COL32(
                                    16,
                                    43,
                                    76,
                                    255
                                ),
                                12.0f
                            );

                            draw->AddRect(
                                ImVec2(
                                    windowPos.x + 8.5f,
                                    windowPos.y +
                                    itemY + 0.5f
                                ),
                                ImVec2(
                                    windowPos.x +
                                    kSidebarWidth -
                                    8.5f,
                                    windowPos.y +
                                    itemY +
                                    42.5f
                                ),
                                IM_COL32(
                                    48,
                                    108,
                                    185,
                                    145
                                ),
                                12.0f,
                                0,
                                1.0f
                            );

                            draw->AddCircleFilled(
                                ImVec2(
                                    windowPos.x + 18.0f,
                                    windowPos.y +
                                    itemY +
                                    21.5f
                                ),
                                3.2f,
                                IM_COL32(
                                    80,
                                    160,
                                    255,
                                    255
                                )
                            );
                        }

                        char id[128];

                        snprintf(
                            id,
                            sizeof(id),
                            "%s##page_%d",
                            uniqueCategories[i],
                            i
                        );

                        ImGui::SetCursorPos(
                            ImVec2(
                                10.0f,
                                itemY
                            )
                        );

                        ImGui::PushID(i);

                        ImGui::PushStyleVar(
                            ImGuiStyleVar_FrameRounding,
                            11.0f
                        );

                        ImGui::PushStyleColor(
                            ImGuiCol_Button,
                            ImVec4(
                                0.0f,
                                0.0f,
                                0.0f,
                                0.0f
                            )
                        );

                        ImGui::PushStyleColor(
                            ImGuiCol_ButtonHovered,
                            ImVec4(
                                0.10f,
                                0.17f,
                                0.27f,
                                0.85f
                            )
                        );

                        ImGui::PushStyleColor(
                            ImGuiCol_ButtonActive,
                            ImVec4(
                                0.13f,
                                0.24f,
                                0.39f,
                                1.0f
                            )
                        );

                        ImGui::PushFont(
                            ImGui::GetIO()
                                .Fonts
                                ->Fonts[0]
                        );

                        ImGui::SetWindowFontScale(
                            1.06f
                        );

                        if (ImGui::Button(
                                id,
                                ImVec2(
                                    kSidebarWidth -
                                    20.0f,
                                    43.0f
                                ))) {

                            if (gSelectedPage == i) {

                                gCategoriesVisible =
                                    !gCategoriesVisible;

                                gOpenCategoriesTouchCandidate =
                                    NO;

                                gPendingContentScrollY =
                                    0.0f;

                                gContentScrollVelocity =
                                    0.0f;

                                gContentDragging =
                                    NO;

                                gContentTouchCandidate =
                                    NO;

                            } else {

                                gSelectedPage =
                                    i;

                                gCategoriesVisible =
                                    YES;

                                gOpenCategoriesTouchCandidate =
                                    NO;

                                gPageAnimation =
                                    0.0f;

                                gPageSlide =
                                    16.0f;

                                gPendingContentScrollY =
                                    0.0f;

                                gContentScrollVelocity =
                                    0.0f;

                                gContentDragging =
                                    NO;

                                gContentTouchCandidate =
                                    NO;
                            }
                        }

                        ImGui::SetWindowFontScale(
                            1.0f
                        );

                        ImGui::PopFont();

                        ImGui::PopStyleColor(3);
                        ImGui::PopStyleVar();
                        ImGui::PopID();
                    }
                }

                if (draw &&
                    animatedSidebarWidth > 0.01f) {

                    draw->PopClipRect();
                }
            }

            if (!gMenuCollapsed &&
                gMenuVisible) {

                float contentStartX =
                    animatedSidebarWidth + 1.0f;

                BOOL categoriesFullyClosed =
                    (!gCategoriesVisible &&
                     gCategoriesAnimation <= 0.001f);

                float contentTitleY =
                    categoriesFullyClosed
                    ? kClosedCategoryTitleY
                    : 13.0f;

                float contentLineY =
                    categoriesFullyClosed
                    ? kClosedCategoryHeaderLineY
                    : 53.0f;

                float contentScrollableStartY =
                    categoriesFullyClosed
                    ? kClosedCategoryContentStartY
                    : 62.0f;

                ImGui::SetCursorPos(
                    ImVec2(
                        contentStartX,
                        kHeaderHeight - 2.0f
                    )
                );

                float contentWidth =
                    windowSize.x -
                    animatedSidebarWidth -
                    1.0f;

                float contentHeight =
                    windowSize.y -
                    kHeaderHeight +
                    2.0f;

                if (contentWidth < 100.0f)
                    contentWidth = 100.0f;

                if (contentHeight < 100.0f)
                    contentHeight = 100.0f;

                bool contentRootOpened =
                    ImGui::BeginChild(
                        "##ContentRoot",
                        ImVec2(
                            contentWidth,
                            contentHeight
                        ),
                        false,
                        ImGuiWindowFlags_NoBackground |
                        ImGuiWindowFlags_NoScrollbar
                    );

                if (contentRootOpened) {

                    if (categoriesFullyClosed) {

                        ImGui::SetCursorPos(
                            ImVec2(
                                7.0f,
                                kClosedCategoryArrowY
                            )
                        );

                        ImGui::PushID(
                            "ASASEC_OPEN_CATEGORIES"
                        );

                        ImGui::PushStyleVar(
                            ImGuiStyleVar_FrameRounding,
                            9.0f
                        );

                        ImGui::PushStyleColor(
                            ImGuiCol_Button,
                            ImVec4(
                                0.045f,
                                0.075f,
                                0.12f,
                                0.95f
                            )
                        );

                        ImGui::PushStyleColor(
                            ImGuiCol_ButtonHovered,
                            ImVec4(
                                0.10f,
                                0.17f,
                                0.27f,
                                1.0f
                            )
                        );

                        ImGui::PushStyleColor(
                            ImGuiCol_ButtonActive,
                            ImVec4(
                                0.13f,
                                0.25f,
                                0.40f,
                                1.0f
                            )
                        );

                        ImGui::Button(
                            "##open_categories",
                            ImVec2(
                                kClosedCategoryArrowWidth,
                                kClosedCategoryArrowHeight
                            )
                        );

                        bool openCategoriesPressed =
                            ImGui::IsItemClicked(
                                ImGuiMouseButton_Left
                            );

                        bool openCategoriesHovered =
                            ImGui::IsItemHovered();

                        ImVec2 openMin =
                            ImGui::GetItemRectMin();

                        ImVec2 openMax =
                            ImGui::GetItemRectMax();

                        ImDrawList *openDraw =
                            ImGui::GetWindowDrawList();

                        if (openDraw) {

                            float centerX =
                                (openMin.x +
                                 openMax.x) *
                                0.5f;

                            float centerY =
                                (openMin.y +
                                 openMax.y) *
                                0.5f;

                            float arrowWidth =
                                7.0f;

                            float arrowHeight =
                                5.0f;

                            ImU32 arrowColor =
                                openCategoriesHovered
                                ? ASASECColor(
                                    0.42f,
                                    0.74f,
                                    1.0f,
                                    1.0f
                                )
                                : ASASECColor(
                                    0.78f,
                                    0.85f,
                                    0.94f,
                                    0.96f
                                );

                            openDraw->AddLine(
                                ImVec2(
                                    centerX -
                                    arrowWidth,
                                    centerY -
                                    arrowHeight
                                ),
                                ImVec2(
                                    centerX,
                                    centerY
                                ),
                                arrowColor,
                                2.3f
                            );

                            openDraw->AddLine(
                                ImVec2(
                                    centerX,
                                    centerY
                                ),
                                ImVec2(
                                    centerX -
                                    arrowWidth,
                                    centerY +
                                    arrowHeight
                                ),
                                arrowColor,
                                2.3f
                            );
                        }

                        if (openCategoriesPressed) {

                            gCategoriesVisible =
                                YES;

                            gOpenCategoriesTouchCandidate =
                                NO;

                            gContentDragging =
                                NO;

                            gContentTouchCandidate =
                                NO;

                            gContentHasMoved =
                                NO;

                            gPendingContentScrollY =
                                0.0f;

                            gContentScrollVelocity =
                                0.0f;
                        }

                        ImGui::PopStyleColor(3);
                        ImGui::PopStyleVar();
                        ImGui::PopID();
                    }

                    ImGui::SetCursorPos(
                        ImVec2(
                            categoriesFullyClosed
                            ? 49.0f
                            : 17.0f,
                            contentTitleY
                        )
                    );

                    ImGui::TextColored(
                        ImVec4(
                            0.94f,
                            0.97f,
                            1.0f,
                            1.0f
                        ),
                        "%s",
                        currentCategoryName
                    );

                    ImGui::SameLine(
                        0.0f,
                        8.0f
                    );

                    ImGui::TextColored(
                        ImVec4(
                            0.30f,
                            0.37f,
                            0.47f,
                            1.0f
                        ),
                        "/ ASASEC"
                    );

                    ImDrawList *contentDraw =
                        ImGui::GetWindowDrawList();

                    if (contentDraw) {

                        contentDraw->AddLine(
                            ImVec2(
                                windowPos.x +
                                animatedSidebarWidth +
                                16.0f,
                                windowPos.y +
                                kHeaderHeight +
                                contentLineY
                            ),
                            ImVec2(
                                windowEnd.x -
                                16.0f,
                                windowPos.y +
                                kHeaderHeight +
                                contentLineY
                            ),
                            IM_COL32(
                                32,
                                42,
                                58,
                                220
                            ),
                            1.0f
                        );
                    }

                    ImGui::SetCursorPos(
                        ImVec2(
                            0.0f,
                            contentScrollableStartY
                        )
                    );

                    float scrollHeight =
                        contentHeight -
                        contentScrollableStartY;

                    if (scrollHeight < 100.0f)
                        scrollHeight = 100.0f;

                    bool scrollableOpened =
                        ImGui::BeginChild(
                            "##ScrollableContent",
                            ImVec2(
                                contentWidth,
                                scrollHeight
                            ),
                            false,
                            ImGuiWindowFlags_NoScrollbar
                        );

                    if (scrollableOpened) {

                        float fade =
                            ASASECClampFloat(
                                gPageAnimation,
                                0.0f,
                                1.0f
                            );

                        ImGui::PushStyleVar(
                            ImGuiStyleVar_Alpha,
                            fade
                        );

                        ImGui::SetCursorPosX(
                            17.0f +
                            gPageSlide
                        );

                        float cardWidth =
                            ImGui::GetContentRegionAvail().x -
                            22.0f;

                        if (cardWidth < 200.0f)
                            cardWidth = 200.0f;

                        char childID[128];

                        snprintf(
                            childID,
                            sizeof(childID),
                            "##Card_%s",
                            currentCategoryName
                        );

                        int featureCount =
                            0;

                        for (int i = 0;
                             i < gRegisteredFeatureCount;
                             i++) {

                            if (
                                gRegisteredFeatures[i].category &&
                                strcmp(
                                    gRegisteredFeatures[i].category,
                                    currentCategoryName
                                ) == 0
                            ) {

                                featureCount++;
                            }
                        }

                        float calculatedHeight =
                            (featureCount * 65.0f) +
                            40.0f;

                        if (calculatedHeight <
                            scrollHeight - 10.0f) {

                            calculatedHeight =
                                scrollHeight - 10.0f;
                        }

                        bool cardOpened =
                            ImGui::BeginChild(
                                childID,
                                ImVec2(
                                    cardWidth,
                                    calculatedHeight
                                ),
                                false,
                                ImGuiWindowFlags_NoBackground
                            );

                        if (cardOpened) {

                            for (int i = 0;
                                 i < gRegisteredFeatureCount;
                                 i++) {

                                ASASECCustomFeature *feature =
                                    &gRegisteredFeatures[i];

                                if (!feature->category)
                                    continue;

                                if (strcmp(
                                        feature->category,
                                        currentCategoryName
                                    ) != 0)
                                    continue;

                                if (feature->type ==
                                    ASASECFeatureTypeSwitch) {

                                    bool *valPtr =
                                        feature->valuePointer;

                                    if (valPtr) {

                                        bool oldVal =
                                            *valPtr;

                                        bool switchClicked =
                                            ASASECModernSwitch(
                                                feature->title,
                                                valPtr
                                            );

                                        if (switchClicked &&
                                            oldVal != *valPtr) {

                                            if (feature->switchCallback) {

                                                feature->switchCallback(
                                                    *valPtr
                                                );
                                            }
                                        }
                                    }

                                    ImGui::Dummy(
                                        ImVec2(
                                            0.0f,
                                            6.0f
                                        )
                                    );

                                } else if (
                                    feature->type ==
                                    ASASECFeatureTypeButton) {

                                    bool buttonClicked =
                                        ASASECModernButton(
                                            feature->title
                                        );

                                    if (buttonClicked) {

                                        if (feature->buttonCallback) {

                                            feature->buttonCallback();
                                        }
                                    }

                                    ImGui::Dummy(
                                        ImVec2(
                                            0.0f,
                                            7.0f
                                        )
                                    );
                                } else if (feature->type == ASASECFeatureTypeSlider) {
                                    float *valPtr = feature->floatValuePointer;
                                    if (valPtr) {
                                        float oldVal = *valPtr;
                                        bool sliderChanged = ASASECModernSlider(feature->title, valPtr, feature->sliderMin, feature->sliderMax);
                                        if (sliderChanged && oldVal != *valPtr) {
                                            if (feature->sliderCallback) {
                                                feature->sliderCallback(*valPtr);
                                            }
                                        }
                                    }
                                    ImGui::Dummy(ImVec2(0.0f, 6.0f));
                                } else if (feature->type == ASASECFeatureTypeCheckbox) {
                                    bool *valPtr = feature->valuePointer;
                                    if (valPtr) {
                                        bool oldVal = *valPtr;
                                        bool checkChanged = ASASECModernCheckbox(feature->title, valPtr);
                                        if (checkChanged && oldVal != *valPtr) {
                                            if (feature->checkboxCallback) {
                                                feature->checkboxCallback(*valPtr);
                                            }
                                        }
                                    }
                                    ImGui::Dummy(ImVec2(0.0f, 6.0f));
                                }
                            }
                        }

                        ImGui::EndChild();

                        ImGui::PopStyleVar();

                        if (fabsf(
                                gPendingContentScrollY
                            ) > 0.001f) {

                            float currentScroll =
                                ImGui::GetScrollY();

                            float maxScroll =
                                ImGui::GetScrollMaxY();

                            float targetScroll =
                                ASASECClampFloat(
                                    currentScroll +
                                    gPendingContentScrollY,
                                    0.0f,
                                    maxScroll
                                );

                            ImGui::SetScrollY(
                                targetScroll
                            );

                            gPendingContentScrollY =
                                0.0f;
                        }
                    }

                    ImGui::EndChild();
                }

                ImGui::EndChild();
            }

            #pragma mark Header Logo - TOP LAYER

            ImDrawList *logoDraw =
                ImGui::GetForegroundDrawList();

            ImFont *headerFont =
                ImGui::GetIO().FontDefault;

            if (!headerFont) {

                if (ImGui::GetIO().Fonts &&
                    !ImGui::GetIO().Fonts->Fonts.empty()) {

                    headerFont =
                        ImGui::GetIO()
                            .Fonts
                            ->Fonts[0];
                }
            }

            const char *partOne =
                "ASASEC";

            const char *partTwo =
                "UI";

            float titleScale =
                1.13f;

            float titleSpacing =
                5.0f;

            float leftSymbolX =
                windowPos.x + 27.0f;

            float titleStartX =
                leftSymbolX + 23.0f;

            float fontHeight =
                ImGui::GetTextLineHeight() *
                titleScale;

            float titleY =
                windowPos.y +
                (kHeaderHeight -
                 fontHeight) *
                0.5f - 1.0f;

            ImVec2 asececSize =
                ImGui::CalcTextSize(partOne);

            ImVec2 uiSize =
                ImGui::CalcTextSize(partTwo);

            float titleWidth =
                (asececSize.x +
                 uiSize.x +
                 titleSpacing) *
                titleScale;

            float rightSymbolX =
                titleStartX +
                titleWidth +
                13.0f;

            float symbolY =
                windowPos.y +
                kHeaderHeight * 0.5f;

            ImU32 statusColor =
                gMenuCollapsed
                ? ASASECColor(
                    1.0f,
                    0.24f,
                    0.28f,
                    1.0f
                )
                : ASASECColor(
                    0.25f,
                    0.86f,
                    0.55f,
                    1.0f
                );

            ImU32 statusGlow =
                gMenuCollapsed
                ? ASASECColor(
                    1.0f,
                    0.18f,
                    0.22f,
                    0.18f
                )
                : ASASECColor(
                    0.20f,
                    0.90f,
                    0.50f,
                    0.18f
                );

            if (logoDraw) {

                logoDraw->AddCircleFilled(
                    ImVec2(
                        leftSymbolX,
                        symbolY
                    ),
                    12.0f,
                    ASASECColor(
                        0.18f,
                        0.55f,
                        1.0f,
                        0.10f
                    ),
                    24
                );

                logoDraw->AddCircleFilled(
                    ImVec2(
                        leftSymbolX,
                        symbolY
                    ),
                    5.0f,
                    ASASECColor(
                        0.30f,
                        0.68f,
                        1.0f,
                        1.0f
                    ),
                    24
                );

                logoDraw->AddCircleFilled(
                    ImVec2(
                        rightSymbolX,
                        symbolY
                    ),
                    9.0f,
                    statusGlow,
                    24
                );

                logoDraw->AddCircleFilled(
                    ImVec2(
                        rightSymbolX,
                        symbolY
                    ),
                    3.5f,
                    statusColor,
                    20
                );
            }

            if (headerFont) {

                ImGui::PushFont(headerFont);

                ImGui::SetWindowFontScale(
                    titleScale
                );

                ImGui::SetCursorPos(
                    ImVec2(
                        titleStartX -
                        windowPos.x,
                        titleY -
                        windowPos.y
                    )
                );

                ImGui::TextColored(
                    ImVec4(
                        0.95f,
                        0.97f,
                        1.0f,
                        1.0f
                    ),
                    "%s",
                    partOne
                );

                ImGui::SameLine(
                    0.0f,
                    titleSpacing
                );

                ImGui::TextColored(
                    ImVec4(
                        0.35f,
                        0.68f,
                        1.0f,
                        1.0f
                    ),
                    "%s",
                    partTwo
                );

                ImGui::SetWindowFontScale(
                    1.0f
                );

                ImGui::PopFont();
            }

            #pragma mark Collapse Button

            float collapseButtonX =
                windowSize.x -
                104.0f;

            ImGui::SetCursorPos(
                ImVec2(
                    collapseButtonX,
                    10.0f
                )
            );

            ImGui::PushID(
                "ASASEC_COLLAPSE_BUTTON"
            );

            ImGui::PushStyleVar(
                ImGuiStyleVar_FrameRounding,
                12.0f
            );

            ImGui::PushStyleColor(
                ImGuiCol_Button,
                ImVec4(
                    0.045f,
                    0.075f,
                    0.12f,
                    1.0f
                )
            );

            ImGui::PushStyleColor(
                ImGuiCol_ButtonHovered,
                ImVec4(
                    0.085f,
                    0.16f,
                    0.26f,
                    1.0f
                )
            );

            ImGui::PushStyleColor(
                ImGuiCol_ButtonActive,
                ImVec4(
                    0.12f,
                    0.25f,
                    0.40f,
                    1.0f
                )
            );

            ImGui::Button(
                "##collapse",
                ImVec2(
                    38.0f,
                    34.0f
                )
            );

            bool collapsePressed =
                ImGui::IsItemClicked(
                    ImGuiMouseButton_Left
                );

            bool collapseHovered =
                ImGui::IsItemHovered();

            ImVec2 arrowMin =
                ImGui::GetItemRectMin();

            ImVec2 arrowMax =
                ImGui::GetItemRectMax();

            ImDrawList *headerDraw =
                ImGui::GetForegroundDrawList();

            if (headerDraw) {

                float centerX =
                    (arrowMin.x +
                     arrowMax.x) *
                    0.5f;

                float centerY =
                    (arrowMin.y +
                     arrowMax.y) *
                    0.5f;

                float arrowWidth =
                    7.0f;

                float arrowHeight =
                    5.0f;

                ImU32 arrowColor =
                    collapseHovered
                    ? ASASECColor(
                        0.42f,
                        0.74f,
                        1.0f,
                        1.0f
                    )
                    : ASASECColor(
                        0.78f,
                        0.85f,
                        0.94f,
                        0.95f
                    );

                if (gMenuCollapsed) {

                    headerDraw->AddLine(
                        ImVec2(
                            centerX -
                            arrowWidth,
                            centerY -
                            arrowHeight
                        ),
                        ImVec2(
                            centerX,
                            centerY +
                            arrowHeight
                        ),
                        arrowColor,
                        2.3f
                    );

                    headerDraw->AddLine(
                        ImVec2(
                            centerX,
                            centerY +
                            arrowHeight
                        ),
                        ImVec2(
                            centerX +
                            arrowWidth,
                            centerY -
                            arrowHeight
                        ),
                        arrowColor,
                        2.3f
                    );

                } else {

                    headerDraw->AddLine(
                        ImVec2(
                            centerX -
                            arrowWidth,
                            centerY +
                            arrowHeight
                        ),
                        ImVec2(
                            centerX,
                            centerY -
                            arrowHeight
                        ),
                        arrowColor,
                        2.3f
                    );

                    headerDraw->AddLine(
                        ImVec2(
                            centerX,
                            centerY -
                            arrowHeight
                        ),
                        ImVec2(
                            centerX +
                            arrowWidth,
                            centerY +
                            arrowHeight
                        ),
                        arrowColor,
                        2.3f
                    );
                }
            }

            if (collapsePressed) {

                gMenuCollapsed =
                    !gMenuCollapsed;

                gDraggingMenu = NO;
                gResizingMenu = NO;
                gContentDragging = NO;
                gContentTouchCandidate = NO;
                gOpenCategoriesTouchCandidate = NO;

                gPendingContentScrollY =
                    0.0f;

                gContentScrollVelocity =
                    0.0f;

                UIWindow *window =
                    view.window;

                if (window)
                    ASASECClampMenuToScreen(
                        window
                    );
            }

            ImGui::PopStyleColor(3);
            ImGui::PopStyleVar();
            ImGui::PopID();

            #pragma mark Close Button

            float closeButtonX =
                windowSize.x -
                51.0f;

            ImGui::SetCursorPos(
                ImVec2(
                    closeButtonX,
                    10.0f
                )
            );

            ImGui::PushID(
                "ASASEC_CLOSE_BUTTON"
            );

            ImGui::PushStyleVar(
                ImGuiStyleVar_FrameRounding,
                12.0f
            );

            ImGui::PushStyleColor(
                ImGuiCol_Button,
                ImVec4(
                    0.095f,
                    0.055f,
                    0.075f,
                    1.0f
                )
            );

            ImGui::PushStyleColor(
                ImGuiCol_ButtonHovered,
                ImVec4(
                    0.30f,
                    0.085f,
                    0.14f,
                    1.0f
                )
            );

            ImGui::PushStyleColor(
                ImGuiCol_ButtonActive,
                ImVec4(
                    0.45f,
                    0.11f,
                    0.18f,
                    1.0f
                )
            );

            ImGui::Button(
                "##close",
                ImVec2(
                    34.0f,
                    34.0f
                )
            );

            bool closePressed =
                ImGui::IsItemClicked(
                    ImGuiMouseButton_Left
                );

            bool closeHovered =
                ImGui::IsItemHovered();

            ImVec2 closeMin =
                ImGui::GetItemRectMin();

            ImVec2 closeMax =
                ImGui::GetItemRectMax();

            ImDrawList *closeDraw =
                ImGui::GetForegroundDrawList();

            if (closeDraw) {

                float cx =
                    (closeMin.x +
                     closeMax.x) *
                    0.5f;

                float cy =
                    (closeMin.y +
                     closeMax.y) *
                    0.5f;

                float size =
                    6.0f;

                ImU32 closeColor =
                    closeHovered
                    ? ASASECColor(
                        1.0f,
                        0.45f,
                        0.52f,
                        1.0f
                    )
                    : ASASECColor(
                        0.86f,
                        0.90f,
                        0.96f,
                        0.95f
                    );

                closeDraw->AddLine(
                    ImVec2(
                        cx - size,
                        cy - size
                    ),
                    ImVec2(
                        cx + size,
                        cy + size
                    ),
                    closeColor,
                    2.2f
                );

                closeDraw->AddLine(
                    ImVec2(
                        cx + size,
                        cy - size
                    ),
                    ImVec2(
                        cx - size,
                        cy + size
                    ),
                    closeColor,
                    2.2f
                );
            }

            if (closePressed) {

                gMenuVisible =
                    NO;

                gMenuCollapsed =
                    NO;

                gDraggingMenu = NO;
                gResizingMenu = NO;
                gContentDragging = NO;
                gContentTouchCandidate = NO;
                gOpenCategoriesTouchCandidate = NO;
            }

            ImGui::PopStyleColor(3);
            ImGui::PopStyleVar();
            ImGui::PopID();

            #pragma mark Resize Indicator

            if (!gMenuCollapsed &&
                gMenuVisible &&
                windowSize.x > 300.0f &&
                windowSize.y > 220.0f) {

                ImDrawList *foreground =
                    ImGui::GetForegroundDrawList();

                if (foreground) {

                    float iconRight =
                        windowEnd.x -
                        8.0f;

                    float iconBottom =
                        windowEnd.y -
                        8.0f;

                    ImVec2 iconCenter =
                        ImVec2(
                            iconRight - 11.0f,
                            iconBottom - 11.0f
                        );

                    ImU32 iconColor =
                        gResizingMenu
                        ? ASASECColor(
                            0.42f,
                            0.72f,
                            1.0f,
                            1.0f
                        )
                        : ASASECColor(
                            0.72f,
                            0.80f,
                            0.91f,
                            0.95f
                        );

                    ImU32 iconGlow =
                        ASASECColor(
                            0.30f,
                            0.68f,
                            1.0f,
                            gResizingMenu
                            ? 0.20f
                            : 0.07f
                        );

                    foreground->AddCircleFilled(
                        iconCenter,
                        13.0f,
                        iconGlow,
                        24
                    );

                    foreground->AddLine(
                        ImVec2(
                            iconCenter.x - 8.0f,
                            iconCenter.y + 8.0f
                        ),
                        ImVec2(
                            iconCenter.x + 8.0f,
                            iconCenter.y + 8.0f
                        ),
                        iconColor,
                        2.2f
                    );

                    foreground->AddLine(
                        ImVec2(
                            iconCenter.x + 8.0f,
                            iconCenter.y - 8.0f
                        ),
                        ImVec2(
                            iconCenter.x + 8.0f,
                            iconCenter.y + 8.0f
                        ),
                        iconColor,
                        2.2f
                    );

                    foreground->AddLine(
                        ImVec2(
                            iconCenter.x - 3.0f,
                            iconCenter.y + 8.0f
                        ),
                        ImVec2(
                            iconCenter.x + 8.0f,
                            iconCenter.y - 3.0f
                        ),
                        iconColor,
                        2.0f
                    );

                    foreground->AddLine(
                        ImVec2(
                            iconCenter.x - 8.0f,
                            iconCenter.y + 3.0f
                        ),
                        ImVec2(
                            iconCenter.x + 8.0f,
                            iconCenter.y - 8.0f
                        ),
                        iconColor,
                        1.6f
                    );
                }
            }
        }

        ImGui::End();

        ImGui::PopStyleColor();

        ImGui::PopStyleVar(2);
    }

    ImGui::Render();

    ImDrawData *drawData =
        ImGui::GetDrawData();

    if (!drawData) {

        [commandBuffer commit];

        return;
    }

    id<MTLRenderCommandEncoder> encoder =
        [commandBuffer
            renderCommandEncoderWithDescriptor:pass];

    if (!encoder) {

        [commandBuffer commit];

        return;
    }

    [encoder setViewport:
        (MTLViewport){
            0.0,
            0.0,
            (double)view.drawableSize.width,
            (double)view.drawableSize.height,
            0.0,
            1.0
        }
    ];

    ImGui_ImplMetal_RenderDrawData(
        drawData,
        commandBuffer,
        encoder
    );

    [encoder endEncoding];

    [commandBuffer
        presentDrawable:drawable];

    [commandBuffer commit];
}

@end

#pragma mark - Start

void ASASECImGuiStart(void)
{
    dispatch_async(
        dispatch_get_main_queue(),
        ^{

            if (gInitialized ||
                gStarting)
                return;

            gStarting = YES;

            UIWindow *window =
                ASASECFindActiveWindow();

            if (!window) {

                gStarting = NO;

                dispatch_after(
                    dispatch_time(
                        DISPATCH_TIME_NOW,
                        (int64_t)(
                            0.25 *
                            NSEC_PER_SEC
                        )
                    ),
                    dispatch_get_main_queue(),
                    ^{
                        ASASECImGuiStart();
                    }
                );

                return;
            }

            id<MTLDevice> device =
                MTLCreateSystemDefaultDevice();

            if (!device) {

                gStarting = NO;

                return;
            }

            id<MTLCommandQueue> queue =
                [device newCommandQueue];

            if (!queue) {

                gStarting = NO;

                return;
            }

            ImGuiContext *oldContext =
                ImGui::GetCurrentContext();

            if (oldContext) {

                ImGui::SetCurrentContext(
                    oldContext
                );

                if (gMetalBackendInitialized) {

                    ImGui_ImplMetal_Shutdown();

                    gMetalBackendInitialized =
                        NO;
                }

                ImGui::DestroyContext(
                    oldContext
                );
            }

            gImGuiView = nil;
            gRenderer = nil;

            gMetalDevice =
                device;

            gCommandQueue =
                queue;

            ImGui::CreateContext();

            ImGuiContext *ctx =
                ImGui::GetCurrentContext();

            if (!ctx) {

                gCommandQueue = nil;
                gMetalDevice = nil;
                gStarting = NO;

                return;
            }

            ImGui::SetCurrentContext(
                ctx
            );

            ImGuiIO &io =
                ImGui::GetIO();

            io.IniFilename =
                NULL;

            io.LogFilename =
                NULL;

            io.FontGlobalScale =
                1.0f;

            io.DisplaySize =
                ImVec2(
                    (float)window.bounds.size.width,
                    (float)window.bounds.size.height
                );

            CGFloat scale =
                window.screen.scale;

            if (scale <= 0.0)
                scale = 1.0;

            io.DisplayFramebufferScale =
                ImVec2(
                    (float)scale,
                    (float)scale
                );

            ASASECApplyStyle();

            gMenuVisible = YES;
            gMenuCollapsed = NO;

            gCategoriesVisible = YES;
            gCategoriesAnimation = 1.0f;

            gSelectedPage = 0;
            gPreviousPage = 0;

            gPageAnimation = 1.0f;
            gPageSlide = 0.0f;

            gDraggingMenu = NO;
            gResizingMenu = NO;
            gContentDragging = NO;

            gOpenCategoriesTouchCandidate =
                NO;

            gContentTouchCandidate =
                NO;

            gContentHasMoved =
                NO;

            gPendingContentScrollY =
                0.0f;

            gContentScrollVelocity =
                0.0f;

            CGRect frame =
                window.bounds;

            ASASECImGuiView *view =
                [[ASASECImGuiView alloc]
                    initWithFrame:frame
                    device:device];

            if (!view) {

                ImGui::DestroyContext();

                gCommandQueue = nil;
                gMetalDevice = nil;
                gStarting = NO;

                return;
            }

            view.backgroundColor =
                UIColor.clearColor;

            view.opaque =
                NO;

            view.clearColor =
                MTLClearColorMake(
                    0.0,
                    0.0,
                    0.0,
                    0.0
                );

            view.colorPixelFormat =
                MTLPixelFormatBGRA8Unorm;

            view.depthStencilPixelFormat =
                MTLPixelFormatInvalid;

            view.preferredFramesPerSecond =
                60;

            view.enableSetNeedsDisplay =
                NO;

            view.paused =
                NO;

            view.multipleTouchEnabled =
                YES;

            view.userInteractionEnabled =
                YES;

            ASASECImGuiRenderer *renderer =
                [[ASASECImGuiRenderer alloc]
                    init];

            if (!renderer) {

                ImGui::DestroyContext();

                gCommandQueue = nil;
                gMetalDevice = nil;
                gStarting = NO;

                return;
            }

            if (!ImGui_ImplMetal_Init(device)) {

                view.delegate = nil;

                ImGui::DestroyContext();

                gCommandQueue = nil;
                gMetalDevice = nil;

                gStarting = NO;

                return;
            }

            gMetalBackendInitialized =
                YES;

            gImGuiView =
                view;

            gRenderer =
                renderer;

            view.delegate =
                renderer;

            [window addSubview:view];

            [window bringSubviewToFront:view];

            ASASECClampMenuToScreen(
                window
            );

            gInitialized =
                YES;

            gStarting =
                NO;
        }
    );
}

#pragma mark - Stop

void ASASECImGuiStop(void)
{
    dispatch_async(
        dispatch_get_main_queue(),
        ^{

            if (!gInitialized &&
                !gStarting)
                return;

            gInitialized = NO;
            gStarting = NO;

            if (gImGuiView) {

                gImGuiView.delegate =
                    nil;

                gImGuiView.paused =
                    YES;

                [gImGuiView
                    removeFromSuperview];

                gImGuiView =
                    nil;
            }

            ImGuiContext *ctx =
                ImGui::GetCurrentContext();

            if (ctx) {

                if (gMetalBackendInitialized) {

                    ImGui_ImplMetal_Shutdown();

                    gMetalBackendInitialized =
                        NO;
                }

                ImGui::DestroyContext(
                    ctx
                );
            }

            gRenderer = nil;
            gCommandQueue = nil;
            gMetalDevice = nil;

            gSwitchAnimationCount =
                0;

            gButtonAnimationCount =
                0;

            gPendingContentScrollY =
                0.0f;

            gContentScrollVelocity =
                0.0f;

            gDraggingMenu = NO;
            gResizingMenu = NO;
            gContentDragging = NO;
            gContentTouchCandidate = NO;
            gContentHasMoved = NO;

            gOpenCategoriesTouchCandidate =
                NO;

            gCategoriesVisible =
                YES;

            gCategoriesAnimation =
                1.0f;
        }
    );
}
