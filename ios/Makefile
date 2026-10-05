# LegacyTikTok - standalone TikTok viewer for jailbroken iOS 6 (armv7). Built with Theos against the iOS 9.3 SDK,
# deployment target 6.0. Talks to TikTok directly through the bundled mbedTLS (vendor/, fetched on first build).
# Installs to /Applications/LegacyTikTok.app. The optional RetroTok server (../server) is not needed.

TARGET := iphone:clang:9.3:6.0
ARCHS := armv7
DEBUG ?= 0

ifeq ($(wildcard vendor/mbedtls/library/ssl_tls.c),)
$(info Fetching mbedTLS...)
$(shell ./tools/fetch_mbedtls.sh >&2)
endif

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME := LegacyTikTok

LegacyTikTok_FILES := $(wildcard src/*.m) src/rt_http.c src/rt_xbogus.c vendor/mbedtls_glue.c $(wildcard vendor/mbedtls/library/*.c)
LegacyTikTok_FRAMEWORKS := UIKit Foundation CoreGraphics QuartzCore AVFoundation CoreMedia Security
LegacyTikTok_CFLAGS := -Isrc -Ivendor -Ivendor/mbedtls/include -Ivendor/mbedtls/library -Os -fvisibility=hidden \
                       -Wall -Wno-deprecated-declarations -Wno-unknown-warning-option -Wno-nullability-completeness \
                       -Wno-unused-function -Wno-unused-variable -Wno-unused-but-set-variable -Wno-unused-parameter
LegacyTikTok_OBJCFLAGS := -fobjc-arc -Wunguarded-availability
LegacyTikTok_LDFLAGS := -lz

include $(THEOS)/makefiles/application.mk
