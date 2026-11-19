// raptua-glb: inspect the GLB archives of your own Raptor install.
//
//   raptua-glb list    <file.glb>
//   raptua-glb extract <file.glb> <out-dir>       (decrypted, one file per item)
//   raptua-glb pack    <out.glb> <list.txt>       (list: "flags name path" per line)
//
// Item files are named NNNN_NAME so duplicate and empty names survive.
#include <cstdio>
#include <filesystem>
#include <fstream>
#include <sstream>

#include "formats/glb.h"

using namespace raptua;
namespace fs = std::filesystem;

static int usage() {
    std::fprintf(stderr, "usage: raptua-glb list <glb> | extract <glb> <dir> | pack <out.glb> <list.txt>\n");
    return 1;
}

int main(int argc, char** argv) {
    if (argc < 3) return usage();
    std::string cmd = argv[1];
    if (cmd == "pack") {
        if (argc < 4) return usage();
        std::ifstream in(argv[3]);
        std::vector<std::pair<GlbEntry, Bytes>> items;
        std::string line;
        while (std::getline(in, line)) {
            std::istringstream ss(line);
            GlbEntry e;
            std::string name, path;
            if (!(ss >> e.flags >> name >> path)) continue;
            e.name = name == "-" ? "" : name;
            std::ifstream f(path, std::ios::binary);
            items.push_back({e, Bytes((std::istreambuf_iterator<char>(f)), std::istreambuf_iterator<char>())});
        }
        Bytes out = GlbFile::build(items);
        std::ofstream(argv[2], std::ios::binary).write(reinterpret_cast<const char*>(out.data()), std::streamsize(out.size()));
        return 0;
    }
    GlbFile g;
    std::string err;
    if (!g.open(argv[2], &err)) { std::fprintf(stderr, "%s\n", err.c_str()); return 1; }
    if (cmd == "list") {
        const auto& es = g.entries();
        for (size_t i = 0; i < es.size(); ++i)
            std::printf("%4zu  %-16s %s %8u @%u\n", i, es[i].name.c_str(), es[i].flags & 1 ? "enc" : "   ",
                        es[i].length, es[i].offset);
        return 0;
    }
    if (cmd == "extract" && argc >= 4) {
        fs::create_directories(argv[3]);
        const auto& es = g.entries();
        for (size_t i = 0; i < es.size(); ++i) {
            std::string nm = es[i].name.empty() ? "noname" : es[i].name;
            for (auto& c : nm) if (c == '/' || c == '\\' || c == ':') c = '_';
            char pre[32];
            std::snprintf(pre, sizeof pre, "%04zu_", i);
            Bytes b = g.read(i);
            std::ofstream(fs::path(argv[3]) / (pre + nm), std::ios::binary)
                .write(reinterpret_cast<const char*>(b.data()), std::streamsize(b.size()));
        }
        return 0;
    }
    return usage();
}
