#include "vm_internal.h"
#include <inttypes.h>

/* Characters in Strings. A String holds bytes, usually UTF-8; its character methods
 * (length, slice, index_of, reverse, chars, ljust, ...) count UTF-8 code points. A
 * byte that does not start a well-formed sequence counts as one character on its own,
 * so every byte belongs to exactly one character and any byte string has a length.
 *
 * The character count is cached on the String (char_count_plus_one, src/object.h).
 * A String whose count equals its byte length is ASCII, and every function here takes
 * that as a fast path: positions are then byte positions, as they always were. */

/* The number of bytes in the character starting at `at` (1 to 4). */
size_t utf8_char_size(const char *chars,size_t length,size_t at) {
    const unsigned char lead=(unsigned char)chars[at];
    size_t size;
    if(lead<0x80)return 1;
    if(lead>=0xC2&&lead<=0xDF)size=2;
    else if(lead>=0xE0&&lead<=0xEF)size=3;
    else if(lead>=0xF0&&lead<=0xF4)size=4;
    else return 1;
    if(at+size>length)return 1;
    const unsigned char second=(unsigned char)chars[at+1];
    if((lead==0xE0&&second<0xA0)||(lead==0xED&&second>=0xA0)||
       (lead==0xF0&&second<0x90)||(lead==0xF4&&second>=0x90))return 1;
    for(size_t index=1;index<size;index++) {
        const unsigned char next=(unsigned char)chars[at+index];
        if(next<0x80||next>0xBF)return 1;
    }
    return size;
}

size_t utf8_count(const char *chars,size_t length) {
    size_t count=0;
    size_t at=0;
    while(at<length) {
        /* ASCII runs, the common case, eight bytes at a time. */
        while(at+8<=length) {
            uint64_t word;
            memcpy(&word,chars+at,8);
            if(word&0x8080808080808080ull)break;
            at+=8;count+=8;
        }
        if(at>=length)break;
        at+=utf8_char_size(chars,length,at);
        count++;
    }
    return count;
}

size_t string_char_count(const DiamondString *string) {
    /* Relaxed: a String can be read by several threads, and each would store the
     * same count, so all a racing reader can see is 0 (and compute it again). */
    size_t cached=__atomic_load_n(&string->char_count_plus_one,__ATOMIC_RELAXED);
    if(cached!=0)return cached-1;
    const size_t count=utf8_count(string->chars,string->length);
    __atomic_store_n(&((DiamondString *)string)->char_count_plus_one,count+1,
        __ATOMIC_RELAXED);
    return count;
}

bool string_is_ascii(const DiamondString *string) {
    return string_char_count(string)==string->length;
}

/* The last character position looked up, per thread: a scan that steps through a
 * non-ASCII String (s[i], slice(i, 1), index_of(x, i)) walks on from there instead
 * of from the start. Keyed by the String's address, so collection and VM
 * teardown invalidate the cursor before an address can be reused. */
typedef struct {
    const DiamondString *string;
    uint64_t epoch;
    size_t index;
    size_t offset;
} StringCursor;

static uint64_t sweep_epoch;
static _Thread_local StringCursor string_cursor;

void string_cursors_invalidate(void) {
    __atomic_add_fetch(&sweep_epoch,1,__ATOMIC_RELAXED);
}

/* Where a walk through `string` can start: the cursor when it belongs to this String,
 * else the start. */
static void cursor_load(const DiamondString *string,size_t *index,size_t *offset) {
    const uint64_t epoch=__atomic_load_n(&sweep_epoch,__ATOMIC_RELAXED);
    if(string_cursor.string==string&&string_cursor.epoch==epoch) {
        *index=string_cursor.index;
        *offset=string_cursor.offset;
    } else {
        *index=0;
        *offset=0;
    }
}

static void cursor_store(const DiamondString *string,size_t index,size_t offset) {
    string_cursor=(StringCursor){
        .string=string,
        .epoch=__atomic_load_n(&sweep_epoch,__ATOMIC_RELAXED),
        .index=index,
        .offset=offset,
    };
}

/* The byte offset where character `index` starts; the byte length for an index at or
 * past the end. */
size_t string_byte_offset(const DiamondString *string,size_t index) {
    if(string_is_ascii(string))return index<string->length?index:string->length;
    size_t seen,at;
    cursor_load(string,&seen,&at);
    if(seen>index)seen=at=0;
    while(seen<index&&at<string->length) {
        at+=utf8_char_size(string->chars,string->length,at);
        seen++;
    }
    cursor_store(string,seen,at);
    return at;
}

/* The character index of the character holding byte `offset` (offsets inside a
 * character count as that character); the character count at or past the end. */
size_t string_char_index(const DiamondString *string,size_t offset) {
    if(string_is_ascii(string))return offset<string->length?offset:string->length;
    size_t index,at;
    cursor_load(string,&index,&at);
    if(at>offset)index=at=0;
    while(at<string->length) {
        const size_t size=utf8_char_size(string->chars,string->length,at);
        if(offset<at+size) {
            cursor_store(string,index,at);
            return index;
        }
        at+=size;index++;
    }
    return index;
}

/* String#slice(start, length) in characters: the shared body of the method and the
 * JIT's native call. A start past the end is an IndexError; a length past the end
 * stops at the end. */
DiamondVmStatus string_char_slice(DiamondVm *vm,const DiamondString *source,
        int64_t start,int64_t requested_length,DiamondValue *out) {
    const size_t char_count=string_char_count(source);
    if(start<0||(uint64_t)start>char_count||requested_length<0) {
        snprintf(vm->error,sizeof vm->error,
            "index %" PRId64 " out of bounds for String of length %zu",start,char_count);
        return DIAMOND_VM_INDEX_ERROR;
    }
    const size_t available=char_count-(size_t)start;
    const size_t take=(uint64_t)requested_length<available?(size_t)requested_length:available;
    const size_t byte_start=string_byte_offset(source,(size_t)start);
    size_t byte_end;
    if(string_is_ascii(source))byte_end=byte_start+take;
    else {
        byte_end=byte_start;
        for(size_t seen=0;seen<take;seen++)
            byte_end+=utf8_char_size(source->chars,source->length,byte_end);
    }
    DiamondString *sliced=allocate_string(vm,source->chars+byte_start,byte_end-byte_start);
    if(sliced==nullptr)return DIAMOND_VM_OUT_OF_MEMORY;
    *out=DIAMOND_OBJECT(sliced);
    return DIAMOND_VM_OK;
}

/* The code point of the character at byte `at`: a malformed byte is its own value
 * (0x80-0xFF), as String#ord has always returned for bytes. */
uint32_t utf8_code_point(const char *chars,size_t length,size_t at) {
    const size_t size=utf8_char_size(chars,length,at);
    const unsigned char *bytes=(const unsigned char *)chars+at;
    if(size==1)return bytes[0];
    uint32_t point=bytes[0]&(0x7F>>size);
    for(size_t index=1;index<size;index++)point=(point<<6)|(bytes[index]&0x3F);
    return point;
}

/* Terminal cells, for String#display_width. Sorted, inclusive code point ranges, after
 * the usual wcwidth tables: characters that combine with the one before them (or
 * format characters) and take no cell, and East Asian Wide/Fullwidth characters and
 * emoji presentation, which take two. Everything else takes one, including malformed
 * bytes (a terminal shows a replacement character). Control characters take none. */
typedef struct { uint32_t first,last; } Utf8Range;

static const Utf8Range ZERO_WIDTH[]={
    {0x0300,0x036F},{0x0483,0x0489},{0x0591,0x05BD},{0x05BF,0x05BF},{0x05C1,0x05C2},
    {0x05C4,0x05C5},{0x05C7,0x05C7},{0x0610,0x061A},{0x064B,0x065F},{0x0670,0x0670},
    {0x06D6,0x06DC},{0x06DF,0x06E4},{0x06E7,0x06E8},{0x06EA,0x06ED},{0x0E31,0x0E31},
    {0x0E34,0x0E3A},{0x0E47,0x0E4E},{0x1AB0,0x1AFF},{0x1DC0,0x1DFF},{0x200B,0x200F},
    {0x2060,0x2064},{0x20D0,0x20FF},{0xFE00,0xFE0F},{0xFE20,0xFE2F},{0xFEFF,0xFEFF},
    {0xE0100,0xE01EF},
};

static const Utf8Range DOUBLE_WIDTH[]={
    {0x1100,0x115F},{0x231A,0x231B},{0x2329,0x232A},{0x23E9,0x23EC},{0x23F0,0x23F0},
    {0x23F3,0x23F3},{0x25FD,0x25FE},{0x2614,0x2615},{0x2648,0x2653},{0x267F,0x267F},
    {0x2693,0x2693},{0x26A1,0x26A1},{0x26AA,0x26AB},{0x26BD,0x26BE},{0x26C4,0x26C5},
    {0x26CE,0x26CE},{0x26D4,0x26D4},{0x26EA,0x26EA},{0x26F2,0x26F3},{0x26F5,0x26F5},
    {0x26FA,0x26FA},{0x26FD,0x26FD},{0x2705,0x2705},{0x270A,0x270B},{0x2728,0x2728},
    {0x274C,0x274C},{0x274E,0x274E},{0x2753,0x2755},{0x2757,0x2757},{0x2795,0x2797},
    {0x27B0,0x27B0},{0x27BF,0x27BF},{0x2B1B,0x2B1C},{0x2B50,0x2B50},{0x2B55,0x2B55},
    {0x2E80,0x303E},{0x3041,0x33FF},{0x3400,0x4DBF},{0x4E00,0x9FFF},{0xA000,0xA4CF},
    {0xA960,0xA97F},{0xAC00,0xD7A3},{0xF900,0xFAFF},{0xFE10,0xFE19},{0xFE30,0xFE6F},
    {0xFF00,0xFF60},{0xFFE0,0xFFE6},{0x16FE0,0x16FE4},{0x17000,0x18AFF},{0x1B000,0x1B2FF},
    {0x1F004,0x1F004},{0x1F0CF,0x1F0CF},{0x1F18E,0x1F18E},{0x1F191,0x1F19A},
    {0x1F200,0x1F202},{0x1F210,0x1F23B},{0x1F240,0x1F248},{0x1F250,0x1F251},
    {0x1F260,0x1F265},{0x1F300,0x1F320},{0x1F32D,0x1F335},{0x1F337,0x1F37C},
    {0x1F37E,0x1F393},{0x1F3A0,0x1F3CA},{0x1F3CF,0x1F3D3},{0x1F3E0,0x1F3F0},
    {0x1F3F4,0x1F3F4},{0x1F3F8,0x1F43E},{0x1F440,0x1F440},{0x1F442,0x1F4FC},
    {0x1F4FF,0x1F53D},{0x1F54B,0x1F54E},{0x1F550,0x1F567},{0x1F57A,0x1F57A},
    {0x1F595,0x1F596},{0x1F5A4,0x1F5A4},{0x1F5FB,0x1F64F},{0x1F680,0x1F6C5},
    {0x1F6CC,0x1F6CC},{0x1F6D0,0x1F6D2},{0x1F6D5,0x1F6D7},{0x1F6EB,0x1F6EC},
    {0x1F6F4,0x1F6FC},{0x1F7E0,0x1F7EB},{0x1F90C,0x1F93A},{0x1F93C,0x1F945},
    {0x1F947,0x1F9FF},{0x1FA70,0x1FAFF},{0x20000,0x2FFFD},{0x30000,0x3FFFD},
};

static bool in_ranges(uint32_t point,const Utf8Range *ranges,size_t count) {
    size_t low=0,high=count;
    while(low<high) {
        const size_t middle=(low+high)/2;
        if(point<ranges[middle].first)high=middle;
        else if(point>ranges[middle].last)low=middle+1;
        else return true;
    }
    return false;
}

size_t string_display_width(const DiamondString *string) {
    size_t width=0;
    size_t at=0;
    while(at<string->length) {
        const unsigned char lead=(unsigned char)string->chars[at];
        const size_t size=utf8_char_size(string->chars,string->length,at);
        if(size==1) {
            /* ASCII controls take no cell; a malformed byte takes one. */
            if(lead>=0x20&&lead!=0x7F)width++;
        } else {
            const uint32_t point=utf8_code_point(string->chars,string->length,at);
            if(point>=0x80&&point<0xA0) {}
            else if(in_ranges(point,ZERO_WIDTH,sizeof ZERO_WIDTH/sizeof ZERO_WIDTH[0])) {}
            else if(in_ranges(point,DOUBLE_WIDTH,sizeof DOUBLE_WIDTH/sizeof DOUBLE_WIDTH[0]))
                width+=2;
            else width++;
        }
        at+=size;
    }
    return width;
}

/* Writes `point` as UTF-8 into `out` (room for 4) and returns the byte count. A value
 * 0x80-0xFF that came from a malformed byte cannot be told apart from U+0080-U+00FF
 * here, so it is written as that character. */
size_t utf8_encode(uint32_t point,char *out) {
    if(point<0x80) {out[0]=(char)point;return 1;}
    if(point<0x800) {
        out[0]=(char)(0xC0|(point>>6));out[1]=(char)(0x80|(point&0x3F));return 2;
    }
    if(point<0x10000) {
        out[0]=(char)(0xE0|(point>>12));out[1]=(char)(0x80|((point>>6)&0x3F));
        out[2]=(char)(0x80|(point&0x3F));return 3;
    }
    out[0]=(char)(0xF0|(point>>18));out[1]=(char)(0x80|((point>>12)&0x3F));
    out[2]=(char)(0x80|((point>>6)&0x3F));out[3]=(char)(0x80|(point&0x3F));return 4;
}
