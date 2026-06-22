export TARGET = iphone:14.0:latest
export ARCHS = arm64 arm64e
export TARGET_SUBSTRATE = 0

INSTALL_TARGET_PROCESSES = YallaLite

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = YallaSlave

YallaSlave_FILES = Tweak.xm
YallaSlave_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -fno-logos
YallaSlave_FRAMEWORKS = UIKit Foundation CoreGraphics QuartzCore

include $(THEOS_MAKE_PATH)/tweak.mk
