const std = @import("std");
const pge = @import("pge");

/// The user's game state.
pub const Game = struct {
    rand_backend: std.rand.DefaultPrng,

    /// User initializes their state here.
    /// Returning false means to cancel engine initialization
    pub fn userInit(
        self: *Game,
        alloc: std.mem.Allocator,
        engine: *pge.EngineState,
    ) bool {
        _ = alloc;
        _ = engine;

        self.* = Game{
            .rand_backend = std.rand.DefaultPrng.init(0),
        };
        return true;
    }

    /// Called every frame. Update game state and draw here
    /// Stops game if this returns false.
    pub fn userUpdate(
        self: *Game,
        alloc: std.mem.Allocator,
        engine: *pge.EngineState,
        /// Seconds elapsed since `userUpdate` was last called
        elapsed_time: f32,
    ) bool {
        _ = alloc;
        _ = elapsed_time;

        var rand = self.rand_backend.random();

        var y: i32 = 0;
        while (y < engine.screen_size.y) : (y += 1) {
            var x: i32 = 0;
            while (x < engine.screen_size.x) : (x += 1) {
                engine.draw(.{ .x = x, .y = y }, pge.Pixel{ .c = .{
                    .r = rand.int(u8),
                    .g = rand.int(u8),
                    .b = rand.int(u8),
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

    // Initializes game and window
    var engine = try pge.PixelGameEngine(Game).init(
        alloc,
        // Game title, as seen in window title
        "test pge game",
        // Pixel size
        .{ .x = 4, .y = 4 },
        // Screen size in pixels
        .{ .x = 256, .y = 240 },
    );
    defer engine.deinit(alloc);
    // Run the game loop
    try engine.start(alloc);
}
