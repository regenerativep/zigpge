const std = @import("std");
const math = std.math;
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

// TODO: split up this file into other files
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

        pub fn clamp(value: Self, lower: Self, upper: Self) Self {
            return .{
                .x = if (value.x < lower.x) lower.x else if (value.x > upper.x) upper.x else value.x,
                .y = if (value.y < lower.y) lower.y else if (value.y > upper.y) upper.y else value.y,
            };
        }
    };
}
/// 2D vector of i32s
pub const V2D = V2(i32);
/// 2D vector of f32s
pub const VF2D = V2(f32);

/// Engine state. Everything here is visible by the user
pub const EngineState = struct {
    /// Name of the application. Appears in the title of the window
    app_name: []const u8 = "pge game",
    /// Size of the screen in engine pixels
    screen_size: V2D,
    /// Size of each pixel in the engine
    pixel_size: V2D = .{ .x = 1, .y = 1 },
    /// I am unsure of purpose. Appears to cost an extra division operation when updating viewport if enabled
    pixel_cohesion: bool = false,
    /// Whether the application is running. Atomically set to false to stop engine loop
    active: std.atomic.Atomic(bool) = .{ .value = true },

    /// State of fullscreen. TODO: Do not modify?
    full_screen: bool = false,
    /// State of vsync. TODO: do not modify?
    vsync: bool = false,
    window_size: V2D = V2D.Zero,
    view_pos: V2D = V2D.Zero,
    view_size: V2D = V2D.Zero,
    last_time: i64,
    font_sheet: ?OwnedDecal = null,

    /// List of layers
    layers: std.ArrayListUnmanaged(Layer) = .{},
    /// Current draw target. Null means draw target is the first layer
    draw_target: ?*Sprite = null,

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

    pub const KeyState = std.EnumSet(Key);
    pub const MouseState = std.EnumSet(MouseButton);

    const Self = @This();

    /// Initializes general engine
    pub fn init(name: []const u8, pixel_size: V2D, screen_size: V2D) Self {
        assert(pixel_size.x > 0 and pixel_size.y > 0);
        assert(screen_size.x > 0 and screen_size.y > 0);
        return Self{
            .app_name = name,
            .screen_size = screen_size,
            .pixel_size = pixel_size,
            .window_size = .{
                .x = screen_size.x * pixel_size.x,
                .y = screen_size.y * pixel_size.y,
            },
            .last_time = std.time.milliTimestamp(),
        };
    }

    /// Draws a single pixel
    pub fn draw(self: *Self, pos: V2D, pixel: Pixel) void {
        var target = self.drawTarget();
        if (pos.x < 0 or pos.y < 0 or pos.x >= target.width or pos.y >= target.height) return;
        const x = @intCast(u32, pos.x);
        const y = @intCast(u32, pos.y);
        self.drawUnchecked(target, x, y, pixel);
    }
    /// Draws a single pixel.
    /// Requires x < target.width, y < target.height
    pub fn drawUnchecked(self: *Self, target: *Sprite, x: u32, y: u32, pixel: Pixel) void {
        switch (self.pixel_mode) {
            .Normal => target.data[target.pixelIndex(x, y)] = pixel,
            .Mask => {
                if (pixel.c.a == 255) target.data[target.pixelIndex(x, y)] = pixel;
            },
            .Alpha => {
                const d = target.getPixel(x, y);
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

        const dx1 = math.abs(dx);
        const dy1 = math.abs(dy);
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
                    if ((dx < 0 and dy < 0) or (dx > 0 and dy > 0)) x += 1 else x += 1;
                    py += 2 * (dx1 - dy1);
                }
                self.draw(.{ .x = x, .y = y }, pixel);
            }
        }
    }
    /// Draws a filled rectangle with the top left location and the rectangle size.
    pub fn fillRect(self: *Self, tl: V2D, size: V2D, pixel: Pixel) void {
        const target = self.drawTarget();
        const size_i = V2D{
            .x = @intCast(i32, target.width),
            .y = @intCast(i32, target.height),
        };
        const tl_clamped = tl.clamp(V2D.Zero, size_i);
        const br_clamped = V2D.clamp(.{ .x = tl.x + size.x, .y = tl.y + size.y }, V2D.Zero, size_i);

        var i = @intCast(u32, tl_clamped.y);
        while (i < br_clamped.y) : (i += 1) {
            var j = @intCast(u32, tl_clamped.x);
            while (j < br_clamped.x) : (j += 1) {
                self.drawUnchecked(target, j, i, pixel);
            }
        }
    }
    /// Clears the screen with the specified color
    pub fn clear(self: *Self, pixel: Pixel) void {
        const target = self.drawTarget();
        for (target.data) |*p| p.* = pixel;
    }

    pub fn updateWindowSize(self: *Self, size: V2D) void {
        self.window_size = size;
        self.updateViewport();
    }
    pub fn updateViewport(self: *Self) void {
        if (self.pixel_cohesion) {
            self.view_size = .{
                .x = @divTrunc(self.window_size.x, self.screen_size.x) * self.screen_size.x,
                .y = @divTrunc(self.window_size.y, self.screen_size.y) * self.screen_size.y,
            };
        } else {
            const prev_size = V2D{
                .x = self.screen_size.x * self.pixel_size.x,
                .y = self.screen_size.y * self.pixel_size.y,
            };
            const aspect = @intToFloat(f32, prev_size.x) / @intToFloat(f32, prev_size.y);
            self.view_size = .{
                .x = self.window_size.x,
                .y = @floatToInt(i32, @intToFloat(f32, self.view_size.x) / aspect),
            };
            if (self.view_size.y > self.window_size.y) {
                self.view_size = .{
                    .x = @floatToInt(i32, @intToFloat(f32, self.window_size.y) * aspect),
                    .y = self.window_size.y,
                };
            }
        }
        self.view_pos = .{
            .x = @divTrunc(self.window_size.x - self.view_size.x, 2),
            .y = @divTrunc(self.window_size.y - self.view_size.y, 2),
        };
    }

    /// Creates a new layer. Returns the layer index.
    pub fn createLayer(self: *Self, alloc: Allocator) !usize {
        var layer = Layer{
            .draw_target = try OwnedDecal.initSize(
                alloc,
                @intCast(u32, self.screen_size.x),
                @intCast(u32, self.screen_size.y),
            ),
        };
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
            name: []const u8,
            game: UserGame,
            pixel_size: V2D,
            screen_size: V2D,
        ) !Self {
            var state = EngineState.init(name, pixel_size, screen_size);
            var impl = try Impl.init(alloc, &state);
            errdefer impl.deinit(alloc);

            state.font_sheet = constructFontSheet(alloc) catch |e| blk: {
                std.log.warn("Failed to construct font sheet: {any}", .{e});
                break :blk null;
            };

            return Self{
                .impl = impl,
                .game = game,
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

            if (@hasDecl(UserGame, "onUserCreate")) // TODO: should we move this to the `init` function?
                if (!self.game.onUserCreate(alloc, &self.state)) self.state.active.store(false, .Monotonic);

            while (self.state.active.load(.Monotonic)) {
                self.update(alloc) catch |e| {
                    std.log.warn("Core update error: {any}", .{e});
                };
            }

            if (@hasDecl(UserGame, "onUserDestroy"))
                self.game.onUserDestroy(alloc, &self.state);

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
                        @intToFloat(f32, self.state.window_size.x - (self.state.view_pos.x * 2)) *
                        @intToFloat(f32, self.state.screen_size.x)),
                    0,
                    self.state.screen_size.x - 1,
                ),
                .y = math.clamp(
                    @floatToInt(i32, @intToFloat(f32, self.state.mouse_pos_cache.y - self.state.view_pos.y) /
                        @intToFloat(f32, self.state.window_size.y - (self.state.view_pos.y * 2)) *
                        @intToFloat(f32, self.state.screen_size.y)),
                    0,
                    self.state.screen_size.y - 1,
                ),
            };
            self.state.mouse_wheel_delta = self.state.mouse_wheel_delta_cache;

            // TODO: text entry

            comptime assert(@hasDecl(UserGame, "onUserUpdate"));
            if (!self.game.onUserUpdate(alloc, &self.state, fElapsed))
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
                layer.decal_draws.clearRetainingCapacity();
            };

            self.impl.displayFrame();

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
            sprite.* = try Sprite.initSize(alloc, 128, 48);
            errdefer sprite.deinit(alloc);

            var did_half = false; // 24 + 24 = 48
            var y: u32 = 0;
            var i: usize = 0;
            while (i < data.len) : (i += 4) {
                const P = packed struct(u24) { a: u6, b: u6, c: u6, d: u6 };
                const part = std.StaticBitSet(24){ .mask = @bitCast(u24, P{
                    .a = @intCast(u6, data[i + 0] - 48),
                    .b = @intCast(u6, data[i + 1] - 48),
                    .c = @intCast(u6, data[i + 2] - 48),
                    .d = @intCast(u6, data[i + 3] - 48),
                }) };
                var j: u32 = 0;
                while (j < 24) : (j += 1) {
                    const k: u8 = if (part.isSet(j)) 255 else 0;
                    // yeah i did a fancy thing here
                    const x = j + if (did_half) @as(u32, 24) else 0;
                    sprite.setPixel(x, y, .{ .c = .{ .r = k, .g = k, .b = k, .a = k } });
                }
                if (did_half) y += 1;
                did_half = !did_half;
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

    // TODO: use a V2(u32) ?
    /// Width of the sprite in pixels
    width: u32,
    /// Height of the sprite in pixels
    height: u32,
    /// Array of the pixels of the sprite.
    data: []Pixel,

    sample_mode: SampleMode = .Normal,

    /// Initializes a sprite with the given size. Pixels are Pixel.Default
    pub fn initSize(alloc: Allocator, width: u32, height: u32) !Sprite {
        var data = try alloc.alloc(Pixel, width * height);
        for (data) |*b| b.* = Pixel.Default;
        return Sprite{
            .width = width,
            .height = height,
            .data = data,
        };
    }
    pub fn deinit(self: *Sprite, alloc: Allocator) void {
        alloc.free(self.data);
        self.* = undefined;
    }

    /// Sets a specific pixel on the sprite
    pub fn setPixel(self: *Sprite, x: u32, y: u32, pixel: Pixel) void {
        if (x >= self.width or y >= self.height) return;
        self.data[self.pixelIndex(x, y)] = pixel;
    }
    /// Gets a specific pixel on the sprite
    pub fn getPixel(self: *Sprite, x: u32, y: u32) Pixel {
        // TODO: sample mode?
        assert(x < self.width and y < self.height);
        return self.data[self.pixelIndex(x, y)];
    }

    pub inline fn pixelIndex(self: *Sprite, x: u32, y: u32) usize {
        return y * self.width + x;
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
            .tex = try Impl.Texture.init(sprite.width, sprite.height, filter, clamp),
        };
        errdefer self.tex.deinit();
        try self.update();
        return self;
    }
    /// Update the decal with any changes in the sprite
    pub fn update(self: *Decal) !void {
        self.uv_scale = .{
            .x = 1.0 / @intToFloat(f32, self.sprite.width),
            .y = 1.0 / @intToFloat(f32, self.sprite.height),
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
    pub fn initSize(alloc: Allocator, w: u32, h: u32) !OwnedDecal {
        var sprite = try alloc.create(Sprite);
        errdefer alloc.destroy(sprite);
        sprite.* = try Sprite.initSize(alloc, w, h);
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
        self.decal_draws.deinit(alloc);
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

pub const LinuxImpl = struct {
    const x = @import("x11.zig");
    const g = @import("gl.zig");

    // TODO: name "Window" or something like that?
    pub const XState = struct {
        display: x.Display,
        window_root: x.Window,
        window: x.Window,
        visual_info: x.VisualInfo,
        color_map: x.Colormap,

        pub fn init(
            window_pos: V2D,
            window_size: *V2D,
            full_screen: bool,
        ) !XState {
            if (!x.initThreads())
                std.log.warn("X says it doesn't support multithreading", .{});
            x.errors.initHandler();

            const display = x.Display.open(null) orelse return error.DisplayOpenFailure;
            errdefer display.close();
            if (!x.errors.initErrors(display)) return error.XErrorInitializationFailure;
            const window_root = display.defaultRootWindow();

            var visual_info = x.chooseVisual(display, 0, .{
                .rgba = true,
                .depth_size = 24,
                .doublebuffer = true,
            });
            errdefer visual_info.deinit();

            const color_map = try x.Colormap.create(display, window_root, visual_info.visual(), .none);
            errdefer color_map.free(display);

            const window = try x.Window.create(
                display,
                window_root,
                window_pos.x,
                window_pos.y,
                @intCast(u32, window_size.x),
                @intCast(u32, window_size.y),
                0,
                visual_info.depth(),
                .InputOutput,
                visual_info.visual(),
                .{ .colormap = true, .event_mask = true },
                x.Window.WindowAttributes{ .colormap = color_map.inner, .event_mask = .{
                    .key_press = true,
                    .key_release = true,
                    .button_press = true,
                    .button_release = true,
                    .pointer_motion = true,
                    .focus_change = true,
                    .structure_notify = true,
                } },
            );
            errdefer window.destroy(display);

            var wm_delete = try x.internAtom(display, "WM_DELETE_WINDOW", true);
            try display.setWMProtocols(window, @as(*[1]x.Atom, &wm_delete));

            window.map(display);
            display.storeName(window, "zig pge"); // TODO: make this app_name? or dont do this here?

            if (full_screen) {
                const wm_state = try x.internAtom(display, "_NET_WM_STATE", false);
                const wm_state_fullscreen = try x.internAtom(display, "_NET_WM_STATE_FULLSCREEN", false);

                // i didnt write a nice abstracted way to interface with x11 here
                var xev = std.mem.zeroes(x.c.XEvent);
                xev.type = x.c.ClientMessage;
                xev.xclient.window = window.inner;
                xev.xclient.message_type = wm_state;
                xev.xclient.format = 32;
                xev.xclient.data.l = [5]c_long{ @boolToInt(full_screen), @intCast(c_long, wm_state_fullscreen), 0, 0, 0 };

                window.map(display);
                try display.sendEvent(
                    window_root,
                    false,
                    .{ .substructure_redirect = true, .substructure_notify = true },
                    &xev,
                );
                display.flush();

                const gwa = try window.getAttributes(display);
                window_size.* = .{ .x = gwa.width, .y = gwa.height };
            }

            return XState{
                .display = display,
                .window_root = window_root,
                .visual_info = visual_info,
                .color_map = color_map,
                .window = window,
            };
        }
        pub fn deinit(self: *XState) void {
            self.visual_info.deinit();
            self.window.destroy(self.display);
            self.color_map.free(self.display);
            self.window.destroy(self.display);
            self.* = undefined;
        }
    };

    x_state: XState,

    device_context: x.Context,

    n_fs: ge.Shader,
    n_vs: ge.Shader,
    n_quad: ge.Program,
    vb_quad: ge.Buffer,
    va_quad: ge.VertexArray,
    blank_quad: OwnedDecal,

    decal_mode: DecalMode = .Normal,

    pub const ge = g.Extensions(.{
        .{ "glXSwapIntervalEXT", fn (*x.c.Display, x.c.GLXDrawable, c_int) callconv(.C) void },
        .{ "glCreateShader", fn (x.c.GLenum) callconv(.C) x.c.GLuint, true },
        .{ "glCompileShader", fn (x.c.GLuint) callconv(.C) void, true },
        .{ "glShaderSource", fn (x.c.GLuint, x.c.GLsizei, [*]const [:0]const u8, ?[*]x.c.GLint) callconv(.C) void, true },
        .{ "glDeleteShader", fn (x.c.GLuint) callconv(.C) void, true },
        .{ "glCreateProgram", fn () callconv(.C) x.c.GLuint, true },
        .{ "glDeleteProgram", fn (x.c.GLuint) callconv(.C) void, true },
        .{ "glLinkProgram", fn (x.c.GLuint) callconv(.C) void, true },
        .{ "glAttachShader", fn (x.c.GLuint, x.c.GLuint) callconv(.C) void, true },
        .{ "glBindBuffer", fn (x.c.GLenum, x.c.GLuint) callconv(.C) void, true },
        .{ "glBufferData", fn (x.c.GLenum, x.c.GLsizeiptr, *const anyopaque, x.c.GLenum) callconv(.C) void, true },
        .{ "glGenBuffers", fn (x.c.GLsizei, [*]x.c.GLuint) callconv(.C) void, true },
        .{ "glDeleteBuffers", fn (x.c.GLsizei, [*]const x.c.GLuint) callconv(.C) void, true },
        .{ "glVertexAttribPointer", fn (x.c.GLuint, x.c.GLint, x.c.GLenum, x.c.GLboolean, x.c.GLsizei, usize) callconv(.C) void, true },
        .{ "glEnableVertexAttribArray", fn (x.c.GLuint) callconv(.C) void, true },
        .{ "glUseProgram", fn (x.c.GLuint) callconv(.C) void },
        .{ "glGetShaderInfoLog", fn (x.c.GLuint, [*c]const u8) callconv(.C) void },
        .{ "glBindVertexArray", fn (x.c.GLuint) callconv(.C) void, true },
        .{ "glGenVertexArrays", fn (x.c.GLsizei, [*]x.c.GLuint) callconv(.C) void, true },
        .{ "glDeleteVertexArrays", fn (x.c.GLsizei, [*]const x.c.GLuint) callconv(.C) void, true },
        .{ "glGetShaderiv", fn (x.c.GLuint, x.c.GLenum, *x.c.GLint) callconv(.C) void, true },
    });
    const Self = @This();

    pub fn init(alloc: Allocator, state: *EngineState) !Self {
        var x_state = try XState.init(.{ .x = 30, .y = 30 }, &state.window_size, state.full_screen);
        errdefer x_state.deinit();

        state.updateViewport();

        const ctx = try x.Context.create(x_state.display, x_state.visual_info, x.Context{ .inner = null }, true);
        errdefer ctx.destroy(x_state.display);
        try x_state.display.makeCurrent(x_state.window, ctx);
        errdefer x_state.display.makeCurrent(x.Window{ .inner = 0 }, x.Context{ .inner = null }) catch unreachable;

        const gwa = try x_state.window.getAttributes(x_state.display);
        g.viewport(0, 0, @intCast(u32, gwa.width), @intCast(u32, gwa.height));

        try ge.load();

        if (!state.vsync)
            if (ge.has("glXSwapIntervalEXT"))
                ge.swapInterval(x_state.display, x_state.window.inner, 0)
            else
                std.log.warn("cannot disable vsync (no glXSwapIntervalEXT)", .{});

        // why did pge hardcode the number here to specify fragment shader?
        var nFS = ge.Shader.init(.Fragment);
        errdefer nFS.deinit();
        // note: following shaders not made for arm. see relevant olcPixelGameEngine source
        const strFS =
            \\#version 330 core
            \\out vec4 pixel;
            \\in vec2 oTex;
            \\in vec4 oCol;
            \\uniform sampler2D sprTex;
            \\void main() {
            \\  pixel = texture(sprTex, oTex) * oCol;
            \\}
        ;
        nFS.source(&[1][:0]const u8{strFS}, null);
        nFS.compile();
        if (!nFS.getCompileStatus()) return error.ShaderCompilationFailure;

        var nVS = ge.Shader.init(.Vertex);
        errdefer nVS.deinit();
        const strVS =
            \\#version 330 core
            \\layout(location = 0) in vec3 aPos;
            \\layout(location = 1) in vec2 aTex;
            \\layout(Location = 2) in vec4 aCol;
            \\out vec2 oTex;
            \\out vec4 oCol;
            \\
            \\void main() {
            \\  float p = 1.0 / aPos.z;
            \\  gl_Position = p * vec4(aPos.x, aPos.y, 0.0, 1.0);
            \\  oTex = p * aTex;
            \\  oCol = aCol;
            \\}
        ;
        nVS.source(&[1][:0]const u8{strVS}, null);
        nVS.compile();
        if (!nVS.getCompileStatus()) return error.ShaderCompilationFailure;

        var quad = ge.Program.init();
        errdefer quad.deinit();
        try quad.attachShader(nFS);
        try quad.attachShader(nVS);
        try quad.link();

        var vb_quad = ge.Buffer.init();
        errdefer vb_quad.deinit();
        var va_quad = ge.VertexArray.init();
        errdefer va_quad.deinit();
        va_quad.bind();
        vb_quad.bind(.Array);

        var verts: [MaxVerts]LocVertex = undefined;
        try ge.Buffer.data(.Array, LocVertex, &verts, .StreamDraw);
        try ge.vertexAttribPointer(0, 3, .Float, false, @sizeOf(LocVertex), @offsetOf(LocVertex, "pos"));
        ge.enableVertexAttribArray(0);
        try ge.vertexAttribPointer(1, 2, .Float, false, @sizeOf(LocVertex), @offsetOf(LocVertex, "tex"));
        ge.enableVertexAttribArray(1);
        try ge.vertexAttribPointer(2, 4, .UnsignedByte, true, @sizeOf(LocVertex), @offsetOf(LocVertex, "col"));
        ge.enableVertexAttribArray(2);
        ge.Buffer.None.bind(.Array);
        ge.VertexArray.None.bind();

        updateViewport(state.view_pos, state.view_size);

        var blank_sprite: *Sprite = undefined;
        var blank_quad: OwnedDecal = undefined;
        {
            // TODO: could we do OwnedDecal.initSize here?
            blank_sprite = try alloc.create(Sprite);
            errdefer alloc.destroy(blank_sprite);
            blank_sprite.* = try Sprite.initSize(alloc, 1, 1);
            errdefer blank_sprite.deinit(alloc);
            blank_sprite.data[0] = Pixel.White;

            blank_quad = OwnedDecal{
                .inner = try Decal.init(blank_sprite, false, true),
            };
        }
        errdefer blank_quad.deinit(alloc);
        try blank_quad.inner.update(); // may be unnecessary to call this here

        return Self{
            .x_state = x_state,
            .n_quad = quad,
            .vb_quad = vb_quad,
            .va_quad = va_quad,
            .device_context = ctx,
            .n_fs = nFS,
            .n_vs = nVS,
            .blank_quad = blank_quad,
        };
    }
    pub fn deinit(self: *Self, alloc: Allocator) void {
        self.x_state.display.makeCurrent(x.Window.None, x.Context.None) catch unreachable;
        self.device_context.destroy(self.x_state.display);
        self.va_quad.deinit();
        self.vb_quad.deinit();
        self.n_quad.deinit();
        self.n_vs.deinit();
        self.n_fs.deinit();
        self.blank_quad.deinit(alloc);
        self.x_state.deinit();
        self.* = undefined;
    }

    pub fn updateViewport(pos: V2D, size: V2D) void {
        g.viewport(pos.x, pos.y, @intCast(u32, size.x), @intCast(u32, size.y));
    }

    pub const Texture = struct {
        inner: g.Texture,

        pub fn init(width: u32, height: u32, filter: bool, clamp: bool) !Texture {
            _ = width;
            _ = height;
            var tex = g.Texture.init();
            errdefer tex.deinit();
            tex.bind(.TwoD);

            // hopefully order doesnt matter. noted that the pge code isnt in same order
            comptime var P = g.TextureParameterValue(.MinFilter); // i guess zig type inference isnt good enough?
            g.texParameter(.TwoD, .MinFilter, if (filter) P.Linear else P.Nearest);
            P = g.TextureParameterValue(.MagFilter);
            g.texParameter(.TwoD, .MagFilter, if (filter) P.Linear else P.Nearest);
            // note: pge uses GL_CLAMP, not GL_CLAMP_TO_EDGE here. unsure if this is a problem
            P = g.TextureParameterValue(.WrapS);
            g.texParameter(.TwoD, .WrapS, if (clamp) P.ClampToEdge else P.Repeat);
            P = g.TextureParameterValue(.WrapT);
            g.texParameter(.TwoD, .WrapT, if (clamp) P.ClampToEdge else P.Repeat);

            return Texture{ .inner = tex };
        }
        pub fn deinit(tex: *Texture) void {
            tex.inner.deinit();
        }
        // this feels like a backend specific thing to do? TODO: see how non-opengl does something like this
        pub fn apply(tex: Texture) !void {
            tex.inner.bind(.TwoD);
        }
        pub fn update(tex: Texture, sprite: *Sprite) void {
            _ = tex;
            g.texImage2D(
                .TwoD,
                0,
                .RGBA,
                @intCast(u32, sprite.width),
                @intCast(u32, sprite.height),
                0,
                .RGBA,
                .UnsignedByte,
                @ptrCast([*]const u8, sprite.data.ptr),
            );
        }

        pub fn read(tex: Texture, sprite: *Sprite) void {
            _ = tex;
            g.readPixels(0, 0, @intCast(u32, sprite.width), @intCast(u32, sprite.height), .RGBA, .UnsignedByte, sprite.data.ptr);
        }
    };

    pub fn clearBuffer(p: Pixel, comptime depth: bool) void {
        g.clear(&(.{.Color} ++ if (depth) .{.Depth} else .{}), .{ .color = .{
            .r = @intToFloat(f32, p.c.r) / 255.0,
            .g = @intToFloat(f32, p.c.g) / 255.0,
            .b = @intToFloat(f32, p.c.b) / 255.0,
            .a = @intToFloat(f32, p.c.a) / 255.0,
        } });
    }

    pub fn handleSystemEvent(self: *Self, pge: *EngineState) !void {
        while (true) {
            const count = self.x_state.display.pending();
            if (count == 0) break;
            var i: usize = 0;
            while (i < count) : (i += 1) {
                var xev = self.x_state.display.nextEvent();
                switch (xev.type) {
                    x.c.Expose => {
                        const attr = try self.x_state.window.getAttributes(self.x_state.display); // should be no error
                        pge.updateWindowSize(.{ .x = attr.width, .y = attr.height });
                    },
                    x.c.ConfigureNotify => {
                        pge.updateWindowSize(.{
                            .x = xev.xconfigure.width,
                            .y = xev.xconfigure.height,
                        });
                    },
                    x.c.KeyPress => {
                        if (mapKey(x.c.XLookupKeysym(&xev.xkey, 0))) |key| pge.updateKeyState(key, true);
                    },
                    x.c.KeyRelease => {
                        if (mapKey(x.c.XLookupKeysym(&xev.xkey, 0))) |key| pge.updateKeyState(key, false);
                    },
                    x.c.ButtonPress => switch (xev.xbutton.button) {
                        x.c.Button1 => pge.mouse_state.insert(.Left),
                        x.c.Button2 => pge.mouse_state.insert(.Middle),
                        x.c.Button3 => pge.mouse_state.insert(.Right),
                        x.c.Button4 => pge.mouse_wheel_delta_cache += MouseScrollAmount,
                        x.c.Button5 => pge.mouse_wheel_delta_cache -= MouseScrollAmount,
                        else => {},
                    },
                    x.c.ButtonRelease => switch (xev.xbutton.button) {
                        x.c.Button1 => pge.mouse_state.remove(.Left),
                        x.c.Button2 => pge.mouse_state.remove(.Middle),
                        x.c.Button3 => pge.mouse_state.remove(.Right),
                        else => {},
                    },
                    x.c.MotionNotify => {
                        pge.mouse_pos_cache = .{ .x = xev.xmotion.x, .y = xev.xmotion.y };
                    },
                    x.c.FocusIn => pge.has_input_focus = true,
                    x.c.FocusOut => pge.has_input_focus = false,
                    x.c.ClientMessage => pge.active.store(false, .Monotonic),
                    else => {},
                }
            }
        }
        x.errors.has() catch |e| {
            for (x.errors.list.slice()) |inst|
                std.log.err("X error: {any}", .{inst});
            x.errors.list.len = 0;
            return e;
        };
    }

    pub fn setDecalMode(self: *Self, mode: DecalMode) void {
        self.decal_mode = mode;
        g.blendFunc(
            switch (mode) {
                .Normal, .Additive, .Wireframe => .SrcAlpha,
                .Multiplicative => .DstColor,
                .Stencil => .Zero,
                .Illuminate => .OneMinusSrcAlpha,
                else => return,
            },
            switch (mode) {
                .Normal, .Multiplicative, .Wireframe => .OneMinusSrcAlpha,
                .Additive => .One,
                .Stencil, .Illuminate => .SrcAlpha,
                else => return,
            },
        );
    }

    pub fn prepareDrawing(self: *Self) void {
        g.enable(.Blend);
        self.setDecalMode(.Normal);
        self.n_quad.use();
        self.va_quad.bind();
    }

    pub fn drawLayerQuad(self: *Self, offset: VF2D, scale: VF2D, tint: Pixel) !void {
        self.vb_quad.bind(.Array);
        const verts = [4]LocVertex{
            .{
                .pos = .{ -1.0, -1.0, 1.0 },
                .tex = .{ .x = 0.0 * scale.x + offset.x, .y = 1.0 * scale.y + offset.y },
                .col = tint,
            },
            .{
                .pos = .{ 1.0, -1.0, 1.0 },
                .tex = .{ .x = 1.0 * scale.x + offset.x, .y = 1.0 * scale.y + offset.y },
                .col = tint,
            },
            .{
                .pos = .{ -1.0, 1.0, 1.0 },
                .tex = .{ .x = 0.0 * scale.x + offset.x, .y = 0.0 * scale.y + offset.y },
                .col = tint,
            },
            .{
                .pos = .{ 1.0, 1.0, 1.0 },
                .tex = .{ .x = 1.0 * scale.x + offset.x, .y = 0.0 * scale.y + offset.y },
                .col = tint,
            },
        };
        try ge.Buffer.data(.Array, LocVertex, &verts, .StreamDraw);
        g.drawArrays(.TriangleStrip, 0, 4);
    }
    /// `DecalStructure.Line` will draw nothing
    pub fn drawDecal(self: *Self, decal: DecalInstance) !void {
        self.setDecalMode(decal.mode);
        decal.decal.tex.inner.bind(.TwoD);
        self.vb_quad.bind(.Array);
        try ge.Buffer.data(.Array, LocVertex, decal.vertices, .StreamDraw);
        g.drawArrays(if (self.decal_mode == .Wireframe)
            .LineLoop
        else switch (decal.structure) {
            .Fan => .TriangleFan,
            .Strip => .TriangleStrip,
            .List => .Triangles,
            .Line => return,
        }, 0, @intCast(u32, decal.vertices.len));
    }

    pub fn displayFrame(self: *Self) void {
        self.x_state.display.swapBuffers(self.x_state.window);
    }

    pub fn setWindowTitle(self: *Self, title: [:0]const u8) void {
        self.x_state.display.storeName(self.x_state.window, title);
    }

    pub fn mapKey(val: x.c.KeySym) ?Key {
        const c = x.c;
        return switch (val) {
            c.XK_a => .A,
            c.XK_b => .B,
            c.XK_c => .C,
            c.XK_d => .D,
            c.XK_e => .E,
            c.XK_f => .F,
            c.XK_g => .G,
            c.XK_h => .H,
            c.XK_i => .I,
            c.XK_j => .J,
            c.XK_k => .K,
            c.XK_l => .L,
            c.XK_m => .M,
            c.XK_n => .N,
            c.XK_o => .O,
            c.XK_p => .P,
            c.XK_q => .Q,
            c.XK_r => .R,
            c.XK_s => .S,
            c.XK_t => .T,
            c.XK_u => .U,
            c.XK_v => .V,
            c.XK_w => .W,
            c.XK_x => .X,
            c.XK_y => .Y,
            c.XK_z => .Z,

            c.XK_F1 => .F1,
            c.XK_F2 => .F2,
            c.XK_F3 => .F3,
            c.XK_F4 => .F4,
            c.XK_F5 => .F5,
            c.XK_F6 => .F6,
            c.XK_F7 => .F7,
            c.XK_F8 => .F8,
            c.XK_F9 => .F9,
            c.XK_F10 => .F10,
            c.XK_F11 => .F11,
            c.XK_F12 => .F12,

            c.XK_Down => .Down,
            c.XK_Left => .Left,
            c.XK_Right => .Right,
            c.XK_Up => .Up,

            c.XK_Return, c.XK_Linefeed, c.XK_KP_Enter => .Enter,
            c.XK_BackSpace => .Back,
            c.XK_Escape => .Escape,
            c.XK_Pause => .Pause,
            c.XK_Scroll_Lock => .Scroll,
            c.XK_Tab => .Tab,
            c.XK_Delete => .Del,
            c.XK_Home => .Home,
            c.XK_End => .End,
            c.XK_Page_Up => .PgUp,
            c.XK_Page_Down => .PgDn,
            c.XK_Insert => .Ins,
            c.XK_Shift_L, c.XK_Shift_R => .Shift,
            c.XK_Control_L, c.XK_Control_R => .Ctrl,
            c.XK_space => .Space,
            c.XK_period => .Period,
            c.XK_Caps_Lock => .CapsLock,

            c.XK_0 => .K0,
            c.XK_1 => .K1,
            c.XK_2 => .K2,
            c.XK_3 => .K3,
            c.XK_4 => .K4,
            c.XK_5 => .K5,
            c.XK_6 => .K6,
            c.XK_7 => .K7,
            c.XK_8 => .K8,
            c.XK_9 => .K9,

            c.XK_KP_0 => .NP0,
            c.XK_KP_1 => .NP1,
            c.XK_KP_2 => .NP2,
            c.XK_KP_3 => .NP3,
            c.XK_KP_4 => .NP4,
            c.XK_KP_5 => .NP5,
            c.XK_KP_6 => .NP6,
            c.XK_KP_7 => .NP7,
            c.XK_KP_8 => .NP8,
            c.XK_KP_9 => .NP9,

            c.XK_KP_Multiply => .NpMul,
            c.XK_KP_Add => .NpAdd,
            c.XK_KP_Divide => .NpDiv,
            c.XK_KP_Subtract => .NpSub,
            c.XK_KP_Decimal => .NpDecimal,

            c.XK_semicolon => .OEM_1,
            c.XK_slash => .OEM_2,
            c.XK_asciitilde => .OEM_3,
            c.XK_bracketleft => .OEM_4,
            c.XK_backslash => .OEM_5,
            c.XK_bracketright => .OEM_6,
            c.XK_apostrophe => .OEM_7,
            c.XK_numbersign => .OEM_8,
            c.XK_equal => .EQUALS,
            c.XK_comma => .COMMA,
            c.XK_minus => .MINUS,

            else => null,
        };
    }
};
