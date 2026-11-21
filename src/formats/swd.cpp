#include "formats/swd.h"

#include <cstring>

namespace raptua {

namespace {

constexpr size_t kHeaderSize = 120, kFieldSize = 148;

int32_t rd32(const uint8_t* p) {
    return int32_t(uint32_t(p[0]) | uint32_t(p[1]) << 8 | uint32_t(p[2]) << 16 | uint32_t(p[3]) << 24);
}

std::string name16(const uint8_t* p) {
    const char* s = reinterpret_cast<const char*>(p);
    return std::string(s, strnlen(s, 16));
}

} // namespace

bool decode_swd(const Bytes& d, SwdWindow& out) {
    out = SwdWindow{};
    if (d.size() < kHeaderSize) return false;
    const uint8_t* h = d.data();
    out.name = name16(h + 32);
    out.item_name = name16(h + 48);
    out.fill = rd32(h + 68);
    int32_t fldofs = rd32(h + 76);
    out.first_field = rd32(h + 84);
    out.color = rd32(h + 92);
    int32_t count = rd32(h + 96);
    out.x = rd32(h + 100);
    out.y = rd32(h + 104);
    out.w = rd32(h + 108);
    out.h = rd32(h + 112);
    out.shadow = rd32(h + 116);
    if (count < 0 || count > 256 || fldofs < int32_t(kHeaderSize) ||
        size_t(fldofs) + size_t(count) * kFieldSize > d.size())
        return false;

    for (int32_t i = 0; i < count; ++i) {
        size_t at = size_t(fldofs) + size_t(i) * kFieldSize;
        const uint8_t* p = d.data() + at;
        SwdField f;
        f.type = rd32(p);
        f.id = rd32(p + 4);
        f.hotkey = rd32(p + 8);
        f.name = name16(p + 32);
        f.item_name = name16(p + 48);
        f.font_name = name16(p + 68);
        f.font_base = rd32(p + 88);
        f.max_chars = rd32(p + 92);
        f.fill = rd32(p + 96);
        f.color = rd32(p + 100);
        f.lite = rd32(p + 104);
        f.shadow = rd32(p + 116);
        f.selectable = rd32(p + 120);
        f.x = rd32(p + 124);
        f.y = rd32(p + 128);
        f.w = rd32(p + 132);
        f.h = rd32(p + 136);
        int32_t txtoff = rd32(p + 140);
        // Text lives after the fields; a field's offset is counted from the
        // field's own start. Only read it when it lands there.
        size_t text_at = at + size_t(txtoff);
        if (txtoff > 0 && f.max_chars > 0 && text_at >= size_t(fldofs) + size_t(count) * kFieldSize &&
            text_at < d.size()) {
            size_t n = std::min(size_t(f.max_chars), d.size() - text_at);
            const char* s = reinterpret_cast<const char*>(d.data() + text_at);
            f.text.assign(s, strnlen(s, n));
        }
        out.fields.push_back(std::move(f));
    }
    return true;
}

} // namespace raptua
