#import "AsasecImgui.h"

#import <UIKit/UIKit.h>
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import <QuartzCore/QuartzCore.h>
#import <dispatch/dispatch.h>
#import <math.h>

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

static BOOL gMenuVisible = YES;
static BOOL gMenuCollapsed = NO;

static ImVec2 gMenuPosition = ImVec2(25.0f, 75.0f);
static ImVec2 gMenuSize = ImVec2(560.0f, 390.0f);

static const float kMenuMinWidth = 430.0f;
static const float kMenuMaxWidth = 760.0f;
static const float kMenuMinHeight = 300.0f;
static const float kMenuMaxHeight = 620.0f;

static const float kHeaderHeight = 54.0f;
static const float kResizeSize = 48.0f;

static int gSelectedPage = 0;

static BOOL gDraggingMenu = NO;
static BOOL gResizingMenu = NO;
static BOOL gScrollingContent = NO;

static CGPoint gDragStartPoint = CGPointZero;
static CGPoint gResizeStartPoint = CGPointZero;
static CGPoint gScrollStartPoint = CGPointZero;

static ImVec2 gDragStartPosition = ImVec2(25.0f, 75.0f);
static ImVec2 gResizeStartSize = ImVec2(560.0f, 390.0f);

static ImRect gContentTouchRect = ImRect(
    ImVec2(0.0f, 0.0f),
    ImVec2(0.0f, 0.0f)
);

static float gCollapseAnimation = 0.0f;
static float gAnimatedHeight = 390.0f;

#pragma mark - Renderer

@interface ASASECImGuiRenderer : NSObject <MTKViewDelegate>
@end

static ASASECImGuiRenderer *gRenderer = nil;

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

static float ASASECEase(float value)
{
    value = ASASECClampFloat(value, 0.0f, 1.0f);

    return value * value * (3.0f - 2.0f * value);
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

static float ASASECCurrentMenuHeight(void)
{
    if (gMenuCollapsed)
        return gAnimatedHeight;

    return gAnimatedHeight;
}

static void ASASECClampMenuToScreen(UIWindow *window)
{
    if (!window)
        return;

    CGSize size =
        window.bounds.size;

    float width =
        gMenuSize.x;

    float height =
        ASASECCurrentMenuHeight();

    const float margin = 8.0f;

    float maxX =
        (float)size.width -
        width -
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

#pragma mark - Modern Switch

static bool ASASECModernSwitch(const char *label,
                               bool *value)
{
    if (!label || !value)
        return false;

    ImGui::PushID(label);

    const float switchWidth = 48.0f;
    const float switchHeight = 27.0f;
    const float rowHeight = 40.0f;

    float available =
        ImGui::GetContentRegionAvail().x;

    if (available < 180.0f)
        available = 180.0f;

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

    if (!draw)
    {
        ImGui::PopID();
        return clicked;
    }

    if (clicked)
        *value = !(*value);

    bool hovered =
        ImGui::IsItemHovered();

    float switchX =
        itemMax.x -
        switchWidth -
        4.0f;

    float switchY =
        itemMin.y +
        (rowHeight - switchHeight) *
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

    ImU32 background;

    if (*value)
    {
        background =
            ASASECColor(
                hovered ? 0.24f : 0.18f,
                hovered ? 0.62f : 0.52f,
                1.0f,
                1.0f
            );
    }
    else
    {
        background =
            ASASECColor(
                hovered ? 0.15f : 0.09f,
                hovered ? 0.19f : 0.13f,
                hovered ? 0.27f : 0.19f,
                1.0f
            );
    }

    draw->AddRectFilled(
        switchMin,
        switchMax,
        background,
        switchHeight * 0.5f
    );

    draw->AddRect(
        ImVec2(
            switchMin.x + 0.5f,
            switchMin.y + 0.5f
        ),
        ImVec2(
            switchMax.x - 0.5f,
            switchMax.y - 0.5f
        ),
        *value
        ? ASASECColor(
            0.45f,
            0.75f,
            1.0f,
            0.75f
        )
        : ASASECColor(
            0.22f,
            0.27f,
            0.36f,
            0.90f
        ),
        switchHeight * 0.5f,
        0,
        1.0f
    );

    float knobRadius = 9.0f;

    float knobX =
        *value
        ? switchMax.x - 14.0f
        : switchMin.x + 14.0f;

    float knobY =
        switchMin.y +
        switchHeight * 0.5f;

    draw->AddCircleFilled(
        ImVec2(knobX, knobY),
        knobRadius + 1.0f,
        ASASECColor(
            0.0f,
            0.0f,
            0.0f,
            0.18f
        )
    );

    draw->AddCircleFilled(
        ImVec2(knobX, knobY),
        knobRadius,
        ASASECColor(
            0.94f,
            0.97f,
            1.0f,
            1.0f
        )
    );

    ImGui::SetCursorScreenPos(
        ImVec2(
            itemMin.x,
            itemMin.y + 8.0f
        )
    );

    ImGui::TextColored(
        ImVec4(
            0.88f,
            0.92f,
            0.98f,
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

#pragma mark - Hit Testing

- (BOOL)pointInsideMenu:(CGPoint)point
{
    if (!gMenuVisible)
        return NO;

    float height =
        ASASECCurrentMenuHeight();

    return
        point.x >= gMenuPosition.x &&
        point.x <= gMenuPosition.x + gMenuSize.x &&
        point.y >= gMenuPosition.y &&
        point.y <= gMenuPosition.y + height;
}

- (BOOL)pointInsideResizeHandle:(CGPoint)point
{
    if (!gMenuVisible)
        return NO;

    if (gMenuCollapsed)
        return NO;

    float right =
        gMenuPosition.x +
        gMenuSize.x;

    float bottom =
        gMenuPosition.y +
        gMenuSize.y;

    return
        point.x >= right - kResizeSize &&
        point.x <= right + 8.0f &&
        point.y >= bottom - kResizeSize &&
        point.y <= bottom + 8.0f;
}

- (BOOL)pointInsideDragHeader:(CGPoint)point
{
    if (!gMenuVisible)
        return NO;

    return
        point.x >= gMenuPosition.x &&
        point.x <= gMenuPosition.x + gMenuSize.x &&
        point.y >= gMenuPosition.y &&
        point.y <= gMenuPosition.y + kHeaderHeight;
}

- (BOOL)pointInsideContent:(CGPoint)point
{
    if (!gMenuVisible)
        return NO;

    return
        point.x >= gContentTouchRect.Min.x &&
        point.x <= gContentTouchRect.Max.x &&
        point.y >= gContentTouchRect.Min.y &&
        point.y <= gContentTouchRect.Max.y;
}

- (UIView *)hitTest:(CGPoint)point
          withEvent:(UIEvent *)event
{
    if (!gInitialized)
        return nil;

    if (!gMenuVisible)
        return nil;

    if ([self pointInsideMenu:point])
        return self;

    return nil;
}

#pragma mark - Drag

- (void)beginMenuDragAtPoint:(CGPoint)point
{
    if (!gMenuVisible)
        return;

    gDraggingMenu = YES;
    gResizingMenu = NO;
    gScrollingContent = NO;

    gDragStartPoint = point;
    gDragStartPosition = gMenuPosition;
}

- (void)updateMenuDragAtPoint:(CGPoint)point
{
    if (!gDraggingMenu)
        return;

    CGFloat dx =
        point.x -
        gDragStartPoint.x;

    CGFloat dy =
        point.y -
        gDragStartPoint.y;

    gMenuPosition.x =
        gDragStartPosition.x +
        (float)dx;

    gMenuPosition.y =
        gDragStartPosition.y +
        (float)dy;

    [self clampMenuPosition];
}

#pragma mark - Resize

- (void)beginMenuResizeAtPoint:(CGPoint)point
{
    if (!gMenuVisible)
        return;

    if (gMenuCollapsed)
        return;

    gResizingMenu = YES;
    gDraggingMenu = NO;
    gScrollingContent = NO;

    gResizeStartPoint = point;
    gResizeStartSize = gMenuSize;
}

- (void)updateMenuResizeAtPoint:(CGPoint)point
{
    if (!gResizingMenu)
        return;

    CGFloat dx =
        point.x -
        gResizeStartPoint.x;

    CGFloat dy =
        point.y -
        gResizeStartPoint.y;

    float newWidth =
        gResizeStartSize.x +
        (float)dx;

    float newHeight =
        gResizeStartSize.y +
        (float)dy;

    newWidth =
        ASASECClampFloat(
            newWidth,
            kMenuMinWidth,
            kMenuMaxWidth
        );

    newHeight =
        ASASECClampFloat(
            newHeight,
            kMenuMinHeight,
            kMenuMaxHeight
        );

    UIWindow *window =
        self.window;

    if (window)
    {
        CGSize screenSize =
            window.bounds.size;

        float availableWidth =
            (float)screenSize.width -
            gMenuPosition.x -
            8.0f;

        float availableHeight =
            (float)screenSize.height -
            gMenuPosition.y -
            8.0f;

        if (availableWidth >= kMenuMinWidth)
        {
            newWidth =
                MIN(
                    newWidth,
                    availableWidth
                );
        }

        if (availableHeight >= kMenuMinHeight)
        {
            newHeight =
                MIN(
                    newHeight,
                    availableHeight
                );
        }
    }

    gMenuSize.x = newWidth;
    gMenuSize.y = newHeight;
}

#pragma mark - Content Touch Scroll

- (void)beginContentScrollAtPoint:(CGPoint)point
{
    if (![self pointInsideContent:point])
        return;

    gScrollingContent = YES;
    gDraggingMenu = NO;
    gResizingMenu = NO;

    gScrollStartPoint = point;
}

- (void)updateContentScrollAtPoint:(CGPoint)point
{
    if (!gScrollingContent)
        return;

    if (!ImGui::GetCurrentContext())
        return;

    CGFloat dy =
        point.y -
        gScrollStartPoint.y;

    gScrollStartPoint = point;

    if (fabs(dy) < 0.25)
        return;

    ImGuiIO &io =
        ImGui::GetIO();

    io.MouseWheel =
        (float)(-dy * 0.045f);
}

- (void)endMenuInteraction
{
    gDraggingMenu = NO;
    gResizingMenu = NO;
    gScrollingContent = NO;
}

- (void)clampMenuPosition
{
    UIWindow *window =
        self.window;

    if (!window)
        return;

    ASASECClampMenuToScreen(window);
}

#pragma mark - Touch -> ImGui

- (void)updateIOWithTouchEvent:(UIEvent *)event
{
    if (!gInitialized)
        return;

    if (!ImGui::GetCurrentContext())
        return;

    ImGuiIO &io =
        ImGui::GetIO();

    UITouch *touch =
        event.allTouches.anyObject;

    if (touch)
    {
        CGPoint point =
            [touch locationInView:self];

        io.MousePos =
            ImVec2(
                (float)point.x,
                (float)point.y
            );
    }

    BOOL touching = NO;

    for (UITouch *currentTouch
         in event.allTouches)
    {
        if (!currentTouch)
            continue;

        if (currentTouch.phase != UITouchPhaseEnded &&
            currentTouch.phase != UITouchPhaseCancelled)
        {
            touching = YES;
            break;
        }
    }

    io.MouseDown[0] =
        touching;
}

#pragma mark - Touches

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

        if ([self pointInsideResizeHandle:point])
        {
            [self beginMenuResizeAtPoint:point];
        }
        else if ([self pointInsideDragHeader:point])
        {
            [self beginMenuDragAtPoint:point];
        }
        else if ([self pointInsideContent:point])
        {
            [self beginContentScrollAtPoint:point];
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
            [self updateMenuResizeAtPoint:point];
        }
        else if (gDraggingMenu)
        {
            [self updateMenuDragAtPoint:point];
        }
        else if (gScrollingContent)
        {
            [self updateContentScrollAtPoint:point];
        }
    }

    [self updateIOWithTouchEvent:event];
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches
           withEvent:(UIEvent *)event
{
    [self endMenuInteraction];

    if (!gInitialized)
        return;

    [self updateIOWithTouchEvent:event];

    if (ImGui::GetCurrentContext())
    {
        ImGuiIO &io =
            ImGui::GetIO();

        io.MouseDown[0] = false;
        io.MouseWheel = 0.0f;
    }
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches
               withEvent:(UIEvent *)event
{
    [self endMenuInteraction];

    if (!gInitialized)
        return;

    [self updateIOWithTouchEvent:event];

    if (ImGui::GetCurrentContext())
    {
        ImGuiIO &io =
            ImGui::GetIO();

        io.MouseDown[0] = false;
        io.MouseWheel = 0.0f;
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
        ImVec2(9.0f, 9.0f);

    style.ItemInnerSpacing =
        ImVec2(7.0f, 6.0f);

    style.ScrollbarSize = 7.0f;
    style.GrabMinSize = 15.0f;

    style.WindowRounding = 20.0f;
    style.ChildRounding = 14.0f;
    style.FrameRounding = 9.0f;
    style.PopupRounding = 11.0f;
    style.ScrollbarRounding = 8.0f;
    style.GrabRounding = 8.0f;
    style.TabRounding = 9.0f;

    style.WindowBorderSize = 0.0f;
    style.ChildBorderSize = 1.0f;
    style.FrameBorderSize = 0.0f;

    style.IndentSpacing = 20.0f;

    ImVec4 *c =
        style.Colors;

    c[ImGuiCol_Text] =
        ImVec4(0.93f, 0.96f, 1.0f, 1.0f);

    c[ImGuiCol_TextDisabled] =
        ImVec4(0.40f, 0.45f, 0.54f, 1.0f);

    c[ImGuiCol_WindowBg] =
        ImVec4(0.018f, 0.024f, 0.038f, 0.985f);

    c[ImGuiCol_ChildBg] =
        ImVec4(0.040f, 0.052f, 0.074f, 0.98f);

    c[ImGuiCol_Border] =
        ImVec4(0.13f, 0.17f, 0.24f, 0.75f);

    c[ImGuiCol_FrameBg] =
        ImVec4(0.060f, 0.076f, 0.108f, 1.0f);

    c[ImGuiCol_FrameBgHovered] =
        ImVec4(0.095f, 0.125f, 0.18f, 1.0f);

    c[ImGuiCol_FrameBgActive] =
        ImVec4(0.12f, 0.18f, 0.27f, 1.0f);

    c[ImGuiCol_Button] =
        ImVec4(0.060f, 0.080f, 0.12f, 1.0f);

    c[ImGuiCol_ButtonHovered] =
        ImVec4(0.105f, 0.15f, 0.23f, 1.0f);

    c[ImGuiCol_ButtonActive] =
        ImVec4(0.14f, 0.24f, 0.39f, 1.0f);

    c[ImGuiCol_CheckMark] =
        ImVec4(0.30f, 0.68f, 1.0f, 1.0f);

    c[ImGuiCol_SliderGrab] =
        ImVec4(0.22f, 0.56f, 1.0f, 1.0f);

    c[ImGuiCol_SliderGrabActive] =
        ImVec4(0.38f, 0.70f, 1.0f, 1.0f);

    c[ImGuiCol_Header] =
        ImVec4(0.10f, 0.17f, 0.27f, 1.0f);

    c[ImGuiCol_HeaderHovered] =
        ImVec4(0.14f, 0.23f, 0.36f, 1.0f);

    c[ImGuiCol_HeaderActive] =
        ImVec4(0.17f, 0.30f, 0.47f, 1.0f);

    c[ImGuiCol_Separator] =
        ImVec4(0.13f, 0.17f, 0.23f, 0.80f);

    c[ImGuiCol_ScrollbarBg] =
        ImVec4(0.020f, 0.027f, 0.042f, 0.15f);

    c[ImGuiCol_ScrollbarGrab] =
        ImVec4(0.17f, 0.23f, 0.33f, 0.25f);

    c[ImGuiCol_ScrollbarGrabHovered] =
        ImVec4(0.23f, 0.32f, 0.46f, 0.40f);

    c[ImGuiCol_ScrollbarGrabActive] =
        ImVec4(0.28f, 0.42f, 0.60f, 0.50f);
}

#pragma mark - Renderer

@implementation ASASECImGuiRenderer

- (void)mtkView:(MTKView *)view
drawableSizeWillChange:(CGSize)size
{
    if (!gInitialized)
        return;

    if (!view)
        return;

    if (!ImGui::GetCurrentContext())
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
}

- (void)drawInMTKView:(MTKView *)view
{
    if (!gInitialized)
        return;

    if (!view)
        return;

    if (!gMetalDevice)
        return;

    if (!gCommandQueue)
        return;

    if (!ImGui::GetCurrentContext())
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

    /*
     * Smooth collapse animation.
     */
    const float targetAnimation =
        gMenuCollapsed
        ? 1.0f
        : 0.0f;

    float animationSpeed =
        io.DeltaTime * 9.0f;

    if (animationSpeed > 1.0f)
        animationSpeed = 1.0f;

    gCollapseAnimation +=
        (targetAnimation - gCollapseAnimation) *
        animationSpeed;

    float eased =
        ASASECEase(gCollapseAnimation);

    gAnimatedHeight =
        gMenuSize.y +
        (kHeaderHeight - gMenuSize.y) *
        eased;

    if (fabs(gAnimatedHeight - kHeaderHeight) < 0.5f &&
        gMenuCollapsed)
    {
        gAnimatedHeight = kHeaderHeight;
    }

    if (fabs(gAnimatedHeight - gMenuSize.y) < 0.5f &&
        !gMenuCollapsed)
    {
        gAnimatedHeight = gMenuSize.y;
    }

    ASASECClampMenuToScreen(view.window);

    ImGui::NewFrame();

    if (gMenuVisible)
    {
        const float sidebarWidth = 145.0f;

        ImGui::SetNextWindowPos(
            gMenuPosition,
            ImGuiCond_Always
        );

        ImGui::SetNextWindowSize(
            ImVec2(
                gMenuSize.x,
                gAnimatedHeight
            ),
            ImGuiCond_Always
        );

        ImGuiWindowFlags flags =
            ImGuiWindowFlags_NoTitleBar |
            ImGuiWindowFlags_NoResize |
            ImGuiWindowFlags_NoCollapse |
            ImGuiWindowFlags_NoSavedSettings;

        ImGui::PushStyleVar(
            ImGuiStyleVar_WindowPadding,
            ImVec2(0.0f, 0.0f)
        );

        ImGui::PushStyleVar(
            ImGuiStyleVar_WindowRounding,
            20.0f
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

        bool began =
            ImGui::Begin(
                "##ASASEC_WINDOW",
                NULL,
                flags
            );

        if (began)
        {
            ImVec2 windowPos =
                ImGui::GetWindowPos();

            ImVec2 windowSize =
                ImGui::GetWindowSize();

            ImVec2 windowEnd =
                ImVec2(
                    windowPos.x + windowSize.x,
                    windowPos.y + windowSize.y
                );

            ImDrawList *draw =
                ImGui::GetWindowDrawList();

            if (draw)
            {
                draw->AddRectFilled(
                    windowPos,
                    windowEnd,
                    IM_COL32(6, 9, 16, 252),
                    20.0f
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
                    IM_COL32(42, 53, 73, 190),
                    20.0f,
                    0,
                    1.0f
                );

                /*
                 * Subtle header glow.
                 */
                float glowAlpha =
                    0.08f +
                    0.04f *
                    sinf((float)ImGui::GetTime() * 2.0f);

                draw->AddRectFilled(
                    ImVec2(
                        windowPos.x + 1.0f,
                        windowPos.y + 1.0f
                    ),
                    ImVec2(
                        windowEnd.x - 1.0f,
                        windowPos.y + kHeaderHeight
                    ),
                    ASASECColor(
                        0.08f,
                        0.30f,
                        0.58f,
                        glowAlpha
                    ),
                    19.0f,
                    ImDrawFlags_RoundCornersTop
                );
            }

            /*
             * Header
             */
            ImGui::SetCursorPos(
                ImVec2(18.0f, 9.0f)
            );

            ImGui::TextColored(
                ImVec4(
                    0.30f,
                    0.68f,
                    1.0f,
                    1.0f
                ),
                "◉"
            );

            ImGui::SameLine(
                0.0f,
                7.0f
            );

            ImGui::TextColored(
                ImVec4(
                    0.93f,
                    0.96f,
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
                    0.38f,
                    0.44f,
                    0.53f,
                    1.0f
                ),
                "UI"
            );

            /*
             * Header drag indicator.
             */
            ImGui::SameLine(
                0.0f,
                12.0f
            );

            ImGui::TextColored(
                ImVec4(
                    0.27f,
                    0.32f,
                    0.40f,
                    1.0f
                ),
                "•••"
            );

            /*
             * Header collapse button.
             */
            float collapseButtonX =
                windowSize.x - 108.0f;

            ImGui::SetCursorPos(
                ImVec2(
                    collapseButtonX,
                    10.0f
                )
            );

            ImGui::PushStyleVar(
                ImGuiStyleVar_FrameRounding,
                10.0f
            );

            ImGui::PushStyleColor(
                ImGuiCol_Button,
                ImVec4(
                    0.065f,
                    0.095f,
                    0.15f,
                    1.0f
                )
            );

            ImGui::PushStyleColor(
                ImGuiCol_ButtonHovered,
                ImVec4(
                    0.12f,
                    0.20f,
                    0.32f,
                    1.0f
                )
            );

            ImGui::PushStyleColor(
                ImGuiCol_ButtonActive,
                ImVec4(
                    0.17f,
                    0.28f,
                    0.44f,
                    1.0f
                )
            );

            const char *collapseIcon =
                gMenuCollapsed
                ? "↓"
                : "↑";

            if (ImGui::Button(
                collapseIcon,
                ImVec2(38.0f, 32.0f)
            ))
            {
                gMenuCollapsed =
                    !gMenuCollapsed;

                if (!gMenuCollapsed)
                {
                    gAnimatedHeight =
                        kHeaderHeight;
                }
            }

            ImGui::PopStyleColor(3);
            ImGui::PopStyleVar();

            /*
             * Close button.
             */
            ImGui::SameLine(
                0.0f,
                7.0f
            );

            ImGui::PushStyleVar(
                ImGuiStyleVar_FrameRounding,
                10.0f
            );

            ImGui::PushStyleColor(
                ImGuiCol_Button,
                ImVec4(
                    0.30f,
                    0.045f,
                    0.075f,
                    1.0f
                )
            );

            ImGui::PushStyleColor(
                ImGuiCol_ButtonHovered,
                ImVec4(
                    0.52f,
                    0.08f,
                    0.13f,
                    1.0f
                )
            );

            ImGui::PushStyleColor(
                ImGuiCol_ButtonActive,
                ImVec4(
                    0.68f,
                    0.12f,
                    0.18f,
                    1.0f
                )
            );

            if (ImGui::Button(
                "×",
                ImVec2(38.0f, 32.0f)
            ))
            {
                gMenuVisible = NO;
            }

            ImGui::PopStyleColor(3);
            ImGui::PopStyleVar();

            /*
             * Header separator.
             */
            if (draw)
            {
                draw->AddLine(
                    ImVec2(
                        windowPos.x + 16.0f,
                        windowPos.y + kHeaderHeight
                    ),
                    ImVec2(
                        windowEnd.x - 16.0f,
                        windowPos.y + kHeaderHeight
                    ),
                    IM_COL32(35, 46, 64, 210),
                    1.0f
                );
            }

            /*
             * Content only when sufficiently expanded.
             */
            if (gCollapseAnimation < 0.94f)
            {
                /*
                 * Sidebar.
                 */
                if (draw)
                {
                    draw->AddRectFilled(
                        ImVec2(
                            windowPos.x,
                            windowPos.y + kHeaderHeight
                        ),
                        ImVec2(
                            windowPos.x + sidebarWidth,
                            windowEnd.y
                        ),
                        IM_COL32(9, 14, 24, 255),
                        20.0f,
                        ImDrawFlags_RoundCornersBottomLeft
                    );
                }

                ImGui::SetCursorPos(
                    ImVec2(
                        18.0f,
                        63.0f
                    )
                );

                ImGui::TextColored(
                    ImVec4(
                        0.27f,
                        0.32f,
                        0.40f,
                        1.0f
                    ),
                    "CONTROL CENTER"
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
                        88.0f +
                        i * 53.0f;

                    if (active && draw)
                    {
                        draw->AddRectFilled(
                            ImVec2(
                                windowPos.x + 9.0f,
                                windowPos.y + itemY
                            ),
                            ImVec2(
                                windowPos.x +
                                sidebarWidth - 9.0f,
                                windowPos.y +
                                itemY + 42.0f
                            ),
                            IM_COL32(19, 48, 84, 255),
                            11.0f
                        );

                        draw->AddRectFilled(
                            ImVec2(
                                windowPos.x + 9.0f,
                                windowPos.y +
                                itemY + 9.0f
                            ),
                            ImVec2(
                                windowPos.x + 12.0f,
                                windowPos.y +
                                itemY + 33.0f
                            ),
                            IM_COL32(75, 153, 255, 255),
                            2.0f
                        );
                    }

                    char id[64];

                    snprintf(
                        id,
                        sizeof(id),
                        "%s  %s##page_%d",
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
                            sidebarWidth - 20.0f,
                            42.0f
                        )
                    ))
                    {
                        gSelectedPage = i;
                    }

                    ImGui::PopStyleColor(3);
                    ImGui::PopStyleVar();
                }

                /*
                 * Main content.
                 */
                float contentWidth =
                    windowSize.x -
                    sidebarWidth;

                float contentHeight =
                    windowSize.y -
                    kHeaderHeight;

                if (contentWidth < 100.0f)
                    contentWidth = 100.0f;

                if (contentHeight < 100.0f)
                    contentHeight = 100.0f;

                ImGui::SetCursorPos(
                    ImVec2(
                        sidebarWidth,
                        kHeaderHeight
                    )
                );

                if (ImGui::BeginChild(
                    "##ContentRoot",
                    ImVec2(
                        contentWidth,
                        contentHeight
                    ),
                    false,
                    ImGuiWindowFlags_NoBackground
                ))
                {
                    ImVec2 contentWindowPos =
                        ImGui::GetWindowPos();

                    ImVec2 contentWindowSize =
                        ImGui::GetWindowSize();

                    gContentTouchRect =
                        ImRect(
                            ImVec2(
                                contentWindowPos.x,
                                contentWindowPos.y
                            ),
                            ImVec2(
                                contentWindowPos.x +
                                contentWindowSize.x,
                                contentWindowPos.y +
                                contentWindowSize.y
                            )
                        );

                    ImGui::SetCursorPos(
                        ImVec2(15.0f, 12.0f)
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

                    /*
                     * No right-side scroll line.
                     *
                     * Content is now scrolled directly
                     * with touch gestures.
                     */
                    ImGui::SetCursorPos(
                        ImVec2(0.0f, 56.0f)
                    );

                    float scrollHeight =
                        contentHeight - 56.0f;

                    if (scrollHeight < 100.0f)
                        scrollHeight = 100.0f;

                    if (ImGui::BeginChild(
                        "##ScrollableContent",
                        ImVec2(
                            contentWidth,
                            scrollHeight
                        ),
                        false,
                        ImGuiWindowFlags_NoScrollbar |
                        ImGuiWindowFlags_NoScrollWithMouse
                    ))
                    {
                        ImGui::SetCursorPosX(15.0f);

                        if (gSelectedPage == 0)
                        {
                            ImGui::TextColored(
                                ImVec4(
                                    0.30f,
                                    0.68f,
                                    1.0f,
                                    1.0f
                                ),
                                "COMBAT"
                            );

                            ImGui::SameLine(
                                0.0f,
                                6.0f
                            );

                            ImGui::TextColored(
                                ImVec4(
                                    0.34f,
                                    0.39f,
                                    0.48f,
                                    1.0f
                                ),
                                "ACTIONS"
                            );

                            ImGui::TextColored(
                                ImVec4(
                                    0.43f,
                                    0.47f,
                                    0.55f,
                                    1.0f
                                ),
                                "Configure your combat options"
                            );

                            ImGui::Spacing();

                            static bool aimbot = false;
                            static bool esp = true;
                            static bool autoFire = false;
                            static bool silentAim = false;
                            static float fov = 90.0f;

                            if (ImGui::BeginChild(
                                "##CombatCard",
                                ImVec2(
                                    ImGui::GetContentRegionAvail().x - 18.0f,
                                    315.0f
                                ),
                                true
                            ))
                            {
                                ImGui::TextColored(
                                    ImVec4(
                                        0.93f,
                                        0.96f,
                                        1.0f,
                                        1.0f
                                    ),
                                    "Combat Features"
                                );

                                ImGui::TextColored(
                                    ImVec4(
                                        0.37f,
                                        0.42f,
                                        0.50f,
                                        1.0f
                                    ),
                                    "Main configuration"
                                );

                                ImGui::Spacing();
                                ImGui::Separator();
                                ImGui::Spacing();

                                ASASECModernSwitch(
                                    "Enable Aimbot",
                                    &aimbot
                                );

                                ASASECModernSwitch(
                                    "Box ESP",
                                    &esp
                                );

                                ASASECModernSwitch(
                                    "Auto Fire",
                                    &autoFire
                                );

                                ASASECModernSwitch(
                                    "Silent Aim",
                                    &silentAim
                                );

                                ImGui::Spacing();

                                ImGui::TextColored(
                                    ImVec4(
                                        0.80f,
                                        0.84f,
                                        0.91f,
                                        1.0f
                                    ),
                                    "FOV Radius"
                                );

                                ImGui::SetNextItemWidth(
                                    ImGui::GetContentRegionAvail().x - 10.0f
                                );

                                ImGui::SliderFloat(
                                    "##FOV",
                                    &fov,
                                    10.0f,
                                    180.0f,
                                    "%.0f"
                                );

                                ImGui::Spacing();

                                if (ImGui::Button(
                                    "Reset Defaults",
                                    ImVec2(130.0f, 36.0f)
                                ))
                                {
                                    aimbot = false;
                                    esp = true;
                                    autoFire = false;
                                    silentAim = false;
                                    fov = 90.0f;
                                }
                            }

                            ImGui::EndChild();

                            ImGui::Spacing();

                            if (ImGui::BeginChild(
                                "##CombatExtra",
                                ImVec2(
                                    ImGui::GetContentRegionAvail().x - 18.0f,
                                    220.0f
                                ),
                                true
                            ))
                            {
                                ImGui::TextColored(
                                    ImVec4(
                                        0.93f,
                                        0.96f,
                                        1.0f,
                                        1.0f
                                    ),
                                    "Advanced"
                                );

                                ImGui::TextColored(
                                    ImVec4(
                                        0.37f,
                                        0.42f,
                                        0.50f,
                                        1.0f
                                    ),
                                    "Additional options"
                                );

                                ImGui::Spacing();
                                ImGui::Separator();
                                ImGui::Spacing();

                                static bool targetLock = false;
                                static bool prediction = false;
                                static bool visibilityCheck = true;

                                ASASECModernSwitch(
                                    "Target Lock",
                                    &targetLock
                                );

                                ASASECModernSwitch(
                                    "Prediction",
                                    &prediction
                                );

                                ASASECModernSwitch(
                                    "Visibility Check",
                                    &visibilityCheck
                                );
                            }

                            ImGui::EndChild();
                        }
                        else if (gSelectedPage == 1)
                        {
                            ImGui::TextColored(
                                ImVec4(
                                    0.28f,
                                    0.86f,
                                    0.58f,
                                    1.0f
                                ),
                                "VISUALS"
                            );

                            ImGui::SameLine(
                                0.0f,
                                6.0f
                            );

                            ImGui::TextColored(
                                ImVec4(
                                    0.34f,
                                    0.39f,
                                    0.48f,
                                    1.0f
                                ),
                                "ESP"
                            );

                            ImGui::TextColored(
                                ImVec4(
                                    0.43f,
                                    0.47f,
                                    0.55f,
                                    1.0f
                                ),
                                "Configure visual options"
                            );

                            ImGui::Spacing();

                            static bool playerESP = true;
                            static bool healthBar = true;
                            static bool wallhack = false;
                            static bool nameTags = true;
                            static bool distance = true;

                            if (ImGui::BeginChild(
                                "##VisualCard",
                                ImVec2(
                                    ImGui::GetContentRegionAvail().x - 18.0f,
                                    315.0f
                                ),
                                true
                            ))
                            {
                                ImGui::TextColored(
                                    ImVec4(
                                        0.93f,
                                        0.96f,
                                        1.0f,
                                        1.0f
                                    ),
                                    "ESP Features"
                                );

                                ImGui::TextColored(
                                    ImVec4(
                                        0.37f,
                                        0.42f,
                                        0.50f,
                                        1.0f
                                    ),
                                    "Visual configuration"
                                );

                                ImGui::Spacing();
                                ImGui::Separator();
                                ImGui::Spacing();

                                ASASECModernSwitch(
                                    "Player ESP",
                                    &playerESP
                                );

                                ASASECModernSwitch(
                                    "Health Bar",
                                    &healthBar
                                );

                                ASASECModernSwitch(
                                    "Wallhack",
                                    &wallhack
                                );

                                ASASECModernSwitch(
                                    "Name Tags",
                                    &nameTags
                                );

                                ASASECModernSwitch(
                                    "Distance",
                                    &distance
                                );
                            }

                            ImGui::EndChild();

                            ImGui::Spacing();

                            if (ImGui::BeginChild(
                                "##VisualExtra",
                                ImVec2(
                                    ImGui::GetContentRegionAvail().x - 18.0f,
                                    240.0f
                                ),
                                true
                            ))
                            {
                                ImGui::TextColored(
                                    ImVec4(
                                        0.93f,
                                        0.96f,
                                        1.0f,
                                        1.0f
                                    ),
                                    "Visual Style"
                                );

                                ImGui::TextColored(
                                    ImVec4(
                                        0.37f,
                                        0.42f,
                                        0.50f,
                                        1.0f
                                    ),
                                    "Overlay configuration"
                                );

                                ImGui::Spacing();
                                ImGui::Separator();
                                ImGui::Spacing();

                                static bool glow = false;
                                static bool skeleton = false;
                                static bool snapLines = false;

                                ASASECModernSwitch(
                                    "Glow",
                                    &glow
                                );

                                ASASECModernSwitch(
                                    "Skeleton",
                                    &skeleton
                                );

                                ASASECModernSwitch(
                                    "Snap Lines",
                                    &snapLines
                                );
                            }

                            ImGui::EndChild();
                        }
                        else
                        {
                            ImGui::TextColored(
                                ImVec4(
                                    1.0f,
                                    0.67f,
                                    0.28f,
                                    1.0f
                                ),
                                "SETTINGS"
                            );

                            ImGui::SameLine(
                                0.0f,
                                6.0f
                            );

                            ImGui::TextColored(
                                ImVec4(
                                    0.34f,
                                    0.39f,
                                    0.48f,
                                    1.0f
                                ),
                                "SYSTEM"
                            );

                            ImGui::TextColored(
                                ImVec4(
                                    0.43f,
                                    0.47f,
                                    0.55f,
                                    1.0f
                                ),
                                "ASASEC configuration"
                            );

                            ImGui::Spacing();

                            if (ImGui::BeginChild(
                                "##SettingsCard",
                                ImVec2(
                                    ImGui::GetContentRegionAvail().x - 18.0f,
                                    330.0f
                                ),
                                true
                            ))
                            {
                                ImGui::TextColored(
                                    ImVec4(
                                        0.93f,
                                        0.96f,
                                        1.0f,
                                        1.0f
                                    ),
                                    "Application"
                                );

                                ImGui::TextColored(
                                    ImVec4(
                                        0.37f,
                                        0.42f,
                                        0.50f,
                                        1.0f
                                    ),
                                    "Runtime information"
                                );

                                ImGui::Spacing();
                                ImGui::Separator();
                                ImGui::Spacing();

                                ImGui::Text("Version");

                                ImGui::SameLine(
                                    ImGui::GetContentRegionAvail().x - 55.0f
                                );

                                ImGui::TextColored(
                                    ImVec4(
                                        0.30f,
                                        0.68f,
                                        1.0f,
                                        1.0f
                                    ),
                                    "3.1"
                                );

                                ImGui::Spacing();

                                ImGui::Text("Renderer");

                                ImGui::SameLine(
                                    ImGui::GetContentRegionAvail().x - 55.0f
                                );

                                ImGui::Text("Metal");

                                ImGui::Spacing();

                                ImGui::Text("Status");

                                ImGui::SameLine(
                                    ImGui::GetContentRegionAvail().x - 55.0f
                                );

                                ImGui::TextColored(
                                    ImVec4(
                                        0.30f,
                                        0.88f,
                                        0.56f,
                                        1.0f
                                    ),
                                    "ACTIVE"
                                );

                                ImGui::Spacing();
                                ImGui::Separator();
                                ImGui::Spacing();

                                static bool animations = true;
                                static bool haptics = true;
                                static bool compactMode = false;

                                ASASECModernSwitch(
                                    "Animations",
                                    &animations
                                );

                                ASASECModernSwitch(
                                    "Haptic Feedback",
                                    &haptics
                                );

                                ASASECModernSwitch(
                                    "Compact Mode",
                                    &compactMode
                                );
                            }

                            ImGui::EndChild();

                            ImGui::Spacing();

                            if (ImGui::BeginChild(
                                "##InfoCard",
                                ImVec2(
                                    ImGui::GetContentRegionAvail().x - 18.0f,
                                    210.0f
                                ),
                                true
                            ))
                            {
                                ImGui::TextColored(
                                    ImVec4(
                                        0.93f,
                                        0.96f,
                                        1.0f,
                                        1.0f
                                    ),
                                    "Interface"
                                );

                                ImGui::TextColored(
                                    ImVec4(
                                        0.37f,
                                        0.42f,
                                        0.50f,
                                        1.0f
                                    ),
                                    "Display configuration"
                                );

                                ImGui::Spacing();
                                ImGui::Separator();
                                ImGui::Spacing();

                                ImGui::TextWrapped(
                                    "Swipe vertically inside the content area to navigate through the menu. Use the lower-right corner icon to resize the interface."
                                );
                            }

                            ImGui::EndChild();
                        }
                    }

                    ImGui::EndChild();
                }

                ImGui::EndChild();

                /*
                 * New resize icon.
                 *
                 * No long resize line anymore.
                 * Only the small inverted-L symbol
                 * in the bottom-right corner is used.
                 */
                if (draw &&
                    windowSize.x > 300.0f &&
                    windowSize.y > 220.0f &&
                    !gMenuCollapsed)
                {
                    float right =
                        windowSize.x - 9.0f;

                    float bottom =
                        windowSize.y - 9.0f;

                    ImVec2 corner =
                        ImVec2(
                            windowPos.x + right,
                            windowPos.y + bottom
                        );

                    ImU32 resizeColor =
                        gResizingMenu
                        ? ASASECColor(
                            0.40f,
                            0.72f,
                            1.0f,
                            1.0f
                        )
                        : ASASECColor(
                            0.65f,
                            0.73f,
                            0.84f,
                            0.70f
                        );

                    float pulse =
                        0.55f +
                        0.15f *
                        sinf(
                            (float)ImGui::GetTime() *
                            3.0f
                        );

                    if (!gResizingMenu)
                    {
                        resizeColor =
                            ASASECColor(
                                0.65f,
                                0.73f,
                                0.84f,
                                pulse
                            );
                    }

                    /*
                     * Shadow.
                     */
                    draw->AddLine(
                        ImVec2(
                            corner.x - 22.0f,
                            corner.y - 3.0f
                        ),
                        ImVec2(
                            corner.x - 3.0f,
                            corner.y - 3.0f
                        ),
                        ASASECColor(
                            0.0f,
                            0.0f,
                            0.0f,
                            0.30f
                        ),
                        4.0f
                    );

                    draw->AddLine(
                        ImVec2(
                            corner.x - 3.0f,
                            corner.y - 22.0f
                        ),
                        ImVec2(
                            corner.x - 3.0f,
                            corner.y - 3.0f
                        ),
                        ASASECColor(
                            0.0f,
                            0.0f,
                            0.0f,
                            0.30f
                        ),
                        4.0f
                    );

                    /*
                     * Inverted L / corner symbol.
                     */
                    draw->AddLine(
                        ImVec2(
                            corner.x - 21.0f,
                            corner.y - 3.0f
                        ),
                        ImVec2(
                            corner.x - 3.0f,
                            corner.y - 3.0f
                        ),
                        resizeColor,
                        gResizingMenu ? 2.8f : 2.2f
                    );

                    draw->AddLine(
                        ImVec2(
                            corner.x - 3.0f,
                            corner.y - 21.0f
                        ),
                        ImVec2(
                            corner.x - 3.0f,
                            corner.y - 3.0f
                        ),
                        resizeColor,
                        gResizingMenu ? 2.8f : 2.2f
                    );

                    /*
                     * Small diagonal accent.
                     */
                    draw->AddLine(
                        ImVec2(
                            corner.x - 13.0f,
                            corner.y - 8.0f
                        ),
                        ImVec2(
                            corner.x - 8.0f,
                            corner.y - 13.0f
                        ),
                        resizeColor,
                        1.8f
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

    [commandBuffer presentDrawable:drawable];

    [commandBuffer commit];
}

@end

#pragma mark - Start

void ASASECImGuiStart(void)
{
    dispatch_async(
        dispatch_get_main_queue(),
        ^{
            if (gInitialized || gStarting)
                return;

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

            if (ImGui::GetCurrentContext())
            {
                ImGui_ImplMetal_Shutdown();
                ImGui::DestroyContext();
            }

            gImGuiView = nil;
            gRenderer = nil;

            gMetalDevice = nil;
            gCommandQueue = nil;

            gMetalDevice = device;
            gCommandQueue = queue;

            ImGui::CreateContext();

            if (!ImGui::GetCurrentContext())
            {
                gCommandQueue = nil;
                gMetalDevice = nil;
                gStarting = NO;
                return;
            }

            ImGuiIO &io =
                ImGui::GetIO();

            io.IniFilename = NULL;
            io.LogFilename = NULL;
            io.FontGlobalScale = 1.0f;

            CGSize bounds =
                window.bounds.size;

            io.DisplaySize =
                ImVec2(
                    (float)bounds.width,
                    (float)bounds.height
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

            CGRect frame =
                window.bounds;

            ASASECImGuiView *view =
                [[ASASECImGuiView alloc]
                 initWithFrame:frame
                 device:device];

            if (!view)
            {
                ImGui::DestroyContext();

                gCommandQueue = nil;
                gMetalDevice = nil;
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

            view.paused = NO;

            view.multipleTouchEnabled =
                YES;

            view.userInteractionEnabled =
                YES;

            ASASECImGuiRenderer *renderer =
                [[ASASECImGuiRenderer alloc] init];

            if (!renderer)
            {
                ImGui::DestroyContext();

                gCommandQueue = nil;
                gMetalDevice = nil;
                gStarting = NO;

                return;
            }

            if (!ImGui_ImplMetal_Init(device))
            {
                view.delegate = nil;

                ImGui::DestroyContext();

                gCommandQueue = nil;
                gMetalDevice = nil;
                gStarting = NO;

                return;
            }

            gImGuiView = view;
            gRenderer = renderer;

            view.delegate =
                renderer;

            [window addSubview:view];

            [window bringSubviewToFront:view];

            gAnimatedHeight =
                gMenuSize.y;

            gCollapseAnimation =
                0.0f;

            gContentTouchRect =
                ImRect(
                    ImVec2(0.0f, 0.0f),
                    ImVec2(0.0f, 0.0f)
                );

            ASASECClampMenuToScreen(window);

            gInitialized = YES;
            gStarting = NO;
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
            {
                return;
            }

            gInitialized = NO;
            gStarting = NO;

            gDraggingMenu = NO;
            gResizingMenu = NO;
            gScrollingContent = NO;

            if (gImGuiView)
            {
                gImGuiView.delegate = nil;
                gImGuiView.paused = YES;

                [gImGuiView removeFromSuperview];

                gImGuiView = nil;
            }

            if (ImGui::GetCurrentContext())
            {
                ImGui_ImplMetal_Shutdown();
                ImGui::DestroyContext();
            }

            gRenderer = nil;

            gCommandQueue = nil;
            gMetalDevice = nil;

            gMenuVisible = YES;
            gMenuCollapsed = NO;

            gSelectedPage = 0;

            gCollapseAnimation = 0.0f;
            gAnimatedHeight = 390.0f;

            gDragStartPoint =
                CGPointZero;

            gResizeStartPoint =
                CGPointZero;

            gScrollStartPoint =
                CGPointZero;

            gMenuPosition =
                ImVec2(
                    25.0f,
                    75.0f
                );

            gDragStartPosition =
                gMenuPosition;

            gResizeStartSize =
                ImVec2(
                    560.0f,
                    390.0f
                );

            gMenuSize =
                ImVec2(
                    560.0f,
                    390.0f
                );

            gContentTouchRect =
                ImRect(
                    ImVec2(0.0f, 0.0f),
                    ImVec2(0.0f, 0.0f)
                );
        }
    );
}
