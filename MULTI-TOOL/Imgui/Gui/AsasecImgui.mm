#import "AsasecImgui.h"

#import <UIKit/UIKit.h>
#import <Metal/Metal.h>

#include "../imgui.h"
#include "../Backends/imgui_impl_metal.h"

static bool g_ImGuiInitialized = false;

void ASASECImGuiStart(void)
{
    if (g_ImGuiInitialized)
        return;

    g_ImGuiInitialized = true;

    ImGui::CreateContext();

    ImGuiIO& io = ImGui::GetIO();

    io.IniFilename = nullptr;

    ImGui::StyleColorsDark();

    NSLog(@"[ASASEC] Dear ImGui initialized");
}

void ASASECImGuiStop(void)
{
    if (!g_ImGuiInitialized)
        return;

    g_ImGuiInitialized = false;

    ImGui::DestroyContext();

    NSLog(@"[ASASEC] Dear ImGui stopped");
}
