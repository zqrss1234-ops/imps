export TARGET = iphone:14.0:latest
export ARCHS = arm64 arm64e
export TARGET_SUBSTRATE = 0

INSTALL_TARGET_PROCESSES = YallaLite

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = YallaMaster

YallaMaster_FILES = Tweak.xm
YallaMaster_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -fno-logos
YallaMaster_FRAMEWORKS = UIKit Foundation CoreGraphics QuartzCore

include $(THEOS_MAKE_PATH)/tweak.mk
