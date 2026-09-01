TARGET := iphone:clang:latest:latest

ARCHS := arm64

include $(THEOS)/makefiles/common.mk

TWEAK_NAME := AsasecMultiTool

AsasecMultiTool_FILES := \
    Asasec.xm \
    ASASECUI/guialert/GuiAlert.m \
    manager/UiManager.mm \
    ASASECUI/imgui/Ui/AsasecUi.mm \
    ASASECUI/imgui/imgui.cpp \
    ASASECUI/imgui/imgui_draw.cpp \
    ASASECUI/imgui/imgui_tables.cpp \
    ASASECUI/imgui/imgui_widgets.cpp \
    ASASECUI/imgui/Backends/imgui_impl_metal.mm

AsasecMultiTool_CFLAGS := \
    -fobjc-arc \
    -Wno-error \
    -IASASECUI/imgui \
    -IASASECUI/imgui/backends

AsasecMultiTool_CCFLAGS := \
    -std=c++17 \
    -fobjc-arc \
    -Wno-error \
    -IASASECUI/imgui \
    -IASASECUI/imgui/backends

AsasecMultiTool_FRAMEWORKS := \
    UIKit \
    Metal \
    MetalKit

include $(THEOS_MAKE_PATH)/tweak.mk
