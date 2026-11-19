// GLB archives (FILE0000.GLB, FILE0001.GLB, ...) used by Raptor v1.2.
//
// Layout: a table of 28-byte entries {u32 flags, u32 offset, u32 length,
// char name[16]} at offset 0, each entry encrypted on its own. Entry 0 is a
// header whose `offset` field holds the item count. Items with flags & 1 are
// encrypted as a whole. See docs/formats.md.
#pragma once
#include <cstdint>
#include <optional>
#include <string>
#include <vector>

namespace raptua {

using Bytes = std::vector<uint8_t>;

// The rolling-key cipher. `reset` starts a new key stream (done per FAT entry).
void glb_decrypt(uint8_t* data, size_t size);
void glb_encrypt(uint8_t* data, size_t size);

struct GlbEntry {
    std::string name;   // as stored, e.g. "PALETTE_DAT" (names are not unique)
    uint32_t flags = 0;
    uint32_t offset = 0;
    uint32_t length = 0;
};

class GlbFile {
public:
    bool open(const std::string& path, std::string* err = nullptr);
    bool parse(Bytes data, std::string* err = nullptr);   // from memory (tests)
    const std::vector<GlbEntry>& entries() const { return entries_; }
    Bytes read(size_t index) const;                       // decrypted contents
    const std::string& path() const { return path_; }

    // Builds an archive (used by tests and `raptua-glb pack`).
    static Bytes build(const std::vector<std::pair<GlbEntry, Bytes>>& items);

private:
    std::string path_;
    Bytes data_;
    std::vector<GlbEntry> entries_;
};

// All FILE000n.GLB of one install. An item handle is (file << 16) | index,
// the same split the original uses.
class GlbSet {
public:
    // Opens FILE0000.GLB.. upward in `dir` (case-insensitive file names).
    int open_dir(const std::string& dir, std::string* err = nullptr);
    void add(GlbFile f) { files_.push_back(std::move(f)); }
    size_t file_count() const { return files_.size(); }
    const GlbFile& file(size_t i) const { return files_[i]; }

    std::optional<uint32_t> find(const std::string& name) const;   // first match
    std::optional<GlbEntry> entry(uint32_t handle) const;
    Bytes read(uint32_t handle) const;
    Bytes read(const std::string& name) const;   // empty if missing

private:
    std::vector<GlbFile> files_;
};

// Case-insensitive lookup of `name` inside directory `dir` (returns full path
// or empty). Data copied from DOS media is often upper case.
std::string find_file_nocase(const std::string& dir, const std::string& name);

} // namespace raptua
