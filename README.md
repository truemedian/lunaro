
# Lunaro

[![Linux Workflow Status](https://img.shields.io/github/actions/workflow/status/truemedian/lunaro/linux.yml?style=for-the-badge&label=Linux)](https://github.com/truemedian/hzzp/actions/workflows/linux.yml)

Bindings to the [Lua](https://www.lua.org/) C API.

The primary goal of Lunaro to provide a stable, agnostic, and idiomatic interface to the Lua C API.
Code using Lunaro can link against any Lua >= 5.1 library and work without issue.

## Documentation

Documentation is available at [pages.truemedian.me/lunaro](https://pages.truemedian.me/lunaro/#A;lunaro).

## Installation

Add lunaro to your list of dependencies in `build.zig.zon` by adding it to the list of dependencies.

```zig
.{
    .name = "project",
    .version = "0.0.1",
    .dependencies = .{
        .lunaro = .{
            .url = "https://github.com/truemedian/lunaro/archive/master.tar.gz",
        },
    },
}
```

The following sections contain code for a `build.zig` for the different ways to link against Lua.

### As a Library

First, link against Lua dynamically (as seen in the [Dynamic Linking](#dynamic-linking) section).

Then add the following to your library:

```zig
const lunaro = @import("lunaro");

...

fn mylibrary(L: *lunaro.State) c_int {
    ...
}

comptime {
    _ = lunaro.exportAs(mylibrary, "mylibrary");
}
```

This exports the `mylibrary` function (following `lunaro.wrapFn` rules) as `luaopen_mylibrary` so that it can be required from lua.

### Dynamic Linking

#### Using System Libraries

```zig
const lunaro = b.dependency("lunaro", .{});

exe.addModule(lunaro.module("lunaro-system"));

// TODO: the following is no longer applicable, I need to find a way for the user to pass this information into lunaro.

exe.linkSystemLibrary("lua"); // or whatever the name of the lua library is under pkg-config

// if pkg-config isn't available, you'll need to add the include path and library path manually
// exe.addIncludePath("/usr/include/lua5.3"); // this directory should contain lua.h
// exe.addLibraryPath("/usr/lib/lua5.3"); // this directory should contain the required liblua.so
// exe.linkLibrary("lua5.3"); // this should be the name of the lua library to link against
```

#### Using a compiled dynamic library

```zig
const lunaro = b.dependency("lunaro", .{
    .lua = .lua51, // request the version of lua here, valid values are: lua51, lua52, lua53, lua54, luajit
    // .strip = true, // strip all debug information from the lua library
    // .target = ... // build lua for a non-native target
});

exe.addModule(lunaro.module("lunaro-shared"));
```

### Static Linking

```zig
const lunaro = b.dependency("lunaro", .{
    .lua = .lua51, // request the version of lua here, valid values are: lua51, lua52, lua53, lua54, luajit
    // .strip = true, // strip all debug information from the lua library
    // .target = ... // build lua for a non-native target
});

exe.addModule(lunaro.module("lunaro-static"));
```

## Differences

For the most part, Lunaro's API is close to the Lua C API with a few exceptions.  
The Lua 5.3 API was the base for Lunaro, any function that has a direct replacement in 5.3 has been replaced with that function (for example: `lua_equal` is replaced with `lua_compare`).

### Naming

All functions have been stripped of their `lua_` and `luaL_` prefixes. These functions are all in the `State` or `Buffer` namespaces.
Most functions have been slightly renamed, or removed in favor of more idiomatic Zig.  

However, function names still follow the lua convention of all lowercase with no separation between words.

| Lua C API           | Lunaro                   |
|---------------------|--------------------------|
| `lua_newstate`      | `State.initWithAlloc`    |
| `lua_type`          | `State.typeof`           |
| `lua_error`         | `State.throw`            |
| `luaL_checktype`    | `State.ensuretype`       |
| `luaL_checkany`     | `State.ensureexists`     |
| `luaL_checkstack`   | `State.ensurestack`      |
| `luaL_newmetatable` | `State.newmetattablefor` |
| `luaL_setmetatable` | `State.setmetatablefor`  |
| `luaL_error`        | `State.raise`            |
| `luaL_loadbuffer`   | `State.loadstring`       |
| `luaL_newstate`     | `State.init`             |
| `luaL_len`          | `State.lenof`            |
| `luaL_typename`     | `State.typenameof`       |
| `luaL_getmetatable` | `State.getmetablefor`    |
| `luaL_checkudata`   | `State.checkResource`    |

### Missing Functions

`lua_tolstring` has been replaced with `tostring`  
`lua_pushlstring` has been replaced with `pushstring` and `pushstringExtra`  
`luaL_loadstring` has been replaced with `State.loadstring`  

`lua_gc` is not yet implemented.  

`lua_isyieldable` is not implementable in Lua 5.1 and 5.2.  
`lua_setwarnf` is not implementable in Lua 5.1, 5.2 and 5.3 without polyfilling the entire warning API.  
`lua_warning` is not implementable in Lua 5.1, 5.2 and 5.3 without polyfilling the entire warning API.  
`lua_upvalueid` is not implementable in Lua 5.1, 5.2 and 5.3.  
`lua_upvaluejoin` is not implementable in Lua 5.1, 5.2 and 5.3.  

`luaL_argerror` replaced with `State.check`.  
`luaL_typeerror` replaced with `State.check`.  
`luaL_checknumber` replaced with `State.check`.  
`luaL_optnumber` replaced with `State.check`.  
`luaL_checkinteger` replaced with `State.check`.  
`luaL_optinteger` replaced with `State.check`.  
`luaL_checklstring` replaced with `State.check`.  
`luaL_optlstring` replaced with `State.check`.  
`luaL_checkoption` replaced with `State.check`.  
`luaL_testudata` replaced with `State.checkResource`.  

### Additions

To deal with the change in `LUA_GLOBALSINDEX` and `LUA_RIDX_GLOBALS`, `State.pushglobaltable` is provided to push the global table onto the stack.

A generic `State.push` function is provided to push any type onto the stack, include structs as a table.  
A generic `State.check` and `State.checkAlloc` function is provided to check the type of any value on the stack. Usually used to check arguments of a function.  

### Resource Mechanism

Lunaro provides a mechanism to manage userdata resources in Lua.

`State.registerResource` registers a type as a resource and creates a metatable for it.  
`State.resource` creates a resource (from a registered type) and pushes it onto the stack and returns a pointer to it.  
`State.checkResource` checks if the value on the stack is a resource of the given type and returns a pointer to it.  
