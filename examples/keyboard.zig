const std = @import("std");
const pge = @import("pge");

pub const Game = struct {
    x: f32 = 0,
    y: f32 = 0,

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

        const move_speed: f32 = 32;
        const corrected_move_speed = move_speed * elapsed_time;
        if (engine.key_state.contains(.Left)) game.x -= corrected_move_speed;
        if (engine.key_state.contains(.Right)) game.x += corrected_move_speed;
        if (engine.key_state.contains(.Up)) game.y -= corrected_move_speed;
        if (engine.key_state.contains(.Down)) game.y += corrected_move_speed;

        const x = @floatToInt(i32, game.x);
        const y = @floatToInt(i32, game.y);

        engine.clear(pge.Pixel.White);
        engine.fillRect(.{ .x = x - 4, .y = y - 4 }, .{ .x = 8, .y = 8 }, pge.Pixel.Black);

        return true;
    }
};
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    var alloc = gpa.allocator();

    var engine = try pge.PixelGameEngine(Game).init(
        alloc,
        "test pge game",
        Game{},
        .{ .x = 4, .y = 4 },
        .{ .x = 128, .y = 120 },
    );
    defer engine.deinit(alloc);
    try engine.start(alloc);
}
