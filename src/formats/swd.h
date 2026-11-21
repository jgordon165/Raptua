// Window layouts (*_SWD): the original's menus and dialogs, as data.
//
// A 120-byte window header (i32 version, size, arrowflag, display, opt3,
// opt4, id, type; char name[16], item_name[16]; i32 item, picflag, lock,
// fldofs, txtofs, firstfld, opt, color, numflds, x, y, lx, ly, shadow), then
// `numflds` 148-byte fields at `fldofs` (i32 type, id, hotkey, kbflag, opt3,
// opt4, input_opt, bstatus; char name[16], item_name[16]; i32 item;
// char font_name[16]; i32 fontid, fontbasecolor, maxchars, picflag, color,
// lite, mark, saveflag, shadow, selectable, x, y, lx, ly, txtoff, unused).
// A field's text is `maxchars` bytes at (field start + txtoff), in the text
// area after the fields. See docs/formats.md.
#pragma once
#include <cstdint>
#include <string>
#include <vector>

#include "formats/glb.h"

namespace raptua {

enum class SwdFieldType : int32_t {
    Off = 0, Text = 1, Button = 2, Input = 3, Mark = 4, Close = 5,
    DragBar = 6, BumpIn = 7, BumpOut = 8, Icon = 9, Slider = 11,
};

// Fill of a window or field.
enum class SwdFill : int32_t { Color = 0, Texture = 1, Picture = 2, SeeThru = 3 };

struct SwdField {
    int32_t type = 0, id = 0, hotkey = 0;
    std::string name, item_name, font_name, text;
    int32_t font_base = 0, max_chars = 0, fill = 0, color = 0, lite = 0;
    int32_t shadow = 0, selectable = 0, x = 0, y = 0, w = 0, h = 0;
};

struct SwdWindow {
    std::string name, item_name;
    int32_t fill = 0, color = 0, first_field = 0, x = 0, y = 0, w = 0, h = 0, shadow = 0;
    std::vector<SwdField> fields;
};

bool decode_swd(const Bytes& data, SwdWindow& out);

} // namespace raptua
