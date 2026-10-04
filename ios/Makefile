# RetroTok - TikTok viewer for jailbroken iOS 6 (armv7). Built with Theos against the iOS 9.3 SDK,
# deployment target 6.0. Talks plain HTTP to the RetroTok server (../server).

TARGET := iphone:clang:9.3:6.0
ARCHS := armv7
DEBUG ?= 0

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME := RetroTok

RetroTok_FILES := $(wildcard src/*.m)
RetroTok_FRAMEWORKS := UIKit Foundation CoreGraphics QuartzCore AVFoundation CoreMedia
RetroTok_CFLAGS := -Isrc -Os -Wall -Wno-deprecated-declarations -Wno-unknown-warning-option \
                   -Wno-nullability-completeness -Wno-unused-function
RetroTok_OBJCFLAGS := -fobjc-arc -Wunguarded-availability

include $(THEOS)/makefiles/application.mk
