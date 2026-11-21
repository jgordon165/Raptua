#include "formats/fsx.h"

#ifndef XENON
#include <filesystem>
#else
#include <dirent.h>
#include <sys/stat.h>
#endif

namespace raptua::fsx {

std::string join(const std::string& a, const std::string& b) {
    if (a.empty()) return b;
    char last = a.back();
    return (last == '/' || last == '\\' || last == ':') ? a + b : a + "/" + b;
}

#ifndef XENON
bool exists(const std::string& path) {
    std::error_code ec;
    return std::filesystem::exists(path, ec);
}

std::vector<std::string> list(const std::string& dir) {
    std::vector<std::string> out;
    std::error_code ec;
    for (auto& de : std::filesystem::directory_iterator(dir, ec)) out.push_back(de.path().filename().string());
    return out;
}
#else
bool exists(const std::string& path) {
    struct stat st;
    return ::stat(path.c_str(), &st) == 0;
}

std::vector<std::string> list(const std::string& dir) {
    std::vector<std::string> out;
    DIR* d = ::opendir(dir.c_str());
    if (!d) return out;
    while (dirent* e = ::readdir(d)) {
        std::string n = e->d_name;
        if (n != "." && n != "..") out.push_back(n);
    }
    ::closedir(d);
    return out;
}
#endif

} // namespace raptua::fsx
