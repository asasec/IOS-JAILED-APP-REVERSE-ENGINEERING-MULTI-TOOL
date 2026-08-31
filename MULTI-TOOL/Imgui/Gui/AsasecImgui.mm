#import "AsasecImgui.h"

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

void ASASECGuiButton(const char *category,
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

static int gSelectedPage = 0;
static int gPreviousPage = 0;

static BOOL gDraggingMenu = NO;
static BOOL gResizingMenu = NO;
static BOOL gContentDragging = NO;

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

#pragma mark - Button Pulse

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

#pragma mark - Switch Animation

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

#pragma mark - Modern Switch

static bool ASASECModernSwitch(const char *label,
                               bool *value)
{
    if (!label || !value)
        return false;

    ImGui::PushID(label);

    const float switchWidth = 48.0f;
    const float switchHeight = 26.0f;
    const float rowHeight = 54.0f;

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

    ImVec2 itemMin =
        ImGui::GetItemRectMin();

    ImVec2 itemMax =
        ImGui::GetItemRectMax();

    ImDrawList *draw =
        ImGui::GetWindowDrawList();

    ASASECSwitchAnimation *animation =
        ASASECGetSwitchAnimationData(label);

    if (clicked) {

        *value = !(*value);

        if (animation)
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
            itemMin.y + 31.0f
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

    const float height = 46.0f;

    bool pressed =
        ImGui::InvisibleButton(
            "##button",
            ImVec2(
                available,
                height
            )
        );

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

        const float sidebarWidth =
            145.0f;

        float contentStartX =
            gMenuPosition.x +
            sidebarWidth;

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
            (fabsf(moveX) > 7.0f ||
             fabsf(moveY) > 7.0f)) {

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

                /*
                 * Header'ın çok hafif üst parlaklığı.
                 */
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

            #pragma mark Header Logo

            /*
             * ASASEC UI
             *
             * Sol sembol
             *      ↓
             * ASASEC UI
             *      ↓
             * Sağ durum sembolü
             *
             * Her iki modda da görünür.
             *
             * Normal  = yeşil
             * Collapse = kırmızı
             */

            ImDrawList *logoDraw =
                ImGui::GetWindowDrawList();

            ImFont *headerFont =
                ImGui::GetIO().FontDefault;

            if (!headerFont) {

                headerFont =
                    ImGui::GetIO()
                    .Fonts
                    ->Fonts[0];
            }

            const float headerFontSize =
                headerFont
                ? headerFont->LegacySize * 1.13f
                : 17.0f;

            const char *partOne =
                "ASASEC";

            const char *partTwo =
                "UI";

            ImVec2 asececSize =
                ImGui::CalcTextSize(partOne);

            ImVec2 uiSize =
                ImGui::CalcTextSize(partTwo);

            float titleSpacing =
                5.0f;

            float titleWidth =
                (asececSize.x +
                 uiSize.x +
                 titleSpacing) *
                1.13f;

            /*
             * Header grubunun konumu.
             */
            float leftSymbolX =
                windowPos.x + 27.0f;

            float titleStartX =
                leftSymbolX +
                23.0f;

            float rightSymbolX =
                titleStartX +
                titleWidth +
                13.0f;

            /*
             * Dikey merkez.
             */
            float titleY =
                windowPos.y +
                (kHeaderHeight -
                 headerFontSize) *
                0.5f -
                1.0f;

            float symbolY =
                windowPos.y +
                kHeaderHeight * 0.5f;

            /*
             * Sağ sembolün rengi:
             *
             * Normal      -> Yeşil
             * Küçültülmüş -> Kırmızı
             */
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

                /*
                 * Sol mavi sembol glow.
                 */
                logoDraw->AddCircleFilled(
                    ImVec2(
                        leftSymbolX,
                        symbolY
                    ),
                    11.0f,
                    ASASECColor(
                        0.18f,
                        0.55f,
                        1.0f,
                        0.12f
                    ),
                    24
                );

                /*
                 * Sol mavi sembol.
                 */
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

                /*
                 * Sağ durum sembolü glow.
                 */
                logoDraw->AddCircleFilled(
                    ImVec2(
                        rightSymbolX,
                        symbolY
                    ),
                    8.0f,
                    statusGlow,
                    24
                );

                /*
                 * Sağ durum sembolü.
                 */
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

            /*
             * ASASEC UI yazısı.
             *
             * İki sembol arasında.
             * Dikey olarak header merkezinde.
             */
            ImGui::PushFont(headerFont);

            ImGui::SetWindowFontScale(
                1.13f
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

                gDraggingMenu = NO;
                gResizingMenu = NO;
                gContentDragging = NO;
                gContentTouchCandidate = NO;
            }

            ImGui::PopStyleColor(3);
            ImGui::PopStyleVar();
            ImGui::PopID();

            #pragma mark Main Content

            if (!gMenuCollapsed &&
                gMenuVisible) {

                if (draw) {

                    /*
                     * Sidebar.
                     */
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
                            7,
                            12,
                            22,
                            255
                        ),
                        0.0f
                    );

                    /*
                     * Sidebar hafif iç parlaklık.
                     */
                    draw->AddLine(
                        ImVec2(
                            windowPos.x +
                            sidebarWidth -
                            1.0f,
                            windowPos.y +
                            72.0f
                        ),
                        ImVec2(
                            windowPos.x +
                            sidebarWidth -
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
                            7,
                            12,
                            22,
                            255
                        ),
                        17.0f,
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
                            7,
                            12,
                            22,
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
                            68.0f
                        ),
                        ImVec2(
                            windowPos.x +
                            sidebarWidth,
                            windowEnd.y -
                            16.0f
                        ),
                        IM_COL32(
                            34,
                            44,
                            61,
                            220
                        ),
                        1.0f
                    );
                }

                #pragma mark Categories

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
                                sidebarWidth -
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
                                sidebarWidth -
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
                                sidebarWidth -
                                20.0f,
                                43.0f
                            ))) {

                        if (gSelectedPage != i) {

                            gSelectedPage = i;

                            gPageAnimation =
                                0.0f;

                            gPageSlide =
                                16.0f;

                            gPendingContentScrollY =
                                0.0f;

                            gContentScrollVelocity =
                                0.0f;
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

                #pragma mark Content Root

                ImGui::SetCursorPos(
                    ImVec2(
                        sidebarWidth + 1.0f,
                        kHeaderHeight - 2.0f
                    )
                );

                float contentWidth =
                    windowSize.x -
                    sidebarWidth -
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

                    ImGui::SetCursorPos(
                        ImVec2(
                            17.0f,
                            13.0f
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

                    if (draw) {

                        draw->AddLine(
                            ImVec2(
                                windowPos.x +
                                sidebarWidth +
                                16.0f,
                                windowPos.y +
                                53.0f
                            ),
                            ImVec2(
                                windowEnd.x -
                                16.0f,
                                windowPos.y +
                                53.0f
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
                            62.0f
                        )
                    );

                    float scrollHeight =
                        contentHeight -
                        62.0f;

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
                            featureCount *
                            60.0f;

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

            gSelectedPage = 0;
            gPreviousPage = 0;

            gPageAnimation = 1.0f;
            gPageSlide = 0.0f;

            gDraggingMenu = NO;
            gResizingMenu = NO;
            gContentDragging = NO;

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
        }
    );
}
