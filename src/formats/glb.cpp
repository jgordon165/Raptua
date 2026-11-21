#include "formats/glb.h"
#include "formats/fsx.h"

#include <algorithm>
#include <cctype>
#include <cstring>
#include <fstream>

namespace raptua {

namespace {

constexpr char kKey[] = "32768GLB";
constexpr size_t kKeyLen = sizeof(kKey) - 1;
constexpr size_t kEntrySize = 28;

uint32_t rd32(const uint8_t* p) {
    return uint32_t(p[0]) | uint32_t(p[1]) << 8 | uint32_t(p[2]) << 16 | uint32_t(p[3]) << 24;
}
void wr32(uint8_t* p, uint32_t v) {
    p[0] = uint8_t(v); p[1] = uint8_t(v >> 8); p[2] = uint8_t(v >> 16); p[3] = uint8_t(v >> 24);
}

std::string lower(std::string s) {
    for (auto& c : s) c = char(std::tolower(static_cast<unsigned char>(c)));
    return s;
}

} // namespace

// The key starts at position 25 % 8; "previous" starts as that key byte.
// plain = cipher - key[pos] - previous_cipher.
void glb_decrypt(uint8_t* data, size_t size) {
    size_t pos = 25 % kKeyLen;
    uint8_t prev = uint8_t(kKey[pos]);
    for (size_t i = 0; i < size; ++i) {
        uint8_t c = data[i];
        data[i] = uint8_t(c - uint8_t(kKey[pos]) - prev);
        prev = c;
        pos = (pos + 1) % kKeyLen;
    }
}

void glb_encrypt(uint8_t* data, size_t size) {
    size_t pos = 25 % kKeyLen;
    uint8_t prev = uint8_t(kKey[pos]);
    for (size_t i = 0; i < size; ++i) {
        uint8_t c = uint8_t(data[i] + uint8_t(kKey[pos]) + prev);
        data[i] = c;
        prev = c;
        pos = (pos + 1) % kKeyLen;
    }
}

bool GlbFile::open(const std::string& path, std::string* err) {
    std::ifstream in(path, std::ios::binary);
    if (!in) { if (err) *err = "cannot open " + path; return false; }
    Bytes data((std::istreambuf_iterator<char>(in)), std::istreambuf_iterator<char>());
    path_ = path;
    return parse(std::move(data), err);
}

bool GlbFile::parse(Bytes data, std::string* err) {
    data_ = std::move(data);
    entries_.clear();
    if (data_.size() < kEntrySize) { if (err) *err = "GLB too small"; return false; }
    uint8_t e[kEntrySize];
    std::memcpy(e, data_.data(), kEntrySize);
    glb_decrypt(e, kEntrySize);
    uint32_t count = rd32(e + 4);
    if (rd32(e) != 0 || count == 0 || (uint64_t(count) + 1) * kEntrySize > data_.size()) {
        if (err) *err = "not a GLB archive (bad header)";
        return false;
    }
    entries_.reserve(count);
    for (uint32_t i = 1; i <= count; ++i) {
        std::memcpy(e, data_.data() + size_t(i) * kEntrySize, kEntrySize);
        glb_decrypt(e, kEntrySize);
        GlbEntry ent;
        ent.flags = rd32(e);
        ent.offset = rd32(e + 4);
        ent.length = rd32(e + 8);
        const char* nm = reinterpret_cast<const char*>(e + 12);
        ent.name.assign(nm, strnlen(nm, 16));
        if (uint64_t(ent.offset) + ent.length > data_.size()) {
            if (err) *err = "GLB entry " + std::to_string(i) + " runs past end of file";
            return false;
        }
        entries_.push_back(std::move(ent));
    }
    return true;
}

Bytes GlbFile::read(size_t index) const {
    if (index >= entries_.size()) return {};
    const auto& e = entries_[index];
    Bytes out(data_.begin() + e.offset, data_.begin() + e.offset + e.length);
    if (e.flags & 1) glb_decrypt(out.data(), out.size());
    return out;
}

Bytes GlbFile::build(const std::vector<std::pair<GlbEntry, Bytes>>& items) {
    size_t fat = (items.size() + 1) * kEntrySize;
    size_t total = fat;
    for (auto& [e, d] : items) total += d.size();
    Bytes out(total, 0);
    uint8_t hdr[kEntrySize] = {};
    wr32(hdr + 4, uint32_t(items.size()));
    glb_encrypt(hdr, kEntrySize);
    std::memcpy(out.data(), hdr, kEntrySize);
    size_t off = fat;
    for (size_t i = 0; i < items.size(); ++i) {
        const auto& [e, d] = items[i];
        uint8_t ent[kEntrySize] = {};
        wr32(ent, e.flags);
        wr32(ent + 4, uint32_t(off));
        wr32(ent + 8, uint32_t(d.size()));
        std::memcpy(ent + 12, e.name.data(), std::min<size_t>(e.name.size(), 15));
        glb_encrypt(ent, kEntrySize);
        std::memcpy(out.data() + (i + 1) * kEntrySize, ent, kEntrySize);
        std::memcpy(out.data() + off, d.data(), d.size());
        if (e.flags & 1) glb_encrypt(out.data() + off, d.size());
        off += d.size();
    }
    return out;
}

std::string find_file_nocase(const std::string& dir, const std::string& name) {
    std::string direct = fsx::join(dir, name);
    if (fsx::exists(direct)) return direct;
    std::string want = lower(name);
    for (const auto& n : fsx::list(dir))
        if (lower(n) == want) return fsx::join(dir, n);
    return {};
}

int GlbSet::open_dir(const std::string& dir, std::string* err) {
    files_.clear();
    for (int n = 0; n < 10; ++n) {
        char nm[16];
        std::snprintf(nm, sizeof nm, "FILE%04d.GLB", n);
        std::string p = find_file_nocase(dir, nm);
        if (p.empty()) break;
        GlbFile f;
        if (!f.open(p, err)) return -1;
        files_.push_back(std::move(f));
    }
    return int(files_.size());
}

std::optional<uint32_t> GlbSet::find(const std::string& name) const {
    for (size_t f = 0; f < files_.size(); ++f) {
        const auto& es = files_[f].entries();
        for (size_t i = 0; i < es.size(); ++i)
            if (es[i].name == name) return uint32_t(f << 16 | i);
    }
    return std::nullopt;
}

std::optional<GlbEntry> GlbSet::entry(uint32_t handle) const {
    size_t f = handle >> 16, i = handle & 0xFFFF;
    if (f >= files_.size() || i >= files_[f].entries().size()) return std::nullopt;
    return files_[f].entries()[i];
}

Bytes GlbSet::read(uint32_t handle) const {
    size_t f = handle >> 16;
    if (f >= files_.size()) return {};
    return files_[f].read(handle & 0xFFFF);
}

Bytes GlbSet::read(const std::string& name) const {
    auto h = find(name);
    return h ? read(*h) : Bytes{};
}

} // namespace raptua
