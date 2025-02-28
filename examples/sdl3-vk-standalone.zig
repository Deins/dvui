const std = @import("std");
const dvui = @import("dvui");
const builtin = @import("builtin");

const vk = dvui.backend.vulkan;
const VkContext = @import("vk/vk_ctx.zig").VkContext;
const VkInstance = @import("vk/vk_instance.zig");
const Swapchain = @import("vk/swapchain.zig").Swapchain;
const vert_spv align(64) = @embedFile("vk/shaders/triangle.vert.spv").*;
const frag_spv align(64) = @embedFile("vk/shaders/triangle.frag.spv").*;

const Backend = dvui.backend;
const sdl = Backend.c;
// const sdl_vk = @cImport({
//     @cInclude("SDL3/SDL_vulkan.h");
// });
const sdl_vk = struct {
    pub extern fn SDL_Vulkan_GetVkGetInstanceProcAddr() callconv(.C) ?*anyopaque;
    pub extern fn SDL_Vulkan_GetInstanceExtensions(count: *c_uint) callconv(.C) [*]const [*:0]u8;
    pub extern fn SDL_Vulkan_CreateSurface(window: *sdl.SDL_Window, instance: *u32, vk_alloc: ?*vk.AllocationCallbacks, surface: *vk.SurfaceKHR) callconv(.C) bool;
    pub extern fn SDL_Vulkan_DestroySurface(instance: *anyopaque, surface: *anyopaque, vk_alloc: ?*vk.AllocationCallbacks) callconv(.C) void;
    pub extern fn SDL_Vulkan_GetPresentationSupport(instance: *u32, physicalDevice: *u32, queueFamilyIdx: u32) callconv(.C) bool;
};

var gpa_instance = std.heap.GeneralPurposeAllocator(.{}){};
const gpa = gpa_instance.allocator();

var scale_val: f32 = 1.0;
const show_demo = true;
var show_dialog_outside_frame: bool = false;
const vulkan = true;

const init_w: f32 = 800;
const init_h: f32 = 600;

const App = struct {
    backend: Backend,
    win: dvui.Window,

    pub fn deinit(self: *@This()) void {
        self.win.deinit();
        self.backend.deinit();
    }
};
pub var g_app: App = undefined;

pub fn main() !void {
    const alloc = gpa_instance.allocator();
    defer if (gpa_instance.deinit() != .ok) @panic("memory leak!");
    if (@import("builtin").os.tag == .windows) { // optional
        // on windows graphical apps have no console, so output goes to nowhere - attach it manually. related: https://github.com/ziglang/zig/issues/4196
        _ = winapi.AttachConsole(0xFFFFFFFF);
    }
    std.log.info("SDL version: {}", .{Backend.getSDLVersion()});

    dvui.Examples.show_demo_window = true;

    var sdl_win: *sdl.SDL_Window = undefined;
    {
        if (sdl.SDL_Init(sdl.SDL_INIT_VIDEO) != true) {
            dvui.log.err("SDL: Couldn't initialize SDL: {s}", .{sdl.SDL_GetError()});
            return error.BackendError;
        }

        var flags = sdl.SDL_WINDOW_HIGH_PIXEL_DENSITY | sdl.SDL_WINDOW_RESIZABLE;
        if (vulkan) flags |= sdl.SDL_WINDOW_VULKAN;
        // flags |= sdl.SDL_WINDOW_INPUT_FOCUS;
        // flags |= sdl.SDL_WINDOW_ALWAYS_ON_TOP;
        // flags |= sdl.SDL_WINDOW_TRANSPARENT;
        sdl_win = sdl.SDL_CreateWindow("APP", @as(c_int, @intFromFloat(init_w)), @as(c_int, @intFromFloat(init_h)), flags) orelse {
            dvui.log.err("SDL: Failed to open window: {s}", .{sdl.SDL_GetError()});
            return error.BackendError;
        };
        // Limit min dimensions, otherwise we will crash if window gets too small.
        // Otherwise we have to handle swapchain creation failure and skipping rendering when swapchain doesn't exist or something like that.
        if (!sdl.SDL_SetWindowMinimumSize(sdl_win, 64, 64)) return errorSDL("Can't enforce min window dimenstions");

        {
            const n: usize = @intCast(sdl.SDL_GetNumRenderDrivers());
            for (0..n) |i| std.debug.print("renderer {}: {s}\n", .{ i, sdl.SDL_GetRenderDriver(@intCast(i)) });
        }
    }
    defer g_app.deinit();

    // vk
    var n_ext: u32 = 0;
    const sdl_platform_extensions = sdl_vk.SDL_Vulkan_GetInstanceExtensions(&n_ext);
    //for (0..n_ext) |i| std.debug.print("sdl req extension: {s}\n", .{sdl_platform_extensions[i]});
    const getProcAddr = sdl_vk.SDL_Vulkan_GetVkGetInstanceProcAddr() orelse {
        dvui.log.err("SDL: Failed to get vulkan VkGetInstanceProcAddr: {s}", .{sdl.SDL_GetError()});
        return error.BackendError;
    };
    const vk_instance = try VkInstance.init(alloc, .{
        .app_name = "MyApp",
        .instance_extensions = @ptrCast(sdl_platform_extensions[0..n_ext]),
        .vkGetInstanceProcAddr = @ptrCast(getProcAddr),
    });
    defer VkInstance.deinit(vk_instance);
    var vk_surface: vk.SurfaceKHR = vk.SurfaceKHR.null_handle;
    if (!sdl_vk.SDL_Vulkan_CreateSurface(@ptrCast(sdl_win), @ptrFromInt(@intFromEnum(vk_instance.handle)), null, @ptrCast(&vk_surface))) return errorSDL("Failed to create vulkan surface");
    defer sdl_vk.SDL_Vulkan_DestroySurface(@ptrFromInt(@intFromEnum(vk_instance.handle)), @ptrFromInt(@intFromEnum(vk_surface)), null);

    var ctx = try VkContext.init(alloc, .{
        .instance = vk_instance,
        .surface = vk_surface,
    });
    defer ctx.deinit();
    // surface must be destroyed first to avoid validatioin errors
    std.debug.assert(sdl_vk.SDL_Vulkan_GetPresentationSupport(@ptrFromInt(@intFromEnum(vk_instance.handle)), @ptrFromInt(@intFromEnum(ctx.pdev)), ctx.main_queue_idx));

    var swapchain = Swapchain.init(&ctx, alloc, vk.Extent2D{ .width = init_w, .height = init_h }) catch |err| {
        @breakpoint();
        std.debug.panic("Can't create swapchain: {}", .{err});
    };
    defer swapchain.deinit();

    const pipeline_layout = try ctx.dev.createPipelineLayout(&.{
        .flags = .{},
        .set_layout_count = 0,
        .p_set_layouts = undefined,
        .push_constant_range_count = 0,
        .p_push_constant_ranges = undefined,
    }, null);
    defer ctx.dev.destroyPipelineLayout(pipeline_layout, null);

    const render_pass = try createRenderPass(&ctx, swapchain);
    defer ctx.dev.destroyRenderPass(render_pass, null);

    const pipeline = try createPipeline(&ctx, pipeline_layout, render_pass);
    defer ctx.dev.destroyPipeline(pipeline, null);

    var framebuffers = try createFramebuffers(&ctx, alloc, render_pass, swapchain);
    defer destroyFramebuffers(&ctx, alloc, framebuffers);

    const pool = try ctx.dev.createCommandPool(&.{
        .queue_family_index = ctx.main_queue_idx,
    }, null);
    defer ctx.dev.destroyCommandPool(pool, null);

    const buffer = try ctx.dev.createBuffer(&.{
        .size = @sizeOf(@TypeOf(vertices)),
        .usage = .{ .transfer_dst_bit = true, .vertex_buffer_bit = true },
        .sharing_mode = .exclusive,
    }, null);
    defer ctx.dev.destroyBuffer(buffer, null);
    const mem_reqs = ctx.dev.getBufferMemoryRequirements(buffer);
    const memory = try ctx.allocate(mem_reqs, .{ .device_local_bit = true });
    defer ctx.dev.freeMemory(memory, null);
    try ctx.dev.bindBufferMemory(buffer, memory, 0);

    try uploadVertices(&ctx, pool, buffer);

    var cmdbufs = try createCommandBuffers(
        &ctx,
        pool,
        alloc,
        buffer,
        swapchain.extent,
        render_pass,
        pipeline,
        framebuffers,
    );
    defer destroyCommandBuffers(&ctx, pool, alloc, cmdbufs);

    var backend = try Backend.init(sdl_win);
    // backend.we_own_window = true;
    // g_app = .{
    //     .backend = backend,
    //     .win = try dvui.Window.init(@src(), gpa, backend.backend(), .{}),
    // };

    backend.initial_scale = sdl.SDL_GetDisplayContentScale(sdl.SDL_GetDisplayForWindow(sdl_win));
    dvui.log.info("SDL3 backend scale {d}", .{backend.initial_scale});

    var event: sdl.SDL_Event = undefined;
    main_loop: while (true) {
        while (sdl.SDL_PollEvent(&event)) {
            if (event.type == sdl.SDL_EVENT_QUIT) break :main_loop;

            const cmdbuf = cmdbufs[swapchain.image_index];

            const state = swapchain.present(cmdbuf) catch |err| switch (err) {
                error.OutOfDateKHR => Swapchain.PresentState.suboptimal,
                else => |narrow| return narrow,
            };

            var sdl_w: i32 = 0;
            var sdl_h: i32 = 0;
            if (!sdl.SDL_GetWindowSize(sdl_win, &sdl_w, &sdl_h)) return errorSDL("Can't get window size");
            const extent: vk.Extent2D = .{ .width = @intCast(sdl_w), .height = @intCast(sdl_h) };
            if (state == .suboptimal or extent.width != swapchain.extent.width or extent.height != swapchain.extent.height) {
                std.log.debug("resize framebuffers: {} -> {}", .{ swapchain.extent, extent });
                swapchain.recreate(extent) catch |err| {
                    std.log.err("Resize: Failed to recreate swapchain: {}", .{err});
                };

                destroyFramebuffers(&ctx, alloc, framebuffers);
                framebuffers = createFramebuffers(&ctx, alloc, render_pass, swapchain) catch |err| {
                    std.log.err("Resize: Failed to recreate framebuffer: {}", .{err});
                    return err;
                };

                destroyCommandBuffers(&ctx, pool, alloc, cmdbufs);
                cmdbufs = createCommandBuffers(
                    &ctx,
                    pool,
                    alloc,
                    buffer,
                    swapchain.extent,
                    render_pass,
                    pipeline,
                    framebuffers,
                ) catch |err| {
                    std.log.err("Resize: Failed to recreate cmd buffers: {}", .{err});
                    return err;
                };
            }
        }
    }

    // while (true) {
    //     const win = &g_app.win;
    //     // beginWait coordinates with waitTime below to run frames only when needed
    //     const nstime = win.beginWait(backend.hasEvent());

    //     // marks the beginning of a frame for dvui, can call dvui functions after this
    //     try win.begin(nstime);

    //     // send all SDL events to dvui for processing
    //     const quit = try backend.addAllEvents(win);
    //     if (quit) break;

    //     // if dvui widgets might not cover the whole window, then need to clear
    //     // the previous frame's render
    //     _ = Backend.c.SDL_SetRenderDrawColor(backend.renderer, 55, 0, 0, 55);
    //     _ = Backend.c.SDL_RenderClear(backend.renderer);

    //     // The demos we pass in here show up under "Platform-specific demos"
    //     try gui_frame();

    //     // marks end of dvui frame, don't call dvui functions after this
    //     // - sends all dvui stuff to backend for rendering, must be called before renderPresent()
    //     const end_micros = try win.end(.{});
    //     _ = end_micros; // autofix

    //     // cursor management
    //     backend.setCursor(win.cursorRequested());
    //     backend.textInputRect(win.textInputRequested());

    //     // render frame to OS
    //     backend.renderPresent();

    //     // waitTime and beginWait combine to achieve variable framerates
    //     // const wait_event_micros = win.waitTime(end_micros, null);
    //     // backend.waitEventTimeout(wait_event_micros);

    //     // Example of how to show a dialog from another thread (outside of win.begin/win.end)
    //     // if (show_dialog_outside_frame) {
    //     //     show_dialog_outside_frame = false;
    //     //     try dvui.dialog(@src(), .{ .window = &win, .modal = false, .title = "Dialog from Outside", .message = "This is a non modal dialog that was created outside win.begin()/win.end(), usually from another thread." });
    //     // }
    // }
}

// both dvui and SDL drawing
fn gui_frame() !void {
    const backend = g_app.backend;
    _ = backend; // autofix

    {
        var m = try dvui.menu(@src(), .horizontal, .{ .background = true, .expand = .horizontal });
        defer m.deinit();

        if (try dvui.menuItemLabel(@src(), "File", .{ .submenu = true }, .{ .expand = .none })) |r| {
            var fw = try dvui.floatingMenu(@src(), dvui.Rect.fromPoint(dvui.Point{ .x = r.x, .y = r.y + r.h }), .{});
            defer fw.deinit();

            if (try dvui.menuItemLabel(@src(), "Close Menu", .{}, .{}) != null) {
                m.close();
            }
        }

        if (try dvui.menuItemLabel(@src(), "Edit", .{ .submenu = true }, .{ .expand = .none })) |r| {
            var fw = try dvui.floatingMenu(@src(), dvui.Rect.fromPoint(dvui.Point{ .x = r.x, .y = r.y + r.h }), .{});
            defer fw.deinit();
            _ = try dvui.menuItemLabel(@src(), "Dummy", .{}, .{ .expand = .horizontal });
            _ = try dvui.menuItemLabel(@src(), "Dummy Long", .{}, .{ .expand = .horizontal });
            _ = try dvui.menuItemLabel(@src(), "Dummy Super Long", .{}, .{ .expand = .horizontal });
        }
    }
    // look at demo() for examples of dvui widgets, shows in a floating window
    try dvui.Examples.demo();
}

fn createRenderPass(gc: *VkContext, swapchain: Swapchain) !vk.RenderPass {
    const color_attachment = vk.AttachmentDescription{
        .format = swapchain.surface_format.format,
        .samples = .{ .@"1_bit" = true },
        .load_op = .clear,
        .store_op = .store,
        .stencil_load_op = .dont_care,
        .stencil_store_op = .dont_care,
        .initial_layout = .undefined,
        .final_layout = .present_src_khr,
    };

    const color_attachment_ref = vk.AttachmentReference{
        .attachment = 0,
        .layout = .color_attachment_optimal,
    };

    const subpass = vk.SubpassDescription{
        .pipeline_bind_point = .graphics,
        .color_attachment_count = 1,
        .p_color_attachments = @ptrCast(&color_attachment_ref),
    };

    return try gc.dev.createRenderPass(&.{
        .attachment_count = 1,
        .p_attachments = @ptrCast(&color_attachment),
        .subpass_count = 1,
        .p_subpasses = @ptrCast(&subpass),
    }, null);
}

fn createPipeline(
    gc: *VkContext,
    layout: vk.PipelineLayout,
    render_pass: vk.RenderPass,
) !vk.Pipeline {
    const vert = try gc.dev.createShaderModule(&.{
        .code_size = vert_spv.len,
        .p_code = @ptrCast(&vert_spv),
    }, null);
    defer gc.dev.destroyShaderModule(vert, null);

    const frag = try gc.dev.createShaderModule(&.{
        .code_size = frag_spv.len,
        .p_code = @ptrCast(&frag_spv),
    }, null);
    defer gc.dev.destroyShaderModule(frag, null);

    const pssci = [_]vk.PipelineShaderStageCreateInfo{
        .{
            .stage = .{ .vertex_bit = true },
            .module = vert,
            .p_name = "main",
        },
        .{
            .stage = .{ .fragment_bit = true },
            .module = frag,
            .p_name = "main",
        },
    };

    const pvisci = vk.PipelineVertexInputStateCreateInfo{
        .vertex_binding_description_count = 1,
        .p_vertex_binding_descriptions = @ptrCast(&Vertex.binding_description),
        .vertex_attribute_description_count = Vertex.attribute_description.len,
        .p_vertex_attribute_descriptions = &Vertex.attribute_description,
    };

    const piasci = vk.PipelineInputAssemblyStateCreateInfo{
        .topology = .triangle_list,
        .primitive_restart_enable = vk.FALSE,
    };

    const pvsci = vk.PipelineViewportStateCreateInfo{
        .viewport_count = 1,
        .p_viewports = undefined, // set in createCommandBuffers with cmdSetViewport
        .scissor_count = 1,
        .p_scissors = undefined, // set in createCommandBuffers with cmdSetScissor
    };

    const prsci = vk.PipelineRasterizationStateCreateInfo{
        .depth_clamp_enable = vk.FALSE,
        .rasterizer_discard_enable = vk.FALSE,
        .polygon_mode = .fill,
        .cull_mode = .{ .back_bit = true },
        .front_face = .clockwise,
        .depth_bias_enable = vk.FALSE,
        .depth_bias_constant_factor = 0,
        .depth_bias_clamp = 0,
        .depth_bias_slope_factor = 0,
        .line_width = 1,
    };

    const pmsci = vk.PipelineMultisampleStateCreateInfo{
        .rasterization_samples = .{ .@"1_bit" = true },
        .sample_shading_enable = vk.FALSE,
        .min_sample_shading = 1,
        .alpha_to_coverage_enable = vk.FALSE,
        .alpha_to_one_enable = vk.FALSE,
    };

    const pcbas = vk.PipelineColorBlendAttachmentState{
        .blend_enable = vk.FALSE,
        .src_color_blend_factor = .one,
        .dst_color_blend_factor = .zero,
        .color_blend_op = .add,
        .src_alpha_blend_factor = .one,
        .dst_alpha_blend_factor = .zero,
        .alpha_blend_op = .add,
        .color_write_mask = .{ .r_bit = true, .g_bit = true, .b_bit = true, .a_bit = true },
    };

    const pcbsci = vk.PipelineColorBlendStateCreateInfo{
        .logic_op_enable = vk.FALSE,
        .logic_op = .copy,
        .attachment_count = 1,
        .p_attachments = @ptrCast(&pcbas),
        .blend_constants = [_]f32{ 0, 0, 0, 0 },
    };

    const dynstate = [_]vk.DynamicState{ .viewport, .scissor };
    const pdsci = vk.PipelineDynamicStateCreateInfo{
        .flags = .{},
        .dynamic_state_count = dynstate.len,
        .p_dynamic_states = &dynstate,
    };

    const gpci = vk.GraphicsPipelineCreateInfo{
        .flags = .{},
        .stage_count = 2,
        .p_stages = &pssci,
        .p_vertex_input_state = &pvisci,
        .p_input_assembly_state = &piasci,
        .p_tessellation_state = null,
        .p_viewport_state = &pvsci,
        .p_rasterization_state = &prsci,
        .p_multisample_state = &pmsci,
        .p_depth_stencil_state = null,
        .p_color_blend_state = &pcbsci,
        .p_dynamic_state = &pdsci,
        .layout = layout,
        .render_pass = render_pass,
        .subpass = 0,
        .base_pipeline_handle = .null_handle,
        .base_pipeline_index = -1,
    };

    var pipeline: vk.Pipeline = undefined;
    _ = try gc.dev.createGraphicsPipelines(
        .null_handle,
        1,
        @ptrCast(&gpci),
        null,
        @ptrCast(&pipeline),
    );
    return pipeline;
}

fn createFramebuffers(gc: *const VkContext, allocator: std.mem.Allocator, render_pass: vk.RenderPass, swapchain: Swapchain) ![]vk.Framebuffer {
    const framebuffers = try allocator.alloc(vk.Framebuffer, swapchain.swap_images.len);
    errdefer allocator.free(framebuffers);

    var i: usize = 0;
    errdefer for (framebuffers[0..i]) |fb| gc.dev.destroyFramebuffer(fb, null);

    for (framebuffers) |*fb| {
        fb.* = try gc.dev.createFramebuffer(&.{
            .render_pass = render_pass,
            .attachment_count = 1,
            .p_attachments = @ptrCast(&swapchain.swap_images[i].view),
            .width = swapchain.extent.width,
            .height = swapchain.extent.height,
            .layers = 1,
        }, null);
        i += 1;
    }

    return framebuffers;
}

fn destroyFramebuffers(gc: *const VkContext, allocator: std.mem.Allocator, framebuffers: []const vk.Framebuffer) void {
    for (framebuffers) |fb| gc.dev.destroyFramebuffer(fb, null);
    allocator.free(framebuffers);
}

const Vertex = struct {
    const binding_description = vk.VertexInputBindingDescription{
        .binding = 0,
        .stride = @sizeOf(Vertex),
        .input_rate = .vertex,
    };

    const attribute_description = [_]vk.VertexInputAttributeDescription{
        .{
            .binding = 0,
            .location = 0,
            .format = .r32g32_sfloat,
            .offset = @offsetOf(Vertex, "pos"),
        },
        .{
            .binding = 0,
            .location = 1,
            .format = .r32g32b32_sfloat,
            .offset = @offsetOf(Vertex, "color"),
        },
    };

    pos: [2]f32,
    color: [3]f32,
};

const vertices = [_]Vertex{
    .{ .pos = .{ 0, -0.5 }, .color = .{ 1, 0, 0 } },
    .{ .pos = .{ 0.5, 0.5 }, .color = .{ 0, 1, 0 } },
    .{ .pos = .{ -0.5, 0.5 }, .color = .{ 0, 0, 1 } },
};

fn uploadVertices(gc: *const VkContext, pool: vk.CommandPool, buffer: vk.Buffer) !void {
    const staging_buffer = try gc.dev.createBuffer(&.{
        .size = @sizeOf(@TypeOf(vertices)),
        .usage = .{ .transfer_src_bit = true },
        .sharing_mode = .exclusive,
    }, null);
    defer gc.dev.destroyBuffer(staging_buffer, null);
    const mem_reqs = gc.dev.getBufferMemoryRequirements(staging_buffer);
    const staging_memory = try gc.allocate(mem_reqs, .{ .host_visible_bit = true, .host_coherent_bit = true });
    defer gc.dev.freeMemory(staging_memory, null);
    try gc.dev.bindBufferMemory(staging_buffer, staging_memory, 0);

    {
        const data = try gc.dev.mapMemory(staging_memory, 0, vk.WHOLE_SIZE, .{});
        defer gc.dev.unmapMemory(staging_memory);

        const gpu_vertices: [*]Vertex = @ptrCast(@alignCast(data));
        @memcpy(gpu_vertices, vertices[0..]);
    }

    try copyBuffer(gc, pool, buffer, staging_buffer, @sizeOf(@TypeOf(vertices)));
}

fn copyBuffer(gc: *const VkContext, pool: vk.CommandPool, dst: vk.Buffer, src: vk.Buffer, size: vk.DeviceSize) !void {
    var cmdbuf_handle: vk.CommandBuffer = undefined;
    try gc.dev.allocateCommandBuffers(&.{
        .command_pool = pool,
        .level = .primary,
        .command_buffer_count = 1,
    }, @ptrCast(&cmdbuf_handle));
    defer gc.dev.freeCommandBuffers(pool, 1, @ptrCast(&cmdbuf_handle));

    const cmdbuf = VkContext.CommandBuffer.init(cmdbuf_handle, gc.dev.wrapper);

    try cmdbuf.beginCommandBuffer(&.{
        .flags = .{ .one_time_submit_bit = true },
    });

    const region = vk.BufferCopy{
        .src_offset = 0,
        .dst_offset = 0,
        .size = size,
    };
    cmdbuf.copyBuffer(src, dst, 1, @ptrCast(&region));

    try cmdbuf.endCommandBuffer();

    const si = vk.SubmitInfo{
        .command_buffer_count = 1,
        .p_command_buffers = (&cmdbuf.handle)[0..1],
        .p_wait_dst_stage_mask = undefined,
    };
    try gc.dev.queueSubmit(gc.main_queue, 1, @ptrCast(&si), .null_handle);
    try gc.dev.queueWaitIdle(gc.main_queue);
}

fn createCommandBuffers(
    gc: *const VkContext,
    pool: vk.CommandPool,
    allocator: std.mem.Allocator,
    buffer: vk.Buffer,
    extent: vk.Extent2D,
    render_pass: vk.RenderPass,
    pipeline: vk.Pipeline,
    framebuffers: []vk.Framebuffer,
) ![]vk.CommandBuffer {
    const cmdbufs = try allocator.alloc(vk.CommandBuffer, framebuffers.len);
    errdefer allocator.free(cmdbufs);

    try gc.dev.allocateCommandBuffers(&.{
        .command_pool = pool,
        .level = .primary,
        .command_buffer_count = @intCast(cmdbufs.len),
    }, cmdbufs.ptr);
    errdefer gc.dev.freeCommandBuffers(pool, @intCast(cmdbufs.len), cmdbufs.ptr);

    const clear = vk.ClearValue{
        .color = .{ .float_32 = .{ 0, 0, 0, 1 } },
    };

    const viewport = vk.Viewport{
        .x = 0,
        .y = 0,
        .width = @floatFromInt(extent.width),
        .height = @floatFromInt(extent.height),
        .min_depth = 0,
        .max_depth = 1,
    };

    const scissor = vk.Rect2D{
        .offset = .{ .x = 0, .y = 0 },
        .extent = extent,
    };

    for (cmdbufs, framebuffers) |cmdbuf, framebuffer| {
        try gc.dev.beginCommandBuffer(cmdbuf, &.{});

        gc.dev.cmdSetViewport(cmdbuf, 0, 1, @ptrCast(&viewport));
        gc.dev.cmdSetScissor(cmdbuf, 0, 1, @ptrCast(&scissor));

        // This needs to be a separate definition - see https://github.com/ziglang/zig/issues/7627.
        const render_area = vk.Rect2D{
            .offset = .{ .x = 0, .y = 0 },
            .extent = extent,
        };

        gc.dev.cmdBeginRenderPass(cmdbuf, &.{
            .render_pass = render_pass,
            .framebuffer = framebuffer,
            .render_area = render_area,
            .clear_value_count = 1,
            .p_clear_values = @ptrCast(&clear),
        }, .@"inline");

        gc.dev.cmdBindPipeline(cmdbuf, .graphics, pipeline);
        const offset = [_]vk.DeviceSize{0};
        gc.dev.cmdBindVertexBuffers(cmdbuf, 0, 1, @ptrCast(&buffer), &offset);
        gc.dev.cmdDraw(cmdbuf, vertices.len, 1, 0, 0);

        gc.dev.cmdEndRenderPass(cmdbuf);
        try gc.dev.endCommandBuffer(cmdbuf);
    }

    return cmdbufs;
}

fn destroyCommandBuffers(gc: *const VkContext, pool: vk.CommandPool, allocator: std.mem.Allocator, cmdbufs: []vk.CommandBuffer) void {
    gc.dev.freeCommandBuffers(pool, @truncate(cmdbufs.len), cmdbufs.ptr);
    allocator.free(cmdbufs);
}

pub const std_options: std.Options = .{
    .log_level = .debug,
};

pub fn errorSDL(err: []const u8) !void {
    std.log.err("SDL: {s}: {s}", .{ err, sdl.SDL_GetError() });
    @breakpoint();
    return error.SDL;
}

test {
    std.testing.refAllDeclsRecursive(@This());
}

test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}

// Optional: windows os only
const winapi = if (builtin.os.tag == .windows) struct {
    extern "kernel32" fn AttachConsole(dwProcessId: std.os.windows.DWORD) std.os.windows.BOOL;
} else struct {};
