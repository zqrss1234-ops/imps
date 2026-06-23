export TARGET = iphone:14.0:latest
export ARCHS = arm64 arm64e
export TARGET_SUBSTRATE = 0

INSTALL_TARGET_PROCESSES = YallaLite

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = YallaAgent

YallaAgent_FILES = Tweak.xm
YallaAgent_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -fno-logos
YallaAgent_FRAMEWORKS = UIKit Foundation CoreGraphics QuartzCore Security

include $(THEOS_MAKE_PATH)/tweak.mk
