# Zig Pixel Game Engine

This is a Zig reimplementation of the [olcPixelGameEngine](https://github.com/OneLoneCoder/olcPixelGameEngine) by [javidx9](https://github.com/OneLoneCoder).

I change many things here, differing from the original engine.

Only implemented this for X11+OpenGL3.3, and probably just missing a lot of features in general at the moment.

## Example code

(Also located in `src/main.zig`)

The following is a random pixel example.

```zig
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
        .{ .x = 128, .y = 120 },
    );
    defer engine.deinit(alloc);
    // Run the game loop
    try engine.start(alloc);
}
```

## Engine

- user game state:
    - `userInit(game: *UserGame, alloc: Allocator, engine: *EngineState)`: meant for user initialization of their game state. provided game state pointed to by `game` is undefined. using initialization with a pointer, instead of initialization by returning, is important since user may want to make references to the game state (ex. decal initialization)
    - `userUpdate(game: *UserGame, alloc: Allocator, engine: *EngineState, elapsed_time: f32)`: called every frame. return false to stop engine
    - `userDeinit(game: *UserGame, alloc: Allocator, engine: *EngineState)` optional deinitialization function
- `Key`: possible key presses
- `MouseButton`: possible mouse presses
- `V2D`, `VF2D`: i32 pair, f32 pair
- `Pixel`: RGB pixel color. has color constants like `White`, `Red`, `DarkMagenta`, `Blank`
- `Sprite`: sprite data stored in RAM
    - `width`, `height`: size of sprite
    - `data`: sprite pixel data
    - `initSize(alloc: Allocator, width: u32, height: u32)`: creates a sprite with given size and initialized to `Pixel.Default`
    - `deinit`
    - `setPixel`: sets a pixel
    - `getPixel`: gets a pixel
- `Decal`: sprite data stored in GPU
    - `sprite`: backing sprite
    - `init(sprite: *Sprite, filter: bool, clamp: bool)`, `deinit`
    - `update`: updates decal such as to reflect changes to the sprite
- `EngineState`:
    - `app_name`: name of application in window title. null-terminated
    - `active`: whether engine should keep running
    - `arena`: arena allocator (based on allocator provided by user at initialization). reset every frame.
    - `layers`: list of layers. list allocated with user provided allocator.
    - `draw_target`: draw target to use when calling draw functions
    - `target_layer`: if a layer is the draw target, this specifies which layer
    - `mouse_pos`: position of mouse
    - `mouse_wheel_delta`: change in the mouse wheel during the past frame
    - `key_state`: enum set of held keyboard keys
    - `old_key_state`: enum set of held keyboard keys from the previous frame
    - `mouse_state`: enum set of held mouse keys
    - `old_mouse_state`: enum set of held mouse keys from the previous frame
    - `draw(engine: *EngineState, pos: V2D, pixel: Pixel)`: draws a single pixel
    - `drawLine(engine: *EngineState, a: V2D, b: V2D, pixel: Pixel)`: draws a line
    - `fillRect(engine: *EngineState, tl: V2D, size: V2D, pixel: Pixel)`: draws a filled rectangle
    - `drawDecal(engine: *EngineState, decal: *Decal, pos: VF2D, scale: VF2D, tint: Pixel)` draws a decal. may internally allocate
    - `clear(engine: *EngineState, pixel: Pixel)`: clears screen with given color
    - `setDrawLayer(engine: *EngineState, layer: usize, dirty: bool)` sets the draw target to the specified layer. necessary for `drawDecal` to draw to a layer
    - `createLayer(engine: *EngineState, alloc: Allocator)`: creates a layer that can be drawn to. returns the layer's index.
    - `drawTarget(engine: *EngineState)` returns the current draw target
    - `getKey(engine: *EngineState, key: Key)`: returns keyboard key state in a `HWButton`
    - `keyPressed(engine: *EngineState, key: Key)`: if a key was just pressed
    - `keyReleased(engine: *Enginestate, key: Key)`: if a key was just released
    - `keyHeld(engine: *EngineState, key: Key)`: if a key is being held
- `PixelGameEngine(comptime UserGame: type)`
    - `game`: user's game state
    - `state`: engine state
    - `init(alloc: Allocator, name: [:0]const u8, pixel_size: V2D, screen_size: V2D)`: initializes engine
    - `start(pge: *PixelGameEngine(UserGame), alloc: Allocator)`: starts engine game loop

