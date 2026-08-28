TARGET := iphone:clang:latest:latest

ARCHS := arm64

include $(THEOS)/makefiles/common.mk

TWEAK_NAME := AsasecMultiTool

AsasecMultiTool_FILES := \
    Asasec/Tweak.xm \
    Imgui/Gui/AsasecImgui.mm \
    Imgui/imgui.cpp \
    Imgui/imgui_draw.cpp \
    Imgui/imgui_tables.cpp \
    Imgui/imgui_widgets.cpp \
    Imgui/Backends/imgui_impl_metal.mm

AsasecMultiTool_CFLAGS := -fobjc-arc
AsasecMultiTool_CCFLAGS := -std=c++17 -fobjc-arc

AsasecMultiTool_FRAMEWORKS := UIKit Metal MetalKit

include $(THEOS_MAKE_PATH)/tweak.mk
