const std = @import("std");
const math = std.math;
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

const LinuxImpl = @import("linux.zig");
pub const Impl = LinuxImpl;

/// All of the possible keys that can be pressed by the user
pub const Key = enum {
    A,
    B,
    C,
    D,
    E,
    F,
    G,
    H,
    I,
    J,
    K,
    L,
    M,
    N,
    O,
    P,
    Q,
    R,
    S,
    T,
    U,
    V,
    W,
    X,
    Y,
    Z,

    F1,
    F2,
    F3,
    F4,
    F5,
    F6,
    F7,
    F8,
    F9,
    F10,
    F11,
    F12,

    Down,
    Left,
    Right,
    Up,

    Enter,
    Back,
    Escape,
    Pause,
    Scroll,
    Tab,
    Del,
    Home,
    End,
    PgUp,
    PgDn,
    Ins,
    Shift,
    Ctrl,
    Space,
    Period,
    CapsLock,

    K0,
    K1,
    K2,
    K3,
    K4,
    K5,
    K6,
    K7,
    K8,
    K9,

    NP0,
    NP1,
    NP2,
    NP3,
    NP4,
    NP5,
    NP6,
    NP7,
    NP8,
    NP9,

    NpMul,
    NpAdd,
    NpDiv,
    NpSub,
    NpDecimal,

    /// semicolon
    OEM_1,
    /// forward slash
    OEM_2,
    /// tilde
    OEM_3,
    /// left bracket
    OEM_4,
    /// back slash
    OEM_5,
    /// right bracket
    OEM_6,
    /// apostrophe
    OEM_7,
    /// number sign
    OEM_8,
    EQUALS,
    COMMA,
    MINUS,
};

/// The possible mouse buttons the user can press
pub const MouseButton = enum {
    Left,
    Middle,
    Right,
};
pub const MouseScrollAmount = 120;

pub fn V2(comptime T: type) type {
    return extern struct {
        x: T,
        y: T,

        const Self = @This();
        pub const Zero = Self{ .x = 0, .y = 0 };
        pub const One = Self{ .x = 1, .y = 1 };

        pub fn clamp(value: Self, lower: Self, upper: Self) Self {
            return .{
                .x = if (value.x < lower.x) lower.x else if (value.x > upper.x) upper.x else value.x,
                .y = if (value.y < lower.y) lower.y else if (value.y > upper.y) upper.y else value.y,
            };
        }

        pub fn cast(value: Self, comptime Target: type) V2(Target) {
            return .{
                .x = math.lossyCast(Target, value.x),
                .y = math.lossyCast(Target, value.y),
            };
        }
    };
}
/// 2D vector of i32s
pub const V2D = V2(i32);
/// 2D vector of u32s
pub const VU2D = V2(u32);
/// 2D vector of f32s
pub const VF2D = V2(f32);

/// Engine state. Everything here is visible by the user
pub const EngineState = struct {
    /// Name of the application. Appears in the title of the window
    app_name: [:0]const u8 = "pge game",
    /// Size of the screen in engine pixels
    screen_size: VU2D,
    inv_screen_size: VF2D,
    /// Size of each pixel in the engine
    pixel_size: VU2D = .{ .x = 1, .y = 1 },
    /// I am unsure of purpose. Appears to cost an extra division operation when updating viewport if enabled
    pixel_cohesion: bool = false,
    /// Whether the application is running. Atomically set to false to stop engine loop
    active: std.atomic.Atomic(bool) = .{ .value = true },

    /// State of fullscreen. TODO: Do not modify?
    full_screen: bool = false,
    /// State of vsync. TODO: do not modify?
    vsync: bool = false,
    window_size: VU2D = VU2D.Zero,
    view_pos: V2D = V2D.Zero,
    view_size: VU2D = VU2D.Zero,
    last_time: i64,
    font_sheet: ?OwnedDecal = null,
    /// Per-frame memory allocator
    arena: std.heap.ArenaAllocator,

    /// List of layers
    layers: std.ArrayListUnmanaged(Layer) = .{},
    /// Current draw target. Null means draw target is the first layer
    draw_target: ?*Sprite = null,
    /// Targeted layer
    target_layer: usize = 0,

    /// Mouse position, as it is being updated. This is in screen space (differs from original PGE).
    mouse_pos_cache: V2D = V2D.Zero,
    /// Mouse position, updated every frame. This is in pixel space.
    mouse_pos: V2D = V2D.Zero,
    /// Mouse wheel difference as it is being updated.
    mouse_wheel_delta_cache: i32 = 0,
    /// Mouse wheel difference updated every frame.
    mouse_wheel_delta: i32 = 0,
    /// Key state of current frame
    key_state: KeyState = KeyState.initEmpty(),
    /// Key state of last frame
    old_key_state: KeyState = KeyState.initEmpty(),
    /// Mouse button state of current frame
    mouse_state: MouseState = MouseState.initEmpty(),
    /// Mouse button state of last frame
    old_mouse_state: MouseState = MouseState.initEmpty(),
    /// Whether the game window has user focus
    has_input_focus: bool = false,
    /// Pixel blending mode
    pixel_mode: PixelMode = .Normal,
    /// Used when pixel_mode is PixelMode.Alpha
    blend_factor: f32 = 1.0,
    /// Decal blending mode
    decal_mode: DecalMode = .Normal,
    /// Decal vertex structure
    decal_structure: DecalStructure = .Fan,

    pub const KeyState = std.EnumSet(Key);
    pub const MouseState = std.EnumSet(MouseButton);

    const Self = @This();

    /// Initializes general engine
    pub fn init(
        alloc: Allocator,
        name: [:0]const u8,
        pixel_size: VU2D,
        screen_size: VU2D,
    ) Self {
        var self = Self{
            .app_name = name,
            .screen_size = undefined,
            .inv_screen_size = undefined,
            .pixel_size = pixel_size,
            .window_size = .{
                .x = screen_size.x * pixel_size.x,
                .y = screen_size.y * pixel_size.y,
            },
            .last_time = std.time.milliTimestamp(),
            .arena = std.heap.ArenaAllocator.init(alloc),
        };
        self.updateScreenSize(screen_size);
        return self;
    }

    /// Draws a single pixel
    pub fn draw(self: *Self, pos: V2D, pixel: Pixel) void {
        var target = self.drawTarget();
        if (pos.x < 0 or pos.y < 0 or pos.x >= target.size.x or pos.y >= target.size.y) return;
        const u_pos = pos.cast(u32);
        self.drawUnchecked(target, u_pos.x, u_pos.y, pixel);
    }
    /// Draws a single pixel.
    /// Requires x < target.size.x, y < target.size.y
    pub fn drawUnchecked(self: *Self, target: *Sprite, x: u32, y: u32, pixel: Pixel) void {
        switch (self.pixel_mode) {
            .Normal => target.data[target.pixelIndex(x, y)] = pixel,
            .Mask => {
                if (pixel.c.a == 255) target.data[target.pixelIndex(x, y)] = pixel;
            },
            .Alpha => {
                const d = target.data[target.pixelIndex(x, y)];
                const a = (@intToFloat(f32, pixel.c.a) / 255.0) / self.blend_factor;
                const c = 1.0 - a;
                target.data[target.pixelIndex(x, y)] = Pixel{ .c = .{
                    .r = @floatToInt(u8, a * @intToFloat(f32, pixel.c.r) + c * @intToFloat(f32, d.c.r)),
                    .g = @floatToInt(u8, a * @intToFloat(f32, pixel.c.g) + c * @intToFloat(f32, d.c.g)),
                    .b = @floatToInt(u8, a * @intToFloat(f32, pixel.c.b) + c * @intToFloat(f32, d.c.b)),
                } };
            },
        }
    }
    // TODO: patterned lines
    /// Draws a line between points `a` and `b`.
    pub fn drawLine(self: *Self, a: V2D, b: V2D, pixel: Pixel) void {
        const dx = b.x - a.x;
        const dy = b.y - a.y;

        // TODO: if we clip a and b to screen, then we can use drawUnchecked

        const dx1 = math.absInt(dx) catch return;
        const dy1 = math.absInt(dy) catch return;
        var px = 2 * dy1 - dx1;
        var py = 2 * dx1 - dy1;
        if (dy1 <= dx1) {
            var x: i32 = undefined;
            var y: i32 = undefined;
            var xe: i32 = undefined;
            if (dx >= 0) {
                x = a.x;
                y = a.y;
                xe = b.x;
            } else {
                x = b.x;
                y = b.y;
                xe = a.x;
            }
            self.draw(.{ .x = x, .y = y }, pixel);
            var i: i32 = 0;
            while (x < xe) : (i += 1) {
                x += 1;
                if (px < 0) {
                    px += 2 * dy1;
                } else {
                    if ((dx < 0 and dy < 0) or (dx > 0 and dy > 0)) y += 1 else y -= 1;
                    px += 2 * (dy1 - dx1);
                }
                self.draw(.{ .x = x, .y = y }, pixel);
            }
        } else {
            var x: i32 = undefined;
            var y: i32 = undefined;
            var ye: i32 = undefined;
            if (dy >= 0) {
                x = a.x;
                y = a.y;
                ye = b.y;
            } else {
                x = b.x;
                y = b.y;
                ye = a.y;
            }
            self.draw(.{ .x = x, .y = y }, pixel);
            var i: i32 = 0;
            while (y < ye) : (i += 1) {
                y += 1;
                if (py < 0) {
                    py += 2 * dx1;
                } else {
                    if ((dx < 0 and dy < 0) or (dx > 0 and dy > 0)) x += 1 else x -= 1;
                    py += 2 * (dx1 - dy1);
                }
                self.draw(.{ .x = x, .y = y }, pixel);
            }
        }
    }
    pub fn drawAxisAlignedLine(
        self: *Self,
        from: V2D,
        length: u32,
        comptime direction: enum { down, right },
        pixel: Pixel,
    ) void {
        const target = self.drawTarget();
        const size_i = target.size.cast(i32);
        if ((from.x < 0 and from.y < 0) or from.x >= size_i.x or from.y >= size_i.y) return;
        var pos = from.clamp(V2D.Zero, size_i).cast(u32);
        var i: u32 = 0;
        while (i <= length and switch (direction) {
            .down => pos.y < size_i.y,
            .right => pos.x < size_i.x,
        }) : (i += 1) {
            self.drawUnchecked(target, pos.x, pos.y, pixel);
            switch (direction) {
                .down => pos.y += 1,
                .right => pos.x += 1,
            }
        }
    }
    pub fn drawRect(self: *Self, tl: V2D, size: VU2D, pixel: Pixel) void {
        self.drawAxisAlignedLine(tl, size.x, .right, pixel);
        self.drawAxisAlignedLine(tl, size.y, .down, pixel);
        self.drawAxisAlignedLine(.{ .x = tl.x + @intCast(i32, size.x), .y = tl.y }, size.y, .down, pixel);
        self.drawAxisAlignedLine(.{ .x = tl.x, .y = tl.y + @intCast(i32, size.y) }, size.x, .right, pixel);
    }
    /// Draws a filled rectangle with the top left location and the rectangle size.
    pub fn fillRect(self: *Self, tl: V2D, size: VU2D, pixel: Pixel) void {
        const target = self.drawTarget();
        const t_size_i = target.size.cast(i32);
        const tl_clamped = tl.clamp(V2D.Zero, t_size_i).cast(u32);
        const br_clamped = V2D.clamp(
            .{ .x = tl.x + @intCast(i32, size.x), .y = tl.y + @intCast(i32, size.y) },
            V2D.Zero,
            t_size_i,
        ).cast(u32);

        var i = tl_clamped.y;
        while (i < br_clamped.y) : (i += 1) {
            var j = tl_clamped.x;
            while (j < br_clamped.x) : (j += 1) {
                self.drawUnchecked(target, j, i, pixel);
            }
        }
    }

    pub fn drawDecal(
        self: *Self,
        decal: *Decal,
        pos: VF2D,
        scale: VF2D,
        tint: Pixel,
    ) void {
        drawDecalE(self, decal, pos, scale, tint) catch |e|
            std.log.warn("failed to draw decal: {any}", .{e});
    }

    pub fn drawDecalE(
        self: *Self,
        decal: *Decal,
        pos: VF2D,
        scale: VF2D,
        tint: Pixel,
    ) !void {
        if (self.target_layer >= self.layers.items.len) return;
        var vertices = try self.arena.allocator().alloc(LocVertex, 4);
        errdefer self.arena.allocator().free(vertices);
        const screen_pos = VF2D{
            .x = (pos.x * self.inv_screen_size.x) * 2.0 - 1.0,
            .y = ((pos.y * self.inv_screen_size.y) * 2.0 - 1.0) * -1.0,
        };
        const sprite_size = decal.sprite.size.cast(f32);
        const screen_dim = VF2D{
            .x = screen_pos.x + (2.0 * sprite_size.x * self.inv_screen_size.x * scale.x),
            .y = screen_pos.y - (2.0 * sprite_size.y * self.inv_screen_size.y * scale.y),
        };
        inline for (.{
            .{ VF2D{ .x = 0.0, .y = 0.0 }, screen_pos },
            .{ VF2D{ .x = 0.0, .y = 1.0 }, VF2D{ .x = screen_pos.x, .y = screen_dim.y } },
            .{ VF2D{ .x = 1.0, .y = 1.0 }, screen_dim },
            .{ VF2D{ .x = 1.0, .y = 0.0 }, VF2D{ .x = screen_dim.x, .y = screen_pos.y } },
        }) |pair, i| {
            vertices[i] = .{
                .pos = [3]f32{ pair[1].x, pair[1].y, 1.0 },
                .tex = pair[0],
                .col = tint,
            };
        }
        try self.layers.items[self.target_layer].decal_draws.append(
            self.arena.allocator(),
            .{
                .decal = decal,
                .mode = self.decal_mode,
                .structure = self.decal_structure,
                .vertices = vertices,
            },
        );
    }
    /// Clears the screen with the specified color
    pub fn clear(self: *Self, pixel: Pixel) void {
        std.mem.set(Pixel, self.drawTarget().data, pixel);
    }
    pub const LineHeight = 8;
    pub const MonoCharWidth = 8;
    pub const MonoCharHeight = 8;
    pub const TabLengthInSpaces = 4;
    pub fn drawString(self: *Self, pos: V2D, text: []const u8, pixel: Pixel, scale: u32) void {
        const font = (self.font_sheet orelse return).inner.sprite;
        var s = pos;
        for (text) |c| switch (c) {
            '\n' => {
                s.x = pos.x;
                s.y += @intCast(i32, LineHeight * scale);
            },
            '\t' => {
                s.x += @intCast(i32, MonoCharWidth * TabLengthInSpaces * scale);
            },
            else => {
                const n = c - 32;
                const font_x = n % 16;
                const font_y = n / 16;
                var i: u4 = 0;
                while (i < MonoCharHeight) : (i += 1) {
                    var j: u4 = 0;
                    while (j < MonoCharWidth) : (j += 1) {
                        if (font.getPixel(.{
                            .x = j + (font_x * MonoCharWidth),
                            .y = i + (font_y * MonoCharHeight),
                        }).c.r > 0) {
                            var is: u32 = 0;
                            while (is < scale) : (is += 1) {
                                var js: u32 = 0;
                                while (js < scale) : (js += 1) {
                                    self.draw(.{
                                        .x = s.x + @intCast(i32, (j * scale) + js),
                                        .y = s.y + @intCast(i32, (i * scale) + is),
                                    }, pixel);
                                }
                            }
                        }
                    }
                }
                s.x += @intCast(i32, MonoCharWidth * scale);
            },
        };
    }
    pub fn getTextSize(text: []const u8) VU2D {
        var width: u32 = 0;
        var height: u32 = 1;
        var current_width: u32 = 0;
        for (text) |c| switch (c) {
            '\n' => {
                if (width < current_width) {
                    width = current_width;
                }
                current_width = 0;
                height += 1;
            },
            '\t' => current_width += TabLengthInSpaces,
            else => current_width += 1,
        };
        if (width < current_width)
            width = current_width;
        return .{
            .x = width * MonoCharWidth,
            .y = height * MonoCharHeight,
        };
    }

    // TODO:
    // drawCircle, fillCircle
    // drawTriangle, fillTriangle
    // drawSprite, drawPartialSprite
    // drawStringProp, getTextSizeProp
    // setDecalMode, setDecalStructure
    // drawPartialDecal
    // drawExplicitDecal, drawWarpedDecal, drawPartialWarpedDecal
    // drawRotatedDecal, drawPartialRotatedDecal
    // drawStringDecal, drawStringDecalProp
    // drawRotatedStringDecal, drawRotatedStringPropDecal
    // drawRectDecal, fillRectDecal, drawGradientFillRectDecal
    // drawPolygonDecal, drawLineDecal
    // clipLineToScreen

    pub fn setDrawLayer(self: *Self, layer: usize, dirty: bool) void {
        if (layer >= self.layers.items.len) return;
        self.draw_target = self.layers.items[layer].draw_target.inner.sprite;
        self.layers.items[layer].update = dirty;
        self.target_layer = layer;
    }

    pub fn updateScreenSize(self: *Self, size: VU2D) void {
        assert(size.x > 0 and size.y > 0);
        self.screen_size = size;
        const size_f = size.cast(f32);
        self.inv_screen_size = .{
            .x = 1.0 / size_f.x,
            .y = 1.0 / size_f.y,
        };
    }
    pub fn updateWindowSize(self: *Self, size: VU2D) void {
        self.window_size = size;
        self.updateViewport();
    }
    pub fn updateViewport(self: *Self) void {
        if (self.pixel_cohesion) {
            self.view_size = .{
                .x = (self.window_size.x / self.screen_size.x) * self.screen_size.x,
                .y = (self.window_size.y / self.screen_size.y) * self.screen_size.y,
            };
        } else {
            const prev_size = VU2D{
                .x = self.screen_size.x * self.pixel_size.x,
                .y = self.screen_size.y * self.pixel_size.y,
            };
            const aspect = @intToFloat(f32, prev_size.x) / @intToFloat(f32, prev_size.y);
            self.view_size = .{
                .x = self.window_size.x,
                .y = @floatToInt(u32, @intToFloat(f32, self.view_size.x) / aspect),
            };
            if (self.view_size.y > self.window_size.y) {
                self.view_size = .{
                    .x = @floatToInt(u32, @intToFloat(f32, self.window_size.y) * aspect),
                    .y = self.window_size.y,
                };
            }
        }
        self.view_pos = VU2D.cast(.{
            .x = (self.window_size.x - self.view_size.x) / 2,
            .y = (self.window_size.y - self.view_size.y) / 2,
        }, i32);
    }

    /// Creates a new layer. Returns the layer index.
    pub fn createLayer(self: *Self, alloc: Allocator) !usize {
        var layer = Layer{ .draw_target = try OwnedDecal.initSize(alloc, self.screen_size) };
        errdefer layer.draw_target.deinit(alloc);
        const id = self.layers.items.len;
        try self.layers.append(alloc, layer);
        return id;
    }
    /// Gets the current draw target
    pub fn drawTarget(self: *Self) *Sprite {
        return if (self.draw_target) |t| t else self.layers.items[0].draw_target.inner.sprite;
    }

    pub fn updateKeyState(self: *Self, key: Key, value: bool) void {
        self.key_state.setPresent(key, value);
    }

    /// Checks if a key was released between the current frame and last frame
    pub fn keyReleased(self: *Self, key: Key) bool {
        return !self.key_state.contains(key) and self.old_key_state.contains(key);
    }
    /// Checks if a key was pressed between the current frame and last frame
    pub fn keyPressed(self: *Self, key: Key) bool {
        return self.key_state.contains(key) and !self.old_key_state.contains(key);
    }
    /// Checks if a key is currently being held down
    pub fn keyHeld(self: *Self, key: Key) bool {
        return self.key_state.contains(key);
    }
    pub const HWButton = struct {
        pressed: bool,
        released: bool,
        held: bool,
    };
    /// Gets the state of a key
    pub fn getKey(self: *Self, key: Key) HWButton {
        return .{
            .pressed = self.keyPressed(key),
            .released = self.keyReleased(key),
            .held = self.keyHeld(key),
        };
    }

    pub fn deinit(self: *Self, alloc: Allocator) void {
        if (self.font_sheet) |*font_sheet| font_sheet.deinit(alloc);
        for (self.layers.items) |*layer| layer.deinit(alloc);
        self.layers.deinit(alloc);
        self.arena.deinit();
    }
};
pub fn PixelGameEngine(comptime UserGame: type) type {
    return struct {
        impl: Impl, // TODO: move impl into state?
        game: UserGame,
        state: EngineState,

        second_count: f32 = 0.0,
        frame_i: usize = 0,

        const Self = @This();

        /// Initializes the engine.
        pub fn init(
            alloc: Allocator,
            name: [:0]const u8,
            pixel_size: VU2D,
            screen_size: VU2D,
        ) !Self {
            var state = EngineState.init(alloc, name, pixel_size, screen_size);
            var impl = try Impl.init(alloc, &state, name);
            errdefer impl.deinit(alloc);

            state.font_sheet = constructFontSheet(alloc) catch |e| blk: {
                std.log.warn("Failed to construct font sheet: {any}", .{e});
                break :blk null;
            };
            return Self{
                .impl = impl,
                .game = undefined,
                .state = state,
            };
        }

        /// Starts the engine loop.
        pub fn start(self: *Self, alloc: Allocator) !void {
            if (self.state.layers.items.len == 0) {
                _ = self.state.createLayer(alloc) catch |e| {
                    std.log.err("Failed to create initial draw layer: {any}", .{e});
                    return e;
                };
                self.state.layers.items[0].show = true;
                self.state.layers.items[0].update = true;
            }

            // userInit must run after user game state isn't moving around anymore
            if (!UserGame.userInit(&self.game, alloc, &self.state))
                return error.UserInitializationFailure;

            while (self.state.active.load(.Monotonic))
                self.update(alloc) catch |e|
                    std.log.warn("Core update error: {any}", .{e});

            // TODO: should this be moved to `deinit`?
            if (@hasDecl(UserGame, "userDeinit"))
                self.game.userDeinit(alloc, &self.state);

            // TODO: thread cleanup?
        }

        /// Runs a single frame of the game loop
        pub fn update(self: *Self, alloc: Allocator) !void {
            const now = std.time.milliTimestamp();
            const elapsed = now - self.state.last_time;
            self.state.last_time = now;
            const fElapsed = @intToFloat(f32, elapsed) / std.time.ms_per_s;

            // TODO: some console suspend time thing

            try self.impl.handleSystemEvent(&self.state);

            self.state.mouse_pos = .{
                .x = math.clamp(
                    @floatToInt(i32, @intToFloat(f32, self.state.mouse_pos_cache.x - self.state.view_pos.x) /
                        @intToFloat(f32, @intCast(i32, self.state.window_size.x) - (self.state.view_pos.x * 2)) *
                        @intToFloat(f32, self.state.screen_size.x)),
                    0,
                    self.state.screen_size.x - 1,
                ),
                .y = math.clamp(
                    @floatToInt(i32, @intToFloat(f32, self.state.mouse_pos_cache.y - self.state.view_pos.y) /
                        @intToFloat(f32, @intCast(i32, self.state.window_size.y) - (self.state.view_pos.y * 2)) *
                        @intToFloat(f32, self.state.screen_size.y)),
                    0,
                    self.state.screen_size.y - 1,
                ),
            };
            self.state.mouse_wheel_delta = self.state.mouse_wheel_delta_cache;

            // TODO: text entry

            comptime assert(@hasDecl(UserGame, "userUpdate"));
            if (!self.game.userUpdate(alloc, &self.state, fElapsed))
                self.state.active.store(false, .Monotonic);

            self.state.old_key_state = self.state.key_state;
            self.state.old_mouse_state = self.state.mouse_state;

            // TODO: console show thing

            Impl.updateViewport(self.state.view_pos, self.state.view_size);
            Impl.clearBuffer(Pixel.Black, true);

            self.state.layers.items[0].show = true;
            self.state.layers.items[0].update = true;

            self.impl.prepareDrawing();

            for (self.state.layers.items) |*layer| if (layer.show) {
                layer.draw_target.inner.tex.apply() catch unreachable;
                if (layer.update) {
                    try layer.draw_target.inner.update();
                    layer.update = false;
                }
                try self.impl.drawLayerQuad(layer.offset, layer.scale, layer.tint);
                for (layer.decal_draws.items) |decal| try self.impl.drawDecal(decal);
                layer.decal_draws = .{}; // intentional leak because arena
            };

            self.impl.displayFrame();

            //const child_alloc = self.state.arena.child_allocator;
            //self.state.arena.deinit();
            //self.state.arena = std.heap.ArenaAllocator.init(child_alloc);
            _ = self.state.arena.reset(.retain_capacity);

            const every_n_seconds: f32 = 1;
            if (self.second_count > every_n_seconds) {
                const fps = @intToFloat(f32, self.frame_i) / self.second_count;
                const format = "Pixel Game Engine - {s} - FPS: {}";
                var buf = [_]u8{0} ** (format.len + 257);
                var title = std.fmt.bufPrintZ(
                    buf[0 .. buf.len - 1],
                    format,
                    .{ self.state.app_name, if (fps > 9999) 9999 else @floatToInt(u32, fps) },
                ) catch buf[0 .. buf.len - 1 :0];
                self.impl.setWindowTitle(title);
                self.frame_i = 0;
                self.second_count -= every_n_seconds;
            }
            self.frame_i += 1;
            self.second_count += fElapsed;
        }

        pub fn constructFontSheet(alloc: Allocator) !OwnedDecal {
            // would be nice not to have a blob in the source code

            const data = "?Q`0001oOch0o01o@F40o0<AGD4090LAGD<090@A7ch0?00O7Q`0600>00000000" ++
                "O000000nOT0063Qo4d8>?7a14Gno94AA4gno94AaOT0>o3`oO400o7QN00000400" ++
                "Of80001oOg<7O7moBGT7O7lABET024@aBEd714AiOdl717a_=TH013Q>00000000" ++
                "720D000V?V5oB3Q_HdUoE7a9@DdDE4A9@DmoE4A;Hg]oM4Aj8S4D84@`00000000" ++
                "OaPT1000Oa`^13P1@AI[?g`1@A=[OdAoHgljA4Ao?WlBA7l1710007l100000000" ++
                "ObM6000oOfMV?3QoBDD`O7a0BDDH@5A0BDD<@5A0BGeVO5ao@CQR?5Po00000000" ++
                "Oc``000?Ogij70PO2D]??0Ph2DUM@7i`2DTg@7lh2GUj?0TO0C1870T?00000000" ++
                "70<4001o?P<7?1QoHg43O;`h@GT0@:@LB@d0>:@hN@L0@?aoN@<0O7ao0000?000" ++
                "OcH0001SOglLA7mg24TnK7ln24US>0PL24U140PnOgl0>7QgOcH0K71S0000A000" ++
                "00H00000@Dm1S007@DUSg00?OdTnH7YhOfTL<7Yh@Cl0700?@Ah0300700000000" ++
                "<008001QL00ZA41a@6HnI<1i@FHLM81M@@0LG81?O`0nC?Y7?`0ZA7Y300080000" ++
                "O`082000Oh0827mo6>Hn?Wmo?6HnMb11MP08@C11H`08@FP0@@0004@000000000" ++
                "00P00001Oab00003OcKP0006@6=PMgl<@440MglH@000000`@000001P00000000" ++
                "Ob@8@@00Ob@8@Ga13R@8Mga172@8?PAo3R@827QoOb@820@0O`0007`0000007P0" ++
                "O`000P08Od400g`<3V=P0G`673IP0`@3>1`00P@6O`P00g`<O`000GP800000000" ++
                "?P9PL020O`<`N3R0@E4HC7b0@ET<ATB0@@l6C4B0O`H3N7b0?P01L3R000000020";

            var sprite = try alloc.create(Sprite);
            errdefer alloc.destroy(sprite);
            sprite.* = try Sprite.initSize(alloc, .{ .x = 128, .y = 48 });
            errdefer sprite.deinit(alloc);

            var p = VU2D.Zero;
            var b: usize = 0;
            while (b < data.len) : (b += 4) {
                const P = packed struct { d: u6, c: u6, b: u6, a: u6 };
                const part = std.StaticBitSet(24){ .mask = @bitCast(u24, P{
                    .a = @intCast(u6, data[b + 0] - 48),
                    .b = @intCast(u6, data[b + 1] - 48),
                    .c = @intCast(u6, data[b + 2] - 48),
                    .d = @intCast(u6, data[b + 3] - 48),
                }) };
                var i: math.Log2Int(u24) = 0;
                while (i < 24) : (i += 1) {
                    const k: u8 = if (part.isSet(i)) 255 else 0;
                    sprite.setPixel(p.cast(i32), .{ .c = .{ .r = k, .g = k, .b = k, .a = k } });
                    p.y += 1;
                    if (p.y == 48) {
                        p.x += 1;
                        p.y = 0;
                    }
                }
            }

            // TODO: spacing

            // TODO: keyboard to character mapping

            return OwnedDecal{ .inner = try Decal.init(sprite, false, true) };
        }
        pub fn deinit(self: *Self, alloc: Allocator) void {
            self.impl.deinit(alloc);
            self.state.deinit(alloc);
            self.* = undefined;
        }
    };
}

/// Pixel blending mode
/// - Normal just writes a pixel normally
/// - Mask writes a pixel if pixel alpha is 255
/// - Alpha writes a pixel, blending the existing pixel and the new pixel dependenting on their alpha levels
pub const PixelMode = enum {
    Normal,
    Mask,
    Alpha,
    // TODO: custom blending?
};
/// The color of a pixel
pub const Pixel = extern union {
    /// TODO: do we really need `n` and for this to be a union?
    n: u32,
    c: extern struct { r: u8, g: u8, b: u8, a: u8 = 255 },

    pub fn dark(p: Pixel) Pixel {
        return .{ .c = .{
            .r = math.divCeil(u8, p.c.r, 2),
            .g = math.divCeil(u8, p.c.g, 2),
            .b = math.divCeil(u8, p.c.b, 2),
            .a = p.a,
        } };
    }
    pub const White = Pixel{ .c = .{ .r = 255, .g = 255, .b = 255 } };
    pub const Black = Pixel{ .c = .{ .r = 0, .g = 0, .b = 0 } };
    pub const Grey = Pixel{ .c = .{ .r = 192, .g = 192, .b = 192 } };
    pub const DarkGrey = Pixel{ .c = .{ .r = 128, .g = 128, .b = 128 } };
    pub const VeryDarkGrey = Pixel{ .c = .{ .r = 64, .g = 64, .b = 64 } };

    pub const Red = Pixel{ .c = .{ .r = 255, .g = 0, .b = 0 } };
    pub const DarkRed = dark(Red);
    pub const VeryDarkRed = dark(DarkRed);
    pub const Yellow = Pixel{ .c = .{ .r = 255, .g = 255, .b = 0 } };
    pub const DarkYellow = dark(Yellow);
    pub const VeryDarkYellow = dark(DarkYellow);
    pub const Green = Pixel{ .c = .{ .r = 0, .g = 255, .b = 0 } };
    pub const DarkGreen = dark(Green);
    pub const VeryDarkGreen = dark(DarkGreen);
    pub const Cyan = Pixel{ .c = .{ .r = 0, .g = 255, .b = 255 } };
    pub const DarkCyan = dark(Cyan);
    pub const VeryDarkCyan = dark(DarkCyan);
    pub const Blue = Pixel{ .c = .{ .r = 0, .g = 0, .b = 255 } };
    pub const DarkBlue = dark(Blue);
    pub const VeryDarkBlue = dark(DarkBlue);
    pub const Magenta = Pixel{ .c = .{ .r = 255, .g = 0, .b = 255 } };
    pub const DarkMagenta = dark(Magenta);
    pub const VeryDarkMagenta = dark(DarkMagenta);

    pub const Blank = Pixel{ .c = .{ .r = 0, .g = 0, .b = 0, .a = 0 } };
    pub const Default = Pixel{ .c = .{ .r = 0, .g = 0, .b = 0, .a = 255 } };
};

/// Sprite data. Stored in RAM.
pub const Sprite = struct {
    pub const SampleMode = enum { Normal, Periodic, Clamp };

    /// Size of the sprite in pixels
    size: VU2D,
    /// Array of the pixels of the sprite.
    data: []Pixel,

    sample_mode: SampleMode = .Normal,

    /// Initializes a sprite with the given size. Pixels are Pixel.Default
    pub fn initSize(alloc: Allocator, size: VU2D) !Sprite {
        var data = try alloc.alloc(Pixel, size.x * size.y);
        for (data) |*b| b.* = Pixel.Default;
        return Sprite{
            .size = size,
            .data = data,
        };
    }
    pub fn deinit(self: *Sprite, alloc: Allocator) void {
        alloc.free(self.data);
        self.* = undefined;
    }

    /// Sets a specific pixel on the sprite
    pub fn setPixel(self: *Sprite, pos: V2D, pixel: Pixel) void {
        if (pos.x < 0 or pos.y < 0 or pos.x >= self.size.x or pos.y >= self.size.y) return;
        self.data[self.pixelIndex(pos.x, pos.y)] = pixel;
    }
    /// Gets a specific pixel on the sprite
    pub fn getPixel(self: *Sprite, pos: V2D) Pixel {
        // TODO: sample mode?
        assert(pos.x >= 0 and pos.y >= 0 and pos.x < self.size.x and pos.y < self.size.y);
        return self.data[self.pixelIndex(pos.x, pos.y)];
    }

    pub inline fn pixelIndex(self: *Sprite, x: anytype, y: anytype) usize {
        return (@intCast(usize, y) * self.size.x) + @intCast(usize, x);
    }
};

/// A sprite stored on the GPU.
pub const Decal = struct {
    /// The sprite the decal depends on
    sprite: *Sprite, // not owned by Decal (except when under OwnedDecal)
    /// The implementation specific representation of the texture stored on the GPU
    tex: Impl.Texture,
    /// TODO: appears to be inverse width and height
    uv_scale: VF2D = .{ .x = 1.0, .y = 1.0 },

    // TODO: what does filter and clamp do
    /// Initializes a decal with the given sprite
    pub fn init(sprite: *Sprite, filter: bool, clamp: bool) !Decal {
        var self = Decal{
            .sprite = sprite,
            .tex = try Impl.Texture.init(sprite.size, filter, clamp),
        };
        errdefer self.tex.deinit();
        try self.update();
        return self;
    }
    /// Update the decal with any changes in the sprite
    pub fn update(self: *Decal) !void {
        const size_f = self.sprite.size.cast(f32);
        self.uv_scale = .{
            .x = 1.0 / size_f.x,
            .y = 1.0 / size_f.y,
        };
        try self.tex.apply();
        self.tex.update(self.sprite);
    }
    pub fn deinit(self: *Decal) void {
        self.tex.deinit();
        self.* = undefined;
    }
};

/// Decal but with deinit and init to make both the decal and sprite owned by this
pub const OwnedDecal = struct {
    inner: Decal,

    /// Make a new decal and sprite with the given size
    pub fn initSize(alloc: Allocator, size: VU2D) !OwnedDecal {
        var sprite = try alloc.create(Sprite);
        errdefer alloc.destroy(sprite);
        sprite.* = try Sprite.initSize(alloc, size);
        errdefer sprite.deinit(alloc);
        return OwnedDecal{ .inner = try Decal.init(sprite, false, true) };
    }
    pub fn deinit(self: *OwnedDecal, alloc: Allocator) void {
        self.inner.sprite.deinit(alloc);
        alloc.destroy(self.inner.sprite);
        self.inner.deinit();
    }
};

/// A layer that can be drawn to
pub const Layer = struct {
    /// TODO: unsure
    offset: VF2D = .{ .x = 0.0, .y = 0.0 },
    /// TODO: unsure
    scale: VF2D = .{ .x = 1.0, .y = 1.0 },

    /// whether the layer should be drawn to screen
    show: bool = false,
    /// whether the sprite backing the decal needs to be updated
    /// TODO: should this be moved to like, sprite?
    update: bool = false,
    /// The decal and sprite backing the layer
    draw_target: OwnedDecal,
    /// List of decals to draw. Stored here to maintain draw order
    decal_draws: std.ArrayListUnmanaged(DecalInstance) = .{},
    /// Tint of the layer
    tint: Pixel = Pixel.White,

    pub fn deinit(self: *Layer, alloc: Allocator) void {
        self.draw_target.deinit(alloc);
        // self.decal_draws.deinit(alloc); // no need to dealloc; arena
        self.* = undefined;
    }
};

/// Information about a vertex sent to the GPU.
/// TODO: is this backend specific?
/// TODO: does this need `extern`?
pub const LocVertex = extern struct {
    // [0] = x, [1] = y, [2] = w(? see `strVS` `p`)
    pos: [3]f32,
    // uv
    tex: VF2D,
    // tint
    col: Pixel,
};
pub const MaxVerts = 128; // `OLC_MAX_VERTS`

/// Decal blending mode
pub const DecalMode = enum {
    Normal,
    Additive,
    Multiplicative,
    Stencil,
    Illuminate,
    Wireframe,
    Model3D,
};
/// The structure of the vertices of a decal
pub const DecalStructure = enum {
    Line,
    Fan,
    Strip,
    List,
};
/// A decal to be drawn
pub const DecalInstance = struct {
    decal: *Decal,
    mode: DecalMode = .Normal,
    structure: DecalStructure = .Fan,
    /// List of vertices for drawing the decal. Not owned by this DecalInstance
    vertices: []const LocVertex,
};
