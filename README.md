
# Lunaro

Bindings to the [Lua](https://www.lua.org/) C API.

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

