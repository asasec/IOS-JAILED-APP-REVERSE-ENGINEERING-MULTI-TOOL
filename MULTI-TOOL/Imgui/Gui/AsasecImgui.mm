#import “AsasecImgui.h”

#import <UIKit/UIKit.h>
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import <QuartzCore/QuartzCore.h>
#import <dispatch/dispatch.h>

#define IMGUI_DEFINE_MATH_OPERATORS
#include “../imgui.h”
#include “../imgui_internal.h”
#include “../Backends/imgui_impl_metal.h”

#pragma mark - Global State

static MTKView *gImGuiView = nil;
static id gCommandQueue = nil;
static BOOL gInitialized = NO;

static BOOL gMenuVisible = YES;
static BOOL gMenuCollapsed = NO;

static ImVec2 gMenuPosition = ImVec2(25.0f, 75.0f);
static ImVec2 gMenuSize = ImVec2(560.0f, 390.0f);

static const float kMenuMinWidth = 430.0f;
static const float kMenuMaxWidth = 760.0f;
static const float kMenuMinHeight = 300.0f;
static const float kMenuMaxHeight = 620.0f;

static const float kHeaderHeight = 54.0f;
static const float kResizeSize = 42.0f;

static int gSelectedPage = 0;

static BOOL gDraggingMenu = NO;
static BOOL gResizingMenu = NO;

static CGPoint gDragStartPoint = CGPointZero;
static CGPoint gResizeStartPoint = CGPointZero;

static ImVec2 gDragStartPosition = ImVec2(25.0f, 75.0f);
static ImVec2 gResizeStartSize = ImVec2(560.0f, 390.0f);

#pragma mark - Helpers

static float ASASECClampFloat(float value, float minimum, float maximum)
{
if (value < minimum)
return minimum;

if (value > maximum)
    return maximum;
return value;

}

static void ASASECClampMenuToScreen(UIWindow *window)
{
if (!window)
return;

CGSize screenSize = window.bounds.size;
float width = gMenuSize.x;
float height = gMenuCollapsed ? kHeaderHeight : gMenuSize.y;
const float margin = 8.0f;
float maxX = (float)screenSize.width - width - margin;
float maxY = (float)screenSize.height - height - margin;
if (maxX < margin)
    maxX = margin;
if (maxY < margin)
    maxY = margin;
gMenuPosition.x = ASASECClampFloat(
    gMenuPosition.x,
    margin,
    maxX
);
gMenuPosition.y = ASASECClampFloat(
    gMenuPosition.y,
    margin,
    maxY
);

}

#pragma mark - Modern Switch

static BOOL ASASECModernSwitch(
const char *label,
bool *value
)
{
if (!value)
return NO;

ImGui::PushID(label);
ImVec2 cursor = ImGui::GetCursorScreenPos();
const float switchWidth = 48.0f;
const float switchHeight = 27.0f;
ImVec2 available = ImGui::GetContentRegionAvail();
float totalWidth = available.x;
if (totalWidth < 180.0f)
    totalWidth = 180.0f;
ImVec2 itemSize =
    ImVec2(totalWidth, 38.0f);
bool clicked =
    ImGui::InvisibleButton(
        "##switch_button",
        itemSize
    );
if (clicked)
    *value = !(*value);
bool hovered =
    ImGui::IsItemHovered();
ImDrawList *draw =
    ImGui::GetWindowDrawList();
ImVec2 switchPos =
    ImVec2(
        cursor.x + totalWidth - switchWidth,
        cursor.y + 5.0f
    );
ImVec2 switchEnd =
    ImVec2(
        switchPos.x + switchWidth,
        switchPos.y + switchHeight
    );
ImU32 backgroundColor;
if (*value)
{
    backgroundColor =
        IM_COL32(42, 116, 218, 255);
}
else
{
    backgroundColor =
        hovered
        ? IM_COL32(55, 64, 79, 255)
        : IM_COL32(39, 47, 60, 255);
}
draw->AddRectFilled(
    switchPos,
    switchEnd,
    backgroundColor,
    switchHeight * 0.5f
);
if (*value)
{
    draw->AddRect(
        ImVec2(
            switchPos.x + 0.5f,
            switchPos.y + 0.5f
        ),
        ImVec2(
            switchEnd.x - 0.5f,
            switchEnd.y - 0.5f
        ),
        IM_COL32(96, 166, 245, 190),
        switchHeight * 0.5f,
        0,
        1.0f
    );
}
const float knobSize = 21.0f;
float knobX =
    *value
    ? switchEnd.x - knobSize - 3.0f
    : switchPos.x + 3.0f;
ImVec2 knobMin =
    ImVec2(
        knobX,
        switchPos.y + 3.0f
    );
ImVec2 knobMax =
    ImVec2(
        knobX + knobSize,
        switchPos.y + 3.0f + knobSize
    );
draw->AddCircleFilled(
    ImVec2(
        (knobMin.x + knobMax.x) * 0.5f,
        (knobMin.y + knobMax.y) * 0.5f
    ),
    knobSize * 0.5f,
    IM_COL32(245, 248, 252, 255)
);
const char *stateText =
    *value ? "ON" : "OFF";
ImVec2 stateSize =
    ImGui::CalcTextSize(stateText);
draw->AddText(
    ImVec2(
        switchPos.x - stateSize.x - 9.0f,
        switchPos.y +
        (switchHeight - stateSize.y) * 0.5f
    ),
    *value
        ? IM_COL32(105, 177, 255, 255)
        : IM_COL32(116, 126, 141, 255),
    stateText
);
ImVec2 textPos =
    ImVec2(
        cursor.x,
        cursor.y +
        (itemSize.y -
         ImGui::GetTextLineHeight()) * 0.5f
    );
draw->AddText(
    textPos,
    IM_COL32(224, 230, 240, 255),
    label
);
ImGui::PopID();
return clicked;

}

#pragma mark - ImGui View

@interface ASASECImGuiView : MTKView
@end

@implementation ASASECImGuiView

#pragma mark Hit Testing

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
    if (!gMenuVisible || gMenuCollapsed)
    return NO;
    float right =
    gMenuPosition.x + gMenuSize.x;
    float bottom =
    gMenuPosition.y + gMenuSize.y;
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
* (UIView *)hitTest:(CGPoint)point
    withEvent:(UIEvent *)event
    {
    if (!gInitialized || !gMenuVisible)
    return nil;
    if ([self pointInsideMenu:point])
    return self;
    return nil;
    }

#pragma mark Dragging

* (void)beginMenuDragAtPoint:(CGPoint)point
    {
    gDraggingMenu = YES;
    gResizingMenu = NO;
    gDragStartPoint = point;
    gDragStartPosition = gMenuPosition;
    }
* (void)updateMenuDragAtPoint:(CGPoint)point
    {
    if (!gDraggingMenu)
    return;
    CGFloat dx =
    point.x - gDragStartPoint.x;
    CGFloat dy =
    point.y - gDragStartPoint.y;
    gMenuPosition.x =
    gDragStartPosition.x + (float)dx;
    gMenuPosition.y =
    gDragStartPosition.y + (float)dy;
    [self clampMenuPosition];
    }

#pragma mark Resizing

* (void)beginMenuResizeAtPoint:(CGPoint)point
    {
    if (gMenuCollapsed)
    return;
    gResizingMenu = YES;
    gDraggingMenu = NO;
    gResizeStartPoint = point;
    gResizeStartSize = gMenuSize;
    }
* (void)updateMenuResizeAtPoint:(CGPoint)point
    {
    if (!gResizingMenu)
    return;
    CGFloat dx =
    point.x - gResizeStartPoint.x;
    CGFloat dy =
    point.y - gResizeStartPoint.y;
    float newWidth =
    gResizeStartSize.x + (float)dx;
    float newHeight =
    gResizeStartSize.y + (float)dy;
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
    UIWindow *window = self.window;
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
  if (availableWidth < kMenuMinWidth)
      availableWidth = kMenuMinWidth;
  if (availableHeight < kMenuMinHeight)
      availableHeight = kMenuMinHeight;
  newWidth =
      MIN(newWidth, availableWidth);
  newHeight =
      MIN(newHeight, availableHeight);

    }
    gMenuSize.x = newWidth;
    gMenuSize.y = newHeight;
    }
* (void)endMenuInteraction
    {
    gDraggingMenu = NO;
    gResizingMenu = NO;
    }
* (void)clampMenuPosition
    {
    UIWindow *window = self.window;
    if (window)
    ASASECClampMenuToScreen(window);
    }

#pragma mark Touch -> ImGui

* (void)updateIOWithTouchEvent:(UIEvent *)event
    {
    if (!gInitialized)
    return;
    UITouch *touch =
    event.allTouches.anyObject;
    if (!touch)
    return;
    CGPoint point =
    [touch locationInView:self];
    ImGuiIO &io =
    ImGui::GetIO();
    io.MousePos =
    ImVec2(
    (float)point.x,
    (float)point.y
    );
    BOOL touching = NO;
    for (UITouch *t in event.allTouches)
    {
    if (t.phase != UITouchPhaseEnded &&
    t.phase != UITouchPhaseCancelled)
    {
    touching = YES;
    break;
    }
    }
    io.MouseDown[0] = touching;
    }

#pragma mark Touches

* (void)touchesBegan:(NSSet<UITouch *> *)touches
    withEvent:(UIEvent *)event
    {
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

    }
    [self updateIOWithTouchEvent:event];
    }
* (void)touchesMoved:(NSSet<UITouch *> *)touches
    withEvent:(UIEvent *)event
    {
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

    }
    [self updateIOWithTouchEvent:event];
    }
* (void)touchesEnded:(NSSet<UITouch *> *)touches
    withEvent:(UIEvent *)event
    {
    [self endMenuInteraction];
    [self updateIOWithTouchEvent:event];
    ImGuiIO &io =
    ImGui::GetIO();
    io.MouseDown[0] = false;
    }
* (void)touchesCancelled:(NSSet<UITouch *> *)touches
    withEvent:(UIEvent *)event
    {
    [self endMenuInteraction];
    [self updateIOWithTouchEvent:event];
    ImGuiIO &io =
    ImGui::GetIO();
    io.MouseDown[0] = false;
    }

@end

#pragma mark - Renderer

@interface ASASECImGuiRenderer : NSObject 
@end

@implementation ASASECImGuiRenderer

* (void)mtkView:(MTKView *)view
    drawableSizeWillChange:(CGSize)size
    {
    if (!gInitialized)
    return;
    ImGuiIO &io =
    ImGui::GetIO();
    io.DisplaySize =
    ImVec2(
    (float)view.bounds.size.width,
    (float)view.bounds.size.height
    );
    io.DisplayFramebufferScale =
    ImVec2(
    view.contentScaleFactor,
    view.contentScaleFactor
    );
    }
* (void)drawInMTKView:(MTKView *)view
    {
    if (!gInitialized)
    return;
    if (!gCommandQueue)
    return;
    MTLRenderPassDescriptor *pass =
    view.currentRenderPassDescriptor;
    id drawable =
    view.currentDrawable;
    if (!pass || !drawable)
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
    io.DisplayFramebufferScale =
    ImVec2(
    view.contentScaleFactor,
    view.contentScaleFactor
    );
    float fps =
    (float)view.preferredFramesPerSecond;
    if (fps <= 0.0f)
    fps = 60.0f;
    io.DeltaTime =
    0f / fps;
    ImGui::NewFrame();
    if (gMenuVisible)
    {
    const float sidebarWidth = 145.0f;

  float windowHeight =
      gMenuCollapsed
      ? kHeaderHeight
      : gMenuSize.y;
  ImGui::SetNextWindowPos(
      gMenuPosition,
      ImGuiCond_Always
  );
  ImGui::SetNextWindowSize(
      ImVec2(
          gMenuSize.x,
          windowHeight
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
  ImGui::Begin(
      "##ASASEC_WINDOW",
      NULL,
      flags
  );
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
      IM_COL32(46, 59, 81, 200),
      20.0f,
      0,
      1.0f
  );
  if (gMenuCollapsed)
  {
      draw->AddRectFilled(
          windowPos,
          ImVec2(
              windowEnd.x,
              windowPos.y + kHeaderHeight
          ),
          IM_COL32(10, 15, 25, 255),
          20.0f
      );
      draw->AddLine(
          ImVec2(
              windowPos.x + 18.0f,
              windowPos.y + kHeaderHeight - 1.0f
          ),
          ImVec2(
              windowEnd.x - 18.0f,
              windowPos.y + kHeaderHeight - 1.0f
          ),
          IM_COL32(52, 119, 218, 150),
          1.0f
      );
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
          "ASASEC"
      );
      ImGui::SameLine(
          0.0f,
          6.0f
      );
      ImGui::TextColored(
          ImVec4(
              0.43f,
              0.49f,
              0.59f,
              1.0f
          ),
          "CONTROL"
      );
      ImGui::SetCursorPos(
          ImVec2(
              windowSize.x - 70.0f,
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
              0.07f,
              0.11f,
              0.18f,
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
      if (ImGui::Button(
          "+",
          ImVec2(28.0f, 32.0f)
      ))
      {
          gMenuCollapsed = NO;
          UIWindow *window =
              view.window;
          if (window)
              ASASECClampMenuToScreen(window);
      }
      ImGui::PopStyleColor(3);
      ImGui::PopStyleVar();
      ImGui::SameLine(
          0.0f,
          6.0f
      );
      ImGui::PushStyleVar(
          ImGuiStyleVar_FrameRounding,
          10.0f
      );
      ImGui::PushStyleColor(
          ImGuiCol_Button,
          ImVec4(
              0.32f,
              0.055f,
              0.085f,
              1.0f
          )
      );
      ImGui::PushStyleColor(
          ImGuiCol_ButtonHovered,
          ImVec4(
              0.55f,
              0.09f,
              0.14f,
              1.0f
          )
      );
      ImGui::PushStyleColor(
          ImGuiCol_ButtonActive,
          ImVec4(
              0.70f,
              0.13f,
              0.19f,
              1.0f
          )
      );
      if (ImGui::Button(
          "x",
          ImVec2(28.0f, 32.0f)
      ))
      {
          gMenuVisible = NO;
      }
      ImGui::PopStyleColor(3);
      ImGui::PopStyleVar();
  }
  else
  {
      #pragma mark Sidebar
      draw->AddRectFilled(
          windowPos,
          ImVec2(
              windowPos.x + sidebarWidth,
              windowEnd.y
          ),
          IM_COL32(9, 14, 24, 255),
          20.0f,
          ImDrawFlags_RoundCornersLeft
      );
      draw->AddLine(
          ImVec2(
              windowPos.x + sidebarWidth,
              windowPos.y + 16.0f
          ),
          ImVec2(
              windowPos.x + sidebarWidth,
              windowEnd.y - 16.0f
          ),
          IM_COL32(35, 45, 62, 220),
          1.0f
      );
      ImGui::SetCursorPos(
          ImVec2(18.0f, 13.0f)
      );
      ImGui::TextColored(
          ImVec4(
              0.30f,
              0.68f,
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
              0.46f,
              0.51f,
              0.60f,
              1.0f
          ),
          "UI"
      );
      ImGui::SetCursorPos(
          ImVec2(18.0f, 36.0f)
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
      draw->AddLine(
          ImVec2(
              windowPos.x + 18.0f,
              windowPos.y + 57.0f
          ),
          ImVec2(
              windowPos.x + sidebarWidth - 18.0f,
              windowPos.y + 57.0f
          ),
          IM_COL32(35, 44, 60, 190),
          1.0f
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
              72.0f + i * 53.0f;
          if (active)
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
                      windowPos.y + itemY + 9.0f
                  ),
                  ImVec2(
                      windowPos.x + 12.0f,
                      windowPos.y + itemY + 33.0f
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
      #pragma mark Content
      ImGui::SetCursorPos(
          ImVec2(
              sidebarWidth + 1.0f,
              0.0f
          )
      );
      float contentWidth =
          windowSize.x -
          sidebarWidth -
          1.0f;
      float contentHeight =
          windowSize.y;
      ImGui::BeginChild(
          "##Content",
          ImVec2(
              contentWidth,
              contentHeight
          ),
          false,
          ImGuiWindowFlags_None
      );
      #pragma mark Header
      ImGui::SetCursorPos(
          ImVec2(15.0f, 9.0f)
      );
      ImGui::TextColored(
          ImVec4(
              0.94f,
              0.97f,
              1.0f,
              1.0f
          ),
          "%s",
          pages[gSelectedPage]
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
      ImGui::SetCursorPos(
          ImVec2(
              contentWidth - 70.0f,
              8.0f
          )
      );
      ImGui::PushStyleVar(
          ImGuiStyleVar_FrameRounding,
          9.0f
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
              0.18f,
              0.28f,
              1.0f
          )
      );
      ImGui::PushStyleColor(
          ImGuiCol_ButtonActive,
          ImVec4(
              0.17f,
              0.27f,
              0.42f,
              1.0f
          )
      );
      if (ImGui::Button(
          "-",
          ImVec2(28.0f, 32.0f)
      ))
      {
          gMenuCollapsed = YES;
          UIWindow *window =
              view.window;
          if (window)
              ASASECClampMenuToScreen(window);
      }
      ImGui::PopStyleColor(3);
      ImGui::PopStyleVar();
      ImGui::SameLine(
          0.0f,
          6.0f
      );
      ImGui::PushStyleVar(
          ImGuiStyleVar_FrameRounding,
          9.0f
      );
      ImGui::PushStyleColor(
          ImGuiCol_Button,
          ImVec4(
              0.32f,
              0.055f,
              0.085f,
              1.0f
          )
      );
      ImGui::PushStyleColor(
          ImGuiCol_ButtonHovered,
          ImVec4(
              0.55f,
              0.09f,
              0.14f,
              1.0f
          )
      );
      ImGui::PushStyleColor(
          ImGuiCol_ButtonActive,
          ImVec4(
              0.70f,
              0.13f,
              0.19f,
              1.0f
          )
      );
      if (ImGui::Button(
          "x",
          ImVec2(28.0f, 32.0f)
      ))
      {
          gMenuVisible = NO;
      }
      ImGui::PopStyleColor(3);
      ImGui::PopStyleVar();
      draw->AddLine(
          ImVec2(
              windowPos.x +
              sidebarWidth + 16.0f,
              windowPos.y + 51.0f
          ),
          ImVec2(
              windowEnd.x - 16.0f,
              windowPos.y + 51.0f
          ),
          IM_COL32(32, 41, 56, 220),
          1.0f
      );
      #pragma mark Internal Scroll Area
      ImGui::SetCursorPos(
          ImVec2(
              14.0f,
              63.0f
          )
      );
      ImVec2 scrollSize =
          ImVec2(
              contentWidth - 28.0f,
              contentHeight - 70.0f
          );
      ImGui::PushStyleVar(
          ImGuiStyleVar_ChildRounding,
          13.0f
      );
      ImGui::PushStyleVar(
          ImGuiStyleVar_ScrollbarSize,
          9.0f
      );
      ImGui::PushStyleColor(
          ImGuiCol_ChildBg,
          ImVec4(
              0.025f,
              0.034f,
              0.052f,
              0.55f
          )
      );
      ImGui::PushStyleColor(
          ImGuiCol_ScrollbarBg,
          ImVec4(
              0.018f,
              0.024f,
              0.038f,
              0.90f
          )
      );
      ImGui::PushStyleColor(
          ImGuiCol_ScrollbarGrab,
          ImVec4(
              0.18f,
              0.25f,
              0.36f,
              1.0f
          )
      );
      ImGui::PushStyleColor(
          ImGuiCol_ScrollbarGrabHovered,
          ImVec4(
              0.25f,
              0.39f,
              0.58f,
              1.0f
          )
      );
      ImGui::PushStyleColor(
          ImGuiCol_ScrollbarGrabActive,
          ImVec4(
              0.30f,
              0.50f,
              0.75f,
              1.0f
          )
      );
      ImGui::BeginChild(
          "##InternalScroll",
          scrollSize,
          true,
          ImGuiWindowFlags_AlwaysVerticalScrollbar
      );
      #pragma mark Combat
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
          static float fov = 90.0f;
          ImGui::BeginChild(
              "##CombatCard",
              ImVec2(
                  ImGui::GetContentRegionAvail().x - 8.0f,
                  320.0f
              ),
              true
          );
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
          ImGui::Spacing();
          ASASECModernSwitch(
              "Box ESP",
              &esp
          );
          ImGui::Spacing();
          ASASECModernSwitch(
              "Auto Fire",
              &autoFire
          );
          ImGui::Spacing();
          ImGui::Separator();
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
              ImGui::GetContentRegionAvail().x - 8.0f
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
              ImVec2(140.0f, 36.0f)
          ))
          {
              aimbot = false;
              esp = true;
              autoFire = false;
              fov = 90.0f;
          }
          ImGui::EndChild();
          ImGui::Dummy(
              ImVec2(1.0f, 80.0f)
          );
      }
      #pragma mark Visuals
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
          ImGui::BeginChild(
              "##VisualCard",
              ImVec2(
                  ImGui::GetContentRegionAvail().x - 8.0f,
                  290.0f
              ),
              true
          );
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
          ImGui::Spacing();
          ASASECModernSwitch(
              "Health Bar",
              &healthBar
          );
          ImGui::Spacing();
          ASASECModernSwitch(
              "Wallhack",
              &wallhack
          );
          ImGui::EndChild();
          ImGui::Dummy(
              ImVec2(1.0f, 100.0f)
          );
      }
      #pragma mark Settings
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
          ImGui::BeginChild(
              "##SettingsCard",
              ImVec2(
                  ImGui::GetContentRegionAvail().x - 8.0f,
                  270.0f
              ),
              true
          );
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
              ImGui::GetContentRegionAvail().x - 50.0f
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
              ImGui::GetContentRegionAvail().x - 50.0f
          );
          ImGui::Text(
              "Metal"
          );
          ImGui::Spacing();
          ImGui::Text(
              "Status"
          );
          ImGui::SameLine(
              ImGui::GetContentRegionAvail().x - 50.0f
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
          ImGui::EndChild();
          ImGui::Dummy(
              ImVec2(1.0f, 120.0f)
          );
      }
      ImGui::EndChild();
      ImGui::PopStyleColor(5);
      ImGui::PopStyleVar(2);
      #pragma mark Resize Handle
      float handleX =
          windowSize.x - 31.0f;
      float handleY =
          windowSize.y - 31.0f;
      ImVec2 handleBase =
          ImVec2(
              windowPos.x + handleX,
              windowPos.y + handleY
          );
      ImU32 resizeColor =
          gResizingMenu
          ? IM_COL32(108, 181, 255, 235)
          : IM_COL32(190, 198, 211, 135);
      draw->AddLine(
          ImVec2(
              handleBase.x + 5.0f,
              handleBase.y + 22.0f
          ),
          ImVec2(
              handleBase.x + 22.0f,
              handleBase.y + 22.0f
          ),
          resizeColor,
          2.5f
      );
      draw->AddLine(
          ImVec2(
              handleBase.x + 11.0f,
              handleBase.y + 16.0f
          ),
          ImVec2(
              handleBase.x + 22.0f,
              handleBase.y + 16.0f
          ),
          resizeColor,
          2.5f
      );
      draw->AddLine(
          ImVec2(
              handleBase.x + 17.0f,
              handleBase.y + 10.0f
          ),
          ImVec2(
              handleBase.x + 22.0f,
              handleBase.y + 10.0f
          ),
          resizeColor,
          2.5f
      );
      draw->AddLine(
          ImVec2(
              handleBase.x + 22.0f,
              handleBase.y + 10.0f
          ),
          ImVec2(
              handleBase.x + 22.0f,
              handleBase.y + 22.0f
          ),
          resizeColor,
          2.5f
      );
  }
  ImGui::End();
  ImGui::PopStyleColor();
  ImGui::PopStyleVar(2);

    }
    ImGui::Render();
    id encoder =
    [commandBuffer
    renderCommandEncoderWithDescriptor:pass];
    if (!encoder)
    return;
    [encoder setViewport:(MTLViewport){
    0,
    0,
    (double)view.drawableSize.width,
    (double)view.drawableSize.height,
    0,
    0
    }];
    ImGui_ImplMetal_RenderDrawData(
    ImGui::GetDrawData(),
    commandBuffer,
    encoder
    );
    [encoder endEncoding];
    [commandBuffer presentDrawable:drawable];
    [commandBuffer commit];
    }

@end

#pragma mark - Renderer Instance

static ASASECImGuiRenderer *gRenderer = nil;

#pragma mark - Style

static void ASASECApplyStyle(void)
{
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
style.ScrollbarSize =
    9.0f;
style.GrabMinSize =
    15.0f;
style.WindowRounding =
    20.0f;
style.ChildRounding =
    14.0f;
style.FrameRounding =
    9.0f;
style.PopupRounding =
    11.0f;
style.ScrollbarRounding =
    9.0f;
style.GrabRounding =
    9.0f;
style.TabRounding =
    9.0f;
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
c[ImGuiCol_ScrollbarBg] =
    ImVec4(
        0.020f,
        0.027f,
        0.042f,
        0.85f
    );
c[ImGuiCol_ScrollbarGrab] =
    ImVec4(
        0.14f,
        0.20f,
        0.30f,
        1.0f
    );
c[ImGuiCol_ScrollbarGrabHovered] =
    ImVec4(
        0.21f,
        0.32f,
        0.48f,
        1.0f
    );
c[ImGuiCol_ScrollbarGrabActive] =
    ImVec4(
        0.26f,
        0.42f,
        0.63f,
        1.0f
    );

}

#pragma mark - Start

void ASASECImGuiStart(void)
{
if (gInitialized)
return;

dispatch_async(
    dispatch_get_main_queue(),
    ^{
        if (gInitialized)
            return;
        UIWindow *window = nil;
        for (UIScene *scene
             in UIApplication.sharedApplication.connectedScenes)
        {
            if (scene.activationState !=
                UISceneActivationStateForegroundActive)
                continue;
            if (![scene isKindOfClass:
                 [UIWindowScene class]])
                continue;
            UIWindowScene *windowScene =
                (UIWindowScene *)scene;
            for (UIWindow *candidate
                 in windowScene.windows)
            {
                if (candidate.isKeyWindow)
                {
                    window = candidate;
                    break;
                }
            }
            if (window)
                break;
        }
        if (!window)
        {
            for (UIScene *scene
                 in UIApplication.sharedApplication.connectedScenes)
            {
                if (![scene isKindOfClass:
                     [UIWindowScene class]])
                    continue;
                UIWindowScene *windowScene =
                    (UIWindowScene *)scene;
                if (windowScene.windows.count > 0)
                {
                    window =
                        windowScene.windows.firstObject;
                    if (window)
                        break;
                }
            }
        }
        if (!window)
            return;
        id<MTLDevice> device =
            MTLCreateSystemDefaultDevice();
        if (!device)
            return;
        gCommandQueue =
            [device newCommandQueue];
        if (!gCommandQueue)
            return;
        ImGui::CreateContext();
        ImGuiIO &io =
            ImGui::GetIO();
        io.IniFilename = NULL;
        io.FontGlobalScale = 1.0f;
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
        gImGuiView =
            [[ASASECImGuiView alloc]
             initWithFrame:window.bounds
             device:device];
        if (!gImGuiView)
        {
            ImGui::DestroyContext();
            gCommandQueue = nil;
            return;
        }
        gImGuiView.backgroundColor =
            UIColor.clearColor;
        gImGuiView.opaque = NO;
        gImGuiView.clearColor =
            MTLClearColorMake(
                0.0,
                0.0,
                0.0,
                0.0
            );
        gImGuiView.colorPixelFormat =
            MTLPixelFormatBGRA8Unorm;
        gImGuiView.preferredFramesPerSecond =
            60;
        gImGuiView.enableSetNeedsDisplay =
            NO;
        gImGuiView.paused =
            NO;
        gImGuiView.multipleTouchEnabled =
            YES;
        gRenderer =
            [[ASASECImGuiRenderer alloc] init];
        if (!gRenderer)
        {
            gImGuiView = nil;
            ImGui::DestroyContext();
            gCommandQueue = nil;
            return;
        }
        gImGuiView.delegate =
            gRenderer;
        [window addSubview:gImGuiView];
        [window bringSubviewToFront:gImGuiView];
        ImGui_ImplMetal_Init(device);
        gInitialized = YES;
    }
);

}

#pragma mark - Stop

void ASASECImGuiStop(void)
{
dispatch_async(
dispatch_get_main_queue(),
^{
if (!gInitialized)
return;

        gInitialized = NO;
        if (gImGuiView)
        {
            gImGuiView.delegate = nil;
            [gImGuiView removeFromSuperview];
            gImGuiView = nil;
        }
        ImGui_ImplMetal_Shutdown();
        ImGui::DestroyContext();
        gCommandQueue = nil;
        gRenderer = nil;
        gMenuVisible = YES;
        gMenuCollapsed = NO;
        gSelectedPage = 0;
        gDraggingMenu = NO;
        gResizingMenu = NO;
        gDragStartPoint =
            CGPointZero;
        gResizeStartPoint =
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
    }
);

}
