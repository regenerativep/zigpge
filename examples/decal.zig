const std = @import("std");
const pge = @import("pge");

pub const Game = struct {
    var my_sprite_data = [1]pge.Pixel{pge.Pixel.Red} ** 64;
    random: std.rand.Random,

    my_sprite: pge.Sprite = .{
        .width = 8,
        .height = 8,
        .data = &my_sprite_data,
    },
    my_decal: pge.Decal = undefined,

    pub fn onUserCreate(
        game: *Game,
        alloc: std.mem.Allocator,
        engine: *pge.EngineState,
    ) bool {
        //_ = game;
        _ = alloc;
        _ = engine;

        game.my_decal = pge.Decal.init(&game.my_sprite, false, true) catch return false;
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

        engine.drawDecal(
            &game.my_decal,
            .{
                .x = @intToFloat(f32, engine.mouse_pos.x),
                .y = @intToFloat(f32, engine.mouse_pos.y),
            },
            pge.VF2D.One,
            pge.Pixel.White,
        ) catch return false;
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
