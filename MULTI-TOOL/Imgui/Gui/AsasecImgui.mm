#import “AsasecImgui.h”

#import <UIKit/UIKit.h>
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import <QuartzCore/QuartzCore.h>
#import <dispatch/dispatch.h>
#import <math.h>
#import <string.h>

#define IMGUI_DEFINE_MATH_OPERATORS
#include “../imgui.h”
#include “../imgui_internal.h”
#include “../Backends/imgui_impl_metal.h”

#pragma mark - Global State

static MTKView *gImGuiView = nil;
static id gMetalDevice = nil;
static id gCommandQueue = nil;

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
static float gMenuAnimation = 1.0f;

#pragma mark - Renderer

@interface ASASECImGuiRenderer : NSObject 
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

static float ASASECEase(float current,
float target,
float speed,
float dt)
{
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

CGSize size =
    window.bounds.size;
float width =
    gMenuSize.x;
float height =
    gMenuCollapsed
    ? kHeaderHeight
    : gMenuSize.y;
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

for (int i = 0; i < gSwitchAnimationCount; i++)
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

static bool ASASECModernSwitch(const char *label,
bool *value)
{
if (!label || !value)
return false;

ImGui::PushID(label);
const float switchWidth = 48.0f;
const float switchHeight = 27.0f;
const float rowHeight = 44.0f;
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
        14.0f,
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
            10.0f,
            dt
        );
}
float pulse =
    animationData
    ? animationData->pulse
    : 0.0f;
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
float bgR =
    0.08f +
    (0.18f - 0.08f) * progress;
float bgG =
    0.12f +
    (0.52f - 0.12f) * progress;
float bgB =
    0.18f +
    (1.00f - 0.18f) * progress;
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
    ImVec2(
        switchMin.x + 0.5f,
        switchMin.y + 0.5f
    ),
    ImVec2(
        switchMax.x - 0.5f,
        switchMax.y - 0.5f
    ),
    ASASECColor(
        0.20f + 0.25f * progress,
        0.26f + 0.35f * progress,
        0.36f + 0.45f * progress,
        0.9f
    ),
    switchHeight * 0.5f,
    0,
    1.0f
);
float offX =
    switchMin.x + 14.0f;
float onX =
    switchMax.x - 14.0f;
float knobX =
    offX +
    (onX - offX) *
    progress;
float knobY =
    switchMin.y +
    switchHeight * 0.5f;
float knobRadius =
    9.0f +
    pulse * 1.6f;
if (pulse > 0.01f)
{
    draw->AddCircle(
        ImVec2(
            knobX,
            knobY
        ),
        12.0f + pulse * 3.0f,
        ASASECColor(
            0.30f,
            0.68f,
            1.0f,
            pulse * 0.30f
        ),
        24,
        1.5f
    );
}
draw->AddCircleFilled(
    ImVec2(
        knobX + 1.0f,
        knobY + 1.5f
    ),
    knobRadius + 0.5f,
    ASASECColor(
        0.0f,
        0.0f,
        0.0f,
        0.25f
    )
);
draw->AddCircleFilled(
    ImVec2(
        knobX,
        knobY
    ),
    knobRadius,
    ASASECColor(
        0.95f,
        0.98f,
        1.0f,
        1.0f
    )
);
ImGui::SetCursorScreenPos(
    ImVec2(
        itemMin.x,
        itemMin.y + 11.0f
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

* (BOOL)pointInsideMenu:(CGPoint)point
    {
    if (!gMenuVisible)
    return NO;
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
* (BOOL)pointInsideResizeHandle:(CGPoint)point
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
* (BOOL)pointInsideDragHeader:(CGPoint)point
    {
    if (!gMenuVisible)
    return NO;
    return
    point.x >= gMenuPosition.x &&
    point.x <= gMenuPosition.x + gMenuSize.x &&
    point.y >= gMenuPosition.y &&
    point.y <= gMenuPosition.y + kHeaderHeight;
    }
* (BOOL)pointInsideContent:(CGPoint)point
    {
    if (!gMenuVisible || gMenuCollapsed)
    return NO;
    const float sidebarWidth = 145.0f;
    float contentLeft =
    gMenuPosition.x +
    sidebarWidth;
    float contentTop =
    gMenuPosition.y +
    kHeaderHeight;
    float contentRight =
    gMenuPosition.x +
    gMenuSize.x;
    float contentBottom =
    gMenuPosition.y +
    gMenuSize.y;
    return
    point.x >= contentLeft &&
    point.x <= contentRight &&
    point.y >= contentTop &&
    point.y <= contentBottom;
    }
* (UIView *)hitTest:(CGPoint)point
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

#pragma mark - Menu Drag

* (void)beginMenuDragAtPoint:(CGPoint)point
    {
    if (!gMenuVisible)
    return;
    gDraggingMenu = YES;
    gResizingMenu = NO;
    gContentDragging = NO;
    gDragStartPoint = point;
    gDragStartPosition = gMenuPosition;
    }
* (void)updateMenuDragAtPoint:(CGPoint)point
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

* (void)beginMenuResizeAtPoint:(CGPoint)point
    {
    if (!gMenuVisible)
    return;
    if (gMenuCollapsed)
    return;
    gResizingMenu = YES;
    gDraggingMenu = NO;
    gContentDragging = NO;
    gResizeStartPoint = point;
    gResizeStartSize = gMenuSize;
    }
* (void)updateMenuResizeAtPoint:(CGPoint)point
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

#pragma mark - Content Scroll

* (void)beginContentDragAtPoint:(CGPoint)point
    {
    if (!gMenuVisible)
    return;
    if (gMenuCollapsed)
    return;
    gContentDragging = YES;
    gContentTouchCandidate = YES;
    gContentHasMoved = NO;
    gDraggingMenu = NO;
    gResizingMenu = NO;
    gContentStartPoint = point;
    gContentLastPoint = point;
    gPendingContentScrollY = 0.0f;
    gContentScrollVelocity = 0.0f;
    }
* (void)updateContentDragAtPoint:(CGPoint)point
    {
    if (!gContentDragging)
    return;
    float dy =
    (float)(
    point.y -
    gContentLastPoint.y
    );
    float dx =
    (float)(
    point.x -
    gContentLastPoint.x
    );
    if (fabsf(dy) < 0.05f)
    dy = 0.0f;
    float totalDX =
    fabsf(
    (float)(
    point.x -
    gContentStartPoint.x
    )
    );
    float totalDY =
    fabsf(
    (float)(
    point.y -
    gContentStartPoint.y
    )
    );
    if (!gContentHasMoved)
    {
    if (totalDY > 5.0f &&
    totalDY >= totalDX)
    {
    gContentHasMoved = YES;
    }
    }
    if (gContentHasMoved)
    {
    float scrollDelta =
    -dy;

  gPendingContentScrollY +=
      scrollDelta;
  gContentScrollVelocity =
      scrollDelta;

    }
    gContentLastPoint = point;
    }
* (void)endContentDrag
    {
    if (!gContentDragging)
    return;
    gContentDragging = NO;
    gContentTouchCandidate = NO;
    }

#pragma mark - Interaction

* (void)endMenuInteraction
    {
    gDraggingMenu = NO;
    gResizingMenu = NO;
    gContentDragging = NO;
    gContentTouchCandidate = NO;
    }
* (void)clampMenuPosition
    {
    UIWindow *window =
    self.window;
    if (!window)
    return;
    ASASECClampMenuToScreen(window);
    }

#pragma mark - Touch -> ImGui

* (void)updateIOWithTouchEvent:(UIEvent *)event
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

* (void)touchesBegan:(NSSet<UITouch *> *)touches
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
      [self beginContentDragAtPoint:point];
  }

    }
    [self updateIOWithTouchEvent:event];
    }
* (void)touchesMoved:(NSSet<UITouch *> *)touches
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
  else if (gContentDragging)
  {
      [self updateContentDragAtPoint:point];
  }

    }
    [self updateIOWithTouchEvent:event];
    }
* (void)touchesEnded:(NSSet<UITouch *> *)touches
    withEvent:(UIEvent *)event
    {
    if (gContentDragging)
    {
    [self endContentDrag];
    }
    else
    {
    [self endMenuInteraction];
    }
    if (!gInitialized)
    return;
    [self updateIOWithTouchEvent:event];
    if (ImGui::GetCurrentContext())
    {
    ImGuiIO &io =
    ImGui::GetIO();

  io.MouseDown[0] = false;

    }
    }
* (void)touchesCancelled:(NSSet<UITouch *> *)touches
    withEvent:(UIEvent *)event
    {
    [self endMenuInteraction];
    gContentScrollVelocity = 0.0f;
    gPendingContentScrollY = 0.0f;
    if (!gInitialized)
    return;
    [self updateIOWithTouchEvent:event];
    if (ImGui::GetCurrentContext())
    {
    ImGuiIO &io =
    ImGui::GetIO();

  io.MouseDown[0] = false;

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
style.ScrollbarSize = 1.0f;
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
c[ImGuiCol_ScrollbarBg] =
    ImVec4(
        0.0f,
        0.0f,
        0.0f,
        0.0f
    );
c[ImGuiCol_ScrollbarGrab] =
    ImVec4(
        0.0f,
        0.0f,
        0.0f,
        0.0f
    );
c[ImGuiCol_ScrollbarGrabHovered] =
    ImVec4(
        0.0f,
        0.0f,
        0.0f,
        0.0f
    );
c[ImGuiCol_ScrollbarGrabActive] =
    ImVec4(
        0.0f,
        0.0f,
        0.0f,
        0.0f
    );

}

#pragma mark - Renderer

@implementation ASASECImGuiRenderer

* (void)mtkView:(MTKView *)view
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
* (void)drawInMTKView:(MTKView *)view
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
    id drawable =
    view.currentDrawable;
    if (!drawable)
    return;
    id commandBuffer =
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
    0f / fps;
    ImGui::NewFrame();
    float dt =
    io.DeltaTime;
    if (dt <= 0.0f || dt > 0.1f)
    dt = 1.0f / 60.0f;
    if (gSelectedPage != gPreviousPage)
    {
    gPreviousPage =
    gSelectedPage;

  gPageAnimation =
      0.0f;

    }
    gPageAnimation =
    ASASECEase(
    gPageAnimation,
    0f,
    0f,
    dt
    );
    if (!gContentDragging &&
    fabsf(gContentScrollVelocity) > 0.01f)
    {
    gPendingContentScrollY +=
    gContentScrollVelocity;

  gContentScrollVelocity *=
      expf(-7.0f * dt);
  if (fabsf(gContentScrollVelocity) < 0.01f)
      gContentScrollVelocity = 0.0f;

    }
    if (gMenuVisible)
    {
    const float sidebarWidth = 145.0f;

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
              IM_COL32(
                  42,
                  53,
                  73,
                  190
              ),
              20.0f,
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
              19.0f,
              ImDrawFlags_RoundCornersTop
          );
          if (!gMenuCollapsed)
          {
              draw->AddLine(
                  ImVec2(
                      windowPos.x + 16.0f,
                      windowPos.y + 53.0f
                  ),
                  ImVec2(
                      windowEnd.x - 16.0f,
                      windowPos.y + 53.0f
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
      }
      /*
       HEADER
       */
      ImGui::SetCursorPos(
          ImVec2(
              18.0f,
              9.0f
          )
      );
      ImGui::TextColored(
          ImVec4(
              0.30f,
              0.68f,
              1.0f,
              1.0f
          ),
          "o"
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
              0.42f,
              0.48f,
              0.57f,
              1.0f
          ),
          "UI"
      );
      /*
       TEK AÇ / KAPAT BUTONU
       Artık üç nokta veya başka ikinci
       bir kontrol yok.
       Ok doğrudan DrawList ile çiziliyor.
       Böylece font/glyph problemi oluşmuyor.
       */
      float collapseButtonX =
          windowSize.x - 55.0f;
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
               arrowMax.x) * 0.5f;
          float centerY =
              (arrowMin.y +
               arrowMax.y) * 0.5f;
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
              /*
               Aşağı bakan ok
               */
              headerDraw->AddLine(
                  ImVec2(
                      centerX - arrowWidth,
                      centerY - arrowHeight
                  ),
                  ImVec2(
                      centerX,
                      centerY + arrowHeight
                  ),
                  arrowColor,
                  2.2f
              );
              headerDraw->AddLine(
                  ImVec2(
                      centerX,
                      centerY + arrowHeight
                  ),
                  ImVec2(
                      centerX + arrowWidth,
                      centerY - arrowHeight
                  ),
                  arrowColor,
                  2.2f
              );
          }
          else
          {
              /*
               Yukarı bakan ok
               */
              headerDraw->AddLine(
                  ImVec2(
                      centerX - arrowWidth,
                      centerY + arrowHeight
                  ),
                  ImVec2(
                      centerX,
                      centerY - arrowHeight
                  ),
                  arrowColor,
                  2.2f
              );
              headerDraw->AddLine(
                  ImVec2(
                      centerX,
                      centerY - arrowHeight
                  ),
                  ImVec2(
                      centerX + arrowWidth,
                      centerY + arrowHeight
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
          {
              ASASECClampMenuToScreen(
                  window
              );
          }
      }
      ImGui::PopStyleColor(3);
      ImGui::PopStyleVar();
      ImGui::PopID();
      /*
       KAPALI DURUM
       Sadece header çizilir.
       Content, sidebar, resize handle
       ve diğer bütün alanlar kaldırılır.
       */
      if (!gMenuCollapsed)
      {
          /*
           SIDEBAR
           */
          if (draw)
          {
              draw->AddRectFilled(
                  windowPos,
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
                      windowPos.y + 62.0f
                  ),
                  ImVec2(
                      windowPos.x +
                      sidebarWidth,
                      windowEnd.y - 16.0f
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
                  72.0f +
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
                          windowPos.x + 18.0f,
                          windowPos.y +
                          itemY + 21.0f
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
                      sidebarWidth - 20.0f,
                      42.0f
                  )
              ))
              {
                  if (gSelectedPage != i)
                  {
                      gSelectedPage = i;
                      gPageAnimation = 0.0f;
                      gPendingContentScrollY =
                          0.0f;
                      gContentScrollVelocity =
                          0.0f;
                  }
              }
              ImGui::PopStyleColor(3);
              ImGui::PopStyleVar();
          }
          /*
           CONTENT ROOT
           */
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
                      15.0f,
                      9.0f
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
                          windowPos.y + 51.0f
                      ),
                      ImVec2(
                          windowEnd.x - 16.0f,
                          windowPos.y + 51.0f
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
                      60.0f
                  )
              );
              float scrollHeight =
                  contentHeight - 60.0f;
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
                      15.0f
                  );
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
                              ImVec2(
                                  130.0f,
                                  36.0f
                              )
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
                          ImGui::Text(
                              "Version"
                          );
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
                          ImGui::Text(
                              "Renderer"
                          );
                          ImGui::SameLine(
                              ImGui::GetContentRegionAvail().x - 55.0f
                          );
                          ImGui::Text(
                              "Metal"
                          );
                          ImGui::Spacing();
                          ImGui::Text(
                              "Status"
                          );
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
                              "Swipe directly inside the content area to navigate vertically. Use the bottom-right corner icon to resize the menu."
                          );
                      }
                      ImGui::EndChild();
                  }
                  ImGui::PopStyleVar();
                  if (fabsf(gPendingContentScrollY) > 0.001f)
                  {
                      float currentScroll =
                          ImGui::GetScrollY();
                      float maxScroll =
                          ImGui::GetScrollMaxY();
                      float targetScroll =
                          currentScroll +
                          gPendingContentScrollY;
                      targetScroll =
                          ASASECClampFloat(
                              targetScroll,
                              0.0f,
                              maxScroll
                          );
                      ImGui::SetScrollY(
                          targetScroll
                      );
                      if ((targetScroll <= 0.0f &&
                           gPendingContentScrollY < 0.0f) ||
                          (targetScroll >= maxScroll &&
                           gPendingContentScrollY > 0.0f))
                      {
                          gContentScrollVelocity = 0.0f;
                      }
                      gPendingContentScrollY = 0.0f;
                  }
              }
              ImGui::EndChild();
              /*
               RESIZE ICON
               Ters L korunuyor.
               */
              if (draw &&
                  windowSize.x > 300.0f &&
                  windowSize.y > 220.0f)
              {
                  float right =
                      windowSize.x - 7.0f;
                  float bottom =
                      windowSize.y - 7.0f;
                  ImVec2 iconCenter =
                      ImVec2(
                          windowPos.x +
                          right - 10.0f,
                          windowPos.y +
                          bottom - 10.0f
                      );
                  BOOL resizeActive =
                      gResizingMenu;
                  ImU32 iconColor =
                      resizeActive
                      ? ASASECColor(
                          0.42f,
                          0.72f,
                          1.0f,
                          1.0f
                      )
                      : ASASECColor(
                          0.70f,
                          0.76f,
                          0.86f,
                          0.80f
                      );
                  if (gResizingMenu)
                  {
                      draw->AddCircle(
                          iconCenter,
                          13.0f,
                          ASASECColor(
                              0.30f,
                              0.68f,
                              1.0f,
                              0.18f
                          ),
                          24,
                          1.2f
                      );
                  }
                  draw->AddLine(
                      ImVec2(
                          iconCenter.x - 9.0f,
                          iconCenter.y + 7.0f
                      ),
                      ImVec2(
                          iconCenter.x + 7.0f,
                          iconCenter.y + 7.0f
                      ),
                      iconColor,
                      2.2f
                  );
                  draw->AddLine(
                      ImVec2(
                          iconCenter.x + 7.0f,
                          iconCenter.y + 7.0f
                      ),
                      ImVec2(
                          iconCenter.x + 7.0f,
                          iconCenter.y - 9.0f
                      ),
                      iconColor,
                      2.2f
                  );
                  draw->AddLine(
                      ImVec2(
                          iconCenter.x - 3.0f,
                          iconCenter.y + 7.0f
                      ),
                      ImVec2(
                          iconCenter.x + 7.0f,
                          iconCenter.y - 3.0f
                      ),
                      iconColor,
                      1.7f
                  );
                  draw->AddLine(
                      ImVec2(
                          iconCenter.x + 2.0f,
                          iconCenter.y + 7.0f
                      ),
                      ImVec2(
                          iconCenter.x + 7.0f,
                          iconCenter.y + 2.0f
                      ),
                      iconColor,
                      1.7f
                  );
              }
          }
          ImGui::EndChild();
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
    return;
    id encoder =
    [commandBuffer
    renderCommandEncoderWithDescriptor:pass];
    if (!encoder)
    {
    [commandBuffer commit];
    return;
    }
    [encoder setViewport:(MTLViewport){
    0,
    0,
    (double)view.drawableSize.width,
    (double)view.drawableSize.height,
    0,
    0
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
            [[ASASECImGuiRenderer alloc]
             init];
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
        ASASECClampMenuToScreen(
            window
        );
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
        gContentDragging = NO;
        gContentTouchCandidate = NO;
        gContentHasMoved = NO;
        gPendingContentScrollY = 0.0f;
        gContentScrollVelocity = 0.0f;
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
        gPreviousPage = 0;
        gPageAnimation = 1.0f;
        gMenuAnimation = 1.0f;
        gDragStartPoint =
            CGPointZero;
        gResizeStartPoint =
            CGPointZero;
        gContentStartPoint =
            CGPointZero;
        gContentLastPoint =
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
        gSwitchAnimationCount = 0;
        for (int i = 0; i < 64; i++)
        {
            gSwitchAnimations[i].label =
                NULL;
            gSwitchAnimations[i].progress =
                0.0f;
            gSwitchAnimations[i].pulse =
                0.0f;
        }
    }
);

}
