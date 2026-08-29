#import “AsasecImgui.h”

#import <UIKit/UIKit.h>
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import <dispatch/dispatch.h>

#define IMGUI_DEFINE_MATH_OPERATORS
#include “../imgui.h”
#include “../imgui_internal.h”
#include “../Backends/imgui_impl_metal.h”

static MTKView *gImGuiView = nil;
static id gCommandQueue = nil;
static BOOL gInitialized = NO;

static BOOL gMenuVisible = YES;
static BOOL gMenuCollapsed = NO;

static ImVec2 gMenuPosition = ImVec2(25.0f, 75.0f);
static ImVec2 gMenuSize = ImVec2(560.0f, 390.0f);

static int gSelectedPage = 0;

/*

DRAG STATE

*/

static BOOL gDraggingMenu = NO;
static CGPoint gDragStartTouch = CGPointZero;
static ImVec2 gDragStartMenuPosition = ImVec2(25.0f, 75.0f);

/*

VIEW

*/

@interface ASASECImGuiView : MTKView
@end

@implementation ASASECImGuiView

* (BOOL)pointInsideMenu:(CGPoint)point
    {
    if (!gMenuVisible)
    return NO;
    float width = gMenuSize.x;
    float height =
    gMenuCollapsed ?
    0f :
    gMenuSize.y;
    return
    point.x >= gMenuPosition.x &&
    point.x <= gMenuPosition.x + width &&
    point.y >= gMenuPosition.y &&
    point.y <= gMenuPosition.y + height;
    }

/*

HIT TEST

*/

* (UIView *)hitTest:(CGPoint)point
    withEvent:(UIEvent *)event
    {
    if (!gInitialized || !gMenuVisible)
    return nil;
    if ([self pointInsideMenu:point])
    return self;
    return nil;
    }

/*

DRAG BEGIN

*/

* (void)beginMenuDragAtPoint:(CGPoint)point
    {
    if (!gMenuVisible)
    return;
    gDraggingMenu = YES;
    gDragStartTouch = point;
    gDragStartMenuPosition =
    gMenuPosition;
    }

/*

DRAG UPDATE

*/

* (void)updateMenuDragAtPoint:(CGPoint)point
    {
    if (!gDraggingMenu)
    return;
    float deltaX =
    (float)point.x -
    (float)gDragStartTouch.x;
    float deltaY =
    (float)point.y -
    (float)gDragStartTouch.y;
    gMenuPosition.x =
    gDragStartMenuPosition.x +
    deltaX;
    gMenuPosition.y =
    gDragStartMenuPosition.y +
    deltaY;
    /*
    * Sol sınır
        */
    if (gMenuPosition.x < 0.0f)
    gMenuPosition.x = 0.0f;
    /*
    * Üst sınır
        */
    if (gMenuPosition.y < 0.0f)
    gMenuPosition.y = 0.0f;
    /*
    * Sağ sınır
        */
    if (self.bounds.size.width > 0.0f)
    {
    float maxX =
    self.bounds.size.width -
    gMenuSize.x;

  if (maxX < 0.0f)
      maxX = 0.0f;
  if (gMenuPosition.x > maxX)
      gMenuPosition.x = maxX;

    }
    /*
    * Alt sınır
        */
    float menuHeight =
    gMenuCollapsed ?
    0f :
    gMenuSize.y;
    if (self.bounds.size.height > 0.0f)
    {
    float maxY =
    self.bounds.size.height -
    menuHeight;

  if (maxY < 0.0f)
      maxY = 0.0f;
  if (gMenuPosition.y > maxY)
      gMenuPosition.y = maxY;

    }
    }

/*

DRAG END

*/

* (void)endMenuDrag
    {
    gDraggingMenu = NO;
    }

/*

IMGUI TOUCH INPUT

*/

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
    /*
    * Modern Dear ImGui input API.
        */
    io.AddMouseSourceEvent(
    ImGuiMouseSource_TouchScreen
    );
    io.AddMousePosEvent(
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
    io.AddMouseButtonEvent(
    0,
    touching
    );
    }

/*

TOUCH BEGIN

*/

* (void)touchesBegan:(NSSet<UITouch *> *)touches
    withEvent:(UIEvent *)event
    {
    [self updateIOWithTouchEvent:event];
    if (!gMenuVisible)
    return;
    UITouch *touch =
    touches.anyObject;
    if (!touch)
    return;
    CGPoint point =
    [touch locationInView:self];
    /*
    * Drag başlatma ImGui tarafından
    * başlık alanı aktif olduğunda yapılır.
        */
        }

/*

TOUCH MOVE

*/

* (void)touchesMoved:(NSSet<UITouch *> *)touches
    withEvent:(UIEvent *)event
    {
    [self updateIOWithTouchEvent:event];
    if (!gDraggingMenu)
    return;
    UITouch *touch =
    touches.anyObject;
    if (!touch)
    return;
    CGPoint point =
    [touch locationInView:self];
    [self updateMenuDragAtPoint:point];
    }

/*

TOUCH END

*/

* (void)touchesEnded:(NSSet<UITouch *> *)touches
    withEvent:(UIEvent *)event
    {
    [self updateIOWithTouchEvent:event];
    [self endMenuDrag];
    }

/*

TOUCH CANCEL

*/

* (void)touchesCancelled:(NSSet<UITouch *> *)touches
    withEvent:(UIEvent *)event
    {
    [self updateIOWithTouchEvent:event];
    [self endMenuDrag];
    }

@end

/*

RENDERER

*/

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
    view.bounds.size.width,
    view.bounds.size.height
    );
    io.DisplayFramebufferScale =
    ImVec2(
    view.contentScaleFactor,
    view.contentScaleFactor
    );
    }
* (void)drawInMTKView:(MTKView *)view
    {
    if (!gInitialized ||
    !gCommandQueue)
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
    view.bounds.size.width,
    view.bounds.size.height
    );
    io.DisplayFramebufferScale =
    ImVec2(
    view.contentScaleFactor,
    view.contentScaleFactor
    );
    float fps =
    view.preferredFramesPerSecond;
    if (fps <= 0.0f)
    fps = 60.0f;
    io.DeltaTime =
    0f / fps;
    ImGui::NewFrame();
    /*
    MENU
    */
    if (gMenuVisible)
    {
    const float headerHeight = 50.0f;
    const float sidebarWidth = 145.0f;

  float windowHeight =
      gMenuCollapsed ?
      headerHeight :
      gMenuSize.y;
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
      ImGuiWindowFlags_NoScrollbar |
      ImGuiWindowFlags_NoScrollWithMouse |
      ImGuiWindowFlags_NoSavedSettings;
  ImGui::PushStyleVar(
      ImGuiStyleVar_WindowPadding,
      ImVec2(0.0f, 0.0f)
  );
  ImGui::PushStyleVar(
      ImGuiStyleVar_WindowRounding,
      18.0f
  );
  ImGui::PushStyleColor(
      ImGuiCol_WindowBg,
      ImVec4(
          0.025f,
          0.032f,
          0.050f,
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
  /*
   * Window position is authoritative.
   */
  gMenuPosition =
      windowPos;
  if (!gMenuCollapsed)
      gMenuSize =
          windowSize;
  ImDrawList *draw =
      ImGui::GetWindowDrawList();
  ImVec2 windowEnd =
      ImVec2(
          windowPos.x + windowSize.x,
          windowPos.y + windowSize.y
      );
  /*
   ========================================================
   WINDOW BACKGROUND
   ========================================================
   */
  draw->AddRectFilled(
      windowPos,
      windowEnd,
      IM_COL32(7, 10, 17, 250),
      18.0f
  );
  /*
   ========================================================
   SUBTLE BORDER
   ========================================================
   */
  draw->AddRect(
      windowPos,
      windowEnd,
      IM_COL32(35, 46, 67, 180),
      18.0f,
      0,
      1.0f
  );
  /*
   ========================================================
   ACCENT
   ========================================================
   */
  draw->AddRectFilled(
      ImVec2(
          windowPos.x + 18.0f,
          windowPos.y + 48.0f
      ),
      ImVec2(
          windowPos.x +
          windowSize.x -
          18.0f,
          windowPos.y + 50.0f
      ),
      IM_COL32(
          62,
          137,
          255,
          230
      ),
      1.0f
  );
  /*
   ========================================================
   COLLAPSED
   ========================================================
   */
  if (gMenuCollapsed)
  {
      draw->AddRectFilled(
          windowPos,
          ImVec2(
              windowPos.x +
              windowSize.x,
              windowPos.y +
              headerHeight
          ),
          IM_COL32(
              10,
              14,
              23,
              252
          ),
          18.0f
      );
      /*
       * Drag area.
       */
      ImGui::SetCursorPos(
          ImVec2(
              14.0f,
              7.0f
          )
      );
      ImGui::InvisibleButton(
          "##CollapsedDragZone",
          ImVec2(
              windowSize.x - 88.0f,
              36.0f
          )
      );
      if (ImGui::IsItemActivated())
      {
          CGPoint point =
              CGPointMake(
                  io.MousePos.x,
                  io.MousePos.y
              );
          [gImGuiView
              beginMenuDragAtPoint:point];
      }
      /*
       * Logo.
       */
      ImGui::SetCursorPos(
          ImVec2(
              18.0f,
              10.0f
          )
      );
      ImGui::TextColored(
          ImVec4(
              0.30f,
              0.65f,
              1.0f,
              1.0f
          ),
          "ASASEC"
      );
      ImGui::SameLine();
      ImGui::TextColored(
          ImVec4(
              0.46f,
              0.50f,
              0.59f,
              1.0f
          ),
          "CONTROL"
      );
      /*
       * Expand.
       */
      ImGui::SetCursorPos(
          ImVec2(
              windowSize.x - 68.0f,
              9.0f
          )
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
              0.33f,
              1.0f
          )
      );
      ImGui::PushStyleColor(
          ImGuiCol_ButtonActive,
          ImVec4(
              0.16f,
              0.28f,
              0.45f,
              1.0f
          )
      );
      if (ImGui::Button(
          "+",
          ImVec2(
              28.0f,
              30.0f
          )
      ))
      {
          gMenuCollapsed = NO;
      }
      ImGui::PopStyleColor(3);
      /*
       * Close.
       */
      ImGui::SameLine(
          0.0f,
          6.0f
      );
      ImGui::PushStyleColor(
          ImGuiCol_Button,
          ImVec4(
              0.28f,
              0.06f,
              0.09f,
              1.0f
          )
      );
      ImGui::PushStyleColor(
          ImGuiCol_ButtonHovered,
          ImVec4(
              0.55f,
              0.10f,
              0.15f,
              1.0f
          )
      );
      ImGui::PushStyleColor(
          ImGuiCol_ButtonActive,
          ImVec4(
              0.70f,
              0.14f,
              0.20f,
              1.0f
          )
      );
      if (ImGui::Button(
          "×",
          ImVec2(
              28.0f,
              30.0f
          )
      ))
      {
          gMenuVisible = NO;
      }
      ImGui::PopStyleColor(3);
  }
  /*
   ========================================================
   EXPANDED
   ========================================================
   */
  else
  {
      /*
       * Sidebar.
       */
      draw->AddRectFilled(
          windowPos,
          ImVec2(
              windowPos.x +
              sidebarWidth,
              windowPos.y +
              windowSize.y
          ),
          IM_COL32(
              10,
              14,
              23,
              255
          ),
          18.0f,
          ImDrawFlags_RoundCornersLeft
      );
      /*
       * Sidebar separator.
       */
      draw->AddLine(
          ImVec2(
              windowPos.x +
              sidebarWidth,
              windowPos.y +
              16.0f
          ),
          ImVec2(
              windowPos.x +
              sidebarWidth,
              windowPos.y +
              windowSize.y -
              16.0f
          ),
          IM_COL32(
              27,
              35,
              50,
              220
          ),
          1.0f
      );
      /*
       * Logo.
       */
      ImGui::SetCursorPos(
          ImVec2(
              18.0f,
              13.0f
          )
      );
      ImGui::TextColored(
          ImVec4(
              0.30f,
              0.65f,
              1.0f,
              1.0f
          ),
          "ASASEC"
      );
      ImGui::SameLine();
      ImGui::TextColored(
          ImVec4(
              0.42f,
              0.47f,
              0.56f,
              1.0f
          ),
          "UI"
      );
      /*
       * Subtitle.
       */
      ImGui::SetCursorPos(
          ImVec2(
              18.0f,
              35.0f
          )
      );
      ImGui::TextColored(
          ImVec4(
              0.28f,
              0.32f,
              0.40f,
              1.0f
          ),
          "CONTROL CENTER"
      );
      /*
       * Navigation.
       */
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
      ImGui::SetCursorPos(
          ImVec2(
              10.0f,
              66.0f
          )
      );
      for (int i = 0; i < 3; i++)
      {
          bool active =
              gSelectedPage == i;
          float itemY =
              66.0f +
              i * 50.0f;
          if (active)
          {
              draw->AddRectFilled(
                  ImVec2(
                      windowPos.x + 10.0f,
                      windowPos.y + itemY
                  ),
                  ImVec2(
                      windowPos.x +
                      sidebarWidth -
                      10.0f,
                      windowPos.y +
                      itemY +
                      40.0f
                  ),
                  IM_COL32(
                      20,
                      54,
                      99,
                      255
                  ),
                  10.0f
              );
              draw->AddRectFilled(
                  ImVec2(
                      windowPos.x + 10.0f,
                      windowPos.y +
                      itemY +
                      9.0f
                  ),
                  ImVec2(
                      windowPos.x + 13.0f,
                      windowPos.y +
                      itemY +
                      31.0f
                  ),
                  IM_COL32(
                      65,
                      145,
                      255,
                      255
                  ),
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
                  0.28f,
                  0.75f
              )
          );
          ImGui::PushStyleColor(
              ImGuiCol_ButtonActive,
              ImVec4(
                  0.12f,
                  0.23f,
                  0.38f,
                  1.0f
              )
          );
          if (ImGui::Button(
              id,
              ImVec2(
                  sidebarWidth -
                  20.0f,
                  40.0f
              )
          ))
          {
              gSelectedPage = i;
          }
          ImGui::PopStyleColor(3);
          ImGui::SetCursorPosY(
              ImGui::GetCursorPosY() +
              10.0f
          );
      }
      /*
       * Content area.
       */
      ImGui::SetCursorPos(
          ImVec2(
              sidebarWidth + 1.0f,
              0.0f
          )
      );
      ImGui::BeginChild(
          "##Content",
          ImVec2(
              windowSize.x -
              sidebarWidth -
              1.0f,
              windowSize.y
          ),
          false,
          ImGuiWindowFlags_NoScrollbar
      );
      /*
       * Expanded drag zone.
       */
      ImGui::SetCursorPos(
          ImVec2(
              14.0f,
              8.0f
          )
      );
      ImGui::InvisibleButton(
          "##ExpandedDragZone",
          ImVec2(
              windowSize.x -
              sidebarWidth -
              90.0f,
              34.0f
          )
      );
      if (ImGui::IsItemActivated())
      {
          CGPoint point =
              CGPointMake(
                  io.MousePos.x,
                  io.MousePos.y
              );
          [gImGuiView
              beginMenuDragAtPoint:point];
      }
      /*
       * Page title.
       */
      ImGui::SetCursorPos(
          ImVec2(
              15.0f,
              10.0f
          )
      );
      ImGui::TextColored(
          ImVec4(
              0.94f,
              0.96f,
              1.0f,
              1.0f
          ),
          "%s",
          pages[gSelectedPage]
      );
      ImGui::SameLine();
      ImGui::TextColored(
          ImVec4(
              0.30f,
              0.35f,
              0.44f,
              1.0f
          ),
          " / ASASEC"
      );
      /*
       * Collapse.
       */
      ImGui::SetCursorPos(
          ImVec2(
              windowSize.x -
              sidebarWidth -
              70.0f,
              8.0f
          )
      );
      ImGui::PushStyleColor(
          ImGuiCol_Button,
          ImVec4(
              0.07f,
              0.10f,
              0.16f,
              1.0f
          )
      );
      ImGui::PushStyleColor(
          ImGuiCol_ButtonHovered,
          ImVec4(
              0.12f,
              0.18f,
              0.29f,
              1.0f
          )
      );
      if (ImGui::Button(
          "—",
          ImVec2(
              28.0f,
              30.0f
          )
      ))
      {
          gMenuCollapsed = YES;
      }
      ImGui::PopStyleColor(2);
      /*
       * Close.
       */
      ImGui::SameLine(
          0.0f,
          6.0f
      );
      ImGui::PushStyleColor(
          ImGuiCol_Button,
          ImVec4(
              0.28f,
              0.06f,
              0.09f,
              1.0f
          )
      );
      ImGui::PushStyleColor(
          ImGuiCol_ButtonHovered,
          ImVec4(
              0.55f,
              0.10f,
              0.15f,
              1.0f
          )
      );
      ImGui::PushStyleColor(
          ImGuiCol_ButtonActive,
          ImVec4(
              0.70f,
              0.14f,
              0.20f,
              1.0f
          )
      );
      if (ImGui::Button(
          "×",
          ImVec2(
              28.0f,
              30.0f
          )
      ))
      {
          gMenuVisible = NO;
      }
      ImGui::PopStyleColor(3);
      /*
       * Divider.
       */
      ImGui::SetCursorPosY(
          54.0f
      );
      ImGui::Separator();
      ImGui::SetCursorPosY(
          72.0f
      );
      /*
       ========================================================
       COMBAT
       ========================================================
       */
      if (gSelectedPage == 0)
      {
          ImGui::TextColored(
              ImVec4(
                  0.30f,
                  0.65f,
                  1.0f,
                  1.0f
              ),
              "COMBAT"
          );
          ImGui::SameLine();
          ImGui::TextColored(
              ImVec4(
                  0.32f,
                  0.37f,
                  0.45f,
                  1.0f
              ),
              "ACTIONS"
          );
          ImGui::TextColored(
              ImVec4(
                  0.40f,
                  0.44f,
                  0.52f,
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
                  ImGui::GetContentRegionAvail().x -
                  18.0f,
                  265.0f
              ),
              true
          );
          ImGui::TextColored(
              ImVec4(
                  0.92f,
                  0.95f,
                  1.0f,
                  1.0f
              ),
              "Combat Features"
          );
          ImGui::TextColored(
              ImVec4(
                  0.35f,
                  0.40f,
                  0.49f,
                  1.0f
              ),
              "Main configuration"
          );
          ImGui::Spacing();
          ImGui::Separator();
          ImGui::Spacing();
          ImGui::Checkbox(
              "Enable Aimbot",
              &aimbot
          );
          ImGui::Checkbox(
              "Box ESP",
              &esp
          );
          ImGui::Checkbox(
              "Auto Fire",
              &autoFire
          );
          ImGui::Spacing();
          ImGui::Text(
              "FOV Radius"
          );
          ImGui::SetNextItemWidth(
              ImGui::GetContentRegionAvail().x -
              10.0f
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
                  125.0f,
                  34.0f
              )
          ))
          {
              aimbot = false;
              esp = true;
              autoFire = false;
              fov = 90.0f;
          }
          ImGui::EndChild();
      }
      /*
       ========================================================
       VISUALS
       ========================================================
       */
      else if (gSelectedPage == 1)
      {
          ImGui::TextColored(
              ImVec4(
                  0.30f,
                  0.85f,
                  0.58f,
                  1.0f
              ),
              "VISUALS"
          );
          ImGui::SameLine();
          ImGui::TextColored(
              ImVec4(
                  0.32f,
                  0.37f,
                  0.45f,
                  1.0f
              ),
              "ESP"
          );
          ImGui::TextColored(
              ImVec4(
                  0.40f,
                  0.44f,
                  0.52f,
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
                  ImGui::GetContentRegionAvail().x -
                  18.0f,
                  220.0f
              ),
              true
          );
          ImGui::TextColored(
              ImVec4(
                  0.92f,
                  0.95f,
                  1.0f,
                  1.0f
              ),
              "ESP Features"
          );
          ImGui::TextColored(
              ImVec4(
                  0.35f,
                  0.40f,
                  0.49f,
                  1.0f
              ),
              "Visual configuration"
          );
          ImGui::Spacing();
          ImGui::Separator();
          ImGui::Spacing();
          ImGui::Checkbox(
              "Player ESP",
              &playerESP
          );
          ImGui::Checkbox(
              "Health Bar",
              &healthBar
          );
          ImGui::Checkbox(
              "Wallhack",
              &wallhack
          );
          ImGui::EndChild();
      }
      /*
       ========================================================
       SETTINGS
       ========================================================
       */
      else
      {
          ImGui::TextColored(
              ImVec4(
                  1.0f,
                  0.65f,
                  0.28f,
                  1.0f
              ),
              "SETTINGS"
          );
          ImGui::SameLine();
          ImGui::TextColored(
              ImVec4(
                  0.32f,
                  0.37f,
                  0.45f,
                  1.0f
              ),
              "SYSTEM"
          );
          ImGui::TextColored(
              ImVec4(
                  0.40f,
                  0.44f,
                  0.52f,
                  1.0f
              ),
              "ASASEC configuration"
          );
          ImGui::Spacing();
          ImGui::BeginChild(
              "##SettingsCard",
              ImVec2(
                  ImGui::GetContentRegionAvail().x -
                  18.0f,
                  220.0f
              ),
              true
          );
          ImGui::TextColored(
              ImVec4(
                  0.92f,
                  0.95f,
                  1.0f,
                  1.0f
              ),
              "Application"
          );
          ImGui::TextColored(
              ImVec4(
                  0.35f,
                  0.40f,
                  0.49f,
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
              ImGui::GetContentRegionAvail().x -
              55.0f
          );
          ImGui::TextColored(
              ImVec4(
                  0.30f,
                  0.65f,
                  1.0f,
                  1.0f
              ),
              "3.0"
          );
          ImGui::Spacing();
          ImGui::Text(
              "Renderer"
          );
          ImGui::SameLine(
              ImGui::GetContentRegionAvail().x -
              55.0f
          );
          ImGui::Text(
              "Metal"
          );
          ImGui::Spacing();
          ImGui::Text(
              "Status"
          );
          ImGui::SameLine(
              ImGui::GetContentRegionAvail().x -
              55.0f
          );
          ImGui::TextColored(
              ImVec4(
                  0.30f,
                  0.85f,
                  0.55f,
                  1.0f
              ),
              "ACTIVE"
          );
          ImGui::EndChild();
      }
      ImGui::EndChild();
  }
  ImGui::End();
  ImGui::PopStyleColor();
  ImGui::PopStyleVar(2);

    }
    /*
    RENDER
    */
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

static ASASECImGuiRenderer *gRenderer = nil;

/*

STYLE

*/

static void ASASECApplyStyle(void)
{
ImGuiStyle &style =
ImGui::GetStyle();

style.WindowPadding =
    ImVec2(
        10.0f,
        10.0f
    );
style.FramePadding =
    ImVec2(
        10.0f,
        7.0f
    );
style.ItemSpacing =
    ImVec2(
        8.0f,
        8.0f
    );
style.ItemInnerSpacing =
    ImVec2(
        7.0f,
        6.0f
    );
style.ScrollbarSize =
    7.0f;
style.GrabMinSize =
    12.0f;
style.WindowRounding =
    18.0f;
style.ChildRounding =
    12.0f;
style.FrameRounding =
    8.0f;
style.PopupRounding =
    10.0f;
style.ScrollbarRounding =
    8.0f;
style.GrabRounding =
    8.0f;
style.TabRounding =
    8.0f;
style.WindowBorderSize =
    0.0f;
style.ChildBorderSize =
    1.0f;
style.FrameBorderSize =
    0.0f;
/*
 * Better touch targets.
 */
style.TouchExtraPadding =
    ImVec2(
        3.0f,
        3.0f
    );
style.WindowTitleAlign =
    ImVec2(
        0.5f,
        0.5f
    );
ImVec4 *c =
    style.Colors;
c[ImGuiCol_Text] =
    ImVec4(
        0.92f,
        0.95f,
        1.0f,
        1.0f
    );
c[ImGuiCol_TextDisabled] =
    ImVec4(
        0.40f,
        0.44f,
        0.52f,
        1.0f
    );
c[ImGuiCol_WindowBg] =
    ImVec4(
        0.025f,
        0.032f,
        0.050f,
        0.985f
    );
c[ImGuiCol_ChildBg] =
    ImVec4(
        0.045f,
        0.056f,
        0.080f,
        0.98f
    );
c[ImGuiCol_Border] =
    ImVec4(
        0.12f,
        0.15f,
        0.21f,
        0.75f
    );
c[ImGuiCol_FrameBg] =
    ImVec4(
        0.065f,
        0.080f,
        0.115f,
        1.0f
    );
c[ImGuiCol_FrameBgHovered] =
    ImVec4(
        0.10f,
        0.13f,
        0.19f,
        1.0f
    );
c[ImGuiCol_FrameBgActive] =
    ImVec4(
        0.13f,
        0.19f,
        0.29f,
        1.0f
    );
c[ImGuiCol_Button] =
    ImVec4(
        0.065f,
        0.085f,
        0.125f,
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
        0.28f,
        0.65f,
        1.0f,
        1.0f
    );
c[ImGuiCol_SliderGrab] =
    ImVec4(
        0.22f,
        0.55f,
        1.0f,
        1.0f
    );
c[ImGuiCol_SliderGrabActive] =
    ImVec4(
        0.35f,
        0.68f,
        1.0f,
        1.0f
    );
c[ImGuiCol_Header] =
    ImVec4(
        0.10f,
        0.16f,
        0.25f,
        1.0f
    );
c[ImGuiCol_HeaderHovered] =
    ImVec4(
        0.14f,
        0.22f,
        0.35f,
        1.0f
    );
c[ImGuiCol_HeaderActive] =
    ImVec4(
        0.17f,
        0.29f,
        0.46f,
        1.0f
    );
c[ImGuiCol_Separator] =
    ImVec4(
        0.12f,
        0.15f,
        0.21f,
        0.75f
    );
c[ImGuiCol_ScrollbarBg] =
    ImVec4(
        0.025f,
        0.032f,
        0.050f,
        0.8f
    );
c[ImGuiCol_ScrollbarGrab] =
    ImVec4(
        0.12f,
        0.16f,
        0.23f,
        1.0f
    );
c[ImGuiCol_ScrollbarGrabHovered] =
    ImVec4(
        0.18f,
        0.25f,
        0.36f,
        1.0f
    );
c[ImGuiCol_ScrollbarGrabActive] =
    ImVec4(
        0.22f,
        0.34f,
        0.50f,
        1.0f
    );

}

/*

START

*/

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
            return;
        /*
         * Metal device.
         */
        id<MTLDevice> device =
            MTLCreateSystemDefaultDevice();
        if (!device)
            return;
        gCommandQueue =
            [device newCommandQueue];
        if (!gCommandQueue)
            return;
        /*
         * ImGui context.
         */
        ImGui::CreateContext();
        ImGuiIO &io =
            ImGui::GetIO();
        io.IniFilename = NULL;
        io.FontGlobalScale =
            1.0f;
        io.DisplaySize =
            ImVec2(
                window.bounds.size.width,
                window.bounds.size.height
            );
        CGFloat scale =
            window.screen.scale;
        if (scale <= 0.0)
            scale = 1.0;
        io.DisplayFramebufferScale =
            ImVec2(
                scale,
                scale
            );
        /*
         * Style.
         */
        ASASECApplyStyle();
        /*
         * Metal view.
         */
        gImGuiView =
            [[ASASECImGuiView alloc]
                initWithFrame:window.bounds
                device:device];
        gImGuiView.backgroundColor =
            UIColor.clearColor;
        gImGuiView.opaque =
            NO;
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
            NO;
        /*
         * Renderer.
         */
        gRenderer =
            [[ASASECImGuiRenderer alloc]
                init];
        gImGuiView.delegate =
            gRenderer;
        /*
         * Add overlay.
         */
        [window addSubview:gImGuiView];
        [window bringSubviewToFront:gImGuiView];
        /*
         * Initialize Metal backend.
         */
        ImGui_ImplMetal_Init(device);
        gInitialized =
            YES;
    }
);

}

/*

STOP

*/

void ASASECImGuiStop(void)
{
dispatch_async(
dispatch_get_main_queue(),
^{
if (!gInitialized)
return;

        gInitialized =
            NO;
        gDraggingMenu =
            NO;
        if (gImGuiView)
        {
            gImGuiView.delegate =
                nil;
            [gImGuiView removeFromSuperview];
            gImGuiView =
                nil;
        }
        ImGui_ImplMetal_Shutdown();
        ImGui::DestroyContext();
        gCommandQueue =
            nil;
        gRenderer =
            nil;
        gMenuVisible =
            YES;
        gMenuCollapsed =
            NO;
        gSelectedPage =
            0;
        gMenuPosition =
            ImVec2(
                25.0f,
                75.0f
            );
        gMenuSize =
            ImVec2(
                560.0f,
                390.0f
            );
        gDragStartTouch =
            CGPointZero;
        gDragStartMenuPosition =
            gMenuPosition;
    }
);

}
