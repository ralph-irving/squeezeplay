/*
 Copyright (c) 2011, Joachim Bengtsson
 All rights reserved.

 Redistribution and use in source and binary forms, with or without modification,
 are permitted provided that the following conditions are met:

 * Neither the name of the organization nor the names of its contributors may
   be used to endorse or promote products derived from this software without
   specific prior written permission.

 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
 FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
 SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
 CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
 OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/

// Copyright (c) 2010 Spotify AB
// modifications by Jake Angerman 2023 for SqueezePlay
#import "SPMediaKeyTap.h"
#include "SDL.h"
#include "SDLMain.h"
#include "SDL_events.h"
#include "SDL_keysym.h"
#include <IOKit/hidsystem/ev_keymap.h> /* For multimedia keys */

// Define to enable app list debug output
//#define DEBUG_SPMEDIAKEY_APPLIST 1

NSString *kIgnoreMediaKeysDefaultsKey = @"SPIgnoreMediaKeys";

@interface SPMediaKeyTap () {
    CFMachPortRef _eventPort;
    CFRunLoopSourceRef _eventPortSource;
    CFRunLoopRef _tapThreadRL;
    NSThread *_tapThread;
    BOOL _shouldInterceptMediaKeyEvents;
    id _delegate;
    // The app that is frontmost in this list owns media keys
    NSMutableArray<NSRunningApplication *> *_mediaKeyAppList;
}

- (BOOL)shouldInterceptMediaKeyEvents;
- (void)setShouldInterceptMediaKeyEvents:(BOOL)newSetting;
- (void)startWatchingAppSwitching;
- (void)stopWatchingAppSwitching;
- (void)eventTapThread;
- (void)receivedMediaKeyEvent:(NSEvent*)event;
@end

static CGEventRef tapEventCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *refcon);

static NSArray *mediaKeyUserBundleIdentifiers;

// Inspired by http://gist.github.com/546311

@implementation SPMediaKeyTap

#pragma mark -
#pragma mark Setup and teardown

- (id)initWithDelegate:(id)delegate
{
    self = [super init];
    if (self) {
        _delegate = delegate;
        [self startWatchingAppSwitching];
        _mediaKeyAppList = [NSMutableArray new];
    }
    return self;
}

- (void)dealloc
{
    [self stopWatchingMediaKeys];
    [self stopWatchingAppSwitching];
    [super dealloc];
}

- (void)startWatchingAppSwitching
{
    // Listen to "app switched" event, so that we don't intercept media keys if we
    // weren't the last "media key listening" app to be active

    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self
                                                           selector:@selector(frontmostAppChanged:)
                                                               name:NSWorkspaceDidActivateApplicationNotification
                                                             object:nil];


    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self
                                                           selector:@selector(appTerminated:)
                                                               name:NSWorkspaceDidTerminateApplicationNotification
                                                             object:nil];
}

- (void)stopWatchingAppSwitching
{
    [[[NSWorkspace sharedWorkspace] notificationCenter] removeObserver:self];
}

- (BOOL)startWatchingMediaKeys
{
    // Prevent having multiple mediaKeys threads
    [self stopWatchingMediaKeys];

    [self setShouldInterceptMediaKeyEvents:YES];

    // Add an event tap to intercept the system defined media key events
    _eventPort = CGEventTapCreate(kCGSessionEventTap,
                                  kCGHeadInsertEventTap,
                                  kCGEventTapOptionDefault,
                                  CGEventMaskBit(NX_SYSDEFINED),
                                  tapEventCallback,
                                  (__bridge void * __nullable)(self));

    // Can be NULL if the app has no accessibility access permission
    if (_eventPort == NULL)
        return NO;

    _eventPortSource = CFMachPortCreateRunLoopSource(kCFAllocatorSystemDefault, _eventPort, 0);
    assert(_eventPortSource != NULL);

    if (_eventPortSource == NULL)
        return NO;

    // Let's do this in a separate thread so that a slow app doesn't lag the event tap
    _tapThread = [[NSThread alloc] initWithTarget:self
                                         selector:@selector(eventTapThread)
                                           object:nil];
    [_tapThread start];

    return YES;
}

- (void)stopWatchingMediaKeys
{
    // Shut down tap thread
    if(_tapThreadRL){
        CFRunLoopStop(_tapThreadRL);
        _tapThreadRL = nil;
    }

    // Remove tap port
    if(_eventPort){
        CFMachPortInvalidate(_eventPort);
        CFRelease(_eventPort);
        _eventPort = nil;
    }

    // Remove tap source
    if(_eventPortSource){
        CFRelease(_eventPortSource);
        _eventPortSource = nil;
    }
}

#pragma mark -
#pragma mark Accessors

+ (BOOL)usesGlobalMediaKeyTap
{
#ifdef _DEBUG
    // breaking in gdb with a key tap inserted sometimes locks up all mouse and keyboard input forever, forcing reboot
    return NO;
#else
    // XXX(nevyn): MediaKey event tap doesn't work on 10.4, feel free to figure out why if you have the energy.
    return
        ![[NSUserDefaults standardUserDefaults] boolForKey:kIgnoreMediaKeysDefaultsKey]
        && floor(NSAppKitVersionNumber) >= 949/*NSAppKitVersionNumber10_5*/;
#endif
}

+ (void)initialize {
    // do not run for derived classes
    if (self != [SPMediaKeyTap class])
        return;

    mediaKeyUserBundleIdentifiers = @[
            @"com.logitech.squeezeplay",
            @"com.spotify.client",
            @"com.apple.iTunes",
            @"com.apple.Music",
            @"com.apple.QuickTimePlayerX",
            @"com.apple.quicktimeplayer",
            @"com.apple.iWork.Keynote",
            @"com.apple.iPhoto",
            @"org.videolan.vlc",
            @"com.apple.Aperture",
            @"com.plexsquared.Plex",
            @"com.soundcloud.desktop",
            @"org.niltsh.MPlayerX",
            @"com.ilabs.PandorasHelper",
            @"com.mahasoftware.pandabar",
            @"com.bitcartel.pandorajam",
            @"org.clementine-player.clementine",
            @"fm.last.Last.fm",
            @"fm.last.Scrobbler",
            @"com.beatport.BeatportPro",
            @"com.Timenut.SongKey",
            @"com.macromedia.fireworks", // the tap messes up their mouse input
            @"at.justp.Theremin",
            @"ru.ya.themblsha.YandexMusic",
            @"com.jriver.MediaCenter18",
            @"com.jriver.MediaCenter19",
            @"com.jriver.MediaCenter20",
            @"co.rackit.mate",
            @"com.ttitt.b-music",
            @"com.beardedspice.BeardedSpice",
            @"com.plug.Plug",
            @"com.netease.163music",
			  ];
}

- (BOOL)shouldInterceptMediaKeyEvents
{
    BOOL shouldIntercept = NO;
    @synchronized(self) {
        shouldIntercept = _shouldInterceptMediaKeyEvents;
    }
    return shouldIntercept;
}

- (void)pauseTapOnTapThread:(NSNumber *)yeahno
{
    CGEventTapEnable(self->_eventPort, [yeahno boolValue]);
}

- (void)setShouldInterceptMediaKeyEvents:(BOOL)newSetting
{
    BOOL oldSetting;
    @synchronized(self) {
        oldSetting = _shouldInterceptMediaKeyEvents;
        _shouldInterceptMediaKeyEvents = newSetting;
    }
    if(_tapThreadRL && oldSetting != newSetting) {
        [self performSelector:@selector(pauseTapOnTapThread:)
                     onThread:_tapThread
                   withObject:@(newSetting)
                waitUntilDone:NO];

    }
}


#pragma mark -
#pragma mark Event tap callbacks

// Note: method called on background thread

static CGEventRef tapEventCallback2(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *refcon)
{
    SPMediaKeyTap *self = (__bridge SPMediaKeyTap *)refcon;

    if(type == kCGEventTapDisabledByTimeout) {
        NSLog(@"Media key event tap was disabled by timeout");
        CGEventTapEnable(self->_eventPort, TRUE);
        return event;
    } else if(type == kCGEventTapDisabledByUserInput) {
        // Was disabled manually by -[pauseTapOnTapThread]
        return event;
    }
    NSEvent *nsEvent = nil;
    @try {
        nsEvent = [NSEvent eventWithCGEvent:event];
    }
    @catch (NSException * e) {
        NSLog(@"Strange CGEventType: %d: %@", type, e);
        assert(0);
        return event;
    }

    if (type != NX_SYSDEFINED || [nsEvent subtype] != SPSystemDefinedEventMediaKeys)
        return event;

    int keyCode = (([nsEvent data1] & 0xFFFF0000) >> 16);
    if (keyCode != NX_KEYTYPE_PLAY && keyCode != NX_KEYTYPE_FAST && keyCode != NX_KEYTYPE_REWIND && keyCode != NX_KEYTYPE_PREVIOUS && keyCode != NX_KEYTYPE_NEXT)
        return event;

    if (![self shouldInterceptMediaKeyEvents])
        return event;

    [self performSelectorOnMainThread:@selector(handleAndReleaseMediaKeyEvent:) withObject:nsEvent waitUntilDone:NO];

    return NULL;
}

static CGEventRef tapEventCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *refcon)
{
    @autoreleasepool {
        CGEventRef ret = tapEventCallback2(proxy, type, event, refcon);
        return ret;
    }
}

- (void)handleAndReleaseMediaKeyEvent:(NSEvent *)event
{
    [self receivedMediaKeyEvent:event];
}

- (void)eventTapThread
{
    _tapThreadRL = CFRunLoopGetCurrent();
    CFRunLoopAddSource(_tapThreadRL, _eventPortSource, kCFRunLoopCommonModes);
    CFRunLoopRun();
}


#pragma mark -
#pragma mark Task switching callbacks

- (void)mediaKeyAppListChanged
{
    #ifdef DEBUG_SPMEDIAKEY_APPLIST
    [self debugPrintAppList];
    #endif

    if([_mediaKeyAppList count] == 0)
        return;

    NSRunningApplication *thisApp = [NSRunningApplication currentApplication];
    NSRunningApplication *otherApp = [_mediaKeyAppList firstObject];

    BOOL isCurrent = [thisApp isEqual:otherApp];

    [self setShouldInterceptMediaKeyEvents:isCurrent];
}

- (void)frontmostAppChanged:(NSNotification *)notification
{
    NSRunningApplication *app = [notification.userInfo objectForKey:NSWorkspaceApplicationKey];

    if (app.bundleIdentifier == nil)
        return;

    if (![mediaKeyUserBundleIdentifiers containsObject:app.bundleIdentifier]) {
        return; // we don't care about the app
    }

    [_mediaKeyAppList removeObject:app];
    [_mediaKeyAppList insertObject:app atIndex:0];
    [self mediaKeyAppListChanged];
}

- (void)appTerminated:(NSNotification *)notification
{
    NSRunningApplication *app = [notification.userInfo objectForKey:NSWorkspaceApplicationKey];
    [_mediaKeyAppList removeObject:app];
    [self mediaKeyAppListChanged];
}

#ifdef DEBUG_SPMEDIAKEY_APPLIST
- (void)debugPrintAppList
{
    NSMutableString *list = [NSMutableString stringWithCapacity:255];
    for (NSRunningApplication *app in _mediaKeyAppList) {
        [list appendFormat:@"     - %@\n", app.bundleIdentifier];
    }
    NSLog(@"List: \n%@", list);
}
#endif

/* callback for multimedia key events */
- (void) receivedMediaKeyEvent:(NSEvent*)event
{
    unsigned int type = [ event type ];
    if (type == NSSystemDefined && [event subtype] == 8) {
        /* multimedia key */
        int keyCode = (([event data1] & 0xFFFF0000) >> 16);
        int keyFlags = ([event data1] & 0x0000FFFF);
        int keyDown = (((keyFlags & 0xFF00) >> 8)) == 0xA;
        int keyUp   = (((keyFlags & 0xFF00) >> 8)) == 0xB;
        int keyRepeat = (keyFlags & 0x1);
        static int beenRepeating = 0;
        SDL_EventFilter event_filter;
        SDL_Event sdl_event;

        memset(&sdl_event, 0, sizeof(sdl_event));
        sdl_event.type = SDL_KEYDOWN;
        sdl_event.key.state = SDL_PRESSED;

        switch (keyCode) {
        case NX_KEYTYPE_PLAY:
            /* play/pause */
            if (keyDown) {
                sdl_event.key.keysym.sym = SDLK_AudioPlay;
            }
            break;

        case NX_KEYTYPE_FAST:
        case NX_KEYTYPE_NEXT:
            /* fast-forward */
            if (keyUp && !beenRepeating) {
                /* next track */
                sdl_event.key.keysym.sym = SDLK_AudioNext;
            } else if (keyDown && keyRepeat) {
                /* skip forward */
                beenRepeating = 1;
                sdl_event.key.keysym.sym = SDLK_Forward;
            } else if (keyUp && beenRepeating) {
                /* done skipping forward */
                beenRepeating = 0;
            }
            break;

        case NX_KEYTYPE_REWIND:
        case NX_KEYTYPE_PREVIOUS:
            /* rewind */
            if (keyUp && !beenRepeating) {
                /* previous track */
                sdl_event.key.keysym.sym = SDLK_AudioPrev;
            } else if (keyDown && keyRepeat) {
                /* skip backward */
                beenRepeating = 1;
                sdl_event.key.keysym.sym = SDLK_Back;
            } else if (keyUp && beenRepeating) {
                /* done skipping backward */
                beenRepeating = 0;
            }
            break;

        } /*switch*/

        if ((event_filter=SDL_GetEventFilter()) && sdl_event.key.keysym.sym) {
            /* pump the event through macosx_filter_pump()
             * since SDL_PushEvent() does not perform filtering in SDL 1.2
             */
            event_filter(&sdl_event);
        }

    } /*if*/
}

@end
