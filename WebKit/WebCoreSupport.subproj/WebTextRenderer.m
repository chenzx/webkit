/*	
    WebTextRenderer.m	    
    Copyright 2002, Apple, Inc. All rights reserved.
*/

#import "WebTextRenderer.h"

#import <Cocoa/Cocoa.h>

#import <ApplicationServices/ApplicationServices.h>
#import <CoreGraphics/CoreGraphicsPrivate.h>

#import <WebCore/WebCoreUnicode.h>

#import <WebKit/WebGlyphBuffer.h>
#import <WebKit/WebKitLogging.h>
#import <WebKit/WebTextRendererFactory.h>
#import <WebKit/WebUnicode.h>

#import <QD/ATSUnicodePriv.h>

#import <AppKit/NSFont_Private.h>

#import <float.h>

#define NON_BREAKING_SPACE 0x00A0
#define SPACE 0x0020

#define IS_CONTROL_CHARACTER(c) ((c) < 0x0020 || (c) == 0x007F)

#define ROUND_TO_INT(x) (unsigned int)((x)+.5)

// Lose precision beyond 1000ths place. This is to work around an apparent
// bug in CoreGraphics where there seem to be small errors to some metrics.
#define CEIL_TO_INT(x) ((int)(x + 0.999)) /* ((int)(x + 1.0 - FLT_EPSILON)) */

// MAX_GLYPH_EXPANSION is the maximum numbers of glyphs that may be
// use to represent a single unicode code point.
#define MAX_GLYPH_EXPANSION 4
#define LOCAL_BUFFER_SIZE 2048

// Covers Latin1.
#define INITIAL_BLOCK_SIZE 0x200

// Get additional blocks of glyphs and widths in bigger chunks.
// This will typically be for other character sets.
#define INCREMENTAL_BLOCK_SIZE 0x400

#define UNINITIALIZED_GLYPH_WIDTH 65535

// combining char, hangul jamo, or Apple corporate variant tag
#define JunseongStart 0x1160
#define JonseongEnd 0x11F9
#define IsHangulConjoiningJamo(X) (X >= JunseongStart && X <= JonseongEnd)
#define IsNonBaseChar(X) ((CFCharacterSetIsCharacterMember(nonBaseChars, X) || IsHangulConjoiningJamo(X) || (((X) & 0x1FFFF0) == 0xF870)))

typedef float WebGlyphWidth;
typedef UInt32 UnicodeChar;

struct WidthEntry {
    WebGlyphWidth width;
};

struct WidthMap {
    ATSGlyphRef startRange;
    ATSGlyphRef endRange;
    WidthMap *next;
    WidthEntry *widths;
};

struct GlyphEntry
{
    ATSGlyphRef glyph;
    NSFont *font;
};

struct GlyphMap {
    UniChar startRange;
    UniChar endRange;
    GlyphMap *next;
    GlyphEntry *glyphs;
};

struct UnicodeGlyphMap {
    UnicodeChar startRange;
    UnicodeChar endRange;
    UnicodeGlyphMap *next;
    GlyphEntry *glyphs;
};

struct SubstituteFontWidthMap {
    NSFont *font;
    WidthMap *map;
};

struct CharacterWidthIterator
{
    WebTextRenderer *renderer;
    const WebCoreTextRun *run;
    const WebCoreTextStyle *style;
    unsigned currentCharacter;
    CharacterShapeIterator shapeIterator;
    unsigned int needsShaping;
};

static void initializeCharacterWidthIterator (CharacterWidthIterator *iterator, WebTextRenderer *renderer, const WebCoreTextRun *run , const WebCoreTextStyle *style);
static float widthForNextCharacter (CharacterWidthIterator *iterator);

// These somewhat cryptically named constants were 'borrowed' from
// some example carbon code.
#define kFixedOne ((Fixed)1<<16)
#define fixed1 ((Fixed) 0x00010000L)
#define FixToFloat(f) ((float)((f)  * (1./(float)kFixedOne)))
#define FloatToFixed(a) ((Fixed)((float)(a) * fixed1))

static inline BOOL shouldUseATSU(const WebCoreTextRun *run)
{
    UniChar c;
    const UniChar *characters = run->characters;
    int i, from = run->from, to = run->to;
    
    for (i = from; i < to; i++){
        c = characters[i];
        if (c < 0x300)                      // Early continue to avoid  other checks.
            continue;
            
        if (c >= 0x300 && c <= 0x36F)       // U+0300 through U+036F Combining diacritical marks
            return YES;
        if (c >= 0x20D0 && c <= 0x20FF)     // U+20D0 through U+20FF Combining marks for symbols
            return YES;
        if (c >= 0xFE20 && c <= 0xFE2f)     // U+FE20 through U+FE2F Combining half marks
            return YES;
        if (c >= 0x700 && c <= 0x1059)      // U+0700 through U+1059 Syriac, Thaana, Devanagari, Bengali, Gurmukhi, Gujarati, Oriya, Tamil, Telugu, Kannada, Malayalam, Sinhala, Thai, Lao, Tibetan, Myanmar
            return YES;
        if (c >= 0x1100 && c <= 0x11FF)     // U+1100 through U+11FF Hangul Jamo (only Ancient Korean should be left here if you precompose; Modern Korean will be precomposed as a result of step A)
            return YES;
        if (c >= 0x1780 && c <= 0x18AF)     // U+1780 through U+18AF Khmer, Mongolian
            return YES;
        if (c >= 0x1900 && c <= 0x194F)     // U+1900 through U+194F Limbu (Unicode 4.0)
            return YES;
    }
    
    return NO;
}

@interface NSLanguage : NSObject 
{
}
+ (NSLanguage *)defaultLanguage;
@end

@interface NSFont (WebPrivate)
- (ATSUFontID)_atsFontID;
- (CGFontRef)_backingCGSFont;
// Private method to find a font for a character.
+ (NSFont *) findFontLike:(NSFont *)aFont forCharacter:(UInt32)c inLanguage:(NSLanguage *) language;
+ (NSFont *) findFontLike:(NSFont *)aFont forString:(NSString *)string withRange:(NSRange)range inLanguage:(NSLanguage *) language;
- (NSGlyph)_defaultGlyphForChar:(unichar)uu;
- (BOOL)_forceAscenderDelta;
- (BOOL)_canDrawOutsideLineHeight;
- (BOOL)_isSystemFont;
- (BOOL)_isFakeFixedPitch;
@end

@class NSCGSFont;

// FIXME.  This is a horrible workaround to the problem described in 3129490
@interface NSCGSFont : NSFont {
    NSFaceInfo *_faceInfo;
    id _otherFont;	// Try to get rid of this???
    float *_matrix;
    struct _NS_cgsResv *_reservedCGS;
    float _constWidth;		// if isFixedPitch, the actual scaled width
}
@end

static CFCharacterSetRef nonBaseChars = NULL;


@interface WebTextRenderer (WebPrivate)

- (NSFont *)substituteFontForCharacters: (const unichar *)characters length: (int)numCharacters families: (NSString **)families;

- (WidthMap *)extendGlyphToWidthMapToInclude:(ATSGlyphRef)glyphID font:(NSFont *)font;
- (ATSGlyphRef)extendCharacterToGlyphMapToInclude:(UniChar) c;
- (ATSGlyphRef)extendUnicodeCharacterToGlyphMapToInclude: (UnicodeChar)c;
- (void)updateGlyphEntryForCharacter: (UniChar)c glyphID: (ATSGlyphRef)glyphID font: (NSFont *)substituteFont;

- (float)_floatWidthForRun:(const WebCoreTextRun *)run style:(const WebCoreTextStyle *)style widths:(float *)widthBuffer fonts:(NSFont **)fontBuffer glyphs:(CGGlyph *)glyphBuffer startGlyph:(int *)startGlyph endGlyph:(int *)endGlyph numGlyphs:(int *)_numGlyphs;

// Measuring runs.
- (float)_CG_floatWidthForRun:(const WebCoreTextRun *)run style:(const WebCoreTextStyle *)style widths: (float *)widthBuffer fonts: (NSFont **)fontBuffer glyphs: (CGGlyph *)glyphBuffer  startGlyph:(int *)startGlyph endGlyph:(int *)endGlyph numGlyphs: (int *)_numGlyphs;
- (float)_ATSU_floatWidthForRun:(const WebCoreTextRun *)run style:(const WebCoreTextStyle *)style;

// Drawing runs.
- (void)_CG_drawRun:(const WebCoreTextRun *)run style:(const WebCoreTextStyle *)style atPoint:(NSPoint)point;
- (void)_ATSU_drawRun:(const WebCoreTextRun *)run style:(const WebCoreTextStyle *)style atPoint:(NSPoint)point;

// Selection point detection in runs.
- (int)_CG_pointToOffset:(const WebCoreTextRun *)run style:(const WebCoreTextStyle *)style position:(int)x reversed:(BOOL)reversed;
- (int)_ATSU_pointToOffset:(const WebCoreTextRun *)run style:(const WebCoreTextStyle *)style position:(int)x reversed:(BOOL)reversed;

// Drawing highlight for runs.
- (void)_CG_drawHighlightForRun:(const WebCoreTextRun *)run style:(const WebCoreTextStyle *)style atPoint:(NSPoint)point;
- (void)_ATSU_drawHighlightForRun:(const WebCoreTextRun *)run style:(const WebCoreTextStyle *)style atPoint:(NSPoint)point;

@end


static void freeWidthMap (WidthMap *map)
{
    if (!map)
	return;
    freeWidthMap (map->next);
    free (map->widths);
    free (map);
}


static void freeGlyphMap (GlyphMap *map)
{
    if (!map)
	return;
    freeGlyphMap (map->next);
    free (map->glyphs);
    free (map);
}


static inline ATSGlyphRef glyphForCharacter (GlyphMap *map, UniChar c, NSFont **font)
{
    if (map == 0)
        return nonGlyphID;
        
    if (c >= map->startRange && c <= map->endRange){
        *font = map->glyphs[c-map->startRange].font;
        return map->glyphs[c-map->startRange].glyph;
    }
        
    return glyphForCharacter (map->next, c, font);
}
 
 
static inline ATSGlyphRef glyphForUnicodeCharacter (UnicodeGlyphMap *map, UnicodeChar c, NSFont **font)
{
    if (map == 0)
        return nonGlyphID;
        
    if (c >= map->startRange && c <= map->endRange){
        *font = map->glyphs[c-map->startRange].font;
        return map->glyphs[c-map->startRange].glyph;
    }
        
    return glyphForUnicodeCharacter (map->next, c, font);
}
 

#ifdef _TIMING        
static double totalCGGetAdvancesTime = 0;
#endif

static inline SubstituteFontWidthMap *mapForSubstituteFont(WebTextRenderer *renderer, NSFont *font)
{
    int i;
    
    for (i = 0; i < renderer->numSubstituteFontWidthMaps; i++){
        if (font == renderer->substituteFontWidthMaps[i].font)
            return &renderer->substituteFontWidthMaps[i];
    }
    
    if (renderer->numSubstituteFontWidthMaps == renderer->maxSubstituteFontWidthMaps){
        renderer->maxSubstituteFontWidthMaps = renderer->maxSubstituteFontWidthMaps * 2;
        renderer->substituteFontWidthMaps = realloc (renderer->substituteFontWidthMaps, renderer->maxSubstituteFontWidthMaps * sizeof(SubstituteFontWidthMap));
        for (i = renderer->numSubstituteFontWidthMaps; i < renderer->maxSubstituteFontWidthMaps; i++){
            renderer->substituteFontWidthMaps[i].font = 0;
            renderer->substituteFontWidthMaps[i].map = 0;
        }
    }
    
    renderer->substituteFontWidthMaps[renderer->numSubstituteFontWidthMaps].font = font;
    return &renderer->substituteFontWidthMaps[renderer->numSubstituteFontWidthMaps++];
}

static inline WebGlyphWidth widthFromMap (WebTextRenderer *renderer, WidthMap *map, ATSGlyphRef glyph, NSFont *font)
{
    WebGlyphWidth width = UNINITIALIZED_GLYPH_WIDTH;
    BOOL errorResult;
    
    while (1){
        if (map == 0)
            map = [renderer extendGlyphToWidthMapToInclude: glyph font:font];

        if (glyph >= map->startRange && glyph <= map->endRange){
            width = map->widths[glyph-map->startRange].width;
            if (width == UNINITIALIZED_GLYPH_WIDTH){

#ifdef _TIMING
                double startTime = CFAbsoluteTimeGetCurrent();
#endif
                if (font)
                    errorResult = CGFontGetGlyphScaledAdvances ([font _backingCGSFont], &glyph, 1, &map->widths[glyph-map->startRange].width, [renderer->font pointSize]);
                else
                    errorResult = CGFontGetGlyphScaledAdvances ([renderer->font _backingCGSFont], &glyph, 1, &map->widths[glyph-map->startRange].width, [renderer->font pointSize]);
                if (errorResult == 0)
                    FATAL_ALWAYS ("Unable to cache glyph widths for %@ %f",  [renderer->font displayName], [renderer->font pointSize]);

#ifdef _TIMING
                double thisTime = CFAbsoluteTimeGetCurrent() - startTime;
                totalCGGetAdvancesTime += thisTime;
#endif
                width = map->widths[glyph-map->startRange].width;
            }
        }

        if (width == UNINITIALIZED_GLYPH_WIDTH){
            map = map->next;
            continue;
        }
        
        // Hack to ensure that characters that match the width of the space character
        // have the same integer width as the space character.  This is necessary so
        // glyphs in fixed pitch fonts all have the same integer width.  We can't depend
        // on the fixed pitch property of NSFont because that isn't set for all
        // monospaced fonts, in particular Courier!  This has the downside of inappropriately
        // adjusting the widths of characters in non-monospaced fonts that are coincidentally
        // the same width as a space in that font.  In practice this is not an issue as the
        // adjustment is always as the sub-pixel level.
        if (width == renderer->spaceWidth)
            return renderer->ceiledSpaceWidth;

        return width;
    }
    // never get here.
    return 0;
}    

static inline WebGlyphWidth widthForGlyph (WebTextRenderer *renderer, ATSGlyphRef glyph, NSFont *font)
{
    WidthMap *map;

    if (font && font != renderer->font)
        map = mapForSubstituteFont(renderer, font)->map;
    else
        map = renderer->glyphToWidthMap;

    return widthFromMap (renderer, map, glyph, font);
}


void initializeCharacterWidthIterator (CharacterWidthIterator *iterator, WebTextRenderer *renderer, const WebCoreTextRun *run , const WebCoreTextStyle *style) 
{
    iterator->needsShaping = initializeCharacterShapeIterator (&iterator->shapeIterator, run);
    iterator->renderer = renderer;
    iterator->run = run;
    iterator->style = style;
    iterator->currentCharacter = run->from;
}

static float widthAndGlyphForSurrogate (WebTextRenderer *renderer, UniChar high, UniChar low, ATSGlyphRef *glyphID, NSString **families)
{
    UnicodeChar uc = UnicodeValueForSurrogatePair(high, low);
    NSFont *font = renderer->font;

    *glyphID = glyphForUnicodeCharacter(renderer->unicodeCharacterToGlyphMap, uc, &font);
    if (*glyphID == nonGlyphID) {
        *glyphID = [renderer extendUnicodeCharacterToGlyphMapToInclude: uc];
    }

    if (*glyphID == 0){
        UniChar surrogates[2];
        unsigned int clusterLength;
        
        clusterLength = 2;
        surrogates[0] = high;
        surrogates[1] = low;
        NSFont *substituteFont = [renderer substituteFontForCharacters:&surrogates[0] length: clusterLength families: families];
        if (substituteFont){
            WebTextRenderer *substituteRenderer = [[WebTextRendererFactory sharedFactory] rendererWithFont:substituteFont usingPrinterFont:renderer->usingPrinterFont];
            *glyphID = glyphForUnicodeCharacter(substituteRenderer->unicodeCharacterToGlyphMap, uc, &font);
            if (*glyphID == nonGlyphID)
                *glyphID = [substituteRenderer extendUnicodeCharacterToGlyphMapToInclude: uc];
            return widthForGlyph (substituteRenderer, *glyphID, substituteFont);
       }
    }
    return widthForGlyph (renderer, *glyphID, font);
}

static float widthForNextCharacter (CharacterWidthIterator *iterator)
{
    WebTextRenderer *renderer = iterator->renderer;
    const WebCoreTextRun *run = iterator->run;
    NSFont *font = renderer->font;
    UniChar c;
    unsigned int offset = iterator->currentCharacter;

    if (offset >= run->length)
        // Error!  Offset specified beyond end of run.
        return 0;
        
    // Determine if the string requires any shaping, i.e. Arabic.
    if (iterator->needsShaping)
        c = shapeForNextCharacter(&iterator->shapeIterator);
    else
        c = run->characters[offset];
    iterator->currentCharacter++;
    
    // It's legit to sometimes get 0 from the shape iterator, return a zero width.
    if (c == 0)
        return 0;


    // Get a glyph for the next characters.  Somewhat complicated by surrogate
    // pairs.
    ATSGlyphRef glyphID;

    // Do we have a surrogate pair?  If so, determine the full Unicode (32bit)
    // code point before glyph lookup.  We only provide a width when the offset
    // specifies the first component of the surrogate pair.
    if (c >= HighSurrogateRangeStart && c <= HighSurrogateRangeEnd) {
        UniChar high = c, low;

        // Make sure we have another character and it's a low surrogate.
        if (offset+1 >= run->length || !IsLowSurrogatePair((low = run->characters[offset+1]))) {
            // Error!  The second component of the surrogate pair is missing.
            return 0;
        }

        return widthAndGlyphForSurrogate (renderer, high, low, &glyphID, iterator->style->families);
    }
    else if (c >= LowSurrogateRangeStart && c <= LowSurrogateRangeEnd) {
        // Return 0 width for second component of the surrogate pair.
        return 0;
    }
    else
        glyphID = glyphForCharacter(renderer->characterToGlyphMap, c, &font);
    
    // Now that we have glyph get it's width.
    return widthForGlyph (renderer, glyphID, font);
}


static BOOL FillStyleWithAttributes(ATSUStyle style, NSFont *theFont)
{
    if (theFont) {
        ATSUFontID fontId = (ATSUFontID)[theFont _atsFontID];
        ATSUAttributeTag tag = kATSUFontTag;
        ByteCount size = sizeof(ATSUFontID);
        ATSUFontID *valueArray[1] = {&fontId};

        if (fontId) {
            if (ATSUSetAttributes(style, 1, &tag, &size, (void *)valueArray) != noErr)
                return NO;
        }
        else {
            return NO;
        }
        return YES;
    }
    return NO;
}


static unsigned int findLengthOfCharacterCluster(const UniChar *characters, unsigned int length)
{
    unsigned int k;

    if (length <= 1)
        return length;
    
    if (IsHighSurrogatePair(characters[0]))
        return 2;
        
    if (IsNonBaseChar(characters[0]))
        return 1;
    
    // Find all the non base characters after the current character.
    for (k = 1; k < length; k++)
        if (!IsNonBaseChar(characters[k]))
            break;
    return k;
}

@implementation WebTextRenderer

static BOOL bufferTextDrawing = NO;

+ (BOOL)shouldBufferTextDrawing
{
    return bufferTextDrawing;
}

+ (void)initialize
{
    nonBaseChars = CFCharacterSetGetPredefined(kCFCharacterSetNonBase);
    bufferTextDrawing = [[[NSUserDefaults standardUserDefaults] stringForKey:@"BufferTextDrawing"] isEqual: @"YES"];
}

static inline BOOL _fontContainsString (NSFont *font, NSString *string)
{
    if ([string rangeOfCharacterFromSet:[[font coveredCharacterSet] invertedSet]].location == NSNotFound) {
        return YES;
    }
    return NO;
}

- (NSFont *)substituteFontForString: (NSString *)string families: (NSString **)families
{
    NSFont *substituteFont = nil;

    // First search the CSS family fallback list.  Start at 1 (2nd font)
    // because we've already failed on the first lookup.
    NSString *family = nil;
    int i = 1;
    while (families && families[i] != 0) {
        family = families[i++];
        substituteFont = [[WebTextRendererFactory sharedFactory] cachedFontFromFamily: family traits:[[NSFontManager sharedFontManager] traitsOfFont:font] size:[font pointSize]];
        if (substituteFont && _fontContainsString(substituteFont, string)){
            return substituteFont;
        }
    }
    
    // Now do string based lookup.
    substituteFont = [NSFont findFontLike:font forString:string withRange:NSMakeRange (0,[string length]) inLanguage:[NSLanguage defaultLanguage]];

    // Now do character based lookup.
    if (substituteFont == nil && [string length] == 1)
        substituteFont = [NSFont findFontLike:font forCharacter: [string characterAtIndex: 0] inLanguage:[NSLanguage defaultLanguage]];
    
    if ([substituteFont isEqual: font])
        substituteFont = nil;
    
    return substituteFont;
}


- (NSFont *)substituteFontForCharacters: (const unichar *)characters length: (int)numCharacters families: (NSString **)families
{
    NSFont *substituteFont;
    NSString *string = [[NSString alloc] initWithCharactersNoCopy:(unichar *)characters length: numCharacters freeWhenDone: NO];

    substituteFont = [self substituteFontForString: string families: families];

    [string release];
    
    return substituteFont;
}


/* Convert non-breaking spaces into spaces, and skip control characters. */
- (void)convertCharacters: (const UniChar *)characters length: (unsigned)numCharacters toGlyphs: (ATSGlyphVector *)glyphs skipControlCharacters:(BOOL)skipControlCharacters
{
    unsigned i, numCharactersInBuffer;
    UniChar localBuffer[LOCAL_BUFFER_SIZE];
    UniChar *buffer = localBuffer;
    OSStatus status;
    
    for (i = 0; i < numCharacters; i++) {
        UniChar c = characters[i];
        if ((skipControlCharacters && IS_CONTROL_CHARACTER(c)) || c == NON_BREAKING_SPACE) {
            break;
        }
    }
    
    if (i < numCharacters) {
        if (numCharacters > LOCAL_BUFFER_SIZE) {
            buffer = (UniChar *)malloc(sizeof(UniChar) * numCharacters);
        }
        
        numCharactersInBuffer = 0;
        for (i = 0; i < numCharacters; i++) {
            UniChar c = characters[i];
            if (c == NON_BREAKING_SPACE) {
                buffer[numCharactersInBuffer++] = SPACE;
            } else if (!(skipControlCharacters && IS_CONTROL_CHARACTER(c))) {
                buffer[numCharactersInBuffer++] = characters[i];
            }
        }
        
        characters = buffer;
        numCharacters = numCharactersInBuffer;
    }
    
    status = ATSUConvertCharToGlyphs(styleGroup, characters, 0, numCharacters, 0, glyphs);
    if (status != noErr){
        FATAL_ALWAYS ("unable to get glyphsfor %@ %f error = (%d)", self, [font displayName], [font pointSize], status);
    }

#ifdef DEBUG_GLYPHS
    int foundGlyphs = 0;
    ATSLayoutRecord *glyphRecord;
    for (i = 0; i < numCharacters; i++) {
        glyphRecord = (ATSLayoutRecord *)glyphs->firstRecord;
        for (i = 0; i < numCharacters; i++) {
            if (glyphRecord->glyphID != 0)
                foundGlyphs++;
            glyphRecord = (ATSLayoutRecord *)((char *)glyphRecord + glyphs->recordSize);
        }
    }
    printf ("For %s found %d glyphs in range 0x%04x to 0x%04x\n", [[font displayName] cString], foundGlyphs, characters[0], characters[numCharacters-1]);
#endif
    if (buffer != localBuffer) {
        free(buffer);
    }
}


- (void)convertUnicodeCharacters: (const UnicodeChar *)characters length: (unsigned)numCharacters toGlyphs: (ATSGlyphVector *)glyphs
{
    unsigned numCharactersInBuffer;
    UniChar localBuffer[LOCAL_BUFFER_SIZE];
    UniChar *buffer = localBuffer;
    OSStatus status;
    unsigned i, bufPos = 0;
    
    if (numCharacters*2 > LOCAL_BUFFER_SIZE) {
        buffer = (UniChar *)malloc(sizeof(UniChar) * numCharacters * 2);
    }
    
    numCharactersInBuffer = 0;
    for (i = 0; i < numCharacters; i++) {
        UnicodeChar c = characters[i];
        UniChar h = HighSurrogatePair(c);
        UniChar l = LowSurrogatePair(c);
        buffer[bufPos++] = h;
        buffer[bufPos++] = l;
    }
        
    status = ATSUConvertCharToGlyphs(styleGroup, buffer, 0, numCharacters*2, 0, glyphs);
    if (status != noErr){
        FATAL_ALWAYS ("unable to get glyphsfor %@ %f error = (%d)", self, [font displayName], [font pointSize], status);
    }
    
    if (buffer != localBuffer) {
        free(buffer);
    }
}

// Nasty hack to determine if we should round or ceil space widths.
// If the font is monospace, or fake monospace we ceil to ensure that 
// every character and the space are the same width.  Otherwise we round.
- (BOOL)_computeWidthForSpace
{
    UniChar c = ' ';
    float _spaceWidth;

    spaceGlyph = [self extendCharacterToGlyphMapToInclude: c];
    if (spaceGlyph == 0){
        return NO;
    }
    _spaceWidth = widthForGlyph(self, spaceGlyph, 0);
    ceiledSpaceWidth = (float)CEIL_TO_INT(_spaceWidth);
    roundedSpaceWidth = (float)ROUND_TO_INT(_spaceWidth);
    if ([font isFixedPitch] || [font _isFakeFixedPitch]){
        adjustedSpaceWidth = ceiledSpaceWidth;
    }
    else {
        adjustedSpaceWidth = roundedSpaceWidth;
    }
    spaceWidth = _spaceWidth;
    
    return YES;
}

- (BOOL)_setupFont: (NSFont *)f
{
    OSStatus errCode;
    ATSUStyle fontStyle;
    
    if ((errCode = ATSUCreateStyle(&fontStyle)) != noErr)
        return NO;

    if (!FillStyleWithAttributes(fontStyle, font))
        return NO;

    if ((errCode = ATSUGetStyleGroup(fontStyle, &styleGroup)) != noErr){
        ATSUDisposeStyle(fontStyle);
        return NO;
    }
    
    ATSUDisposeStyle(fontStyle);

    if (![self _computeWidthForSpace]){
        if (styleGroup){
            ATSUDisposeStyleGroup(styleGroup);
            styleGroup = 0;
        }
        return NO;
    }
   
    return YES;
}

#define ATSFontRefFromNSFont(font) (FMGetATSFontRefFromFont((FMFont)[font _atsFontID]))
static NSString *pathFromFont (NSFont *font)
{
    UInt8 _filePathBuffer[PATH_MAX];
    NSString *filePath = nil;
    FSSpec oFile;
    OSStatus status = ATSFontGetFileSpecification(
            ATSFontRefFromNSFont(font),
            &oFile);
    if (status == noErr){
        OSErr err;
        FSRef fileRef;
        err = FSpMakeFSRef(&oFile,&fileRef);
        if (err == noErr){
            status = FSRefMakePath(&fileRef,_filePathBuffer, PATH_MAX);
            if (status == noErr){
                filePath = [NSString stringWithUTF8String:&_filePathBuffer[0]];
            }
        }
    }
    return filePath;
}

static NSString *WebFallbackFontFamily;

- initWithFont:(NSFont *)f usingPrinterFont:(BOOL)p
{
    if ([f glyphPacking] != NSNativeShortGlyphPacking &&
        [f glyphPacking] != NSTwoByteGlyphPacking)
        FATAL_ALWAYS ("%@: Don't know how to pack glyphs for font %@ %f", self, [f displayName], [f pointSize]);
        
    [super init];
    
    maxSubstituteFontWidthMaps = NUM_SUBSTITUTE_FONT_MAPS;
    substituteFontWidthMaps = calloc (1, maxSubstituteFontWidthMaps * sizeof(SubstituteFontWidthMap));
    font = [(p ? [f printerFont] : [f screenFont]) retain];
    usingPrinterFont = p;
    
    if (![self _setupFont:font]){
        // Ack!  Something very bad happened, like a corrupt font.  Try
        // looking for an alternate 'base' font for this renderer.

        // Special case hack to use "Times New Roman" in place of "Times".  "Times RO" is a common font
        // whose family name is "Times".  It overrides the normal "Times" family font.  It also
        // appears to have a corrupt regular variant.
        NSString *fallbackFontFamily;

        if ([[font familyName] isEqual:@"Times"])
            fallbackFontFamily = @"Times New Roman";
        else {
            if (!WebFallbackFontFamily)
                // Could use any size, we just care about the family of the system font.
                WebFallbackFontFamily = [[[NSFont systemFontOfSize:16.0] familyName] retain];
                
            fallbackFontFamily = WebFallbackFontFamily;
        }
        
        // Try setting up the alternate font.
        NSFont *alternateFont = [[NSFontManager sharedFontManager] convertFont:font toFamily:fallbackFontFamily];
        NSFont *initialFont = font;
        [initialFont autorelease];
        font = [alternateFont retain];
        NSString *filePath = pathFromFont(initialFont);
        filePath = filePath ? filePath : @"not known";
        if (![self _setupFont:alternateFont]){
            // Give up!
            FATAL_ALWAYS ("%@ unable to initialize with font %@ at %@", self, initialFont, filePath);
        }

        // Report the problem.
        ERROR ("Corrupt font detected, using %@ in place of %@ (%d glyphs) located at \"%@\".", 
                    [alternateFont familyName], 
                    [initialFont familyName],
                    ATSFontGetGlyphCount(ATSFontRefFromNSFont(initialFont)),
                    filePath);
    }

    // We emulate the appkit metrics by applying rounding as is done
    // in the appkit.
    CGFontRef cgFont = [f _backingCGSFont];
    const CGFontHMetrics *metrics = CGFontGetHMetrics(cgFont);
    unsigned int unitsPerEm = CGFontGetUnitsPerEm(cgFont);
    float pointSize = [f pointSize];
    float asc = (ScaleEmToUnits(metrics->ascent, unitsPerEm)*pointSize);
    float dsc = (-ScaleEmToUnits(metrics->descent, unitsPerEm)*pointSize);
    float lineGap = ScaleEmToUnits(metrics->lineGap, unitsPerEm)*pointSize;
    float adjustment;

    // We need to adjust Times, Helvetica, and Courier to closely match the
    // vertical metrics of their Microsoft counterparts that are the de facto
    // web standard.  The AppKit adjustment of 20% is too big and is
    // incorrectly added to line spacing, so we use a 15% adjustment instead
    // and add it to the ascent.
    if ([[font familyName] isEqualToString:@"Times"] ||
        [[font familyName] isEqualToString:@"Helvetica"] ||
        [[font familyName] isEqualToString:@"Courier"]) {
        adjustment = floor(((asc + dsc) * 0.15) + 0.5);
    } else {
        adjustment = 0.0;
    }

    ascent = ROUND_TO_INT(asc + adjustment);
    descent = ROUND_TO_INT(dsc);

    lineSpacing =  ascent + descent + (int)(lineGap > 0.0 ? floor(lineGap + 0.5) : 0.0);

#ifdef COMPARE_APPKIT_CG_METRICS
    printf ("\nCG/Appkit metrics for font %s, %f, lineGap %f, adjustment %f, _canDrawOutsideLineHeight %d, _isSystemFont %d\n", [[f displayName] cString], [f pointSize], lineGap, adjustment, (int)[f _canDrawOutsideLineHeight], (int)[f _isSystemFont]);
    if ((int)ROUND_TO_INT([f ascender]) != ascent ||
        (int)ROUND_TO_INT(-[f descender]) != descent ||
        (int)ROUND_TO_INT([font defaultLineHeightForFont]) != lineSpacing){
        printf ("\nCG/Appkit mismatched metrics for font %s, %f (%s)\n", [[f displayName] cString], [f pointSize],
                ([f screenFont] ? [[[f screenFont] displayName] cString] : "none"));
        printf ("ascent(%s), descent(%s), lineSpacing(%s)\n",
                ((int)ROUND_TO_INT([f ascender]) != ascent) ? "different" : "same",
                ((int)ROUND_TO_INT(-[f descender]) != descent) ? "different" : "same",
                ((int)ROUND_TO_INT([font defaultLineHeightForFont]) != lineSpacing) ? "different" : "same");
        printf ("CG:  ascent %f, ", asc);
        printf ("descent %f, ", dsc);
        printf ("lineGap %f, ", lineGap);
        printf ("lineSpacing %d\n", lineSpacing);
        
        printf ("NSFont:  ascent %f, ", [f ascender]);
        printf ("descent %f, ", [f descender]);
        printf ("lineSpacing %f\n", [font defaultLineHeightForFont]);
    }
#endif
     
    return self;
}


- (void)dealloc
{
    [font release];

    if (styleGroup)
        ATSUDisposeStyleGroup(styleGroup);

    freeWidthMap (glyphToWidthMap);
    freeGlyphMap (characterToGlyphMap);

    if (ATSUStyleInitialized)
        ATSUDisposeStyle(_ATSUSstyle);
    
    [super dealloc];
}


- (int)widthForCharacters:(const UniChar *)characters length:(unsigned)stringLength
{
    WebCoreTextRun run;
    WebCoreInitializeTextRun (&run, characters, stringLength, 0, stringLength);
    WebCoreTextStyle style;
    WebCoreInitializeEmptyTextStyle(&style);
    return ROUND_TO_INT([self floatWidthForRun:&run style:&style widths: 0]);
}

- (int)widthForString:(NSString *)string
{
    UniChar localCharacterBuffer[LOCAL_BUFFER_SIZE];
    UniChar *characterBuffer = localCharacterBuffer;
    const UniChar *usedCharacterBuffer = CFStringGetCharactersPtr((CFStringRef)string);
    unsigned int length;
    int width;

    // Get the characters from the string into a buffer.
    length = [string length];
    if (!usedCharacterBuffer) {
        if (length > LOCAL_BUFFER_SIZE)
            characterBuffer = (UniChar *)malloc(length * sizeof(UniChar));
        [string getCharacters:characterBuffer];
        usedCharacterBuffer = characterBuffer;
    }

    width = [self widthForCharacters:usedCharacterBuffer length:length];
    
    if (characterBuffer != localCharacterBuffer)
        free(characterBuffer);

    return width;
}


- (int)ascent
{
    return ascent;
}


- (int)descent
{
    return descent;
}


- (int)lineSpacing
{
    return lineSpacing;
}


- (float)xHeight
{
    return [font xHeight];
}


// Useful page for testing http://home.att.net/~jameskass
static void _drawGlyphs(NSFont *font, NSColor *color, CGGlyph *glyphs, CGSize *advances, float x, float y, int numGlyphs)
{
    CGContextRef cgContext;

    if ([WebTextRenderer shouldBufferTextDrawing] && [[WebTextRendererFactory sharedFactory] coalesceTextDrawing]){
        // Add buffered glyphs and advances
        // FIXME:  If we ever use this again, need to add RTL.
        WebGlyphBuffer *gBuffer = [[WebTextRendererFactory sharedFactory] glyphBufferForFont: font andColor: color];
        [gBuffer addGlyphs: glyphs advances: advances count: numGlyphs at: x : y];
    }
    else {
        cgContext = (CGContextRef)[[NSGraphicsContext currentContext] graphicsPort];
        // Setup the color and font.
        [color set];
        [font set];

        CGContextSetTextPosition (cgContext, x, y);
        CGContextShowGlyphsWithAdvances (cgContext, glyphs, advances, numGlyphs);
    }
}

- (void)drawHighlightForRun:(const WebCoreTextRun *)run style:(const WebCoreTextStyle *)style atPoint:(NSPoint)point
{
    if (shouldUseATSU(run))
        [self _ATSU_drawHighlightForRun:run style:style atPoint:point];
    else
        [self _CG_drawHighlightForRun:run style:style atPoint:point];
}

- (void)_CG_drawHighlightForRun:(const WebCoreTextRun *)run style:(const WebCoreTextStyle *)style atPoint:(NSPoint)point
{
    float *widthBuffer, localWidthBuffer[LOCAL_BUFFER_SIZE];
    CGGlyph *glyphBuffer, localGlyphBuffer[LOCAL_BUFFER_SIZE];
    NSFont **fontBuffer, *localFontBuffer[LOCAL_BUFFER_SIZE];
    CGSize *advances, localAdvanceBuffer[LOCAL_BUFFER_SIZE];
    int numGlyphs = 0, i, startGlyph = 0, endGlyph = 0;
    float startX;
    unsigned int length = run->length;
    
    if (run->length == 0)
        return;

    if (length*MAX_GLYPH_EXPANSION > LOCAL_BUFFER_SIZE) {
        advances = (CGSize *)calloc(length*MAX_GLYPH_EXPANSION, sizeof(CGSize));
        widthBuffer = (float *)calloc(length*MAX_GLYPH_EXPANSION, sizeof(float));
        glyphBuffer = (CGGlyph *)calloc(length*MAX_GLYPH_EXPANSION, sizeof(ATSGlyphRef));
        fontBuffer = (NSFont **)calloc(length*MAX_GLYPH_EXPANSION, sizeof(NSFont *));
    } else {
        advances = localAdvanceBuffer;
        widthBuffer = localWidthBuffer;
        glyphBuffer = localGlyphBuffer;
        fontBuffer = localFontBuffer;
    }

    [self _floatWidthForRun:run
        style:style
        widths:widthBuffer 
        fonts:fontBuffer
        glyphs:glyphBuffer
        startGlyph:&startGlyph
        endGlyph:&endGlyph
        numGlyphs: &numGlyphs];
        
    // Eek.  We couldn't generate ANY glyphs for the run.
    if (numGlyphs <= 0)
        return;
        
    // Fill the advances array.
    for (i = 0; i <= endGlyph; i++){
        advances[i].width = widthBuffer[i];
        advances[i].height = 0;
    }

    // Calculate the starting point of the glyphs to be displayed by adding
    // all the advances up to the first glyph.
    startX = point.x;
    for (i = 0; i < startGlyph; i++)
        startX += advances[i].width;

    if (style->backgroundColor != nil){
        // Calculate the width of the selection background by adding
        // up teh advances of all the glyphs in the selection.
        float backgroundWidth = 0.0;
        
        for (i = startGlyph; i <= endGlyph; i++)
            backgroundWidth += advances[i].width;

        [style->backgroundColor set];
        
        if (style->rtl){
            WebCoreTextRun completeRun = *run;
            completeRun.from = 0;
            completeRun.to = run->length;
            float completeRunWidth = [self floatWidthForRun:&completeRun style:style widths:widthBuffer];
            float leftX = 0;
            for (i = 0; i < startGlyph; i++)
                leftX += widthBuffer[i];

            [NSBezierPath fillRect:NSMakeRect(point.x + completeRunWidth - leftX - backgroundWidth, point.y - [self ascent], backgroundWidth, [self lineSpacing])];
        }
        else
            [NSBezierPath fillRect:NSMakeRect(startX, point.y - [self ascent], backgroundWidth, [self lineSpacing])];
    }
    
    if (advances != localAdvanceBuffer) {
        free(advances);
        free(widthBuffer);
        free(glyphBuffer);
        free(fontBuffer);
    }
}

- (void)drawRun:(const WebCoreTextRun *)run style:(const WebCoreTextStyle *)style atPoint:(NSPoint)point
{
    if (shouldUseATSU(run))
        [self _ATSU_drawRun:run style:style atPoint:point];
    else
        [self _CG_drawRun:run style:style atPoint:point];
}

- (void)_CG_drawRun:(const WebCoreTextRun *)run style:(const WebCoreTextStyle *)style atPoint:(NSPoint)point
{
    float *widthBuffer, localWidthBuffer[LOCAL_BUFFER_SIZE];
    CGGlyph *glyphBuffer, localGlyphBuffer[LOCAL_BUFFER_SIZE];
    NSFont **fontBuffer, *localFontBuffer[LOCAL_BUFFER_SIZE];
    CGSize *advances, localAdvanceBuffer[LOCAL_BUFFER_SIZE];
    int numGlyphs = 0, i, startGlyph = 0, endGlyph = 0;
    float startX;
    unsigned int length = run->length;
    
    if (run->length == 0)
        return;

    if (length*MAX_GLYPH_EXPANSION > LOCAL_BUFFER_SIZE) {
        advances = (CGSize *)calloc(length*MAX_GLYPH_EXPANSION, sizeof(CGSize));
        widthBuffer = (float *)calloc(length*MAX_GLYPH_EXPANSION, sizeof(float));
        glyphBuffer = (CGGlyph *)calloc(length*MAX_GLYPH_EXPANSION, sizeof(ATSGlyphRef));
        fontBuffer = (NSFont **)calloc(length*MAX_GLYPH_EXPANSION, sizeof(NSFont *));
    } else {
        advances = localAdvanceBuffer;
        widthBuffer = localWidthBuffer;
        glyphBuffer = localGlyphBuffer;
        fontBuffer = localFontBuffer;
    }

    [self _floatWidthForRun:run
        style:style
        widths:widthBuffer 
        fonts:fontBuffer
        glyphs:glyphBuffer
        startGlyph:&startGlyph
        endGlyph:&endGlyph
        numGlyphs: &numGlyphs];
        
    // Eek.  We couldn't generate ANY glyphs for the run.
    if (numGlyphs <= 0)
        return;
        
    // Fill the advances array.
    for (i = 0; i <= endGlyph; i++){
        advances[i].width = widthBuffer[i];
        advances[i].height = 0;
    }

    // Calculate the starting point of the glyphs to be displayed by adding
    // all the advances up to the first glyph.
    startX = point.x;
    for (i = 0; i < startGlyph; i++)
        startX += advances[i].width;

    if (style->backgroundColor != nil)
        [self _CG_drawHighlightForRun:run style:style atPoint:point];
    
    // Finally, draw the glyphs.
    int lastFrom = startGlyph;
    int pos = startGlyph;

    // Swap the order of the glyphs if right-to-left.
    if (style->rtl && numGlyphs > 1){
        int i;
        int end = numGlyphs;
        CGGlyph gswap1, gswap2;
        CGSize aswap1, aswap2;
        NSFont *fswap1, *fswap2;
        
        for (i = pos, end = numGlyphs; i < (numGlyphs - pos)/2; i++){
            gswap1 = glyphBuffer[i];
            gswap2 = glyphBuffer[--end];
            glyphBuffer[i] = gswap2;
            glyphBuffer[end] = gswap1;
        }
        for (i = pos, end = numGlyphs; i < (numGlyphs - pos)/2; i++){
            aswap1 = advances[i];
            aswap2 = advances[--end];
            advances[i] = aswap2;
            advances[end] = aswap1;
        }
        for (i = pos, end = numGlyphs; i < (numGlyphs - pos)/2; i++){
            fswap1 = fontBuffer[i];
            fswap2 = fontBuffer[--end];
            fontBuffer[i] = fswap2;
            fontBuffer[end] = fswap1;
        }
    }

    // Draw each contiguous run of glyphs that are included in the same font.
    NSFont *currentFont = fontBuffer[pos];
    float nextX = startX;
    int nextGlyph = pos;

    while (nextGlyph <= endGlyph && nextGlyph < numGlyphs){
        if ((fontBuffer[nextGlyph] != 0 && fontBuffer[nextGlyph] != currentFont)){
            _drawGlyphs(currentFont, style->textColor, &glyphBuffer[lastFrom], &advances[lastFrom], startX, point.y, nextGlyph - lastFrom);
            lastFrom = nextGlyph;
            currentFont = fontBuffer[nextGlyph];
            startX = nextX;
        }
        nextX += advances[nextGlyph].width;
        nextGlyph++;
    }
    _drawGlyphs(currentFont, style->textColor, &glyphBuffer[lastFrom], &advances[lastFrom], startX, point.y, nextGlyph - lastFrom);

    if (advances != localAdvanceBuffer) {
        free(advances);
        free(widthBuffer);
        free(glyphBuffer);
        free(fontBuffer);
    }
}

- (void)drawLineForCharacters:(NSPoint)point yOffset:(float)yOffset withWidth: (int)width withColor:(NSColor *)color
{
    NSGraphicsContext *graphicsContext = [NSGraphicsContext currentContext];
    CGContextRef cgContext;
    float lineWidth;

    // This will draw the text from the top of the bounding box down.
    // Qt expects to draw from the baseline.
    // Remember that descender is negative.
    point.y -= [self lineSpacing] - [self descent];
    
    BOOL flag = [graphicsContext shouldAntialias];

    [graphicsContext setShouldAntialias: NO];

    [color set];

    cgContext = (CGContextRef)[graphicsContext graphicsPort];
    lineWidth = 0.0;
    if ([graphicsContext isDrawingToScreen] && lineWidth == 0.0) {
        CGSize size = CGSizeApplyAffineTransform(CGSizeMake(1.0, 1.0), CGAffineTransformInvert(CGContextGetCTM(cgContext)));
        lineWidth = size.width;
    }
    CGContextSetLineWidth(cgContext, lineWidth);
    CGContextMoveToPoint(cgContext, point.x, point.y + [self lineSpacing] + 1.5 - [self descent] + yOffset);
    CGContextAddLineToPoint(cgContext, point.x + width, point.y + [self lineSpacing] + 1.5 - [self descent] + yOffset);
    CGContextStrokePath(cgContext);

    [graphicsContext setShouldAntialias: flag];
}


- (float)floatWidthForCharacters:(const UniChar *)characters stringLength:(unsigned)stringLength characterPosition: (int)pos
{
    // Return the width of the first complete character at the specified position.  Even though
    // the first 'character' may contain more than one unicode characters this method will
    // work correctly.
    WebCoreTextRun run;
    WebCoreInitializeTextRun (&run, characters, stringLength, pos, 1);
    WebCoreTextStyle style;
    WebCoreInitializeEmptyTextStyle(&style);
        
    return [self _floatWidthForRun:&run style:&style widths:nil fonts:nil  glyphs:nil startGlyph:nil endGlyph:nil numGlyphs:nil];
}


- (float)floatWidthForCharacters:(const UniChar *)characters stringLength:(unsigned)stringLength fromCharacterPosition: (int)pos numberOfCharacters: (int)len
{
    WebCoreTextRun run;
    WebCoreInitializeTextRun (&run, characters, stringLength, 0, stringLength);
    WebCoreTextStyle style;
    WebCoreInitializeEmptyTextStyle(&style);
        
    return [self _floatWidthForRun:&run style:&style widths:nil fonts:nil  glyphs:nil startGlyph:nil endGlyph:nil numGlyphs:nil];
}


- (float)floatWidthForCharacters:(const UniChar *)characters stringLength:(unsigned)stringLength fromCharacterPosition:(int)pos numberOfCharacters:(int)len withPadding:(int)padding widths:(float *)widthBuffer letterSpacing: (int)letterSpacing wordSpacing:(int)wordSpacing smallCaps:(BOOL)smallCaps fontFamilies:(NSString **)families
{
    WebCoreTextRun run;
    WebCoreInitializeTextRun (&run, characters, stringLength, pos, pos+len);
    WebCoreTextStyle style;
    WebCoreInitializeEmptyTextStyle(&style);
    
    style.padding = padding;
    style.letterSpacing = letterSpacing;
    style.wordSpacing = wordSpacing;
    style.smallCaps = smallCaps;
    style.families = families;
    
    return [self _floatWidthForRun:&run style:&style widths:widthBuffer fonts:nil glyphs:nil startGlyph:nil endGlyph:nil numGlyphs:nil];
}

- (float)floatWidthForRun:(const WebCoreTextRun *)run style:(const WebCoreTextStyle *)style widths:(float *)widthBuffer
{
    return [self _floatWidthForRun:run style:style widths:widthBuffer fonts:nil glyphs:nil startGlyph:nil endGlyph:nil numGlyphs:nil];
}

#ifdef DEBUG_COMBINING
static const char *directionNames[] = {
        "DirectionL", 	// Left Letter 
        "DirectionR",	// Right Letter
        "DirectionEN",	// European Number
        "DirectionES",	// European Separator
        "DirectionET",	// European Terminator (post/prefix e.g. $ and %)
        "DirectionAN",	// Arabic Number
        "DirectionCS",	// Common Separator 
        "DirectionB", 	// Paragraph Separator (aka as PS)
        "DirectionS", 	// Segment Separator (TAB)
        "DirectionWS", 	// White space
        "DirectionON",	// Other Neutral

	// types for explicit controls
        "DirectionLRE", 
        "DirectionLRO", 

        "DirectionAL", 	// Arabic Letter (Right-to-left)

        "DirectionRLE", 
        "DirectionRLO", 
        "DirectionPDF", 

        "DirectionNSM", 	// Non-spacing Mark
        "DirectionBN"	// Boundary neutral (type of RLE etc after explicit levels)
};

static const char *joiningNames[] = {
        "JoiningOther",
        "JoiningDual",
        "JoiningRight",
        "JoiningCausing"
};
#endif

- (float)_floatWidthForRun:(const WebCoreTextRun *)run style:(const WebCoreTextStyle *)style widths:(float *)widthBuffer fonts:(NSFont **)fontBuffer glyphs:(CGGlyph *)glyphBuffer startGlyph:(int *)startGlyph endGlyph:(int *)endGlyph numGlyphs:(int *)_numGlyphs
{
    if (shouldUseATSU(run))
        return [self _ATSU_floatWidthForRun:run style:style];
    
    return [self _CG_floatWidthForRun:run style:style widths:widthBuffer fonts:fontBuffer glyphs:glyphBuffer startGlyph:startGlyph endGlyph:endGlyph numGlyphs:_numGlyphs];

}

- (float)_CG_floatWidthForRun:(const WebCoreTextRun *)run style:(const WebCoreTextStyle *)style widths: (float *)widthBuffer fonts: (NSFont **)fontBuffer glyphs: (CGGlyph *)glyphBuffer  startGlyph:(int *)startGlyph endGlyph:(int *)endGlyph numGlyphs: (int *)_numGlyphs
{
    float totalWidth = 0;
    unsigned int i, clusterLength;
    NSFont *substituteFont = nil;
    ATSGlyphRef glyphID;
    float lastWidth = 0;
    uint numSpaces = 0;
    int padPerSpace = 0;
    int numGlyphs = 0;
    UniChar high = 0, low = 0;
    int from = run->from;
    int to = run->to;
    int len = to - from;
    const UniChar *characters = run->characters;
    unsigned int stringLength = run->length;
    int pos = run->from;
    int padding = style->padding;
    
    if (run->length <= 0)
        return 0;
        
    if (len <= 0){
        if (_numGlyphs)
            *_numGlyphs = 0;
        return 0;
    }

#define SHAPE_STRINGS
#ifdef SHAPE_STRINGS
     UniChar *munged = 0;
     UniChar _localMunged[LOCAL_BUFFER_SIZE];
    {
        UniChar *shaped;
        int lengthOut;

        // FIXME:  Change to use the new CharacterShapeIterator internal API.
        shaped = shapedString (run, 0, &lengthOut);        
        if (shaped){
             if (run->length < LOCAL_BUFFER_SIZE)
                 munged = &_localMunged[0];
             else
                 munged = (UniChar *)malloc(stringLength * sizeof(UniChar));
            //printf ("%d input, %d output\n", len, lengthOut);
            //for (i = 0; i < (int)len; i++){
            //    printf ("0x%04x shaped to 0x%04x\n", characters[i], shaped[i]);
            //}
            // FIXME:  Hack-o-rific, copy shaped buffer into munged
            // character buffer.
            int k;
            for (k = 0; k < from; k++){
                munged[k] = characters[k];
            }
            for (k = from; k < from + lengthOut; k++){
                munged[k] = shaped[k-from];
            }
            characters = munged;
            len = lengthOut;
        }
    }
#endif
    
    // If the padding is non-zero, count the number of spaces in the string
    // and divide that by the padding for per space addition.
    if (style->padding > 0){
        int k;
        for (k = from; k < from + len; k++){
            if (characters[k] == NON_BREAKING_SPACE || characters[k] == SPACE)
                numSpaces++;
        }
        padPerSpace = CEIL_TO_INT ((((float)style->padding) / ((float)numSpaces)));
    }

    for (i = 0; i < stringLength; i++) {

        UniChar c = characters[i];
        BOOL foundMetrics = NO;
        
        // Skip control characters.
        if (IS_CONTROL_CHARACTER(c)) {
            if (glyphBuffer && i < (unsigned int)(run->to) && endGlyph)
                *endGlyph = numGlyphs-1;
            continue;
        }
        
        if (c == NON_BREAKING_SPACE) {
            c = SPACE;
        }
        
        // Drop out early if we've measured to the end of the requested
        // fragment.
        if ((int)i - pos >= len) {
            // Check if next character is a space. If so, we have to apply rounding.
            if (c == SPACE && style->applyRounding) {
                float delta = CEIL_TO_INT(totalWidth) - totalWidth;
                totalWidth += delta;
                if (widthBuffer && numGlyphs > 0)
                    widthBuffer[numGlyphs - 1] += delta;
            }

            if (glyphBuffer && i < (unsigned int)(run->to) && endGlyph)
                *endGlyph = numGlyphs-1;

            break;
        }
        // Deal with surrogate pairs
        if (c >= HighSurrogateRangeStart && c <= HighSurrogateRangeEnd){
            high = c;

            // Make sure we have another character and it's a low surrogate.
            if (i+1 >= run->length || !IsLowSurrogatePair((low = characters[++i]))){
                // Error!  Use 0 glyph.
                glyphID = 0;
            }
            else {
                UnicodeChar uc = UnicodeValueForSurrogatePair(high, low);
                glyphID = glyphForUnicodeCharacter(unicodeCharacterToGlyphMap, uc, &substituteFont);
                if (glyphID == nonGlyphID) {
                    glyphID = [self extendUnicodeCharacterToGlyphMapToInclude: uc];
                }
            }
        }
        // Otherwise we have a valid 16bit unicode character.
        else {
            glyphID = glyphForCharacter(characterToGlyphMap, c, &substituteFont);
            if (glyphID == nonGlyphID) {
                glyphID = [self extendCharacterToGlyphMapToInclude: c];
            }
        }

        // FIXME:  look at next character to determine if it is non-base, then
        // determine the characters cluster from this base character.
#ifdef DEBUG_DIACRITICAL
        if (IsNonBaseChar(c)){
            printf ("NonBaseCharacter 0x%04x, joining attribute %d(%s), combining class %d, direction %d, glyph %d, width %f\n", c, WebCoreUnicodeJoiningFunction(c), joiningNames(WebCoreUnicodeJoiningFunction(c)), WebCoreUnicodeCombiningClassFunction(c), WebCoreUnicodeDirectionFunction(c), glyphID, widthForGlyph(self, glyphID));
        }
#endif
        
        // Try to find a substitute font if this font didn't have a glyph for a character in the
        // string.  If one isn't found we end up drawing and measuring the 0 glyph, usually a box.
        if (glyphID == 0 && style->attemptFontSubstitution) {
            const UniChar *_characters;
            UniChar surrogates[2];
            
            if (high && low){
                clusterLength = 2;
                surrogates[0] = high;
                surrogates[1] = low;
                _characters = &surrogates[0];
            }
            else {
                clusterLength = findLengthOfCharacterCluster (&characters[i], run->length - i);
                _characters = &characters[i];
            }
            substituteFont = [self substituteFontForCharacters: _characters length: clusterLength families: style->families];
            if (substituteFont) {
                int cNumGlyphs = 0;
                ATSGlyphRef localGlyphBuffer[clusterLength*4];
                
                WebCoreTextRun clusterRun;
                WebCoreInitializeTextRun(&clusterRun, _characters, clusterLength, 0, clusterLength);
                WebCoreTextStyle clusterStyle = *style;
                clusterStyle.padding = 0;
                clusterStyle.applyRounding = false;
                clusterStyle.attemptFontSubstitution = false;
                lastWidth = [[[WebTextRendererFactory sharedFactory] rendererWithFont:substituteFont usingPrinterFont:usingPrinterFont]
                                _floatWidthForRun:&clusterRun
                                style:&clusterStyle 
                                widths: ((widthBuffer != 0 ) ? (&widthBuffer[numGlyphs]) : nil)
                                fonts: nil
                                glyphs: &localGlyphBuffer[0]
                                startGlyph:nil
                                endGlyph:nil
                                numGlyphs: &cNumGlyphs];
                
                int j;
                if (glyphBuffer){
                    if (i-1 == (unsigned int)run->from && startGlyph)
                        *startGlyph = numGlyphs;
                    for (j = 0; j < cNumGlyphs; j++){
                        glyphBuffer[numGlyphs+j] = localGlyphBuffer[j];
                    }
                }
                
                if (fontBuffer){
                    for (j = 0; j < cNumGlyphs; j++)
                        fontBuffer[numGlyphs+j] = substituteFont;
                }
                
                if (clusterLength == 1 && cNumGlyphs == 1 && localGlyphBuffer[0] != 0){
                    [self updateGlyphEntryForCharacter: _characters[0] glyphID: localGlyphBuffer[0] font: substituteFont];
                }

                numGlyphs += cNumGlyphs;

                if (glyphBuffer && i == (unsigned int)(run->to-1) && endGlyph)
                    *endGlyph = numGlyphs-1;

                foundMetrics = YES;
            }
#ifdef DEBUG_MISSING_GLYPH
            else {
                BOOL hasFont = [[NSFont coveredCharacterCache] characterIsMember:c];
                printf ("Unable to find glyph for base character 0x%04x in font %s(%s) hasFont1 = %d\n", c, [[font displayName] cString], [[substituteFont displayName] cString], (int)hasFont);
            }
#endif
        }
        
        // If we have a valid glyph OR if we couldn't find a substitute font
        // measure the glyph.
        if ((glyphID > 0 || ((glyphID == 0) && substituteFont == nil)) && !foundMetrics) {
            if (glyphID == spaceGlyph && style->applyRounding) {
                if (lastWidth > 0){
                    float delta = CEIL_TO_INT(totalWidth) - totalWidth;
                    totalWidth += delta;
                    if (widthBuffer)
                        widthBuffer[numGlyphs - 1] += delta;
                } 
                lastWidth = adjustedSpaceWidth;
                if (padding > 0){
                    // Only use left over padding if note evenly divisible by 
                    // number of spaces.
                    if (padding < padPerSpace){
                        lastWidth += padding;
                        padding = 0;
                    }
                    else {
                        lastWidth += padPerSpace;
                        padding -= padPerSpace;
                    }
                }
            }
            else
                lastWidth = widthForGlyph(self, glyphID, substituteFont);
            
            if (fontBuffer){
                fontBuffer[numGlyphs] = (substituteFont ? substituteFont: font);
            }
            if (glyphBuffer) {
                if (i == (unsigned int)run->from && startGlyph)
                    *startGlyph = numGlyphs;
                glyphBuffer[numGlyphs] = glyphID;
            }

            // Account for the letter-spacing.  Only add width to base characters.
            // Combining glyphs should have zero width.
            if (lastWidth > 0)
                lastWidth += style->letterSpacing;

            // Account for word-spacing.  Make the size of the last character (grapheme cluster)
            // in the word wider.
            if (glyphID == spaceGlyph && numGlyphs > 0 && (characters[i-1] != SPACE || characters[i-1] != NON_BREAKING_SPACE)){
                // Find the base glyph in the grapheme cluster.  Combining glyphs
                // should have zero width.
                if (widthBuffer){
                    int ng = numGlyphs-1;
                    if (ng >= 0){
                        while (ng && widthBuffer[ng] == 0)
                            ng--;
                        widthBuffer[ng] += style->wordSpacing;
                    }
                }
                totalWidth += style->wordSpacing;
            }
            
            if (widthBuffer){
                widthBuffer[numGlyphs] = lastWidth;
            }
            numGlyphs++;

            if (glyphBuffer && i == (unsigned int)(run->to-1) && endGlyph)
                *endGlyph = numGlyphs-1;
        }
#ifdef DEBUG_COMBINING        
        printf ("Character 0x%04x, joining attribute %d(%s), combining class %d, direction %d(%s)\n", c, WebCoreUnicodeJoiningFunction(c), joiningNames[WebCoreUnicodeJoiningFunction(c)], WebCoreUnicodeCombiningClassFunction(c), WebCoreUnicodeDirectionFunction(c), directionNames[WebCoreUnicodeDirectionFunction(c)]);
#endif
        
        if (i >= (unsigned int)pos)
            totalWidth += lastWidth;       
    }

    // Ceil the last glyph, but only if
    // 1) The string is longer than one character
    // 2) or the entire stringLength is one character
    if ((len > 1 || run->length == 1) && style->applyRounding){
        float delta = CEIL_TO_INT(totalWidth) - totalWidth;
        totalWidth += delta;
        if (widthBuffer && numGlyphs > 0)
            widthBuffer[numGlyphs-1] += delta;
    }

    if (_numGlyphs)
        *_numGlyphs = numGlyphs;

#ifdef SHAPE_STRINGS
     if (munged != &_localMunged[0])
         free (munged);
#endif
    
    return totalWidth;
}

- (ATSGlyphRef)extendUnicodeCharacterToGlyphMapToInclude: (UnicodeChar)c
{
    UnicodeGlyphMap *map = (UnicodeGlyphMap *)calloc (1, sizeof(UnicodeGlyphMap));
    ATSLayoutRecord *glyphRecord;
    ATSGlyphVector glyphVector;
    UnicodeChar end, start;
    unsigned int blockSize;
    ATSGlyphRef glyphID;
    
    if (unicodeCharacterToGlyphMap == 0)
        blockSize = INITIAL_BLOCK_SIZE;
    else
        blockSize = INCREMENTAL_BLOCK_SIZE;
    start = (c / blockSize) * blockSize;
    end = start + (blockSize - 1);
        
    LOG(FontCache, "%@ (0x%04x) adding glyphs for 0x%04x to 0x%04x", font, c, start, end);

    map->startRange = start;
    map->endRange = end;
    
    unsigned int i, count = end - start + 1;
    UnicodeChar buffer[INCREMENTAL_BLOCK_SIZE+2];
    
    for (i = 0; i < count; i++){
        buffer[i] = i+start;
    }

    OSStatus status;
    status = ATSInitializeGlyphVector(count*2, 0, &glyphVector);
    if (status != noErr){
        // This should never happen, indicates a bad font!  If it does the
        // font substitution code will find an alternate font.
        return 0;
    }
    
    [self convertUnicodeCharacters: &buffer[0] length: count toGlyphs: &glyphVector];
    unsigned numGlyphs = glyphVector.numGlyphs;
    if (numGlyphs != count){
        // This should never happen, indicates a bad font!  If it does the
        // font substitution code will find an alternate font.
        return 0;
    }
            
    map->glyphs = (GlyphEntry *)malloc (count * sizeof(GlyphEntry));
    glyphRecord = (ATSLayoutRecord *)glyphVector.firstRecord;
    for (i = 0; i < count; i++) {
        map->glyphs[i].glyph = glyphRecord->glyphID;
        map->glyphs[i].font = 0;
        glyphRecord = (ATSLayoutRecord *)((char *)glyphRecord + glyphVector.recordSize);
    }
    ATSClearGlyphVector(&glyphVector);
    
    if (unicodeCharacterToGlyphMap == 0)
        unicodeCharacterToGlyphMap = map;
    else {
        UnicodeGlyphMap *lastMap = unicodeCharacterToGlyphMap;
        while (lastMap->next != 0)
            lastMap = lastMap->next;
        lastMap->next = map;
    }

    glyphID = map->glyphs[c - start].glyph;
    
    return glyphID;
}

- (void)updateGlyphEntryForCharacter: (UniChar)c glyphID: (ATSGlyphRef)glyphID font: (NSFont *)substituteFont
{
    GlyphMap *lastMap = characterToGlyphMap;
    while (lastMap != 0){
        if (c >= lastMap->startRange && c <= lastMap->endRange){
            lastMap->glyphs[c - lastMap->startRange].glyph = glyphID;
            // This font will leak.  No problem though, it has to stick around
            // forever.  Max theoretical retain counts applied here will be
            // num_fonts_on_system * num_glyphs_in_font.
            lastMap->glyphs[c - lastMap->startRange].font = [substituteFont retain];
            break;
        }
        lastMap = lastMap->next;
    }
}

- (ATSGlyphRef)extendCharacterToGlyphMapToInclude:(UniChar) c
{
    GlyphMap *map = (GlyphMap *)calloc (1, sizeof(GlyphMap));
    ATSLayoutRecord *glyphRecord;
    ATSGlyphVector glyphVector;
    UniChar end, start;
    unsigned int blockSize;
    ATSGlyphRef glyphID;
    
    if (characterToGlyphMap == 0)
        blockSize = INITIAL_BLOCK_SIZE;
    else
        blockSize = INCREMENTAL_BLOCK_SIZE;
    start = (c / blockSize) * blockSize;
    end = start + (blockSize - 1);
        
    LOG(FontCache, "%@ (0x%04x) adding glyphs for 0x%04x to 0x%04x", font, c, start, end);

    map->startRange = start;
    map->endRange = end;
    
    unsigned int i, count = end - start + 1;
    short unsigned int buffer[INCREMENTAL_BLOCK_SIZE+2];
    
    for (i = 0; i < count; i++){
        buffer[i] = i+start;
    }

    OSStatus status = ATSInitializeGlyphVector(count, 0, &glyphVector);
    if (status != noErr){
        // This should never happen, perhaps indicates a bad font!  If it does the
        // font substitution code will find an alternate font.
        return 0;
    }

    [self convertCharacters: &buffer[0] length: count toGlyphs: &glyphVector skipControlCharacters: NO];
    unsigned numGlyphs = glyphVector.numGlyphs;
    if (numGlyphs != count){
        // This should never happen, perhaps indicates a bad font!  If it does the
        // font substitution code will find an alternate font.
        return 0;
    }
            
    map->glyphs = (GlyphEntry *)malloc (count * sizeof(GlyphEntry));
    glyphRecord = (ATSLayoutRecord *)glyphVector.firstRecord;
    for (i = 0; i < count; i++) {
        map->glyphs[i].glyph = glyphRecord->glyphID;
        map->glyphs[i].font = 0;
        glyphRecord = (ATSLayoutRecord *)((char *)glyphRecord + glyphVector.recordSize);
    }
    ATSClearGlyphVector(&glyphVector);
    
    if (characterToGlyphMap == 0)
        characterToGlyphMap = map;
    else {
        GlyphMap *lastMap = characterToGlyphMap;
        while (lastMap->next != 0)
            lastMap = lastMap->next;
        lastMap->next = map;
    }

    glyphID = map->glyphs[c - start].glyph;
    
    // Special case for characters 007F-00A0.
    if (glyphID == 0 && c >= 0x7F && c <= 0xA0){
        glyphID = [font _defaultGlyphForChar: c];
        map->glyphs[c - start].glyph = glyphID;
        map->glyphs[c - start].font = 0;
    }

    return glyphID;
}


- (WidthMap *)extendGlyphToWidthMapToInclude:(ATSGlyphRef)glyphID font:(NSFont *)subFont
{
    WidthMap *map = (WidthMap *)calloc (1, sizeof(WidthMap)), **rootMap;
    unsigned int end;
    ATSGlyphRef start;
    unsigned int blockSize;
    unsigned int i, count;
    
    if (subFont && subFont != font)
        rootMap = &mapForSubstituteFont(self,subFont)->map;
    else
        rootMap = &glyphToWidthMap;
        
    if (*rootMap == 0){
        if ([(subFont ? subFont : font) numberOfGlyphs] < INITIAL_BLOCK_SIZE)
            blockSize = [font numberOfGlyphs];
         else
            blockSize = INITIAL_BLOCK_SIZE;
    }
    else
        blockSize = INCREMENTAL_BLOCK_SIZE;
    start = (glyphID / blockSize) * blockSize;
    end = ((unsigned int)start) + blockSize; 
    if (end > 0xffff)
        end = 0xffff;

    LOG(FontCache, "%@ (0x%04x) adding widths for range 0x%04x to 0x%04x", font, glyphID, start, end);

    map->startRange = start;
    map->endRange = end;
    count = end - start + 1;

    map->widths = (WidthEntry *)malloc (count * sizeof(WidthEntry));

    for (i = 0; i < count; i++){
        map->widths[i].width = UNINITIALIZED_GLYPH_WIDTH;
    }

    if (*rootMap == 0)
        *rootMap = map;
    else {
        WidthMap *lastMap = *rootMap;
        while (lastMap->next != 0)
            lastMap = lastMap->next;
        lastMap->next = map;
    }

#ifdef _TIMING
    LOG(FontCache, "%@ total time to advances lookup %f seconds", font, totalCGGetAdvancesTime);
#endif
    return map;
}


- (void)_initializeATSUStyle
{
    if (!ATSUStyleInitialized){
        OSStatus status;
        
        status = ATSUCreateStyle (&_ATSUSstyle);
        if(status != noErr)
            FATAL_ALWAYS ("ATSUCreateStyle failed (%d)", status);
    
        ATSUFontID fontID = [font _atsFontID];
        if (fontID == 0){
            ERROR ("unable to get ATSUFontID for %@", font);
            return;
        }
        
        CGAffineTransform transform = CGAffineTransformMakeScale (1,-1);
        Fixed fontSize = FloatToFixed([font pointSize]);
        ATSUAttributeTag styleTags[] = { kATSUSizeTag, kATSUFontTag, kATSUFontMatrixTag};
        ByteCount styleSizes[] = {  sizeof(Fixed), sizeof(ATSUFontID), sizeof(CGAffineTransform) };
        ATSUAttributeValuePtr styleValues[] = { &fontSize, &fontID, &transform  };
        status = ATSUSetAttributes (_ATSUSstyle, 3, styleTags, styleSizes, styleValues);
        if(status != noErr)
            FATAL_ALWAYS ("ATSUSetAttributes failed (%d)", status);

        ATSUStyleInitialized = YES;
    }
}

- (ATSUTextLayout)_createATSUTextLayoutForRun:(const WebCoreTextRun *)run
{
    ATSUTextLayout layout;
    UniCharCount runLength;
    OSStatus status;
    
    [self _initializeATSUStyle];
    
    runLength = run->to - run->from;
    status = ATSUCreateTextLayoutWithTextPtr(
            run->characters,
            run->from,           // offset
            runLength,        // length
            run->length,         // total length
            1,              // styleRunCount
            &runLength,    // length of style run
            &_ATSUSstyle, 
            &layout);
    if(status != noErr)
        FATAL_ALWAYS ("ATSUCreateTextLayoutWithTextPtr failed(%d)", status);

    CGContextRef cgContext = (CGContextRef)[[NSGraphicsContext currentContext] graphicsPort];
    ATSUAttributeTag tags[] = { kATSUCGContextTag};
    ByteCount sizes[] = { sizeof(CGContextRef) };
    ATSUAttributeValuePtr values[] = { &cgContext };
    
    status = ATSUSetLayoutControls(layout, 1, tags, sizes, values);
    if(status != noErr)
        FATAL_ALWAYS ("ATSUSetLayoutControls failed(%d)", status);


    status = ATSUSetTransientFontMatching (layout, YES);
    if(status != noErr)
        FATAL_ALWAYS ("ATSUSetTransientFontMatching failed(%d)", status);
        
    return layout;
}


- (ATSTrapezoid)_trapezoidForRun:(const WebCoreTextRun *)run style:(const WebCoreTextStyle *)style atPoint:(NSPoint )p
{
    ATSUTextLayout layout;
    OSStatus status;
    
    if (run->to - run->from <= 0){
        ATSTrapezoid nilTrapezoid = { {0,0} , {0,0}, {0,0}, {0,0} };
        return nilTrapezoid;
    }
        
    layout = [self _createATSUTextLayoutForRun:run];

    ATSTrapezoid firstGlyphBounds;
    ItemCount actualNumBounds;
    status = ATSUGetGlyphBounds (layout, FloatToFixed(p.x), FloatToFixed(p.y), run->from, run->to - run->from, kATSUseDeviceOrigins, 1, &firstGlyphBounds, &actualNumBounds);    
    if(status != noErr)
        FATAL_ALWAYS ("ATSUGetGlyphBounds() failed(%d)", status);
    
    if (actualNumBounds != 1)
        FATAL_ALWAYS ("unexpected result from ATSUGetGlyphBounds():  actualNumBounds(%d) != 1", actualNumBounds);

    ATSUDisposeTextLayout (layout); // Ignore the error.  Nothing we can do anyway.
            
    return firstGlyphBounds;
}


- (float)_ATSU_floatWidthForRun:(const WebCoreTextRun *)run style:(const WebCoreTextStyle *)style
{
    ATSTrapezoid oGlyphBounds;
    
    oGlyphBounds = [self _trapezoidForRun:run style:style atPoint:NSMakePoint (0,0)];
    
    float width = 
        MAX(FixToFloat(oGlyphBounds.upperRight.x), FixToFloat(oGlyphBounds.lowerRight.x)) - 
        MIN(FixToFloat(oGlyphBounds.upperLeft.x), FixToFloat(oGlyphBounds.lowerLeft.x));
    
    return width;
}


- (void)_ATSU_drawHighlightForRun:(const WebCoreTextRun *)run style:(const WebCoreTextStyle *)style atPoint:(NSPoint)point
{
    ATSUTextLayout layout;
    int from = run->from;
    int to = run->to;
    float selectedLeftX;

    if (style->backgroundColor == nil)
        return;
    
    if (from == -1)
        from = 0;
    if (to == -1)
        to = run->length;
   
    int runLength = to - from;
    if (runLength <= 0){
        return;
    }

    layout = [self _createATSUTextLayoutForRun:run];

    WebCoreTextRun leadingRun = *run;
    leadingRun.from = 0;
    leadingRun.to = run->from;
    
    // ATSU provides the bounds of the glyphs for the run with an origin of
    // (0,0), so we need to find the width of the glyphs immediately before
    // the actually selected glyphs.
    ATSTrapezoid leadingTrapezoid = [self _trapezoidForRun:&leadingRun style:style atPoint:point];
    ATSTrapezoid selectedTrapezoid = [self _trapezoidForRun:run style:style atPoint:point];

    float backgroundWidth = 
            MAX(FixToFloat(selectedTrapezoid.upperRight.x), FixToFloat(selectedTrapezoid.lowerRight.x)) - 
            MIN(FixToFloat(selectedTrapezoid.upperLeft.x), FixToFloat(selectedTrapezoid.lowerLeft.x));

    if (run->from == 0)
        selectedLeftX = point.x;
    else
        selectedLeftX = MIN(FixToFloat(leadingTrapezoid.upperRight.x), FixToFloat(leadingTrapezoid.lowerRight.x));
    
    [style->backgroundColor set];
    
    float yPos = point.y - [self ascent];
    if (style->rtl){
        WebCoreTextRun completeRun = *run;
        completeRun.from = 0;
        completeRun.to = run->length;
        float completeRunWidth = [self floatWidthForRun:&completeRun style:style widths:0];
        [NSBezierPath fillRect:NSMakeRect(point.x + completeRunWidth - (selectedLeftX-point.x) - backgroundWidth, yPos, backgroundWidth, [self lineSpacing])];
    }
    else {
        [NSBezierPath fillRect:NSMakeRect(selectedLeftX, yPos, backgroundWidth, [self lineSpacing])];
    }

    ATSUDisposeTextLayout (layout); // Ignore the error.  Nothing we can do anyway.
}


- (void)_ATSU_drawRun:(const WebCoreTextRun *)run style:(const WebCoreTextStyle *)style atPoint:(NSPoint)point
{
    ATSUTextLayout layout;
    OSStatus status;
    int from = run->from;
    int to = run->to;
    
    if (from == -1)
        from = 0;
    if (to == -1)
        to = run->length;
   
    int runLength = to - from;
    if (runLength <= 0)
        return;

    layout = [self _createATSUTextLayoutForRun:run];

    if (style->backgroundColor != nil)
        [self _ATSU_drawHighlightForRun:run style:style atPoint:point];

    [style->textColor set];

    status = ATSUDrawText(layout, 
            from,
            runLength,
            FloatToFixed(point.x),   // these values are
            FloatToFixed(point.y));  // also of type Fixed
    if (status != noErr){
        // Nothing to do but report the error (dev build only).
        ERROR ("ATSUDrawText() failed(%d)", status);
    }

    ATSUDisposeTextLayout (layout); // Ignore the error.  Nothing we can do anyway.
}

- (int)pointToOffset:(const WebCoreTextRun *)run style:(const WebCoreTextStyle *)style position:(int)x reversed:(BOOL)reversed
{
    if (shouldUseATSU(run))
        return [self _ATSU_pointToOffset:run style:style position:x reversed:reversed];
    return [self _CG_pointToOffset:run style:style position:x reversed:reversed];
}


- (int)_ATSU_pointToOffset:(const WebCoreTextRun *)run style:(const WebCoreTextStyle *)style position:(int)x reversed:(BOOL)reversed
{
    unsigned int offset = 0;
    ATSUTextLayout layout;
    UniCharArrayOffset primaryOffset = 0;
    UniCharArrayOffset secondaryOffset = 0;
    OSStatus status;
    Boolean isLeading;

    layout = [self _createATSUTextLayoutForRun:run];

    status = ATSUPositionToOffset (layout, (ATSUTextMeasurement)FloatToFixed(((float)x)), 1, &primaryOffset, &isLeading, &secondaryOffset);
    if (status == noErr){
        offset = (unsigned int)primaryOffset;
    }
    else {
        // Failed to find offset!  Return 0 offset.
    }

    return offset;
}

#define LOCAL_WIDTH_BUF_SIZE 1024

- (int)_CG_pointToOffset:(const WebCoreTextRun *)run style:(const WebCoreTextStyle *)style position:(int)x reversed:(BOOL)reversed
{
    float delta = (float)x;
    float width;
    unsigned int offset = run->from;
    CharacterWidthIterator widthIterator;
    
    initializeCharacterWidthIterator(&widthIterator, self, run, style);

    if (reversed) {
        width = [self floatWidthForRun:run style:style widths:nil];
        delta -= width;
        while(offset < run->length) {
            float w = widthForNextCharacter(&widthIterator);
            if (w){
                float w2 = w/2;
                w -= w2;
                delta += w2;
                if(delta >= 0)
                    break;
                delta += w;
            }
            offset++;
        }
    } else {
        while(offset < run->length) {
            float w = widthForNextCharacter(&widthIterator);
            if (w){
                float w2 = w/2;
                w -= w2;
                delta -= w2;
                if(delta <= 0) 
                    break;
                delta -= w;
            }
            offset++;
        }
    }
    
    return offset - run->from;
}

@end
