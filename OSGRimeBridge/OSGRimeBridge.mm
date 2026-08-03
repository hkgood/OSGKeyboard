#import "include/OSGRimeBridge.h"

@import RimeStatic;

const int OSGRimeKeyBackSpace = 0xff08;
const int OSGRimeKeyReturn = 0xff0d;

static NSString *const OSGRimeErrorDomain = @"com.osgkeyboard.rime";
static RimeApi_stdbool *OSGRimeAPI(void) {
    return rime_get_api_stdbool();
}

@implementation OSGRimeCandidate

- (instancetype)initWithText:(NSString *)text
                     comment:(NSString *)comment
                       index:(NSInteger)index {
    self = [super init];
    if (self) {
        _text = [text copy];
        _comment = [comment copy];
        _index = index;
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

/// Longest-prefix match against Mandarin pinyin syllables (no tones).
static NSString *OSGLongestPinyinSyllablePrefix(NSString *input) {
    static NSSet<NSString *> *syllables;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // Keep longest forms available; matcher tries length 6→1.
        syllables = [NSSet setWithArray:@[
            @"chuang", @"shuang", @"zhuang",
            @"chang", @"cheng", @"chong", @"chuai", @"chuan", @"chuo",
            @"hang", @"heng", @"hong", @"huai", @"huan", @"huang", @"huo",
            @"jiang", @"jiong", @"kuang", @"liang", @"niang", @"qiang", @"qiong",
            @"shang", @"sheng", @"shuai", @"shuan", @"shuo",
            @"xiang", @"xiong", @"zhang", @"zheng", @"zhong", @"zhuai", @"zhuan", @"zhuo",
            @"bang", @"beng", @"bian", @"biao", @"bing",
            @"cang", @"ceng", @"chai", @"chao", @"chen", @"chou", @"chua", @"chui", @"chun", @"cong", @"cuan", @"cui", @"cun", @"cuo",
            @"dang", @"deng", @"dian", @"diao", @"ding", @"dong", @"dou", @"duan", @"dui", @"dun", @"duo",
            @"fang", @"feng", @"fiao",
            @"gang", @"geng", @"gong", @"guai", @"guan", @"guang", @"guo",
            @"kang", @"keng", @"kong", @"kuai", @"kuan", @"kuo",
            @"lang", @"leng", @"lian", @"liao", @"ling", @"long", @"luan", @"lue", @"lun", @"luo", @"lüe",
            @"mang", @"meng", @"mian", @"miao", @"ming", @"miu",
            @"nang", @"neng", @"nian", @"niao", @"ning", @"nong", @"nuan", @"nue", @"nun", @"nuo", @"nüe",
            @"pang", @"peng", @"pian", @"piao", @"ping",
            @"rang", @"reng", @"rong", @"ruan", @"rui", @"run", @"ruo",
            @"sang", @"seng", @"shai", @"shan", @"shao", @"shei", @"shen", @"shou", @"shua", @"shui", @"shun", @"song", @"suan", @"sui", @"sun", @"suo",
            @"tang", @"teng", @"tian", @"tiao", @"ting", @"tong", @"tou", @"tuan", @"tui", @"tun", @"tuo",
            @"wang", @"weng",
            @"yang", @"ying", @"yong", @"yuan",
            @"zang", @"zeng", @"zhai", @"zhan", @"zhao", @"zhei", @"zhen", @"zhou", @"zhua", @"zhui", @"zhun", @"zong", @"zuan", @"zui", @"zun", @"zuo",
            @"ang", @"eng", @"ong",
            @"bai", @"ban", @"bao", @"bei", @"ben", @"bie", @"bin", @"bo", @"bu",
            @"cai", @"can", @"cao", @"ce", @"cen", @"cha", @"che", @"chi", @"chu", @"ci", @"cong", @"cou", @"cu",
            @"dai", @"dan", @"dao", @"de", @"dei", @"den", @"di", @"dia", @"die", @"diu", @"dong", @"dou", @"du",
            @"ei", @"en", @"er",
            @"fa", @"fan", @"fei", @"fen", @"fo", @"fou", @"fu",
            @"gai", @"gan", @"gao", @"ge", @"gei", @"gen", @"gou", @"gu",
            @"hai", @"han", @"hao", @"he", @"hei", @"hen", @"hou", @"hu",
            @"ji", @"jia", @"jie", @"jin", @"jiu", @"ju", @"juan", @"jue", @"jun",
            @"kai", @"kan", @"kao", @"ke", @"ken", @"kou", @"ku",
            @"lai", @"lan", @"lao", @"le", @"lei", @"leng", @"li", @"lia", @"lie", @"lin", @"liu", @"long", @"lou", @"lu", @"luan", @"lun", @"lü",
            @"mai", @"man", @"mao", @"me", @"mei", @"men", @"mi", @"mie", @"min", @"miu", @"mo", @"mou", @"mu",
            @"nai", @"nan", @"nao", @"ne", @"nei", @"nen", @"ni", @"nie", @"nin", @"niu", @"nong", @"nou", @"nu", @"nü",
            @"ou",
            @"pai", @"pan", @"pao", @"pei", @"pen", @"pi", @"pie", @"pin", @"po", @"pou", @"pu",
            @"qi", @"qia", @"qie", @"qin", @"qiu", @"qu", @"quan", @"que", @"qun",
            @"ran", @"rao", @"re", @"ren", @"ri", @"rou", @"ru",
            @"sai", @"san", @"sao", @"se", @"sen", @"sha", @"she", @"shi", @"shu", @"si", @"sou", @"su",
            @"tai", @"tan", @"tao", @"te", @"tei", @"ten", @"ti", @"tie", @"tou", @"tu",
            @"wa", @"wai", @"wan", @"wei", @"wen", @"wo", @"wu",
            @"xi", @"xia", @"xie", @"xin", @"xiu", @"xu", @"xuan", @"xue", @"xun",
            @"ya", @"yan", @"yao", @"ye", @"yi", @"yin", @"yo", @"you", @"yu", @"yue", @"yun",
            @"zai", @"zan", @"zao", @"ze", @"zei", @"zen", @"zha", @"zhe", @"zhi", @"zhou", @"zhu", @"zi", @"zou", @"zu",
            @"ai", @"an", @"ao",
            @"ba", @"bi", @"bu",
            @"ca", @"ce", @"ci", @"cu",
            @"da", @"de", @"di", @"du",
            @"fa", @"fo", @"fu",
            @"ga", @"ge", @"gu",
            @"ha", @"he", @"hu",
            @"ji", @"ju",
            @"ka", @"ke", @"ku",
            @"la", @"le", @"li", @"lo", @"lu", @"lü",
            @"ma", @"me", @"mi", @"mo", @"mu",
            @"na", @"ne", @"ni", @"nu", @"nü",
            @"pa", @"pi", @"po", @"pu",
            @"qi", @"qu",
            @"re", @"ri", @"ru",
            @"sa", @"se", @"si", @"su",
            @"ta", @"te", @"ti", @"tu",
            @"wa", @"wo", @"wu",
            @"xi", @"xu",
            @"ya", @"ye", @"yi", @"yo", @"yu",
            @"za", @"ze", @"zi", @"zu",
            @"a", @"e", @"o",
        ]];
    });

    NSInteger maxLen = MIN((NSInteger)6, (NSInteger)input.length);
    for (NSInteger len = maxLen; len >= 1; len--) {
        NSString *prefix = [input substringToIndex:(NSUInteger)len];
        if ([syllables containsObject:prefix]) {
            return prefix;
        }
    }
    return @"";
}

/// First spelling unit: pinyin syllable, or 2-key double-pinyin fallback.
static NSString *OSGFirstSpellingUnit(NSString *rawInput) {
    if (rawInput.length == 0) {
        return @"";
    }
    NSString *syllable = OSGLongestPinyinSyllablePrefix(rawInput);
    if (syllable.length > 0) {
        return syllable;
    }
    // Microsoft / Sogou double pinyin: typical syllable is two keys.
    if (rawInput.length > 2) {
        return [rawInput substringToIndex:2];
    }
    return @"";
}

/// When input continues past the first spelling unit, prefer multi-character
/// phrases first, then single-character first-syllable backups (PC-IME style).
static NSArray<OSGRimeCandidate *> *OSGAssembleDisplayCandidates(
    NSArray<OSGRimeCandidate *> *scanned,
    NSString *rawInput,
    NSInteger limit
) {
    if (limit <= 0 || scanned.count == 0) {
        return @[];
    }

    NSString *firstUnit = OSGFirstSpellingUnit(rawInput);
    BOOL hasRemainder = firstUnit.length > 0 && rawInput.length > firstUnit.length;
    if (!hasRemainder) {
        NSInteger count = MIN(limit, (NSInteger)scanned.count);
        return [scanned subarrayWithRange:NSMakeRange(0, (NSUInteger)count)];
    }

    NSMutableArray<OSGRimeCandidate *> *phrases = [NSMutableArray array];
    NSMutableArray<OSGRimeCandidate *> *characters = [NSMutableArray array];
    for (OSGRimeCandidate *candidate in scanned) {
        if (candidate.text.length >= 2) {
            [phrases addObject:candidate];
        } else if (candidate.text.length == 1) {
            [characters addObject:candidate];
        }
    }

    // Reserve roughly a quarter of the pool (min 24) for first-syllable chars.
    NSInteger charSlots = MIN((NSInteger)characters.count, MAX((NSInteger)24, limit / 4));
    NSInteger phraseSlots = MAX((NSInteger)0, limit - charSlots);

    NSMutableArray<OSGRimeCandidate *> *assembled = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];

    void (^appendUnique)(OSGRimeCandidate *, NSInteger) =
        ^(OSGRimeCandidate *candidate, NSInteger cap) {
            if ((NSInteger)assembled.count >= cap) {
                return;
            }
            if (candidate.text.length == 0 || [seen containsObject:candidate.text]) {
                return;
            }
            [seen addObject:candidate.text];
            [assembled addObject:candidate];
        };

    for (OSGRimeCandidate *candidate in phrases) {
        appendUnique(candidate, phraseSlots);
        if ((NSInteger)assembled.count >= phraseSlots) {
            break;
        }
    }
    for (OSGRimeCandidate *candidate in characters) {
        appendUnique(candidate, limit);
        if ((NSInteger)assembled.count >= limit) {
            return assembled;
        }
    }
    // Fill any leftover slots with remaining phrases.
    for (OSGRimeCandidate *candidate in phrases) {
        appendUnique(candidate, limit);
        if ((NSInteger)assembled.count >= limit) {
            break;
        }
    }
    return assembled;
}

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
    RIME_STRUCT(RimeContext_stdbool, context);
    if (api->get_context(self.session, &context)) {
        composing = context.composition.length > 0;
        if (context.composition.preedit) {
            preedit = [NSString stringWithUTF8String:context.composition.preedit];
        }
        api->free_context(&context);
    }

    NSString *rawInput = [self rawInput];
    NSInteger safeLimit = MAX((NSInteger)0, limit);
    NSString *firstUnit = OSGFirstSpellingUnit(rawInput);
    BOOL hasRemainder = firstUnit.length > 0 && rawInput.length > firstUnit.length;
    NSMutableArray<OSGRimeCandidate *> *scanned = [NSMutableArray array];
    // Deep-scan only when a trailing spelling unit exists so we can still
    // surface first-syllable characters buried under completion flood.
    NSInteger scanCap = hasRemainder ? MAX(safeLimit * 4, (NSInteger)400) : safeLimit;

    if (RIME_API_AVAILABLE(api, candidate_list_begin) &&
        RIME_API_AVAILABLE(api, candidate_list_next) &&
        RIME_API_AVAILABLE(api, candidate_list_end)) {
        RimeCandidateListIterator iterator = {0};
        if (api->candidate_list_begin(self.session, &iterator)) {
            NSInteger phrasesSeen = 0;
            NSInteger charsSeen = 0;
            NSInteger charQuota = hasRemainder ? MAX((NSInteger)24, safeLimit / 4) : 0;
            while ((NSInteger)scanned.count < scanCap && api->candidate_list_next(&iterator)) {
                NSString *text = iterator.candidate.text
                    ? [NSString stringWithUTF8String:iterator.candidate.text]
                    : @"";
                NSString *comment = iterator.candidate.comment
                    ? [NSString stringWithUTF8String:iterator.candidate.comment]
                    : @"";
                [scanned addObject:[[OSGRimeCandidate alloc] initWithText:text
                                                                  comment:comment
                                                                    index:iterator.index]];
                if (text.length >= 2) {
                    phrasesSeen += 1;
                } else if (text.length == 1) {
                    charsSeen += 1;
                }
                if (!hasRemainder && (NSInteger)scanned.count >= safeLimit) {
                    break;
                }
                if (hasRemainder && phrasesSeen >= safeLimit && charsSeen >= charQuota) {
                    break;
                }
            }
            api->candidate_list_end(&iterator);
        }
    }

    // Fallback: current menu page only (older librime / API hole).
    if (scanned.count == 0) {
        RIME_STRUCT(RimeContext_stdbool, menuContext);
        if (api->get_context(self.session, &menuContext)) {
            NSInteger count = MIN((NSInteger)menuContext.menu.num_candidates, safeLimit);
            for (NSInteger index = 0; index < count; index++) {
                RimeCandidate item = menuContext.menu.candidates[index];
                NSString *text = item.text ? [NSString stringWithUTF8String:item.text] : @"";
                NSString *comment = item.comment ? [NSString stringWithUTF8String:item.comment] : @"";
                // Menu indices are page-local; absolute index ≈ page_no * page_size + i.
                NSInteger absolute = (NSInteger)menuContext.menu.page_no
                    * (NSInteger)menuContext.menu.page_size
                    + index;
                [scanned addObject:[[OSGRimeCandidate alloc] initWithText:text
                                                                  comment:comment
                                                                    index:absolute]];
            }
            api->free_context(&menuContext);
        }
    }

    NSArray<OSGRimeCandidate *> *display =
        OSGAssembleDisplayCandidates(scanned, rawInput, safeLimit);

    return [[OSGRimeSnapshot alloc] initWithPreedit:preedit
                                        candidates:display
                                        commitText:commitText
                                         composing:composing];
}

@end
