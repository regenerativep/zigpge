# Zig Pixel Game Engine

This is a Zig reimplementation of the [olcPixelGameEngine](https://github.com/OneLoneCoder/olcPixelGameEngine) by [javidx9](https://github.com/OneLoneCoder).

Many parts of this are different from the original olcPixelGameEngine, such from common practices in Zig and personal preferences on how I think things should be.

Only implemented this for X11+OpenGL3.3, and probably just missing a lot of features in general at the moment.

## Example code

(Also located in `src/main.zig`)

The following is the classic random pixel example.

```zig
const std = @import("std");
const pge = @import("pge");

pub const Game = struct {
    random: std.rand.Random,

    pub fn onUserCreate(
        game: *Game,
        alloc: std.mem.Allocator,
        engine: *pge.EngineState,
    ) bool {
        _ = game;
        _ = alloc;
        _ = engine;
        return true;
    }

    pub fn onUserUpdate(
        game: *Game,
        alloc: std.mem.Allocator,
        engine: *pge.EngineState,
        elapsed_time: f32,
    ) bool {
        _ = alloc;
        _ = elapsed_time;
        var x: i32 = 0;
        while (x < engine.screen_size.x) : (x += 1) {
            var y: i32 = 0;
            while (y < engine.screen_size.y) : (y += 1) {
                engine.draw(.{ .x = x, .y = y }, pge.Pixel{ .c = .{
                    .r = game.random.int(u8),
                    .g = game.random.int(u8),
                    .b = game.random.int(u8),
                } });
            }
        }
        return true;
    }
};
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    var alloc = gpa.allocator();

    var rand_backend = std.rand.DefaultPrng.init(0);

    var engine = try pge.PixelGameEngine(Game).init(
        alloc,
        "test pge game",
        Game{ .random = rand_backend.random() },
        .{ .x = 4, .y = 4 },
        .{ .x = 128, .y = 120 },
    );
    defer engine.deinit(alloc);
    try engine.start(alloc);
}
```
