#import "AsasecImgui.h"

#import <UIKit/UIKit.h>
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import <QuartzCore/QuartzCore.h>
#import <dispatch/dispatch.h>
#import <math.h>
#import <string.h>
#import <time.h>

#define IMGUI_DEFINE_MATH_OPERATORS
#include "../imgui.h"
#include "../imgui_internal.h"
#include "../Backends/imgui_impl_metal.h"

#pragma mark - External Feature Registration System

typedef enum {
    ASASECFeatureTypeSwitch = 0,
    ASASECFeatureTypeButton = 1
} ASASECFeatureType;

typedef void (*ASASECSwitchCallback)(bool isOn);
typedef void (*ASASECButtonCallback)(void);

typedef struct {
    ASASECFeatureType type;
    const char *category;
    const char *title;
    bool *valuePointer;
    ASASECSwitchCallback switchCallback;
    ASASECButtonCallback buttonCallback;
} ASASECCustomFeature;

#define MAX_CUSTOM_FEATURES 128

static ASASECCustomFeature gRegisteredFeatures[MAX_CUSTOM_FEATURES];
static int gRegisteredFeatureCount = 0;

void ASASECGuiSwitch(const char *category,
                     const char *title,
                     bool *valuePointer,
                     ASASECSwitchCallback callback)
{
    if (!category || !title || !valuePointer) return;

    if (gRegisteredFeatureCount >= MAX_CUSTOM_FEATURES) return;

    ASASECCustomFeature *feature =
        &gRegisteredFeatures[gRegisteredFeatureCount];

    feature->type = ASASECFeatureTypeSwitch;
    feature->category = category;
    feature->title = title;
    feature->valuePointer = valuePointer;
    feature->switchCallback = callback;
    feature->buttonCallback = NULL;

    gRegisteredFeatureCount++;
}

void ASASECGuiButton(const char *category,
                     const char *title,
                     ASASECButtonCallback callback)
{
    if (!category || !title) return;

    if (gRegisteredFeatureCount >= MAX_CUSTOM_FEATURES) return;

    ASASECCustomFeature *feature =
        &gRegisteredFeatures[gRegisteredFeatureCount];

    feature->type = ASASECFeatureTypeButton;
    feature->category = category;
    feature->title = title;
    feature->valuePointer = NULL;
    feature->switchCallback = NULL;
    feature->buttonCallback = callback;

    gRegisteredFeatureCount++;
}

#pragma mark - Unique Categories

static int ASASECGetUniqueCategories(const char *categoriesOut[],
                                      int maxCategories)
{
    if (!categoriesOut || maxCategories <= 0) return 0;

    int count = 0;

    for (int i = 0; i < gRegisteredFeatureCount; i++) {

        const char *category =
            gRegisteredFeatures[i].category;

        if (!category || category[0] == '\0') continue;

        bool exists = false;

        for (int j = 0; j < count; j++) {
            if (categoriesOut[j] &&
                strcmp(categoriesOut[j], category) == 0) {

                exists = true;
                break;
            }
        }

        if (!exists && count < maxCategories) {
            categoriesOut[count++] = category;
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

static ImVec2 gMenuPosition =
    ImVec2(25.0f, 75.0f);

static ImVec2 gMenuSize =
    ImVec2(560.0f, 390.0f);

static const float kMenuMinWidth = 320.0f;
static const float kMenuMaxWidth = 760.0f;

static const float kMenuMinHeight = 260.0f;
static const float kMenuMaxHeight = 620.0f;

static const float kHeaderHeight = 54.0f;
static const float kResizeSize = 56.0f;

static int gSelectedPage = 0;
static int gPreviousPage = 0;

static BOOL gDraggingMenu = NO;
static BOOL gResizingMenu = NO;
static BOOL gContentDragging = NO;

static CGPoint gDragStartPoint = CGPointZero;
static CGPoint gResizeStartPoint = CGPointZero;

static CGPoint gContentStartPoint = CGPointZero;
static CGPoint gContentLastPoint = CGPointZero;

static ImVec2 gDragStartPosition =
    ImVec2(25.0f, 75.0f);

static ImVec2 gResizeStartSize =
    ImVec2(560.0f, 390.0f);

static float gPendingContentScrollY = 0.0f;
static float gContentScrollVelocity = 0.0f;

static BOOL gContentHasMoved = NO;
static BOOL gContentTouchCandidate = NO;

static float gPageAnimation = 1.0f;
static float gPageSlide = 0.0f;

#pragma mark - Touch Tap State

/*
 * Switch / button yalnızca kısa dokun-bırak hareketinde çalışır.
 *
 * Bu değer bir kullanıcının normal tap süresini rahatça kapsar.
 * Daha uzun basılı tutmalar click olarak kabul edilmez.
 */

static CFTimeInterval gContentTouchBeginTime = 0.0;
static BOOL gContentTapCancelled = NO;

static const CFTimeInterval kMaximumTapDuration = 0.35;

#pragma mark - Button Animation

typedef struct {
    const char *label;
    float progress;
    float glow;
} ASASECButtonAnimation;

static ASASECButtonAnimation
gButtonAnimations[MAX_CUSTOM_FEATURES];

static int gButtonAnimationCount = 0;

static ASASECButtonAnimation *
ASASECGetButtonAnimationData(const char *label)
{
    if (!label) return NULL;

    for (int i = 0; i < gButtonAnimationCount; i++) {

        if (gButtonAnimations[i].label &&
            strcmp(gButtonAnimations[i].label, label) == 0) {

            return &gButtonAnimations[i];
        }
    }

    if (gButtonAnimationCount >= MAX_CUSTOM_FEATURES) {
        return NULL;
    }

    int index = gButtonAnimationCount++;

    gButtonAnimations[index].label = label;
    gButtonAnimations[index].progress = 0.0f;
    gButtonAnimations[index].glow = 0.0f;

    return &gButtonAnimations[index];
}

#pragma mark - Switch Animation

typedef struct {
    const char *label;
    float progress;
    float pulse;
} ASASECSwitchAnimation;

static ASASECSwitchAnimation
gSwitchAnimations[MAX_CUSTOM_FEATURES];

static int gSwitchAnimationCount = 0;

static ASASECSwitchAnimation *
ASASECGetSwitchAnimationData(const char *label)
{
    if (!label) return NULL;

    for (int i = 0; i < gSwitchAnimationCount; i++) {

        if (gSwitchAnimations[i].label &&
            strcmp(gSwitchAnimations[i].label, label) == 0) {

            return &gSwitchAnimations[i];
        }
    }

    if (gSwitchAnimationCount >= MAX_CUSTOM_FEATURES) {
        return NULL;
    }

    int index = gSwitchAnimationCount++;

    gSwitchAnimations[index].label = label;
    gSwitchAnimations[index].progress = 0.0f;
    gSwitchAnimations[index].pulse = 0.0f;

    return &gSwitchAnimations[index];
}

#pragma mark - Helpers

static float ASASECClampFloat(float value,
                              float minValue,
                              float maxValue)
{
    if (maxValue < minValue) {
        maxValue = minValue;
    }

    if (value < minValue) return minValue;
    if (value > maxValue) return maxValue;

    return value;
}

static float ASASECEase(float current,
                        float target,
                        float speed,
                        float dt)
{
    if (dt <= 0.0f) {
        dt = 1.0f / 60.0f;
    }

    if (dt > 0.1f) {
        dt = 0.1f;
    }

    if (speed <= 0.0f) {
        return target;
    }

    float factor =
        1.0f - expf(-speed * dt);

    return current +
           (target - current) * factor;
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

#pragma mark - Active Window

static UIWindow *ASASECFindActiveWindow(void)
{
    UIApplication *application =
        UIApplication.sharedApplication;

    if (!application) return nil;

    for (UIScene *scene in application.connectedScenes) {

        if (![scene isKindOfClass:[UIWindowScene class]]) {
            continue;
        }

        UIWindowScene *windowScene =
            (UIWindowScene *)scene;

        if (windowScene.activationState !=
            UISceneActivationStateForegroundActive) {
            continue;
        }

        for (UIWindow *window in windowScene.windows) {

            if (!window ||
                window.hidden ||
                window.alpha <= 0.0) {
                continue;
            }

            if (window.isKeyWindow) {
                return window;
            }
        }
    }

    for (UIScene *scene in application.connectedScenes) {

        if (![scene isKindOfClass:[UIWindowScene class]]) {
            continue;
        }

        UIWindowScene *windowScene =
            (UIWindowScene *)scene;

        if (windowScene.activationState !=
            UISceneActivationStateForegroundActive) {
            continue;
        }

        for (UIWindow *window in windowScene.windows) {

            if (!window ||
                window.hidden ||
                window.alpha <= 0.0) {
                continue;
            }

            return window;
        }
    }

    return nil;
}

#pragma mark - Menu Bounds

static void ASASECClampMenuToScreen(UIWindow *window)
{
    if (!window) return;

    CGSize size = window.bounds.size;

    const float margin = 12.0f;

    float maxAllowedWidth =
        (float)size.width - margin * 2.0f;

    float targetMaxWidth =
        MIN(kMenuMaxWidth, maxAllowedWidth);

    if (targetMaxWidth < kMenuMinWidth) {
        targetMaxWidth = kMenuMinWidth;
    }

    float maxAllowedHeight =
        (float)size.height - margin * 2.0f;

    float targetMaxHeight =
        MIN(kMenuMaxHeight, maxAllowedHeight);

    if (targetMaxHeight < kMenuMinHeight) {
        targetMaxHeight = kMenuMinHeight;
    }

    float width =
        ASASECClampFloat(
            gMenuSize.x,
            kMenuMinWidth,
            targetMaxWidth
        );

    float height =
        gMenuCollapsed
        ? kHeaderHeight
        : ASASECClampFloat(
            gMenuSize.y,
            kMenuMinHeight,
            targetMaxHeight
        );

    gMenuSize.x = width;
    gMenuSize.y = height;

    float maxX =
        (float)size.width - width - margin;

    float maxY =
        (float)size.height - height - margin;

    if (maxX < margin) {
        maxX = margin;
    }

    if (maxY < margin) {
        maxY = margin;
    }

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

#pragma mark - Modern Switch

static bool ASASECModernSwitch(const char *label,
                               bool *value)
{
    if (!label || !value) {
        return false;
    }

    ImGui::PushID(label);

    const float switchWidth = 48.0f;
    const float switchHeight = 26.0f;
    const float rowHeight = 52.0f;

    float available =
        ImGui::GetContentRegionAvail().x;

    if (available < 150.0f) {
        available = 150.0f;
    }

    bool clicked =
        ImGui::InvisibleButton(
            "##switch",
            ImVec2(available, rowHeight)
        );

    ImVec2 itemMin =
        ImGui::GetItemRectMin();

    ImVec2 itemMax =
        ImGui::GetItemRectMax();

    ImDrawList *draw =
        ImGui::GetWindowDrawList();

    ASASECSwitchAnimation *animationData =
        ASASECGetSwitchAnimationData(label);

    if (clicked) {
        *value = !(*value);

        if (animationData) {
            animationData->pulse = 1.0f;
        }
    }

    bool hovered =
        ImGui::IsItemHovered();

    float dt =
        ImGui::GetIO().DeltaTime;

    if (dt <= 0.0f || dt > 0.1f) {
        dt = 1.0f / 60.0f;
    }

    float progress =
        animationData
        ? animationData->progress
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

    if (animationData) {

        animationData->progress =
            progress;

        animationData->pulse =
            ASASECEase(
                animationData->pulse,
                0.0f,
                12.0f,
                dt
            );
    }

    float pulse =
        animationData
        ? animationData->pulse
        : 0.0f;

    ImU32 cardBackground =
        hovered
        ? ASASECColor(
            0.075f,
            0.100f,
            0.145f,
            0.98f
        )
        : ASASECColor(
            0.052f,
            0.070f,
            0.105f,
            0.98f
        );

    ImU32 cardBorder =
        hovered
        ? ASASECColor(
            0.18f,
            0.28f,
            0.42f,
            0.80f
        )
        : ASASECColor(
            0.12f,
            0.17f,
            0.25f,
            0.75f
        );

    if (draw) {

        draw->AddRectFilled(
            itemMin,
            itemMax,
            cardBackground,
            11.0f
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
            11.0f,
            0,
            1.0f
        );

        float switchX =
            itemMax.x -
            switchWidth -
            14.0f;

        float switchY =
            itemMin.y +
            (rowHeight - switchHeight) * 0.5f;

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
            0.09f +
            (0.18f - 0.09f) *
            progress;

        float bgG =
            0.13f +
            (0.52f - 0.13f) *
            progress;

        float bgB =
            0.20f +
            (0.95f - 0.20f) *
            progress;

        if (hovered) {
            bgR += 0.025f;
            bgG += 0.025f;
            bgB += 0.025f;
        }

        bgR = ASASECClampFloat(bgR, 0.0f, 1.0f);
        bgG = ASASECClampFloat(bgG, 0.0f, 1.0f);
        bgB = ASASECClampFloat(bgB, 0.0f, 1.0f);

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
                0.24f + 0.24f * progress,
                0.32f + 0.32f * progress,
                0.46f + 0.40f * progress,
                0.85f
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
            pulse * 1.3f;

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
                0.30f
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
            itemMin.y + 8.0f
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
            itemMin.y + 29.0f
        )
    );

    ImGui::TextColored(
        ImVec4(
            0.38f,
            0.44f,
            0.53f,
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
    if (!label) {
        return false;
    }

    ImGui::PushID(label);

    float available =
        ImGui::GetContentRegionAvail().x;

    if (available < 150.0f) {
        available = 150.0f;
    }

    const float buttonHeight = 48.0f;

    /*
     * InvisibleButton ile kendi görünümümüzü çiziyoruz.
     * Böylece ImGui'nin standart basılı mavi durumunu
     * kullanmıyoruz.
     */

    ImGui::InvisibleButton(
        "##modern_button",
        ImVec2(
            available,
            buttonHeight
        )
    );

    ImVec2 itemMin =
        ImGui::GetItemRectMin();

    ImVec2 itemMax =
        ImGui::GetItemRectMax();

    bool hovered =
        ImGui::IsItemHovered();

    bool mouseReleased =
        ImGui::IsItemDeactivated();

    bool mouseClicked =
        ImGui::IsItemClicked(
            ImGuiMouseButton_Left
        );

    /*
     * ImGui tıklamayı release anında üretir.
     * Burada ek olarak uzun basmayı engellemek
     * için touch tarafındaki iptal durumu kontrol edilir.
     */

    bool clicked =
        mouseReleased &&
        mouseClicked &&
        !gContentTapCancelled;

    ASASECButtonAnimation *animationData =
        ASASECGetButtonAnimationData(label);

    if (clicked && animationData) {
        animationData->glow = 1.0f;
    }

    float dt =
        ImGui::GetIO().DeltaTime;

    if (dt <= 0.0f || dt > 0.1f) {
        dt = 1.0f / 60.0f;
    }

    if (animationData) {

        animationData->glow =
            ASASECEase(
                animationData->glow,
                0.0f,
                9.0f,
                dt
            );

        animationData->progress =
            ASASECEase(
                animationData->progress,
                0.0f,
                12.0f,
                dt
            );
    }

    float glow =
        animationData
        ? animationData->glow
        : 0.0f;

    ImDrawList *draw =
        ImGui::GetWindowDrawList();

    if (draw) {

        ImU32 normalBackground =
            ASASECColor(
                0.055f,
                0.075f,
                0.115f,
                1.0f
            );

        ImU32 hoverBackground =
            ASASECColor(
                0.075f,
                0.115f,
                0.18f,
                1.0f
            );

        ImU32 background =
            hovered
            ? hoverBackground
            : normalBackground;

        /*
         * Kısa mavi pulse.
         * Basılı kalırken mavi tutulmaz.
         */

        if (glow > 0.001f) {

            draw->AddRectFilled(
                ImVec2(
                    itemMin.x - 2.0f,
                    itemMin.y - 2.0f
                ),
                ImVec2(
                    itemMax.x + 2.0f,
                    itemMax.y + 2.0f
                ),
                ASASECColor(
                    0.20f,
                    0.60f,
                    1.0f,
                    glow * 0.18f
                ),
                13.0f
            );

            background =
                ASASECColor(
                    0.055f +
                    0.10f * glow,

                    0.075f +
                    0.20f * glow,

                    0.115f +
                    0.45f * glow,

                    1.0f
                );
        }

        ImU32 border =
            hovered
            ? ASASECColor(
                0.18f,
                0.34f,
                0.55f,
                0.90f
            )
            : ASASECColor(
                0.12f,
                0.18f,
                0.27f,
                0.80f
            );

        if (glow > 0.001f) {

            border =
                ASASECColor(
                    0.25f +
                    0.25f * glow,

                    0.42f +
                    0.25f * glow,

                    0.70f +
                    0.25f * glow,

                    0.90f
                );
        }

        draw->AddRectFilled(
            itemMin,
            itemMax,
            background,
            12.0f
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
            border,
            12.0f,
            0,
            1.0f
        );

        if (glow > 0.01f) {

            draw->AddRect(
                ImVec2(
                    itemMin.x + 1.5f,
                    itemMin.y + 1.5f
                ),
                ImVec2(
                    itemMax.x - 1.5f,
                    itemMax.y - 1.5f
                ),
                ASASECColor(
                    0.25f,
                    0.65f,
                    1.0f,
                    glow * 0.65f
                ),
                11.0f,
                0,
                1.4f
            );
        }
    }

    ImVec2 textSize =
        ImGui::CalcTextSize(label);

    ImVec2 textPosition =
        ImVec2(
            itemMin.x +
            (available - textSize.x) * 0.5f,

            itemMin.y +
            (buttonHeight - textSize.y) * 0.5f
        );

    ImGui::SetCursorScreenPos(
        textPosition
    );

    ImGui::TextColored(
        hovered
        ? ImVec4(
            0.94f,
            0.97f,
            1.0f,
            1.0f
        )
        : ImVec4(
            0.84f,
            0.89f,
            0.96f,
            1.0f
        ),
        "%s",
        label
    );

    ImGui::PopID();

    return clicked;
}

#pragma mark - ImGui View

@interface ASASECImGuiView : MTKView
@end

@implementation ASASECImGuiView

- (BOOL)pointInsideMenu:(CGPoint)point
{
    if (!gMenuVisible) {
        return NO;
    }

    float height =
        gMenuCollapsed
        ? kHeaderHeight
        : gMenuSize.y;

    return
        point.x >= gMenuPosition.x &&
        point.x <= gMenuPosition.x + gMenuSize.x &&
        point.y >= gMenuPosition.y &&
        point.y <= gMenuPosition.y + height;
}

- (UIView *)hitTest:(CGPoint)point
           withEvent:(UIEvent *)event
{
    if (!gInitialized ||
        !gMenuVisible) {
        return nil;
    }

    if ([self pointInsideMenu:point]) {
        return self;
    }

    return nil;
}

- (void)updateIOWithTouchEvent:(UIEvent *)event
{
    if (!gInitialized || !event) {
        return;
    }

    ImGuiContext *ctx =
        ImGui::GetCurrentContext();

    if (!ctx) {
        return;
    }

    ImGuiIO &io =
        ImGui::GetIO();

    UITouch *touch =
        event.allTouches.anyObject;

    if (!touch) {
        return;
    }

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

        if (!currentTouch) {
            continue;
        }

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
    if (!gInitialized) {
        return;
    }

    [self updateIOWithTouchEvent:event];

    UITouch *touch =
        touches.anyObject;

    if (!touch) {
        return;
    }

    CGPoint point =
        [touch locationInView:self];

    if (!gMenuVisible) {
        return;
    }

    if (!gMenuCollapsed) {

        float resizeIconX =
            gMenuPosition.x +
            gMenuSize.x -
            kResizeSize;

        float resizeIconY =
            gMenuPosition.y +
            gMenuSize.y -
            kResizeSize;

        if (point.x >= resizeIconX &&
            point.y >= resizeIconY &&
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

            gContentTapCancelled = YES;

            return;
        }

        const float sidebarWidth = 145.0f;

        float contentStartX =
            gMenuPosition.x +
            sidebarWidth;

        float contentStartY =
            gMenuPosition.y +
            62.0f;

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

            gContentTouchCandidate = YES;
            gContentHasMoved = NO;
            gContentDragging = NO;

            gContentStartPoint =
                point;

            gContentLastPoint =
                point;

            gContentScrollVelocity =
                0.0f;

            gContentTouchBeginTime =
                CACurrentMediaTime();

            gContentTapCancelled = NO;

            return;
        }

        if (point.x >= gMenuPosition.x &&
            point.x <=
                gMenuPosition.x +
                gMenuSize.x &&
            point.y >= gMenuPosition.y &&
            point.y <=
                gMenuPosition.y +
                kHeaderHeight) {

            gDraggingMenu = YES;

            gDragStartPoint =
                point;

            gDragStartPosition =
                gMenuPosition;

            gContentTapCancelled = YES;

            return;
        }

    } else {

        if (point.x >= gMenuPosition.x &&
            point.x <=
                gMenuPosition.x +
                gMenuSize.x &&
            point.y >= gMenuPosition.y &&
            point.y <=
                gMenuPosition.y +
                kHeaderHeight) {

            gDraggingMenu = YES;

            gDragStartPoint =
                point;

            gDragStartPosition =
                gMenuPosition;

            gContentTapCancelled = YES;

            return;
        }
    }
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches
           withEvent:(UIEvent *)event
{
    if (!gInitialized) {
        return;
    }

    [self updateIOWithTouchEvent:event];

    UITouch *touch =
        touches.anyObject;

    if (!touch) {
        return;
    }

    CGPoint point =
        [touch locationInView:self];

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

        if (window) {
            ASASECClampMenuToScreen(window);
        }

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

        if (window) {
            ASASECClampMenuToScreen(window);
        }

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

        /*
         * Uzun basma.
         * Kullanıcı 350 ms'den fazla basılı tutarsa
         * bunu tap olarak kabul etmiyoruz.
         */

        CFTimeInterval duration =
            CACurrentMediaTime() -
            gContentTouchBeginTime;

        if (duration >
            kMaximumTapDuration) {

            gContentTapCancelled = YES;
        }

        if (!gContentDragging &&
            (fabsf(moveX) > 6.0f ||
             fabsf(moveY) > 6.0f)) {

            gContentDragging = YES;
            gContentHasMoved = YES;
            gContentTapCancelled = YES;
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
    if (!gInitialized) {
        return;
    }

    [self updateIOWithTouchEvent:event];

    CFTimeInterval duration =
        CACurrentMediaTime() -
        gContentTouchBeginTime;

    /*
     * Uzun basma kesinlikle click üretmesin.
     */

    if (gContentTouchCandidate &&
        duration >
            kMaximumTapDuration) {

        gContentTapCancelled = YES;
    }

    ImGuiContext *ctx =
        ImGui::GetCurrentContext();

    if (ctx) {
        ImGui::GetIO().MouseDown[0] =
            false;
    }

    gDraggingMenu = NO;
    gResizingMenu = NO;
    gContentDragging = NO;
    gContentTouchCandidate = NO;

    /*
     * Bir sonraki tap için reset.
     */

    gContentTapCancelled = NO;
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches
               withEvent:(UIEvent *)event
{
    if (!gInitialized) {
        return;
    }

    [self updateIOWithTouchEvent:event];

    ImGuiContext *ctx =
        ImGui::GetCurrentContext();

    if (ctx) {
        ImGui::GetIO().MouseDown[0] =
            false;
    }

    gDraggingMenu = NO;
    gResizingMenu = NO;
    gContentDragging = NO;
    gContentTouchCandidate = NO;

    gContentTapCancelled = YES;
}

@end

#pragma mark - Style

static void ASASECApplyStyle(void)
{
    if (!ImGui::GetCurrentContext()) {
        return;
    }

    ImGuiStyle &style =
        ImGui::GetStyle();

    style.WindowPadding =
        ImVec2(10.0f, 10.0f);

    style.FramePadding =
        ImVec2(11.0f, 8.0f);

    style.ItemSpacing =
        ImVec2(9.0f, 12.0f);

    style.ItemInnerSpacing =
        ImVec2(7.0f, 6.0f);

    style.ScrollbarSize =
        1.0f;

    style.GrabMinSize =
        15.0f;

    style.WindowRounding =
        22.0f;

    style.ChildRounding =
        14.0f;

    style.FrameRounding =
        10.0f;

    style.PopupRounding =
        12.0f;

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
            0.93f,
            0.96f,
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
            0.018f,
            0.024f,
            0.038f,
            0.985f
        );

    c[ImGuiCol_ChildBg] =
        ImVec4(
            0.040f,
            0.052f,
            0.074f,
            0.98f
        );

    c[ImGuiCol_Border] =
        ImVec4(
            0.13f,
            0.17f,
            0.24f,
            0.75f
        );

    c[ImGuiCol_FrameBg] =
        ImVec4(
            0.060f,
            0.076f,
            0.108f,
            1.0f
        );

    c[ImGuiCol_FrameBgHovered] =
        ImVec4(
            0.095f,
            0.125f,
            0.18f,
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
            0.060f,
            0.080f,
            0.12f,
            1.0f
        );

    c[ImGuiCol_ButtonHovered] =
        ImVec4(
            0.105f,
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
    if (!gInitialized || !view) {
        return;
    }

    ImGuiContext *ctx =
        ImGui::GetCurrentContext();

    if (!ctx) {
        return;
    }

    ImGuiIO &io =
        ImGui::GetIO();

    io.DisplaySize =
        ImVec2(
            (float)view.bounds.size.width,
            (float)view.bounds.size.height
        );

    CGFloat scale =
        view.contentScaleFactor;

    if (scale <= 0.0) {
        scale = 1.0;
    }

    io.DisplayFramebufferScale =
        ImVec2(
            (float)scale,
            (float)scale
        );

    UIWindow *window =
        view.window;

    if (window) {
        ASASECClampMenuToScreen(window);
    }
}

- (void)drawInMTKView:(MTKView *)view
{
    if (!gInitialized ||
        !view ||
        !gMetalDevice ||
        !gCommandQueue ||
        !gMetalBackendInitialized) {

        return;
    }

    ImGuiContext *ctx =
        ImGui::GetCurrentContext();

    if (!ctx) {
        return;
    }

    MTLRenderPassDescriptor *pass =
        view.currentRenderPassDescriptor;

    if (!pass) {
        return;
    }

    id drawable =
        view.currentDrawable;

    if (!drawable) {
        return;
    }

    id<MTLCommandBuffer> commandBuffer =
        [gCommandQueue commandBuffer];

    if (!commandBuffer) {
        return;
    }

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

    if (scale <= 0.0) {
        scale = 1.0;
    }

    io.DisplayFramebufferScale =
        ImVec2(
            (float)scale,
            (float)scale
        );

    float fps =
        (float)view.preferredFramesPerSecond;

    if (fps < 1.0f) {
        fps = 60.0f;
    }

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

    if (gSelectedPage != gPreviousPage) {

        gPreviousPage =
            gSelectedPage;

        gPageAnimation =
            0.0f;

        gPageSlide =
            18.0f;

        gContentTapCancelled =
            NO;
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
        fabsf(gContentScrollVelocity) > 0.01f) {

        gPendingContentScrollY +=
            gContentScrollVelocity;

        gContentScrollVelocity *=
            expf(-7.0f * dt);

        if (fabsf(gContentScrollVelocity) <
            0.01f) {

            gContentScrollVelocity =
                0.0f;
        }
    }

    if (gMenuVisible) {

        UIWindow *win =
            view.window;

        if (win) {
            ASASECClampMenuToScreen(win);
        }

        const float sidebarWidth =
            145.0f;

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
                0.018f,
                0.024f,
                0.038f,
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

            #pragma mark Window Background

            if (draw) {

                draw->AddRectFilled(
                    windowPos,
                    windowEnd,
                    IM_COL32(
                        6,
                        9,
                        16,
                        252
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
                        48,
                        62,
                        84,
                        185
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
                        10,
                        15,
                        25,
                        255
                    ),
                    21.0f,
                    ImDrawFlags_RoundCornersTop
                );

                draw->AddLine(
                    ImVec2(
                        windowPos.x + 16.0f,
                        windowPos.y +
                        kHeaderHeight
                    ),
                    ImVec2(
                        windowEnd.x - 16.0f,
                        windowPos.y +
                        kHeaderHeight
                    ),
                    IM_COL32(
                        38,
                        48,
                        66,
                        220
                    ),
                    1.0f
                );
            }

            #pragma mark Header

            ImGui::SetCursorPos(
                ImVec2(
                    18.0f,
                    11.0f
                )
            );

            ImGui::TextColored(
                ImVec4(
                    0.30f,
                    0.68f,
                    1.0f,
                    1.0f
                ),
                "●"
            );

            ImGui::SameLine(
                0.0f,
                7.0f
            );

            ImGuiIO &currentIO =
                ImGui::GetIO();

            if (currentIO.Fonts &&
                currentIO.Fonts->Fonts.Size > 0) {

                ImGui::PushFont(
                    currentIO.Fonts->Fonts[0]
                );
            }

            ImGui::SetWindowFontScale(
                1.15f
            );

            ImGui::TextColored(
                ImVec4(
                    0.94f,
                    0.97f,
                    1.0f,
                    1.0f
                ),
                "ASASEC"
            );

            ImGui::SameLine(
                0.0f,
                5.0f
            );

            ImGui::TextColored(
                ImVec4(
                    0.43f,
                    0.49f,
                    0.59f,
                    1.0f
                ),
                "UI"
            );

            ImGui::SetWindowFontScale(
                1.0f
            );

            if (currentIO.Fonts &&
                currentIO.Fonts->Fonts.Size > 0) {

                ImGui::PopFont();
            }

            #pragma mark Collapse Button

            float collapseButtonX =
                windowSize.x - 96.0f;

            if (collapseButtonX < 0.0f) {
                collapseButtonX = 0.0f;
            }

            ImGui::SetCursorPos(
                ImVec2(
                    collapseButtonX,
                    9.0f
                )
            );

            ImGui::PushID(
                "ASASEC_COLLAPSE_BUTTON"
            );

            ImGui::PushStyleVar(
                ImGuiStyleVar_FrameRounding,
                10.0f
            );

            ImGui::PushStyleColor(
                ImGuiCol_Button,
                ImVec4(
                    0.06f,
                    0.09f,
                    0.14f,
                    1.0f
                )
            );

            ImGui::PushStyleColor(
                ImGuiCol_ButtonHovered,
                ImVec4(
                    0.11f,
                    0.18f,
                    0.29f,
                    1.0f
                )
            );

            ImGui::PushStyleColor(
                ImGuiCol_ButtonActive,
                ImVec4(
                    0.17f,
                    0.28f,
                    0.43f,
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
                ImGui::GetWindowDrawList();

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
                        0.84f,
                        0.93f,
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
                        2.2f
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
                        2.2f
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
                        2.2f
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
                        2.2f
                    );
                }
            }

            if (collapsePressed) {

                gMenuCollapsed =
                    !gMenuCollapsed;

                gDraggingMenu =
                    NO;

                gResizingMenu =
                    NO;

                gContentDragging =
                    NO;

                gContentScrollVelocity =
                    0.0f;

                gPendingContentScrollY =
                    0.0f;

                UIWindow *window =
                    view.window;

                if (window) {
                    ASASECClampMenuToScreen(
                        window
                    );
                }
            }

            ImGui::PopStyleColor(3);
            ImGui::PopStyleVar();
            ImGui::PopID();

            #pragma mark Close Button

            float closeButtonX =
                windowSize.x - 50.0f;

            if (closeButtonX < 0.0f) {
                closeButtonX = 0.0f;
            }

            ImGui::SetCursorPos(
                ImVec2(
                    closeButtonX,
                    9.0f
                )
            );

            ImGui::PushID(
                "ASASEC_CLOSE_BUTTON"
            );

            ImGui::PushStyleVar(
                ImGuiStyleVar_FrameRounding,
                10.0f
            );

            ImGui::PushStyleColor(
                ImGuiCol_Button,
                ImVec4(
                    0.10f,
                    0.065f,
                    0.085f,
                    1.0f
                )
            );

            ImGui::PushStyleColor(
                ImGuiCol_ButtonHovered,
                ImVec4(
                    0.34f,
                    0.10f,
                    0.15f,
                    1.0f
                )
            );

            ImGui::PushStyleColor(
                ImGuiCol_ButtonActive,
                ImVec4(
                    0.48f,
                    0.12f,
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
                ImGui::GetWindowDrawList();

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

                gDraggingMenu =
                    NO;

                gResizingMenu =
                    NO;

                gContentDragging =
                    NO;
            }

            ImGui::PopStyleColor(3);
            ImGui::PopStyleVar();
            ImGui::PopID();

            #pragma mark Main Content

            if (!gMenuCollapsed &&
                gMenuVisible) {

                if (draw) {

                    draw->AddRectFilled(
                        ImVec2(
                            windowPos.x,
                            windowPos.y +
                            kHeaderHeight
                        ),
                        ImVec2(
                            windowPos.x +
                            sidebarWidth,
                            windowEnd.y
                        ),
                        IM_COL32(
                            9,
                            14,
                            24,
                            255
                        ),
                        0.0f
                    );

                    draw->AddRectFilled(
                        ImVec2(
                            windowPos.x,
                            windowPos.y
                        ),
                        ImVec2(
                            windowPos.x +
                            sidebarWidth,
                            windowPos.y +
                            kHeaderHeight
                        ),
                        IM_COL32(
                            9,
                            14,
                            24,
                            255
                        ),
                        16.0f,
                        ImDrawFlags_RoundCornersTopLeft
                    );

                    draw->AddRectFilled(
                        ImVec2(
                            windowPos.x,
                            windowEnd.y -
                            22.0f
                        ),
                        ImVec2(
                            windowPos.x +
                            sidebarWidth,
                            windowEnd.y
                        ),
                        IM_COL32(
                            9,
                            14,
                            24,
                            255
                        ),
                        20.0f,
                        ImDrawFlags_RoundCornersBottomLeft
                    );

                    draw->AddLine(
                        ImVec2(
                            windowPos.x +
                            sidebarWidth,
                            windowPos.y +
                            62.0f
                        ),
                        ImVec2(
                            windowPos.x +
                            sidebarWidth,
                            windowEnd.y -
                            16.0f
                        ),
                        IM_COL32(
                            34,
                            43,
                            59,
                            210
                        ),
                        1.0f
                    );
                }

                #pragma mark Categories

                /*
                 * Navigation -> KATEGORİLER
                 * ASASEC UI'dan ayrılmıştır.
                 */

                ImGui::SetCursorPos(
                    ImVec2(
                        18.0f,
                        39.0f
                    )
                );

                ImGui::TextColored(
                    ImVec4(
                        0.27f,
                        0.32f,
                        0.40f,
                        1.0f
                    ),
                    "KATEGORİLER"
                );

                const char *uniqueCategories[32];

                int uniqueCategoryCount =
                    ASASECGetUniqueCategories(
                        uniqueCategories,
                        32
                    );

                if (gSelectedPage >=
                    uniqueCategoryCount) {

                    gSelectedPage = 0;
                }

                #pragma mark Category Buttons

                for (int i = 0;
                     i < uniqueCategoryCount;
                     i++) {

                    bool active =
                        gSelectedPage == i;

                    float itemY =
                        74.0f +
                        i * 54.0f;

                    if (active && draw) {

                        draw->AddRectFilled(
                            ImVec2(
                                windowPos.x +
                                9.0f,
                                windowPos.y +
                                itemY
                            ),
                            ImVec2(
                                windowPos.x +
                                sidebarWidth -
                                9.0f,
                                windowPos.y +
                                itemY +
                                43.0f
                            ),
                            IM_COL32(
                                19,
                                48,
                                84,
                                255
                            ),
                            11.0f
                        );

                        draw->AddCircleFilled(
                            ImVec2(
                                windowPos.x +
                                18.0f,
                                windowPos.y +
                                itemY +
                                21.5f
                            ),
                            3.0f,
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

                    ImGui::PushID(
                        id
                    );

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

                    /*
                     * Kategori yazıları biraz büyütüldü.
                     */

                    ImGui::SetWindowFontScale(
                        1.05f
                    );

                    bool categoryPressed =
                        ImGui::Button(
                            uniqueCategories[i],
                            ImVec2(
                                sidebarWidth -
                                20.0f,
                                43.0f
                            )
                        );

                    ImGui::SetWindowFontScale(
                        1.0f
                    );

                    if (categoryPressed) {

                        if (gSelectedPage != i) {

                            gSelectedPage =
                                i;

                            gPageAnimation =
                                0.0f;

                            gPageSlide =
                                18.0f;

                            gPendingContentScrollY =
                                0.0f;

                            gContentScrollVelocity =
                                0.0f;
                        }
                    }

                    ImGui::PopStyleColor(3);
                    ImGui::PopStyleVar();
                    ImGui::PopID();
                }

                #pragma mark Content Root

                ImGui::SetCursorPos(
                    ImVec2(
                        sidebarWidth + 1.0f,
                        54.0f
                    )
                );

                float contentWidth =
                    windowSize.x -
                    sidebarWidth -
                    1.0f;

                float contentHeight =
                    windowSize.y -
                    54.0f;

                if (contentWidth < 100.0f) {
                    contentWidth = 100.0f;
                }

                if (contentHeight < 100.0f) {
                    contentHeight = 100.0f;
                }

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

                    /*
                     * BURADA:
                     *
                     * "Configure your loaded features"
                     * tamamen kaldırıldı.
                     *
                     * Kategori başlığı da kaldırıldı.
                     *
                     * İçerikte artık doğrudan switch
                     * ve butonlar gösteriliyor.
                     */

                    ImGui::SetCursorPos(
                        ImVec2(
                            0.0f,
                            8.0f
                        )
                    );

                    float scrollHeight =
                        contentHeight -
                        8.0f;

                    if (scrollHeight < 100.0f) {
                        scrollHeight = 100.0f;
                    }

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

                        /*
                         * Switch ve butonların başladığı
                         * yatay konum.
                         */

                        ImGui::SetCursorPosX(
                            17.0f +
                            gPageSlide
                        );

                        float cardWidth =
                            ImGui::GetContentRegionAvail().x -
                            22.0f;

                        if (cardWidth < 200.0f) {
                            cardWidth = 200.0f;
                        }

                        char childID[128];

                        const char *currentCategoryName =
                            (
                                uniqueCategoryCount > 0 &&
                                gSelectedPage <
                                uniqueCategoryCount
                            )
                            ? uniqueCategories[gSelectedPage]
                            : "General";

                        snprintf(
                            childID,
                            sizeof(childID),
                            "##Card_%s",
                            currentCategoryName
                        );

                        /*
                         * Card yüksekliğini sabit 294 yerine
                         * içerik miktarına göre genişletiyoruz.
                         * Böylece fazla switch/buton kaybolmuyor.
                         */

                        int featureCountForPage = 0;

                        for (int i = 0;
                             i < gRegisteredFeatureCount;
                             i++) {

                            if (gRegisteredFeatures[i].category &&
                                strcmp(
                                    gRegisteredFeatures[i].category,
                                    currentCategoryName
                                ) == 0) {

                                featureCountForPage++;
                            }
                        }

                        float calculatedHeight =
                            12.0f +
                            featureCountForPage * 60.0f +
                            20.0f;

                        float visibleCardHeight =
                            MAX(
                                calculatedHeight,
                                100.0f
                            );

                        bool cardOpened =
                            ImGui::BeginChild(
                                childID,
                                ImVec2(
                                    cardWidth,
                                    visibleCardHeight
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

                                if (!feature->category) {
                                    continue;
                                }

                                if (strcmp(
                                        feature->category,
                                        currentCategoryName
                                    ) != 0) {

                                    continue;
                                }

                                if (feature->type ==
                                    ASASECFeatureTypeSwitch) {

                                    bool *valPtr =
                                        feature->valuePointer;

                                    if (valPtr) {

                                        bool oldVal =
                                            *valPtr;

                                        /*
                                         * Switch yalnızca normal
                                         * tap ile değişir.
                                         */

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
                                            8.0f
                                        )
                                    );
                                }
                            }
                        }

                        ImGui::EndChild();

                        ImGui::PopStyleVar();

                        /*
                         * Manuel touch scrolling.
                         */

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

            #pragma mark Resize Icon

            if (!gMenuCollapsed &&
                gMenuVisible &&
                windowSize.x > 300.0f &&
                windowSize.y > 220.0f) {

                ImDrawList *foreground =
                    ImGui::GetForegroundDrawList();

                if (foreground) {

                    float iconRight =
                        windowEnd.x -
                        9.0f;

                    float iconBottom =
                        windowEnd.y -
                        9.0f;

                    ImVec2 iconCenter =
                        ImVec2(
                            iconRight -
                            11.0f,
                            iconBottom -
                            11.0f
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
                            ? 0.18f
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
                gStarting) {

                return;
            }

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

            if (scale <= 0.0) {
                scale = 1.0;
            }

            io.DisplayFramebufferScale =
                ImVec2(
                    (float)scale,
                    (float)scale
                );

            ASASECApplyStyle();

            gMenuVisible =
                YES;

            gMenuCollapsed =
                NO;

            gSelectedPage =
                0;

            gPreviousPage =
                0;

            gPageAnimation =
                1.0f;

            gPageSlide =
                0.0f;

            gDraggingMenu =
                NO;

            gResizingMenu =
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

            gContentTouchBeginTime =
                0.0;

            gContentTapCancelled =
                NO;

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

                view.delegate =
                    nil;

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
                !gStarting) {

                return;
            }

            gInitialized =
                NO;

            gStarting =
                NO;

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

            gRenderer =
                nil;

            gCommandQueue =
                nil;

            gMetalDevice =
                nil;

            gSwitchAnimationCount =
                0;

            gButtonAnimationCount =
                0;

            gPendingContentScrollY =
                0.0f;

            gContentScrollVelocity =
                0.0f;

            gDraggingMenu =
                NO;

            gResizingMenu =
                NO;

            gContentDragging =
                NO;

            gContentTouchCandidate =
                NO;

            gContentHasMoved =
                NO;

            gContentTapCancelled =
                NO;

            gContentTouchBeginTime =
                0.0;
        }
    );
}
