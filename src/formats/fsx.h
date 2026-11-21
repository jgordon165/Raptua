// The two file-system calls the engine needs, on std::filesystem where the
// platform has it and on plain stat/opendir where it doesn't (the Xbox 360's
// LibXenon C++ library has no directory support in std::filesystem).
#pragma once
#include <string>
#include <vector>

namespace raptua::fsx {

bool exists(const std::string& path);
// Names in a folder (no "." or ".."), unsorted; empty if it can't be read.
std::vector<std::string> list(const std::string& dir);
std::string join(const std::string& a, const std::string& b);

} // namespace raptua::fsx
