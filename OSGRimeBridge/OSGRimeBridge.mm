#import "include/OSGRimeBridge.h"

@import RimeStatic;

const int OSGRimeKeyBackSpace = 0xff08;
const int OSGRimeKeyReturn = 0xff0d;

static NSString *const OSGRimeErrorDomain = @"com.osgkeyboard.rime";
static RimeApi_stdbool *OSGRimeAPI(void) {
    return rime_get_api_stdbool();
}

@implementation OSGRimeCandidate

- (instancetype)initWithText:(NSString *)text comment:(NSString *)comment {
    self = [super init];
    if (self) {
        _text = [text copy];
        _comment = [comment copy];
    }
    return self;
}

@end

@implementation OSGRimeSnapshot

- (instancetype)initWithPreedit:(NSString *)preedit
                     candidates:(NSArray<OSGRimeCandidate *> *)candidates
                     commitText:(NSString *)commitText
                      composing:(BOOL)composing {
    self = [super init];
    if (self) {
        _preedit = [preedit copy];
        _candidates = [candidates copy];
        _commitText = [commitText copy];
        _composing = composing;
    }
    return self;
}

@end

@interface OSGRimeBridge ()
@property(nonatomic, copy) NSString *sharedDataDirectory;
@property(nonatomic, copy) NSString *userDataDirectory;
@property(nonatomic, copy) NSString *distributionVersion;
@property(nonatomic) RimeSessionId session;
@end

@implementation OSGRimeBridge

static BOOL sSetupComplete = NO;
static BOOL sInitialized = NO;

- (instancetype)initWithSharedDataDirectory:(NSString *)sharedDataDirectory
                          userDataDirectory:(NSString *)userDataDirectory
                        distributionVersion:(NSString *)distributionVersion {
    self = [super init];
    if (self) {
        _sharedDataDirectory = [sharedDataDirectory copy];
        _userDataDirectory = [userDataDirectory copy];
        _distributionVersion = [distributionVersion copy];
        _session = 0;
    }
    return self;
}

- (BOOL)running {
    return self.session != 0 && OSGRimeAPI()->find_session(self.session);
}

- (void)populateTraits:(RimeTraits *)traits {
    traits->shared_data_dir = self.sharedDataDirectory.UTF8String;
    traits->user_data_dir = self.userDataDirectory.UTF8String;
    traits->distribution_name = "OSGKeyboard";
    traits->distribution_code_name = "OSGKeyboard";
    traits->distribution_version = self.distributionVersion.UTF8String;
    traits->app_name = "rime.OSGKeyboard";
    traits->min_log_level = 2;
}

- (BOOL)prepareRuntime:(NSError **)error {
    RimeApi_stdbool *api = OSGRimeAPI();
    if (api == NULL) {
        if (error) {
            *error = [NSError errorWithDomain:OSGRimeErrorDomain
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"librime API unavailable"}];
        }
        return NO;
    }

    @synchronized([OSGRimeBridge class]) {
        RIME_STRUCT(RimeTraits, traits);
        [self populateTraits:&traits];
        if (!sSetupComplete) {
            api->setup(&traits);
            sSetupComplete = YES;
        }
        if (!sInitialized) {
            api->initialize(&traits);
            sInitialized = YES;
        }
    }
    return YES;
}

- (BOOL)start:(NSError **)error {
    if (![self prepareRuntime:error]) {
        return NO;
    }
    if ([self running]) {
        return YES;
    }
    self.session = OSGRimeAPI()->create_session();
    if (self.session == 0) {
        if (error) {
            *error = [NSError errorWithDomain:OSGRimeErrorDomain
                                         code:2
                                     userInfo:@{NSLocalizedDescriptionKey: @"Unable to create Rime session"}];
        }
        return NO;
    }
    return YES;
}

- (void)stopSession {
    if (self.session != 0) {
        OSGRimeAPI()->destroy_session(self.session);
        self.session = 0;
    }
}

- (void)finalizeRuntime {
    [self stopSession];
    @synchronized([OSGRimeBridge class]) {
        if (sInitialized) {
            OSGRimeAPI()->finalize();
            sInitialized = NO;
        }
    }
}

- (BOOL)deployWithFullCheck:(BOOL)fullCheck error:(NSError **)error {
    if (![self prepareRuntime:error]) {
        return NO;
    }
    RimeApi_stdbool *api = OSGRimeAPI();
    Bool started = api->start_maintenance(fullCheck ? True : False);
    if (started && api->is_maintenance_mode()) {
        api->join_maintenance_thread();
    }
    return YES;
}

- (BOOL)selectSchema:(NSString *)schemaIdentifier {
    if (![self running]) {
        return NO;
    }
    return OSGRimeAPI()->select_schema(self.session, schemaIdentifier.UTF8String);
}

- (BOOL)setASCIIMode:(BOOL)enabled {
    if (![self running]) {
        return NO;
    }
    OSGRimeAPI()->set_option(self.session, "ascii_mode", enabled ? True : False);
    return YES;
}

- (BOOL)processKeyCode:(int)keyCode modifiers:(int)modifiers {
    if (![self running]) {
        return NO;
    }
    return OSGRimeAPI()->process_key(self.session, keyCode, modifiers);
}

- (BOOL)selectCandidateAtIndex:(NSInteger)index {
    if (![self running] || index < 0) {
        return NO;
    }
    return OSGRimeAPI()->select_candidate(self.session, (size_t)index);
}

- (BOOL)commitComposition {
    if (![self running]) {
        return NO;
    }
    return OSGRimeAPI()->commit_composition(self.session);
}

- (void)clearComposition {
    if ([self running]) {
        OSGRimeAPI()->clear_composition(self.session);
    }
}

- (NSString *)rawInput {
    if (![self running]) {
        return @"";
    }
    const char *input = OSGRimeAPI()->get_input(self.session);
    return input ? [NSString stringWithUTF8String:input] : @"";
}

- (OSGRimeSnapshot *)snapshotWithCandidateLimit:(NSInteger)limit {
    if (![self running]) {
        return [[OSGRimeSnapshot alloc] initWithPreedit:@""
                                            candidates:@[]
                                            commitText:@""
                                             composing:NO];
    }

    RimeApi_stdbool *api = OSGRimeAPI();
    NSString *commitText = @"";
    RIME_STRUCT(RimeCommit, commit);
    if (api->get_commit(self.session, &commit)) {
        if (commit.text) {
            commitText = [NSString stringWithUTF8String:commit.text];
        }
        api->free_commit(&commit);
    }

    NSString *preedit = @"";
    BOOL composing = NO;
    NSMutableArray<OSGRimeCandidate *> *candidates = [NSMutableArray array];
    RIME_STRUCT(RimeContext_stdbool, context);
    if (api->get_context(self.session, &context)) {
        composing = context.composition.length > 0;
        if (context.composition.preedit) {
            preedit = [NSString stringWithUTF8String:context.composition.preedit];
        }
        NSInteger count = MIN((NSInteger)context.menu.num_candidates, MAX((NSInteger)0, limit));
        for (NSInteger index = 0; index < count; index++) {
            RimeCandidate item = context.menu.candidates[index];
            NSString *text = item.text ? [NSString stringWithUTF8String:item.text] : @"";
            NSString *comment = item.comment ? [NSString stringWithUTF8String:item.comment] : @"";
            [candidates addObject:[[OSGRimeCandidate alloc] initWithText:text comment:comment]];
        }
        api->free_context(&context);
    }

    return [[OSGRimeSnapshot alloc] initWithPreedit:preedit
                                        candidates:candidates
                                        commitText:commitText
                                         composing:composing];
}

@end
