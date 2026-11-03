// Loaded into /usr/bin/perl by NowPlaying.swift. Since macOS 15.4, MediaRemote only
// returns now-playing info to Apple-signed processes, so we run inside the system perl
// binary instead of the app. Protocol: one JSON object per line on stdout; commands
// ("toggle", "next", "prev", "seek <seconds>") one per line on stdin. Exits on stdin EOF
// so the helper never outlives the app.

#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <unistd.h>

typedef void (*RegisterFn)(dispatch_queue_t);
typedef void (*GetInfoFn)(dispatch_queue_t, void (^)(NSDictionary *));
typedef void (*GetIsPlayingFn)(dispatch_queue_t, void (^)(BOOL));
typedef void (*GetClientFn)(dispatch_queue_t, void (^)(id));
typedef NSString *(*ClientStringFn)(id);
typedef Boolean (*SendCommandFn)(int, NSDictionary *);
typedef void (*SetElapsedFn)(double);

static RegisterFn mrRegister;
static GetInfoFn mrGetInfo;
static GetIsPlayingFn mrGetIsPlaying;
static GetClientFn mrGetClient;
static ClientStringFn mrClientBundle;
static ClientStringFn mrClientParentBundle;
static SendCommandFn mrSend;
static SetElapsedFn mrSetElapsed;

static dispatch_queue_t queue;
static NSUInteger lastArtworkHash = 0;
static BOOL scheduled = NO;

static void emit(NSDictionary *object) {
    NSData *json = [NSJSONSerialization dataWithJSONObject:object options:0 error:nil];
    if (!json) return;
    NSMutableData *line = [json mutableCopy];
    [line appendBytes:"\n" length:1];
    const uint8_t *bytes = line.bytes;
    size_t remaining = line.length;
    while (remaining > 0) {
        ssize_t written = write(STDOUT_FILENO, bytes, remaining);
        if (written <= 0) exit(0);
        bytes += written;
        remaining -= (size_t)written;
    }
}

// JSON can't hold NaN or infinity, and NSJSONSerialization throws on them (live streams can
// report an infinite duration), so anything that isn't a finite number becomes 0.
static NSNumber *finite(id value) {
    if (![value isKindOfClass:[NSNumber class]] || !isfinite([value doubleValue])) return @0;
    return value;
}

static void publish(void) {
    mrGetInfo(queue, ^(NSDictionary *info) {
        mrGetIsPlaying(queue, ^(BOOL playing) {
            mrGetClient(queue, ^(id client) {
                NSMutableDictionary *out = [NSMutableDictionary dictionary];
                out[@"playing"] = @(playing);
                NSString *title = info[@"kMRMediaRemoteNowPlayingInfoTitle"];
                if (title.length == 0) {
                    lastArtworkHash = 0;
                    emit(@{ @"empty": @YES });
                    return;
                }
                out[@"title"] = title;
                out[@"artist"] = info[@"kMRMediaRemoteNowPlayingInfoArtist"] ?: @"";
                out[@"duration"] = finite(info[@"kMRMediaRemoteNowPlayingInfoDuration"]);
                out[@"elapsed"] = finite(info[@"kMRMediaRemoteNowPlayingInfoElapsedTime"]);
                out[@"rate"] = finite(info[@"kMRMediaRemoteNowPlayingInfoPlaybackRate"]);
                NSDate *timestamp = info[@"kMRMediaRemoteNowPlayingInfoTimestamp"];
                out[@"timestamp"] = @([(timestamp ?: [NSDate date]) timeIntervalSince1970]);

                if (client) {
                    NSString *bundle = mrClientParentBundle ? mrClientParentBundle(client) : nil;
                    if (bundle.length == 0 && mrClientBundle) bundle = mrClientBundle(client);
                    if (bundle.length) out[@"bundle"] = bundle;
                }

                // Artwork is the only large field; send it only when it changes.
                NSData *artwork = info[@"kMRMediaRemoteNowPlayingInfoArtworkData"];
                NSUInteger hash = artwork.length ? (artwork.length ^ [[artwork subdataWithRange:NSMakeRange(0, MIN(artwork.length, (NSUInteger)4096))] hash]) : 0;
                if (hash != lastArtworkHash) {
                    lastArtworkHash = hash;
                    if (artwork.length) out[@"artwork"] = [artwork base64EncodedStringWithOptions:0];
                    else out[@"noArtwork"] = @YES;
                }
                emit(out);
            });
        });
    });
}

// Notifications arrive in bursts (one track change fires several); coalesce them.
static void schedulePublish(void) {
    if (scheduled) return;
    scheduled = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 80 * NSEC_PER_MSEC), queue, ^{
        scheduled = NO;
        publish();
    });
}

// MRMediaRemoteSendCommand values: 2 = toggle play/pause, 4 = next track, 5 = previous track.
static void handleCommand(NSString *line) {
    if ([line isEqualToString:@"toggle"]) mrSend(2, nil);
    else if ([line isEqualToString:@"next"]) mrSend(4, nil);
    else if ([line isEqualToString:@"prev"]) mrSend(5, nil);
    else if ([line hasPrefix:@"seek "] && mrSetElapsed) mrSetElapsed([[line substringFromIndex:5] doubleValue]);
}

static void readCommands(void) {
    dispatch_source_t source = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, STDIN_FILENO, 0, queue);
    __block NSMutableData *buffer = [NSMutableData data];
    dispatch_source_set_event_handler(source, ^{
        char chunk[512];
        ssize_t count = read(STDIN_FILENO, chunk, sizeof chunk);
        if (count <= 0) exit(0);
        [buffer appendBytes:chunk length:(NSUInteger)count];
        while (YES) {
            NSRange newline = [buffer rangeOfData:[NSData dataWithBytes:"\n" length:1] options:0 range:NSMakeRange(0, buffer.length)];
            if (newline.location == NSNotFound) break;
            NSData *lineData = [buffer subdataWithRange:NSMakeRange(0, newline.location)];
            [buffer replaceBytesInRange:NSMakeRange(0, newline.location + 1) withBytes:NULL length:0];
            NSString *line = [[NSString alloc] initWithData:lineData encoding:NSUTF8StringEncoding];
            if (line.length) handleCommand(line);
        }
    });
    dispatch_resume(source);
    // Keep the source alive for the life of the process.
    static dispatch_source_t retained;
    retained = source;
}

// Installed as a perl XSUB, so perl calls it as fn(interpreter, cv); both are ignored.
void notch_bridge_run(void *interpreter, void *cv) {
    @autoreleasepool {
        void *mr = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY);
        if (!mr) { emit(@{ @"error": @"MediaRemote unavailable" }); exit(1); }
        mrRegister = (RegisterFn)dlsym(mr, "MRMediaRemoteRegisterForNowPlayingNotifications");
        mrGetInfo = (GetInfoFn)dlsym(mr, "MRMediaRemoteGetNowPlayingInfo");
        mrGetIsPlaying = (GetIsPlayingFn)dlsym(mr, "MRMediaRemoteGetNowPlayingApplicationIsPlaying");
        mrGetClient = (GetClientFn)dlsym(mr, "MRMediaRemoteGetNowPlayingClient");
        mrClientBundle = (ClientStringFn)dlsym(mr, "MRNowPlayingClientGetBundleIdentifier");
        mrClientParentBundle = (ClientStringFn)dlsym(mr, "MRNowPlayingClientGetParentAppBundleIdentifier");
        mrSend = (SendCommandFn)dlsym(mr, "MRMediaRemoteSendCommand");
        mrSetElapsed = (SetElapsedFn)dlsym(mr, "MRMediaRemoteSetElapsedTime");
        if (!mrRegister || !mrGetInfo || !mrGetIsPlaying || !mrGetClient || !mrSend) {
            emit(@{ @"error": @"MediaRemote symbols missing" });
            exit(1);
        }

        queue = dispatch_queue_create("notch.mediaremote", DISPATCH_QUEUE_SERIAL);
        mrRegister(queue);
        NSArray *names = @[
            @"kMRMediaRemoteNowPlayingInfoDidChangeNotification",
            @"kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
            @"kMRMediaRemoteNowPlayingApplicationDidChangeNotification",
        ];
        for (NSString *name in names) {
            [[NSNotificationCenter defaultCenter] addObserverForName:name object:nil queue:nil usingBlock:^(NSNotification *note) {
                dispatch_async(queue, ^{ schedulePublish(); });
            }];
        }
        readCommands();
        dispatch_async(queue, ^{ publish(); });
    }
    CFRunLoopRun();
    exit(0);
}
