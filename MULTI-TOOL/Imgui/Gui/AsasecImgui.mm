#import "AsasecImgui.h"

#import <UIKit/UIKit.h>
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import <QuartzCore/QuartzCore.h>
#import <dispatch/dispatch.h>
#import <math.h>
#import <string.h>
#import <stdio.h>

#define IMGUI_DEFINE_MATH_OPERATORS
#include "../imgui.h"
#include "../imgui_internal.h"
#include "../Backends/imgui_impl_metal.h"

#pragma mark - Global State

static MTKView *gImGuiView = nil;
static id<MTLDevice> gMetalDevice = nil;
static id<MTLCommandQueue> gCommandQueue = nil;

static BOOL gInitialized = NO;
static BOOL gStarting = NO;
static BOOL gMetalBackendInitialized = NO;

static ImGuiContext *gImGuiContext = NULL;
static ImGuiContext *gPreviousImGuiContext = NULL;

static BOOL gMenuVisible = YES;
static BOOL gMenuCollapsed = NO;

static ImVec2 gMenuPosition = ImVec2(25.0f, 75.0f);
static ImVec2 gMenuSize = ImVec2(560.0f, 390.0f);

static const float kMenuMinWidth = 430.0f;
static const float kMenuMaxWidth = 760.0f;
static const float kMenuMinHeight = 300.0f;
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

static ImVec2 gDragStartPosition = ImVec2(25.0f, 75.0f);
static ImVec2 gResizeStartSize = ImVec2(560.0f, 390.0f);

static float gPendingContentScrollY = 0.0f;
static float gContentScrollVelocity = 0.0f;

static BOOL gContentHasMoved = NO;
static BOOL gContentTouchCandidate = NO;

static float gPageAnimation = 1.0f;
static float gPageSlide = 0.0f;

#pragma mark - Renderer

@interface ASASECImGuiRenderer : NSObject <MTKViewDelegate>
@end

static ASASECImGuiRenderer *gRenderer = nil;

#pragma mark - Helpers

static float ASASECClampFloat(float value,
                              float minValue,
                              float maxValue)
{
    if (minValue > maxValue)
    {
        float temp = minValue;
        minValue = maxValue;
        maxValue = temp;
    }

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
           (target - current) *
           factor;
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

    for (UIScene *scene in application.connectedScenes)
    {
        if (![scene isKindOfClass:[UIWindowScene class]])
            continue;

        UIWindowScene *windowScene =
            (UIWindowScene *)scene;

        if (windowScene.activationState !=
            UISceneActivationStateForegroundActive)
        {
            continue;
        }

        for (UIWindow *window in windowScene.windows)
        {
            if (!window)
                continue;

            if (window.hidden)
                continue;

            if (window.alpha <= 0.0)
                continue;

            if (window.isKeyWindow)
                return window;
        }
    }

    for (UIScene *scene in application.connectedScenes)
    {
        if (![scene isKindOfClass:[UIWindowScene class]])
            continue;

        UIWindowScene *windowScene =
            (UIWindowScene *)scene;

        if (windowScene.activationState !=
            UISceneActivationStateForegroundActive)
        {
            continue;
        }

        for (UIWindow *window in windowScene.windows)
        {
            if (!window)
                continue;

            if (window.hidden)
                continue;

            if (window.alpha <= 0.0)
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

    CGSize size = window.bounds.size;

    float availableWidth =
        (float)size.width - 16.0f;

    float availableHeight =
        (float)size.height - 16.0f;

    float maxAllowedWidth =
        fmaxf(kMenuMinWidth,
              fminf(kMenuMaxWidth,
                    availableWidth));

    float maxAllowedHeight =
        fmaxf(kMenuMinHeight,
              fminf(kMenuMaxHeight,
                    availableHeight));

    gMenuSize.x =
        ASASECClampFloat(
            gMenuSize.x,
            kMenuMinWidth,
            maxAllowedWidth
        );

    gMenuSize.y =
        ASASECClampFloat(
            gMenuSize.y,
            kMenuMinHeight,
            maxAllowedHeight
        );

    float height =
        gMenuCollapsed
        ? kHeaderHeight
        : gMenuSize.y;

    const float margin = 8.0f;

    float maxX =
        (float)size.width -
        gMenuSize.x -
        margin;

    float maxY =
        (float)size.height -
        height -
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

#pragma mark - Switch Animation

typedef struct
{
    const char *label;
    float progress;
    float pulse;
} ASASECSwitchAnimation;

static ASASECSwitchAnimation gSwitchAnimations[64];
static int gSwitchAnimationCount = 0;

static ASASECSwitchAnimation *
ASASECGetSwitchAnimationData(const char *label)
{
    if (!label)
        return NULL;

    for (int i = 0;
         i < gSwitchAnimationCount;
         i++)
    {
        if (gSwitchAnimations[i].label &&
            strcmp(
                gSwitchAnimations[i].label,
                label
            ) == 0)
        {
            return &gSwitchAnimations[i];
        }
    }

    if (gSwitchAnimationCount >= 64)
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

#pragma mark - Modern Switch

static bool ASASECModernSwitch(const char *label,
                               bool *value)
{
    if (!label || !value)
        return false;

    ImGui::PushID(label);

    const float switchWidth = 48.0f;
    const float switchHeight = 26.0f;
    const float rowHeight = 52.0f;

    float available =
        ImGui::GetContentRegionAvail().x;

    if (available < 200.0f)
        available = 200.0f;

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

    ASASECSwitchAnimation *animationData =
        ASASECGetSwitchAnimationData(label);

    if (clicked)
    {
        *value = !(*value);

        if (animationData)
            animationData->pulse = 1.0f;
    }

    bool hovered =
        ImGui::IsItemHovered();

    float dt =
        ImGui::GetIO().DeltaTime;

    if (dt <= 0.0f || dt > 0.1f)
        dt = 1.0f / 60.0f;

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

    if (animationData)
    {
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

    if (draw)
    {
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

        if (hovered)
        {
            bgR += 0.025f;
            bgG += 0.025f;
            bgB += 0.025f;
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
                0.24f +
                    0.24f * progress,
                0.32f +
                    0.32f * progress,
                0.46f +
                    0.40f * progress,
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

        if (pulse > 0.01f)
        {
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
        *value ? "Enabled" : "Disabled"
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
    if (!gInitialized ||
        !gMenuVisible)
    {
        return NO;
    }

    float height =
        gMenuCollapsed
        ? kHeaderHeight
        : gMenuSize.y;

    return point.x >= gMenuPosition.x &&
           point.x <=
               gMenuPosition.x +
               gMenuSize.x &&
           point.y >= gMenuPosition.y &&
           point.y <=
               gMenuPosition.y +
               height;
}

- (BOOL)pointInsideResizeArea:(CGPoint)point
{
    if (!gInitialized ||
        !gMenuVisible ||
        gMenuCollapsed)
    {
        return NO;
    }

    float right =
        gMenuPosition.x +
        gMenuSize.x;

    float bottom =
        gMenuPosition.y +
        gMenuSize.y;

    return point.x >=
               right - kResizeSize &&
           point.x <= right &&
           point.y >=
               bottom - kResizeSize &&
           point.y <= bottom;
}

- (BOOL)pointInsideHeader:(CGPoint)point
{
    if (!gInitialized ||
        !gMenuVisible)
    {
        return NO;
    }

    return point.x >= gMenuPosition.x &&
           point.x <=
               gMenuPosition.x +
               gMenuSize.x &&
           point.y >= gMenuPosition.y &&
           point.y <=
               gMenuPosition.y +
               kHeaderHeight;
}

- (UIView *)hitTest:(CGPoint)point
          withEvent:(UIEvent *)event
{
    if (!gInitialized ||
        !gMenuVisible)
    {
        return nil;
    }

    if ([self pointInsideMenu:point])
        return self;

    return nil;
}

- (void)updateIOWithTouchEvent:(UIEvent *)event
{
    if (!gInitialized ||
        !gImGuiContext)
    {
        return;
    }

    if (ImGui::GetCurrentContext() !=
        gImGuiContext)
    {
        ImGui::SetCurrentContext(
            gImGuiContext
        );
    }

    ImGuiIO &io =
        ImGui::GetIO();

    UITouch *primaryTouch = nil;

    for (UITouch *touch in event.allTouches)
    {
        if (!touch)
            continue;

        primaryTouch = touch;
        break;
    }

    if (primaryTouch)
    {
        CGPoint point =
            [primaryTouch locationInView:self];

        io.MousePos =
            ImVec2(
                (float)point.x,
                (float)point.y
            );
    }

    BOOL touching = NO;

    for (UITouch *touch in event.allTouches)
    {
        if (!touch)
            continue;

        UITouchPhase phase =
            touch.phase;

        if (phase != UITouchPhaseEnded &&
            phase != UITouchPhaseCancelled)
        {
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

    UITouch *touch =
        touches.anyObject;

    if (touch)
    {
        CGPoint point =
            [touch locationInView:self];

        if ([self pointInsideResizeArea:point])
        {
            gResizingMenu = YES;
            gDraggingMenu = NO;
            gContentDragging = NO;

            gResizeStartPoint =
                point;

            gResizeStartSize =
                gMenuSize;

            gContentTouchCandidate =
                NO;

            gContentHasMoved =
                NO;

            gContentScrollVelocity =
                0.0f;

            [self updateIOWithTouchEvent:event];
            return;
        }

        if ([self pointInsideHeader:point])
        {
            float collapseAreaLeft =
                gMenuPosition.x +
                gMenuSize.x -
                105.0f;

            BOOL inControlArea =
                point.x >=
                    collapseAreaLeft;

            if (!inControlArea)
            {
                gDraggingMenu = YES;
                gResizingMenu = NO;
                gContentDragging = NO;

                gDragStartPoint =
                    point;

                gDragStartPosition =
                    gMenuPosition;

                gContentTouchCandidate =
                    NO;

                gContentHasMoved =
                    NO;

                [self updateIOWithTouchEvent:event];
                return;
            }
        }

        if (!gMenuCollapsed &&
            [self pointInsideMenu:point])
        {
            gContentTouchCandidate = YES;
            gContentHasMoved = NO;
            gContentDragging = NO;

            gContentStartPoint =
                point;

            gContentLastPoint =
                point;

            gContentScrollVelocity =
                0.0f;
        }
    }

    [self updateIOWithTouchEvent:event];
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches
           withEvent:(UIEvent *)event
{
    if (!gInitialized)
        return;

    UITouch *touch =
        touches.anyObject;

    if (touch)
    {
        CGPoint point =
            [touch locationInView:self];

        if (gResizingMenu)
        {
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
                : self.bounds.size;

            float maxWidth =
                (float)screenSize.width -
                gMenuPosition.x -
                8.0f;

            float maxHeight =
                (float)screenSize.height -
                gMenuPosition.y -
                8.0f;

            float widthUpper =
                fminf(
                    kMenuMaxWidth,
                    maxWidth
                );

            float heightUpper =
                fminf(
                    kMenuMaxHeight,
                    maxHeight
                );

            if (widthUpper <
                kMenuMinWidth)
            {
                widthUpper =
                    kMenuMinWidth;
            }

            if (heightUpper <
                kMenuMinHeight)
            {
                heightUpper =
                    kMenuMinHeight;
            }

            gMenuSize.x =
                ASASECClampFloat(
                    gResizeStartSize.x +
                        deltaX,
                    kMenuMinWidth,
                    widthUpper
                );

            gMenuSize.y =
                ASASECClampFloat(
                    gResizeStartSize.y +
                        deltaY,
                    kMenuMinHeight,
                    heightUpper
                );

            [self updateIOWithTouchEvent:event];
            return;
        }

        if (gDraggingMenu)
        {
            float deltaX =
                point.x -
                gDragStartPoint.x;

            float deltaY =
                point.y -
                gDragStartPoint.y;

            gMenuPosition =
                ImVec2(
                    gDragStartPosition.x +
                        deltaX,
                    gDragStartPosition.y +
                        deltaY
                );

            UIWindow *window =
                self.window;

            if (window)
            {
                ASASECClampMenuToScreen(
                    window
                );
            }

            [self updateIOWithTouchEvent:event];
            return;
        }

        if (gContentTouchCandidate)
        {
            float deltaX =
                point.x -
                gContentStartPoint.x;

            float deltaY =
                point.y -
                gContentStartPoint.y;

            if (!gContentHasMoved &&
                (fabsf(deltaX) > 6.0f ||
                 fabsf(deltaY) > 6.0f))
            {
                gContentHasMoved = YES;
                gContentDragging = YES;
            }

            if (gContentDragging)
            {
                float frameDelta =
                    point.y -
                    gContentLastPoint.y;

                gPendingContentScrollY -=
                    frameDelta;

                gContentScrollVelocity =
                    -frameDelta;

                gContentLastPoint =
                    point;
            }
        }
    }

    [self updateIOWithTouchEvent:event];
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches
           withEvent:(UIEvent *)event
{
    if (!gInitialized)
        return;

    if (gContentDragging)
    {
        gContentScrollVelocity =
            ASASECClampFloat(
                gContentScrollVelocity,
                -28.0f,
                28.0f
            );
    }

    gDraggingMenu = NO;
    gResizingMenu = NO;
    gContentDragging = NO;
    gContentTouchCandidate = NO;
    gContentHasMoved = NO;

    [self updateIOWithTouchEvent:event];

    if (gImGuiContext &&
        ImGui::GetCurrentContext() ==
            gImGuiContext)
    {
        ImGui::GetIO().MouseDown[0] =
            false;
    }
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches
               withEvent:(UIEvent *)event
{
    if (!gInitialized)
        return;

    gDraggingMenu = NO;
    gResizingMenu = NO;
    gContentDragging = NO;
    gContentTouchCandidate = NO;
    gContentHasMoved = NO;
    gContentScrollVelocity = 0.0f;

    [self updateIOWithTouchEvent:event];

    if (gImGuiContext &&
        ImGui::GetCurrentContext() ==
            gImGuiContext)
    {
        ImGui::GetIO().MouseDown[0] =
            false;
    }
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

    style.ScrollbarSize = 1.0f;
    style.GrabMinSize = 15.0f;

    style.WindowRounding = 22.0f;
    style.ChildRounding = 14.0f;
    style.FrameRounding = 10.0f;
    style.PopupRounding = 12.0f;
    style.ScrollbarRounding = 8.0f;
    style.GrabRounding = 8.0f;
    style.TabRounding = 10.0f;

    style.WindowBorderSize = 0.0f;
    style.ChildBorderSize = 1.0f;
    style.FrameBorderSize = 0.0f;

    style.IndentSpacing = 20.0f;

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

#pragma mark - Content Components

static void ASASECSectionHeader(const char *title,
                                const char *subtitle,
                                ImU32 accent)
{
    if (!title)
        return;

    ImGui::PushStyleVar(
        ImGuiStyleVar_ItemSpacing,
        ImVec2(5.0f, 4.0f)
    );

    ImGui::TextColored(
        ImGui::ColorConvertU32ToFloat4(accent),
        "%s",
        title
    );

    if (subtitle)
    {
        ImGui::SameLine(
            0.0f,
            7.0f
        );

        ImGui::TextColored(
            ImVec4(
                0.34f,
                0.40f,
                0.49f,
                1.0f
            ),
            "%s",
            subtitle
        );
    }

    ImGui::PopStyleVar();
}

static void ASASECPageDescription(const char *text)
{
    if (!text)
        return;

    ImGui::TextColored(
        ImVec4(
            0.42f,
            0.47f,
            0.56f,
            1.0f
        ),
        "%s",
        text
    );
}

static void ASASECFeatureCard(const char *id,
                              const char *title,
                              const char *description,
                              bool *value)
{
    if (!id ||
        !title ||
        !description ||
        !value)
    {
        return;
    }

    float width =
        ImGui::GetContentRegionAvail().x;

    if (width < 260.0f)
        width = 260.0f;

    const float cardHeight = 68.0f;

    ImGui::PushID(id);

    ImVec2 start =
        ImGui::GetCursorScreenPos();

    ImGui::InvisibleButton(
        "##feature",
        ImVec2(
            width,
            cardHeight
        )
    );

    ImVec2 end =
        ImGui::GetItemRectMax();

    bool hovered =
        ImGui::IsItemHovered();

    bool clicked =
        ImGui::IsItemClicked();

    if (clicked)
        *value = !(*value);

    ImDrawList *draw =
        ImGui::GetWindowDrawList();

    ImU32 bg =
        hovered
        ? ASASECColor(
            0.075f,
            0.105f,
            0.155f,
            0.98f
        )
        : ASASECColor(
            0.045f,
            0.062f,
            0.092f,
            0.98f
        );

    ImU32 border =
        hovered
        ? ASASECColor(
            0.18f,
            0.30f,
            0.46f,
            0.90f
        )
        : ASASECColor(
            0.12f,
            0.17f,
            0.25f,
            0.78f
        );

    if (draw)
    {
        draw->AddRectFilled(
            start,
            end,
            bg,
            12.0f
        );

        draw->AddRect(
            ImVec2(
                start.x + 0.5f,
                start.y + 0.5f
            ),
            ImVec2(
                end.x - 0.5f,
                end.y - 0.5f
            ),
            border,
            12.0f,
            0,
            1.0f
        );

        draw->AddCircleFilled(
            ImVec2(
                start.x + 18.0f,
                start.y + 20.0f
            ),
            4.0f,
            *value
            ? ASASECColor(
                0.30f,
                0.68f,
                1.0f,
                1.0f
            )
            : ASASECColor(
                0.25f,
                0.30f,
                0.38f,
                1.0f
            )
        );
    }

    ImGui::SetCursorScreenPos(
        ImVec2(
            start.x + 31.0f,
            start.y + 9.0f
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
        title
    );

    ImGui::SetCursorScreenPos(
        ImVec2(
            start.x + 31.0f,
            start.y + 31.0f
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
        description
    );

    float switchWidth = 46.0f;
    float switchHeight = 24.0f;

    float sx =
        end.x -
        switchWidth -
        14.0f;

    float sy =
        start.y +
        (cardHeight -
         switchHeight) *
        0.5f;

    ImVec2 sMin =
        ImVec2(
            sx,
            sy
        );

    ImVec2 sMax =
        ImVec2(
            sx + switchWidth,
            sy + switchHeight
        );

    if (draw)
    {
        draw->AddRectFilled(
            sMin,
            sMax,
            *value
            ? ASASECColor(
                0.16f,
                0.48f,
                0.86f,
                1.0f
            )
            : ASASECColor(
                0.12f,
                0.16f,
                0.23f,
                1.0f
            ),
            switchHeight * 0.5f
        );

        float knobX =
            *value
            ? sMax.x - 12.0f
            : sMin.x + 12.0f;

        draw->AddCircleFilled(
            ImVec2(
                knobX,
                sy +
                    switchHeight *
                    0.5f
            ),
            8.0f,
            ASASECColor(
                0.94f,
                0.97f,
                1.0f,
                1.0f
            )
        );
    }

    ImGui::PopID();

    ImGui::SetCursorScreenPos(
        ImVec2(
            start.x,
            end.y + 8.0f
        )
    );
}

#pragma mark - Renderer

@implementation ASASECImGuiRenderer

- (void)mtkView:(MTKView *)view
drawableSizeWillChange:(CGSize)size
{
    if (!gInitialized ||
        !view ||
        !gImGuiContext)
    {
        return;
    }

    if (ImGui::GetCurrentContext() !=
        gImGuiContext)
    {
        ImGui::SetCurrentContext(
            gImGuiContext
        );
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
        !gImGuiContext ||
        !gMetalDevice ||
        !gCommandQueue ||
        !gMetalBackendInitialized)
    {
        return;
    }

    if (ImGui::GetCurrentContext() !=
        gImGuiContext)
    {
        ImGui::SetCurrentContext(
            gImGuiContext
        );
    }

    ImGuiContext *ctx =
        ImGui::GetCurrentContext();

    if (!ctx)
        return;

    MTLRenderPassDescriptor *pass =
        view.currentRenderPassDescriptor;

    if (!pass)
        return;

    id<CAMetalDrawable> drawable =
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
        io.DeltaTime > 0.1f)
    {
        io.DeltaTime =
            1.0f / 60.0f;
    }

    ImGui::NewFrame();

    float dt =
        io.DeltaTime;

    if (dt <= 0.0f ||
        dt > 0.1f)
    {
        dt = 1.0f / 60.0f;
    }

    if (gSelectedPage !=
        gPreviousPage)
    {
        gPreviousPage =
            gSelectedPage;

        gPageAnimation =
            0.0f;

        gPageSlide =
            18.0f;
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
            0.01f)
    {
        gPendingContentScrollY +=
            gContentScrollVelocity;

        gContentScrollVelocity *=
            expf(
                -7.0f * dt
            );

        if (fabsf(gContentScrollVelocity) <
            0.01f)
        {
            gContentScrollVelocity =
                0.0f;
        }
    }

    if (gMenuVisible)
    {
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

        if (windowOpened)
        {
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

            if (draw)
            {
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

            ImFont *defaultFont = NULL;

            if (ImGui::GetIO().Fonts &&
                ImGui::GetIO().Fonts->Fonts.Size >
                    0)
            {
                defaultFont =
                    ImGui::GetIO().Fonts->Fonts[0];
            }

            if (defaultFont)
                ImGui::PushFont(defaultFont);

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

            if (defaultFont)
                ImGui::PopFont();

            #pragma mark Control Panel Title

            if (!gMenuCollapsed)
            {
                float headerTitleX =
                    windowSize.x -
                    230.0f;

                if (headerTitleX > 170.0f)
                {
                    ImGui::SetCursorPos(
                        ImVec2(
                            headerTitleX,
                            19.0f
                        )
                    );

                    ImGui::TextColored(
                        ImVec4(
                            0.35f,
                            0.42f,
                            0.52f,
                            1.0f
                        ),
                        "CONTROL PANEL"
                    );
                }
            }

            #pragma mark Collapse Button

            float collapseButtonX =
                windowSize.x -
                96.0f;

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
                ImGui::IsItemClicked();

            bool collapseHovered =
                ImGui::IsItemHovered();

            ImVec2 arrowMin =
                ImGui::GetItemRectMin();

            ImVec2 arrowMax =
                ImGui::GetItemRectMax();

            ImDrawList *headerDraw =
                ImGui::GetWindowDrawList();

            if (headerDraw)
            {
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

                if (gMenuCollapsed)
                {
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
                }
                else
                {
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

            if (collapsePressed)
            {
                gMenuCollapsed =
                    !gMenuCollapsed;

                gDraggingMenu = NO;
                gResizingMenu = NO;
                gContentDragging = NO;

                gContentScrollVelocity =
                    0.0f;

                gPendingContentScrollY =
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
                50.0f;

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
                ImGui::IsItemClicked();

            bool closeHovered =
                ImGui::IsItemHovered();

            ImVec2 closeMin =
                ImGui::GetItemRectMin();

            ImVec2 closeMax =
                ImGui::GetItemRectMax();

            ImDrawList *closeDraw =
                ImGui::GetWindowDrawList();

            if (closeDraw)
            {
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

            if (closePressed)
            {
                gMenuVisible = NO;
                gMenuCollapsed = NO;

                gDraggingMenu = NO;
                gResizingMenu = NO;
                gContentDragging = NO;

                gContentTouchCandidate = NO;
                gContentHasMoved = NO;

                gContentScrollVelocity =
                    0.0f;

                if (gImGuiView)
                {
                    gImGuiView.userInteractionEnabled =
                        YES;
                }
            }

            ImGui::PopStyleColor(3);
            ImGui::PopStyleVar();
            ImGui::PopID();

            #pragma mark Main Content

            if (!gMenuCollapsed &&
                gMenuVisible)
            {
                if (draw)
                {
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

                #pragma mark Sidebar

                ImGui::SetCursorPos(
                    ImVec2(
                        18.0f,
                        36.0f
                    )
                );

                ImGui::TextColored(
                    ImVec4(
                        0.27f,
                        0.32f,
                        0.40f,
                        1.0f
                    ),
                    "NAVIGATION"
                );

                const char *pages[] =
                {
                    "Combat",
                    "Visuals",
                    "Settings"
                };

                const char *icons[] =
                {
                    "A",
                    "V",
                    "S"
                };

                for (int i = 0; i < 3; i++)
                {
                    bool active =
                        gSelectedPage == i;

                    float itemY =
                        72.0f +
                        i * 54.0f;

                    if (active && draw)
                    {
                        draw->AddRectFilled(
                            ImVec2(
                                windowPos.x + 9.0f,
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

                    char id[64];

                    snprintf(
                        id,
                        sizeof(id),
                        "%s   %s##page_%d",
                        icons[i],
                        pages[i],
                        i
                    );

                    ImGui::SetCursorPos(
                        ImVec2(
                            10.0f,
                            itemY
                        )
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

                    if (ImGui::Button(
                            id,
                            ImVec2(
                                sidebarWidth -
                                    20.0f,
                                43.0f
                            )))
                    {
                        if (gSelectedPage != i)
                        {
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

                if (contentWidth < 100.0f)
                    contentWidth = 100.0f;

                if (contentHeight < 100.0f)
                    contentHeight = 100.0f;

                if (ImGui::BeginChild(
                    "##ContentRoot",
                    ImVec2(
                        contentWidth,
                        contentHeight
                    ),
                    false,
                    ImGuiWindowFlags_NoBackground |
                    ImGuiWindowFlags_NoScrollbar
                ))
                {
                    ImGui::SetCursorPos(
                        ImVec2(
                            17.0f,
                            10.0f
                        )
                    );

                    const char *pageTitle =
                        gSelectedPage == 0
                        ? "Combat"
                        : gSelectedPage == 1
                        ? "Visuals"
                        : "Settings";

                    ImGui::TextColored(
                        ImVec4(
                            0.94f,
                            0.97f,
                            1.0f,
                            1.0f
                        ),
                        "%s",
                        pageTitle
                    );

                    ImGui::SameLine(
                        0.0f,
                        7.0f
                    );

                    ImGui::TextColored(
                        ImVec4(
                            0.30f,
                            0.36f,
                            0.45f,
                            1.0f
                        ),
                        "/ ASASEC"
                    );

                    if (draw)
                    {
                        draw->AddLine(
                            ImVec2(
                                windowPos.x +
                                    sidebarWidth +
                                    16.0f,
                                windowPos.y +
                                    51.0f
                            ),
                            ImVec2(
                                windowEnd.x -
                                    16.0f,
                                windowPos.y +
                                    51.0f
                            ),
                            IM_COL32(
                                32,
                                41,
                                56,
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

                    if (ImGui::BeginChild(
                        "##ScrollableContent",
                        ImVec2(
                            contentWidth,
                            scrollHeight
                        ),
                        false,
                        ImGuiWindowFlags_NoScrollbar
                    ))
                    {
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

                        #pragma mark Combat

                        if (gSelectedPage == 0)
                        {
                            ASASECSectionHeader(
                                "COMBAT",
                                "ACTIONS",
                                ASASECColor(
                                    0.30f,
                                    0.68f,
                                    1.0f,
                                    1.0f
                                )
                            );

                            ASASECPageDescription(
                                "Configure your combat options"
                            );

                            ImGui::Dummy(
                                ImVec2(
                                    0.0f,
                                    10.0f
                                )
                            );

                            static bool sw1 = false;
                            static bool sw2 = false;
                            static bool sw3 = false;
                            static bool sw4 = false;

                            float cardWidth =
                                ImGui::GetContentRegionAvail().x -
                                22.0f;

                            if (cardWidth < 280.0f)
                                cardWidth = 280.0f;

                            if (ImGui::BeginChild(
                                "##CombatCard",
                                ImVec2(
                                    cardWidth,
                                    294.0f
                                ),
                                false,
                                ImGuiWindowFlags_NoBackground
                            ))
                            {
                                ASASECFeatureCard(
                                    "aimbot",
                                    "swicht 1",
                                    "Automatic target assistance",
                                    &sw1
                                );

                                ASASECFeatureCard(
                                    "silent",
                                    "swicht 2",
                                    "Hidden targeting correction",
                                    &sw2
                                );

                                ASASECFeatureCard(
                                    "recoil",
                                    "swicht 3",
                                    "Reduce weapon recoil",
                                    &sw3
                                );

                                ASASECFeatureCard(
                                    "rapid",
                                    "swicht 4",
                                    "Increase firing response",
                                    &sw4
                                );
                            }

                            ImGui::EndChild();
                        }

                        #pragma mark Visuals

                        else if (gSelectedPage == 1)
                        {
                            ASASECSectionHeader(
                                "VISUALS",
                                "ESP",
                                ASASECColor(
                                    0.28f,
                                    0.86f,
                                    0.58f,
                                    1.0f
                                )
                            );

                            ASASECPageDescription(
                                "Configure visual and player information"
                            );

                            ImGui::Dummy(
                                ImVec2(
                                    0.0f,
                                    10.0f
                                )
                            );

                            static bool sw1 = false;
                            static bool sw2 = false;
                            static bool sw3 = false;
                            static bool sw4 = false;

                            float cardWidth =
                                ImGui::GetContentRegionAvail().x -
                                22.0f;

                            if (cardWidth < 280.0f)
                                cardWidth = 280.0f;

                            if (ImGui::BeginChild(
                                "##VisualCard",
                                ImVec2(
                                    cardWidth,
                                    294.0f
                                ),
                                false,
                                ImGuiWindowFlags_NoBackground
                            ))
                            {
                                ASASECFeatureCard(
                                    "player",
                                    "swicht 1",
                                    "Display nearby players",
                                    &sw1
                                );

                                ASASECFeatureCard(
                                    "box",
                                    "swicht 2",
                                    "Draw player bounding boxes",
                                    &sw2
                                );

                                ASASECFeatureCard(
                                    "distance",
                                    "swicht 3",
                                    "Show player distance",
                                    &sw3
                                );

                                ASASECFeatureCard(
                                    "skeleton",
                                    "swicht 4",
                                    "Display player skeleton",
                                    &sw4
                                );
                            }

                            ImGui::EndChild();
                        }

                        #pragma mark Settings

                        else
                        {
                            ASASECSectionHeader(
                                "SETTINGS",
                                "SYSTEM",
                                ASASECColor(
                                    1.0f,
                                    0.67f,
                                    0.28f,
                                    1.0f
                                )
                            );

                            ASASECPageDescription(
                                "Configure ASASEC interface and system"
                            );

                            ImGui::Dummy(
                                ImVec2(
                                    0.0f,
                                    10.0f
                                )
                            );

                            static bool sw1 = false;
                            static bool sw2 = false;
                            static bool sw3 = false;
                            static bool sw4 = false;

                            float cardWidth =
                                ImGui::GetContentRegionAvail().x -
                                22.0f;

                            if (cardWidth < 280.0f)
                                cardWidth = 280.0f;

                            if (ImGui::BeginChild(
                                "##SettingsCard",
                                ImVec2(
                                    cardWidth,
                                    294.0f
                                ),
                                false,
                                ImGuiWindowFlags_NoBackground
                            ))
                            {
                                ASASECFeatureCard(
                                    "save",
                                    "swicht 1",
                                    "Keep your interface settings",
                                    &sw1
                                );

                                ASASECFeatureCard(
                                    "theme",
                                    "swicht 2",
                                    "Use the ASASEC dark interface",
                                    &sw2
                                );

                                ASASECFeatureCard(
                                    "vibration",
                                    "swicht 3",
                                    "Enable touch feedback",
                                    &sw3
                                );

                                ASASECFeatureCard(
                                    "developer",
                                    "swicht 4",
                                    "Enable developer options",
                                    &sw4
                                );
                            }

                            ImGui::EndChild();
                        }

                        ImGui::PopStyleVar();

                        if (fabsf(gPendingContentScrollY) >
                            0.001f)
                        {
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
                windowSize.y > 220.0f)
            {
                ImDrawList *foreground =
                    ImGui::GetForegroundDrawList();

                if (foreground)
                {
                    float iconRight =
                        windowEnd.x - 9.0f;

                    float iconBottom =
                        windowEnd.y - 9.0f;

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

    if (!drawData)
    {
        [commandBuffer commit];
        return;
    }

    id<MTLRenderCommandEncoder> encoder =
        [commandBuffer
            renderCommandEncoderWithDescriptor:pass];

    if (!encoder)
    {
        [commandBuffer commit];
        return;
    }

    [encoder setViewport:(MTLViewport){
        0.0,
        0.0,
        (double)view.drawableSize.width,
        (double)view.drawableSize.height,
        0.0,
        1.0
    }];

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

#pragma mark - Start / Stop

void ASASECImGuiStart(void)
{
    dispatch_async(
        dispatch_get_main_queue(),
        ^{
            if (gInitialized ||
                gStarting)
            {
                return;
            }

            gStarting = YES;

            UIWindow *window =
                ASASECFindActiveWindow();

            if (!window)
            {
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

            if (!device)
            {
                gStarting = NO;
                return;
            }

            id<MTLCommandQueue> queue =
                [device newCommandQueue];

            if (!queue)
            {
                gStarting = NO;
                return;
            }

            /*
             * Mevcut context'i ASLA körlemesine
             * Destroy/Shutdown etmiyoruz.
             *
             * Bu, önceki sürümdeki en riskli
             * lifecycle noktalarından biriydi.
             */
            gPreviousImGuiContext =
                ImGui::GetCurrentContext();

            gImGuiContext = NULL;
            gMetalBackendInitialized = NO;

            /*
             * Yeni context oluştur.
             */
            ImGuiContext *ctx =
                ImGui::CreateContext();

            if (!ctx)
            {
                gStarting = NO;
                return;
            }

            gImGuiContext =
                ctx;

            ImGui::SetCurrentContext(
                gImGuiContext
            );

            ImGuiIO &io =
                ImGui::GetIO();

            io.IniFilename = NULL;
            io.LogFilename = NULL;

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

            /*
             * Touch/mouse input.
             */
            io.MousePos =
                ImVec2(
                    -FLT_MAX,
                    -FLT_MAX
                );

            io.MouseDown[0] =
                false;

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

            gContentTouchCandidate = NO;
            gContentHasMoved = NO;

            gPendingContentScrollY =
                0.0f;

            gContentScrollVelocity =
                0.0f;

            /*
             * View'i başlangıçta PAUSED oluşturuyoruz.
             *
             * Böylece view daha global state hazır
             * olmadan drawInMTKView çağırıp crash
             * oluşturamaz.
             */
            CGRect frame =
                window.bounds;

            ASASECImGuiView *view =
                [[ASASECImGuiView alloc]
                    initWithFrame:frame
                    device:device];

            if (!view)
            {
                ImGui::SetCurrentContext(
                    gPreviousImGuiContext
                );

                ImGui::DestroyContext(
                    gImGuiContext
                );

                gImGuiContext = NULL;
                gStarting = NO;

                return;
            }

            view.backgroundColor =
                UIColor.clearColor;

            view.opaque = NO;

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

            /*
             * Kritik:
             * Önce paused YES.
             */
            view.paused = YES;

            view.multipleTouchEnabled =
                YES;

            view.userInteractionEnabled =
                YES;

            ASASECImGuiRenderer *renderer =
                [[ASASECImGuiRenderer alloc]
                    init];

            if (!renderer)
            {
                [view removeFromSuperview];

                ImGui::SetCurrentContext(
                    gPreviousImGuiContext
                );

                ImGui::DestroyContext(
                    gImGuiContext
                );

                gImGuiContext = NULL;
                gStarting = NO;

                return;
            }

            /*
             * Backend initialize.
             */
            BOOL metalInit =
                ImGui_ImplMetal_Init(
                    device
                );

            if (!metalInit)
            {
                view.delegate = nil;

                [view removeFromSuperview];

                ImGui::SetCurrentContext(
                    gPreviousImGuiContext
                );

                ImGui::DestroyContext(
                    gImGuiContext
                );

                gImGuiContext = NULL;
                gMetalBackendInitialized = NO;
                gStarting = NO;

                return;
            }

            gMetalBackendInitialized =
                YES;

            gMetalDevice =
                device;

            gCommandQueue =
                queue;

            gImGuiView =
                view;

            gRenderer =
                renderer;

            /*
             * Delegate hazır.
             */
            view.delegate =
                renderer;

            /*
             * View'i önce ekliyoruz ama hâlâ paused.
             */
            [window addSubview:view];

            [window bringSubviewToFront:view];

            /*
             * Frame ve menu sınırlarını kesinleştir.
             */
            view.frame =
                window.bounds;

            [view setNeedsLayout];
            [view layoutIfNeeded];

            ASASECClampMenuToScreen(
                window
            );

            /*
             * Artık bütün global state hazır.
             *
             * En son initialized.
             */
            gInitialized = YES;
            gStarting = NO;

            /*
             * İlk frame güvenli şekilde hazırlandıktan
             * sonra render başlasın.
             */
            view.paused = NO;
        }
    );
}

void ASASECImGuiStop(void)
{
    dispatch_async(
        dispatch_get_main_queue(),
        ^{
            if (!gInitialized &&
                !gStarting)
            {
                return;
            }

            /*
             * İlk olarak render'ın yeni frame
             * üretmesini engelle.
             */
            gInitialized = NO;
            gStarting = NO;

            ASASECImGuiView *view =
                gImGuiView;

            /*
             * Delegate'i kaldır ve view'i pause et.
             */
            if (view)
            {
                view.paused = YES;
                view.delegate = nil;
                view.userInteractionEnabled = NO;

                [view removeFromSuperview];
            }

            gImGuiView = nil;

            /*
             * Backend shutdown sadece initialize
             * edilmişse çağrılıyor.
             */
            if (gMetalBackendInitialized)
            {
                if (gImGuiContext)
                {
                    ImGui::SetCurrentContext(
                        gImGuiContext
                    );
                }

                ImGui_ImplMetal_Shutdown();

                gMetalBackendInitialized =
                    NO;
            }

            /*
             * Sadece bizim oluşturduğumuz context'i
             * destroy et.
             */
            if (gImGuiContext)
            {
                if (ImGui::GetCurrentContext() ==
                    gImGuiContext)
                {
                    ImGui::SetCurrentContext(
                        gImGuiContext
                    );
                }

                ImGui::DestroyContext(
                    gImGuiContext
                );

                gImGuiContext = NULL;
            }

            /*
             * Daha önce var olan context'i geri koy.
             */
            if (gPreviousImGuiContext)
            {
                ImGui::SetCurrentContext(
                    gPreviousImGuiContext
                );
            }
            else
            {
                ImGui::SetCurrentContext(
                    NULL
                );
            }

            gPreviousImGuiContext =
                NULL;

            gRenderer = nil;

            gCommandQueue = nil;
            gMetalDevice = nil;

            gSwitchAnimationCount =
                0;

            memset(
                gSwitchAnimations,
                0,
                sizeof(gSwitchAnimations)
            );

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
