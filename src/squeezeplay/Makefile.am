## Makefile.am -- Process this file with automake to produce Makefile.in

#tw touch for poky test

# Rules for tolua++ binding files
SUFFIXES = .pkg

TOLUA = tolua++
.pkg.c:
	$(TOLUA) $(TOLUAFLAGS) $(AM_TOLUAFLAGS) -n jive -o $@ $^


# Check lua syntax
lua-lint:
	@rm -f badsyntax
	@find . -name "*.lua" -and \( -exec luac -p '{}' \; -or -print \) > badsyntax
	@test \! -s badsyntax
	@rm -f badsyntax

JIVE_BUILD_DIR = $(DESTDIR)$(pkgdatadir)

include Makefile.am.jive-install.include

install-data-local: jive-static-install
	##eliminate anything we still want private
	rm -rf $(JIVE_BUILD_DIR)/strict.lua
	rm -rf $(JIVE_BUILD_DIR)/applets/*/images/Reference_Screens
	rm -rf $(JIVE_BUILD_DIR)/applets/*/images/Guidelines


OSX_LIB_DIR = $(PREFIX)/lib
OSX_BUILD_DIR = $(PREFIX)
JIVE_DEPENDENCIES_LIB_DIR = $(top_builddir)/.libs
JIVE_STATIC_PROGRAM = SqueezePlay

OSX_STATIC_LIBS = `$(SDL_CONFIG) --static-libs` \
	$(OSX_LIB_DIR)/liblua.a $(OSX_LIB_DIR)/libtolua++.a \
	$(OSX_LIB_DIR)/libogg.a \
	$(OSX_LIB_DIR)/libFLAC.a \
	$(OSX_LIB_DIR)/libfreetype.a \
	$(OSX_LIB_DIR)/libmad.a \
	$(OSX_LIB_DIR)/libvorbisidec.a \
	$(OSX_LIB_DIR)/libportaudio.a \
	$(OSX_LIB_DIR)/libSDL.a \
	$(OSX_LIB_DIR)/libSDL_gfx.a \
	$(OSX_LIB_DIR)/libSDL_image.a \
	$(OSX_LIB_DIR)/libSDL_ttf.a \
	$(OSX_LIB_DIR)/libSDLmain.a \
	$(OSX_LIB_DIR)/libpng.a \
	$(OSX_LIB_DIR)/libjpeg.a \
	$(OSX_LIB_DIR)/libfdk-aac.a \
	$(JIVE_DEPENDENCIES_LIB_DIR)/libaudio.a $(JIVE_DEPENDENCIES_LIB_DIR)/libnet.a $(JIVE_DEPENDENCIES_LIB_DIR)/libui.a $(JIVE_DEPENDENCIES_LIB_DIR)/libdecode.a

SqueezePlay: $(jive_OBJECTS) $(jive_DEPENDENCIES)
	$(CC) $(LDFLAGS) \
	-force_cpusubtype_ALL \
	-framework CoreAudio \
	-o $(JIVE_STATIC_PROGRAM) $(jive_OBJECTS)   \
	$(OSX_STATIC_LIBS) \
	-lz -lresolv

BUNDLE_NAME = SqueezePlay.app
APP_NAME = SqueezePlay
BUNDLE_CONTENTS = $(BUNDLE_NAME)/Contents
PLIST_FILE = $(BUNDLE_CONTENTS)/Info.plist

VERSION_TEXT = $(shell cat ../squeezeplay.version)r$(shell svnversion -n .. | sed -e 's/[MS]//g')
DEB_VERSION_TEXT = $(shell cat ../squeezeplay.version)~$(shell svnversion -n .. | sed -e 's/[MS]//g')
TGZ_VERSION_TEXT = $(shell cat ../squeezeplay.version)-$(shell svnversion -n .. | sed -e 's/[MS]//g')
ICNS_NAME = icon.icns
DMG_TEMP_DIR = temp-SqueezePlay_image
DMG_IMAGE_DIR = SqueezePlay_image
DMG_IMAGE_DIR_MOUNTPOINT = $(DMG_IMAGE_DIR)-$(VERSION_TEXT)
DMG_TMP_IMAGE_FILENAME = $(DMG_TEMP_DIR).dmg
DMG_IMAGE_FILENAME = SqueezePlay.dmg

#todo: make clean work the right way(not the rm -rf hackery seen below)
SqueezePlay_bundle: SqueezePlay
	rm -rf $(BUNDLE_CONTENTS)/
	rm -rf $(OSX_BUILD_DIR)/$(BUNDLE_NAME)
	mkdir -p $(BUNDLE_CONTENTS)/MacOS
	mkdir -p $(BUNDLE_CONTENTS)/Resources
	mkdir -p $(BUNDLE_CONTENTS)/lib
	mkdir -p $(BUNDLE_CONTENTS)/share
	echo "APPLSQPL" > $(BUNDLE_CONTENTS)/PkgInfo
	cp -R $(OSX_BUILD_DIR)/share/lua $(BUNDLE_CONTENTS)/share
	cp -R $(OSX_BUILD_DIR)/share/jive $(BUNDLE_CONTENTS)/share
	cp -R $(OSX_BUILD_DIR)/lib/lua $(BUNDLE_CONTENTS)/lib
	cp rsc/$(ICNS_NAME) $(BUNDLE_CONTENTS)/Resources
	echo "<?xml version=\"1.0\" encoding=\"UTF-8\"?>" > $(PLIST_FILE)
	echo "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">" >> $(PLIST_FILE)
	echo "<plist version=\"1.0\">" >> $(PLIST_FILE)
	echo "<dict>" >> $(PLIST_FILE)
	echo "	<key>CFBundleDevelopmentRegion</key>" >> $(PLIST_FILE)
	echo "	<string>English</string>" >> $(PLIST_FILE)
	echo "	<key>CFBundleExecutable</key>" >> $(PLIST_FILE)
	echo "	<string>$(JIVE_STATIC_PROGRAM)</string>" >> $(PLIST_FILE)
	echo "	<key>CFBundleDisplayName</key>" >> $(PLIST_FILE)
	echo "	<string>$(APP_NAME)</string>" >> $(PLIST_FILE)
	echo "	<key>CFBundleIdentifier</key>" >> $(PLIST_FILE)
	echo "	<string>com.logitech.squeezeplay</string>" >> $(PLIST_FILE)
	echo "	<key>CFBundleIconFile</key>" >> $(PLIST_FILE)
	echo "	<string>$(ICNS_NAME)</string>" >> $(PLIST_FILE)
	echo "	<key>CFBundleInfoDictionaryVersion</key>" >> $(PLIST_FILE)
	echo "	<string>6.0</string>" >> $(PLIST_FILE)
	echo "	<key>CFBundlePackageType</key>" >> $(PLIST_FILE)
	echo "	<string>APPL</string>" >> $(PLIST_FILE)
	echo "	<key>CFBundleSignature</key>" >> $(PLIST_FILE)
	echo "	<string>SQPL</string>" >> $(PLIST_FILE)
	echo "	<key>CFBundleShortVersionString</key>" >> $(PLIST_FILE)
	echo "	<string>$(VERSION_TEXT)</string>" >> $(PLIST_FILE)
	echo "	<key>CFBundleVersion</key>" >> $(PLIST_FILE)
	echo "	<string>$(VERSION_TEXT)</string>" >> $(PLIST_FILE)
	echo "	<key>CFBundleGetInfoString</key>" >> $(PLIST_FILE)
	echo "	<string>$(APP_NAME) $(VERSION_TEXT), Copyright 2008 Logitech</string>" >> $(PLIST_FILE)
	echo "  <key>NSAppleEventsUsageDescription</key>" >> $(PLIST_FILE)
	echo "  <string>$(APP_NAME) wants to pause and resume external media players.</string>" >> $(PLIST_FILE)
	echo "</dict>" >> $(PLIST_FILE)
	echo "</plist>" >> $(PLIST_FILE)
	chmod 644 $(BUNDLE_CONTENTS)/Resources/*
	$(INSTALL_PROGRAM) $(JIVE_STATIC_PROGRAM) $(BUNDLE_CONTENTS)/MacOS/
	cp -Rp $(BUNDLE_NAME) $(OSX_BUILD_DIR)

SqueezePlay_dmg: SqueezePlay_bundle
	##following image creation model basd on sc buildme.pl (might avoid build system hang on hdiutil cmd
	rm -rf $(DMG_IMAGE_DIR)
	rm -rf $(DMG_TEMP_DIR)
	-rm $(DMG_TMP_IMAGE_FILENAME)
	mkdir -p $(DMG_TEMP_DIR)
	-hdiutil detach "/Volumes/$(DMG_IMAGE_DIR_MOUNTPOINT)"
	-rm -rf "/Volumes/$(DMG_IMAGE_DIR_MOUNTPOINT)"
	hdiutil create -fs HFS+ -layout SPUD -volname "$(DMG_IMAGE_DIR_MOUNTPOINT)" -size 100m "$(DMG_TEMP_DIR)"
	hdiutil mount "$(DMG_TMP_IMAGE_FILENAME)"
	cp -r $(BUNDLE_NAME) /Volumes/$(DMG_IMAGE_DIR_MOUNTPOINT)
	hdiutil detach "/Volumes/$(DMG_IMAGE_DIR_MOUNTPOINT)"
	hdiutil convert -ov -format UDZO "$(DMG_TMP_IMAGE_FILENAME)" -o "$(DMG_IMAGE_FILENAME)"
	rm -rf $(DMG_IMAGE_DIR)
	rm -rf $(DMG_TEMP_DIR)
	-rm $(DMG_TMP_IMAGE_FILENAME)
	cp -p $(DMG_IMAGE_FILENAME) $(OSX_BUILD_DIR)/SqueezePlay-$(VERSION_TEXT).dmg

squeezeplay-tgz: 
	cd $(prefix); tar -zcf ../squeezeplay-$(TGZ_VERSION_TEXT).tgz *; tar -ztvf ../squeezeplay-$(TGZ_VERSION_TEXT).tgz

squeezeplay-deb:
	sed -e 's/_VERSION_/$(DEB_VERSION_TEXT)/g' ../platforms/debian/changelog.in > ../platforms/debian/changelog
	cd ../platforms; fakeroot dpkg-buildpackage -b; ls -lah ../squeezeplay*.deb

# Convenience library:
noinst_LTLIBRARIES = libui.la libaudio.la libdecode.la libnet.la

BUILT_SOURCES = \
	src/ui/lua_jiveui.c \
	src/version.h

src/version.h: FORCE
	@echo '/* This file is automatically generated */' > src/version.h
	@echo '#ifndef SQUEEZEPLAY_RELEASE' >> src/version.h
	@echo '#define SQUEEZEPLAY_RELEASE "'`cat ../squeezeplay.version`'"' >> src/version.h
	@echo '#endif' >> src/version.h
	@echo '#ifndef SQUEEZEPLAY_REVISION' >> src/version.h
	@echo '#define SQUEEZEPLAY_REVISION "'`svnversion -n .. | sed -e 's/[MS]//g'`'"' >> src/version.h
	@echo '#endif' >> src/version.h
	@echo '#define JIVE_VERSION SQUEEZEPLAY_RELEASE" r"SQUEEZEPLAY_REVISION' >> src/version.h

FORCE:

libui_la_SOURCES = \
	src/ui/jive_event.c \
	src/ui/jive_font.c \
	src/ui/jive_framework.c \
	src/ui/jive_group.c \
	src/ui/jive_icon.c \
	src/ui/jive_label.c \
	src/ui/jive_menu.c \
	src/ui/platform_osx.c \
	src/ui/platform_linux.c \
	src/ui/jive_slider.c \
	src/ui/jive_style.c \
	src/ui/jive_surface.c \
	src/ui/system.c \
	src/ui/jive_textarea.c \
	src/ui/jive_textinput.c \
	src/ui/jive_utils.c \
	src/ui/jive_widget.c \
	src/ui/jive_window.c \
	src/ui/lua_jiveui.c

libui_la_LIBADD = -ltolua++ -llua -lSDL_image -lSDL_ttf -lSDL_gfx -lSDL

libaudio_la_CFLAGS = -DRESAMPLE_EFFECTS -DOUTSIDE_SPEEX -DFIXED_POINT -DRANDOM_PREFIX=jive -DEXPORT=""

libaudio_la_SOURCES = \
	src/audio/decode/audio_helper.c \
	src/audio/speex/resample.c \
	src/audio/fifo.c \
	src/audio/fixed_math.c

libdecode_la_SOURCES = \
	src/audio/mp4.c \
	src/audio/mqueue.c \
	src/audio/streambuf.c \
	src/audio/alac/alac.c \
	src/audio/decode/decode.c \
	src/audio/decode/decode_alsa.c \
	src/audio/decode/decode_aac.c \
	src/audio/decode/decode_flac.c \
	src/audio/decode/decode_mad.c \
	src/audio/decode/decode_output.c \
	src/audio/decode/decode_pcm.c \
	src/audio/decode/decode_portaudio.c \
	src/audio/decode/decode_sample.c \
	src/audio/decode/decode_vorbis.c \
	src/audio/decode/decode_alac.c \
	src/audio/decode/visualizer_vumeter.c \
	src/audio/decode/visualizer_spectrum.c \
	src/audio/kiss_fft.c


libdecode_la_LIBADD = libaudio.la -lSDL -lFLAC -lmad -lvorbisidec

libnet_la_SOURCES = \
	src/net/jive_dns.c

libnet_la_LIBADD = -lSDL -lresolv


# Program: jivebrowser
if ALSA_ENABLED
bin_PROGRAMS = jive jive_alsa
else
bin_PROGRAMS = jive
endif

# Test programs: jiveblit
testdir = $(bindir)
if TEST_PROGRAMS
test_PROGRAMS = jiveblit
else
test_PROGRAMS = 
endif


jive_SOURCES = \
	src/jive.c \
	src/jive_debug.c \
	src/log.c

jive_LDADD = libui.la libdecode.la libnet.la -lfdk-aac -llua ${SPPRIVATE_LIB}

jive_alsa_SOURCES = \
	src/audio/decode/decode_alsa_backend.c

jive_alsa_LDADD = libaudio.la -lasound


# Test program: jiveblit
jiveblit_SOURCES = \
	src/jiveblit.c

jiveblit_LDADD = -lSDL_image -lSDL_ttf -lSDL_gfx -lSDL
