// Lua is built from its git sources, which have no lua.hpp.
#pragma once
extern "C" {
#include <lauxlib.h>
#include <lua.h>
#include <lualib.h>
}
