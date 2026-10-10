// SPDX-License-Identifier: GPL-2.0-or-later
//! Vulkan 1.3 device, swapchain, memory, frames, bindless textures and pipelines.
//! Everything is loaded through SDL's vkGetInstanceProcAddr; nothing links libvulkan.
const std = @import("std");
const c = @import("c.zig").c;
const common = @import("common.zig");

pub const frames_in_flight = 2;
pub const max_textures = 16384;
pub const scene_format = c.VK_FORMAT_R8G8B8A8_UNORM;

const Global = struct {
    CreateInstance: c.PFN_vkCreateInstance = null,
    EnumerateInstanceExtensionProperties: c.PFN_vkEnumerateInstanceExtensionProperties = null,
    EnumerateInstanceLayerProperties: c.PFN_vkEnumerateInstanceLayerProperties = null,
    EnumerateInstanceVersion: c.PFN_vkEnumerateInstanceVersion = null,
};

const Instance = struct {
    DestroyInstance: c.PFN_vkDestroyInstance = null,
    EnumeratePhysicalDevices: c.PFN_vkEnumeratePhysicalDevices = null,
    GetPhysicalDeviceProperties: c.PFN_vkGetPhysicalDeviceProperties = null,
    GetPhysicalDeviceProperties2: c.PFN_vkGetPhysicalDeviceProperties2 = null,
    GetPhysicalDeviceFeatures2: c.PFN_vkGetPhysicalDeviceFeatures2 = null,
    GetPhysicalDeviceQueueFamilyProperties: c.PFN_vkGetPhysicalDeviceQueueFamilyProperties = null,
    GetPhysicalDeviceMemoryProperties: c.PFN_vkGetPhysicalDeviceMemoryProperties = null,
    GetPhysicalDeviceFormatProperties: c.PFN_vkGetPhysicalDeviceFormatProperties = null,
    EnumerateDeviceExtensionProperties: c.PFN_vkEnumerateDeviceExtensionProperties = null,
    GetPhysicalDeviceSurfaceSupportKHR: c.PFN_vkGetPhysicalDeviceSurfaceSupportKHR = null,
    GetPhysicalDeviceSurfaceCapabilitiesKHR: c.PFN_vkGetPhysicalDeviceSurfaceCapabilitiesKHR = null,
    GetPhysicalDeviceSurfaceFormatsKHR: c.PFN_vkGetPhysicalDeviceSurfaceFormatsKHR = null,
    GetPhysicalDeviceSurfacePresentModesKHR: c.PFN_vkGetPhysicalDeviceSurfacePresentModesKHR = null,
    DestroySurfaceKHR: c.PFN_vkDestroySurfaceKHR = null,
    CreateDevice: c.PFN_vkCreateDevice = null,
    GetDeviceProcAddr: c.PFN_vkGetDeviceProcAddr = null,
};

const Device = struct {
    DestroyDevice: c.PFN_vkDestroyDevice = null,
    GetDeviceQueue: c.PFN_vkGetDeviceQueue = null,
    DeviceWaitIdle: c.PFN_vkDeviceWaitIdle = null,
    CreateSwapchainKHR: c.PFN_vkCreateSwapchainKHR = null,
    DestroySwapchainKHR: c.PFN_vkDestroySwapchainKHR = null,
    GetSwapchainImagesKHR: c.PFN_vkGetSwapchainImagesKHR = null,
    AcquireNextImageKHR: c.PFN_vkAcquireNextImageKHR = null,
    QueuePresentKHR: c.PFN_vkQueuePresentKHR = null,
    QueueSubmit2: c.PFN_vkQueueSubmit2 = null,
    CreateCommandPool: c.PFN_vkCreateCommandPool = null,
    DestroyCommandPool: c.PFN_vkDestroyCommandPool = null,
    ResetCommandPool: c.PFN_vkResetCommandPool = null,
    AllocateCommandBuffers: c.PFN_vkAllocateCommandBuffers = null,
    BeginCommandBuffer: c.PFN_vkBeginCommandBuffer = null,
    EndCommandBuffer: c.PFN_vkEndCommandBuffer = null,
    CreateSemaphore: c.PFN_vkCreateSemaphore = null,
    DestroySemaphore: c.PFN_vkDestroySemaphore = null,
    WaitSemaphores: c.PFN_vkWaitSemaphores = null,
    AllocateMemory: c.PFN_vkAllocateMemory = null,
    FreeMemory: c.PFN_vkFreeMemory = null,
    MapMemory: c.PFN_vkMapMemory = null,
    CreateBuffer: c.PFN_vkCreateBuffer = null,
    DestroyBuffer: c.PFN_vkDestroyBuffer = null,
    GetBufferMemoryRequirements: c.PFN_vkGetBufferMemoryRequirements = null,
    BindBufferMemory: c.PFN_vkBindBufferMemory = null,
    GetBufferDeviceAddress: c.PFN_vkGetBufferDeviceAddress = null,
    CreateImage: c.PFN_vkCreateImage = null,
    DestroyImage: c.PFN_vkDestroyImage = null,
    GetImageMemoryRequirements: c.PFN_vkGetImageMemoryRequirements = null,
    BindImageMemory: c.PFN_vkBindImageMemory = null,
    CreateImageView: c.PFN_vkCreateImageView = null,
    DestroyImageView: c.PFN_vkDestroyImageView = null,
    CreateSampler: c.PFN_vkCreateSampler = null,
    DestroySampler: c.PFN_vkDestroySampler = null,
    CreateDescriptorSetLayout: c.PFN_vkCreateDescriptorSetLayout = null,
    DestroyDescriptorSetLayout: c.PFN_vkDestroyDescriptorSetLayout = null,
    CreateDescriptorPool: c.PFN_vkCreateDescriptorPool = null,
    DestroyDescriptorPool: c.PFN_vkDestroyDescriptorPool = null,
    AllocateDescriptorSets: c.PFN_vkAllocateDescriptorSets = null,
    UpdateDescriptorSets: c.PFN_vkUpdateDescriptorSets = null,
    CreatePipelineLayout: c.PFN_vkCreatePipelineLayout = null,
    DestroyPipelineLayout: c.PFN_vkDestroyPipelineLayout = null,
    CreateShaderModule: c.PFN_vkCreateShaderModule = null,
    DestroyShaderModule: c.PFN_vkDestroyShaderModule = null,
    CreateGraphicsPipelines: c.PFN_vkCreateGraphicsPipelines = null,
    DestroyPipeline: c.PFN_vkDestroyPipeline = null,
    CmdPipelineBarrier2: c.PFN_vkCmdPipelineBarrier2 = null,
    CmdCopyBufferToImage: c.PFN_vkCmdCopyBufferToImage = null,
    CmdCopyImageToBuffer: c.PFN_vkCmdCopyImageToBuffer = null,
    CmdCopyBuffer: c.PFN_vkCmdCopyBuffer = null,
    CmdCopyImage: c.PFN_vkCmdCopyImage = null,
    CmdBeginRendering: c.PFN_vkCmdBeginRendering = null,
    CmdEndRendering: c.PFN_vkCmdEndRendering = null,
    CmdSetViewport: c.PFN_vkCmdSetViewport = null,
    CmdSetScissor: c.PFN_vkCmdSetScissor = null,
    CmdSetCullMode: c.PFN_vkCmdSetCullMode = null,
    CmdSetFrontFace: c.PFN_vkCmdSetFrontFace = null,
    CmdSetDepthTestEnable: c.PFN_vkCmdSetDepthTestEnable = null,
    CmdSetDepthWriteEnable: c.PFN_vkCmdSetDepthWriteEnable = null,
    CmdSetDepthCompareOp: c.PFN_vkCmdSetDepthCompareOp = null,
    CmdSetDepthBiasEnable: c.PFN_vkCmdSetDepthBiasEnable = null,
    CmdSetDepthBias: c.PFN_vkCmdSetDepthBias = null,
    CmdBindPipeline: c.PFN_vkCmdBindPipeline = null,
    CmdBindDescriptorSets: c.PFN_vkCmdBindDescriptorSets = null,
    CmdPushConstants: c.PFN_vkCmdPushConstants = null,
    CmdDraw: c.PFN_vkCmdDraw = null,
    CmdDispatch: c.PFN_vkCmdDispatch = null,
    CreateComputePipelines: c.PFN_vkCreateComputePipelines = null,
    CmdFillBuffer: c.PFN_vkCmdFillBuffer = null,
    CmdClearColorImage: c.PFN_vkCmdClearColorImage = null,
    CmdClearAttachments: c.PFN_vkCmdClearAttachments = null,
    // VK_KHR_acceleration_structure (null without the ray tracing tier).
    CreateAccelerationStructureKHR: c.PFN_vkCreateAccelerationStructureKHR = null,
    DestroyAccelerationStructureKHR: c.PFN_vkDestroyAccelerationStructureKHR = null,
    GetAccelerationStructureBuildSizesKHR: c.PFN_vkGetAccelerationStructureBuildSizesKHR = null,
    CmdBuildAccelerationStructuresKHR: c.PFN_vkCmdBuildAccelerationStructuresKHR = null,
    GetAccelerationStructureDeviceAddressKHR: c.PFN_vkGetAccelerationStructureDeviceAddressKHR = null,
};

/// The ray tracing tier is active: acceleration structures and ray queries are enabled.
pub var ray_tracing = false;
pub var as_scratch_alignment: u64 = 256;

/// Extra usage for buffers that feed acceleration-structure builds.
pub fn rtInputUsage() c.VkBufferUsageFlags {
    return if (ray_tracing) c.VK_BUFFER_USAGE_ACCELERATION_STRUCTURE_BUILD_INPUT_READ_ONLY_BIT_KHR else 0;
}

pub var g: Global = .{};
pub var i: Instance = .{};
pub var d: Device = .{};

fn loadTable(comptime T: type, table: *T, loader: anytype, handle: anytype) void {
    inline for (std.meta.fields(T)) |field| {
        @field(table, field.name) = @ptrCast(loader(handle, "vk" ++ field.name));
    }
}

pub fn check(result: c.VkResult, comptime what: []const u8) !void {
    if (result == c.VK_SUCCESS) return;
    common.warn("Vulkan {s} failed: {d}\n", .{ what, result });
    return error.Vulkan;
}

/// Errors after initialization lose the frame; the engine drops to the console.
pub fn must(result: c.VkResult, comptime what: []const u8) void {
    if (result != c.VK_SUCCESS) common.fail(c.ERR_FATAL, "Vulkan {s} failed: {d}", .{ what, result });
}

pub const Capabilities = struct {
    ray_query: bool = false,
    acceleration_structure: bool = false,
    ray_tracing_pipeline: bool = false,
    shader_object: bool = false,
    fragment_shading_rate: bool = false,
    descriptor_heap: bool = false,
};

pub const State = struct {
    instance: c.VkInstance = null,
    surface: c.VkSurfaceKHR = null,
    physical: c.VkPhysicalDevice = null,
    device: c.VkDevice = null,
    queue: c.VkQueue = null,
    family: u32 = 0,
    properties: c.VkPhysicalDeviceProperties = undefined,
    memory: c.VkPhysicalDeviceMemoryProperties = undefined,
    driver: c.VkPhysicalDeviceDriverProperties = undefined,
    capabilities: Capabilities = .{},
    extensions: [24][*:0]const u8 = undefined,
    extension_count: u32 = 0,
    depth_format: c.VkFormat = c.VK_FORMAT_D32_SFLOAT,
};
pub var s: State = .{};

const required_device_extensions = [_][*:0]const u8{c.VK_KHR_SWAPCHAIN_EXTENSION_NAME};

fn getInstanceProcAddr() c.PFN_vkGetInstanceProcAddr {
    return @ptrCast(c.SDL_Vulkan_GetVkGetInstanceProcAddr());
}

/// Loads the Vulkan library through SDL; video must be initialized.
pub fn loadLibrary() !void {
    if (g.CreateInstance != null) return;
    if (c.SDL_Vulkan_LoadLibrary(null) != 0) {
        common.warn("SDL_Vulkan_LoadLibrary: {s}\n", .{common.span(c.SDL_GetError())});
        return error.NoVulkan;
    }
    const gipa = getInstanceProcAddr() orelse return error.NoVulkan;
    loadTable(Global, &g, gipa, @as(c.VkInstance, null));
    if (g.CreateInstance == null) return error.NoVulkan;
}

fn hasLayer(name: []const u8) bool {
    var count: u32 = 0;
    _ = g.EnumerateInstanceLayerProperties.?(&count, null);
    var layers: [128]c.VkLayerProperties = undefined;
    count = @min(count, layers.len);
    _ = g.EnumerateInstanceLayerProperties.?(&count, &layers);
    for (layers[0..count]) |layer| if (std.mem.eql(u8, common.span(&layer.layerName), name)) return true;
    return false;
}

/// Creates the instance. `window` may be null for the capability probe.
pub fn createInstance(window: ?*c.SDL_Window, validation: bool) !void {
    var version: u32 = c.VK_API_VERSION_1_0;
    if (g.EnumerateInstanceVersion) |enumerate| _ = enumerate(&version);
    if (version < c.VK_API_VERSION_1_3) {
        common.warn("Vulkan loader reports {d}.{d}; 1.3 is required\n", .{ c.VK_API_VERSION_MAJOR(version), c.VK_API_VERSION_MINOR(version) });
        return error.NoVulkan13;
    }
    var names: [16][*c]const u8 = undefined;
    var count: c_uint = names.len;
    if (c.SDL_Vulkan_GetInstanceExtensions(window, &count, @ptrCast(&names)) == 0) {
        common.warn("SDL_Vulkan_GetInstanceExtensions: {s}\n", .{common.span(c.SDL_GetError())});
        return error.NoVulkan;
    }
    const layer: [*:0]const u8 = "VK_LAYER_KHRONOS_validation";
    const use_validation = validation and hasLayer(std.mem.span(layer));
    if (validation and !use_validation) common.warn("r_vkValidation 1, but {s} is not installed\n", .{layer});
    const application = std.mem.zeroInit(c.VkApplicationInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_APPLICATION_INFO,
        .pApplicationName = "dk3",
        .applicationVersion = 1,
        .pEngineName = "dk3 renderer_vulkan",
        .engineVersion = 1,
        .apiVersion = c.VK_API_VERSION_1_3,
    });
    const create = std.mem.zeroInit(c.VkInstanceCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
        .pApplicationInfo = &application,
        .enabledExtensionCount = count,
        .ppEnabledExtensionNames = @as([*c]const [*c]const u8, @ptrCast(&names)),
        .enabledLayerCount = @as(u32, if (use_validation) 1 else 0),
        .ppEnabledLayerNames = @as([*c]const [*c]const u8, @ptrCast(&layer)),
    });
    try check(g.CreateInstance.?(&create, null, &s.instance), "vkCreateInstance");
    loadTable(Instance, &i, getInstanceProcAddr().?, s.instance);
    if (use_validation) common.info("Vulkan validation layer enabled\n", .{});
}

pub fn destroyInstance() void {
    if (s.surface != null) i.DestroySurfaceKHR.?(s.instance, s.surface, null);
    s.surface = null;
    if (s.instance != null) i.DestroyInstance.?(s.instance, null);
    s.instance = null;
}

fn deviceHasExtension(physical: c.VkPhysicalDevice, available: []const c.VkExtensionProperties, name: []const u8) bool {
    _ = physical;
    for (available) |extension| if (std.mem.eql(u8, common.span(&extension.extensionName), name)) return true;
    return false;
}

const Features = struct {
    base: c.VkPhysicalDeviceFeatures2 = undefined,
    v12: c.VkPhysicalDeviceVulkan12Features = undefined,
    v13: c.VkPhysicalDeviceVulkan13Features = undefined,

    fn chain(self: *Features) void {
        self.v13 = std.mem.zeroInit(c.VkPhysicalDeviceVulkan13Features, .{ .sType = c.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_3_FEATURES });
        self.v12 = std.mem.zeroInit(c.VkPhysicalDeviceVulkan12Features, .{ .sType = c.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_2_FEATURES, .pNext = &self.v13 });
        self.base = std.mem.zeroInit(c.VkPhysicalDeviceFeatures2, .{ .sType = c.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2, .pNext = &self.v12 });
    }

    fn sufficient(self: *const Features) bool {
        return self.v13.dynamicRendering != 0 and self.v13.synchronization2 != 0 and self.v12.timelineSemaphore != 0 and
            self.v12.bufferDeviceAddress != 0 and self.v12.descriptorIndexing != 0 and self.v12.runtimeDescriptorArray != 0 and
            self.v12.descriptorBindingPartiallyBound != 0 and self.v12.descriptorBindingSampledImageUpdateAfterBind != 0 and
            self.v12.descriptorBindingStorageImageUpdateAfterBind != 0 and self.v13.shaderDemoteToHelperInvocation != 0 and
            self.v12.descriptorBindingVariableDescriptorCount != 0 and self.v12.shaderSampledImageArrayNonUniformIndexing != 0 and
            self.base.features.shaderClipDistance != 0 and self.base.features.shaderStorageImageReadWithoutFormat != 0 and
            self.base.features.shaderStorageImageWriteWithoutFormat != 0;
    }
};

const Candidate = struct { physical: c.VkPhysicalDevice, family: u32, score: i32, properties: c.VkPhysicalDeviceProperties };

/// Picks the device: an explicit `r_vkDevice`, otherwise discrete > integrated > virtual > CPU.
/// With `prefer_cpu` (software rendering requested) the CPU device wins.
pub fn pickDevice(require_present: bool, explicit: i32, prefer_cpu: bool) !Candidate {
    var count: u32 = 0;
    try check(i.EnumeratePhysicalDevices.?(s.instance, &count, null), "vkEnumeratePhysicalDevices");
    var devices: [16]c.VkPhysicalDevice = undefined;
    count = @min(count, devices.len);
    try check(i.EnumeratePhysicalDevices.?(s.instance, &count, &devices), "vkEnumeratePhysicalDevices");
    var best: ?Candidate = null;
    for (devices[0..count], 0..) |physical, index| {
        var properties: c.VkPhysicalDeviceProperties = undefined;
        i.GetPhysicalDeviceProperties.?(physical, &properties);
        const name = common.span(&properties.deviceName);
        if (properties.apiVersion < c.VK_API_VERSION_1_3) {
            common.developer("Vulkan device {d} {s}: API below 1.3\n", .{ index, name });
            continue;
        }
        var features: Features = .{};
        features.chain();
        i.GetPhysicalDeviceFeatures2.?(physical, &features.base);
        if (!features.sufficient()) {
            common.developer("Vulkan device {d} {s}: missing 1.3 features\n", .{ index, name });
            continue;
        }
        var family_count: u32 = 0;
        i.GetPhysicalDeviceQueueFamilyProperties.?(physical, &family_count, null);
        var families: [32]c.VkQueueFamilyProperties = undefined;
        family_count = @min(family_count, families.len);
        i.GetPhysicalDeviceQueueFamilyProperties.?(physical, &family_count, &families);
        var family: ?u32 = null;
        for (families[0..family_count], 0..) |properties_family, family_index| {
            if (properties_family.queueFlags & c.VK_QUEUE_GRAPHICS_BIT == 0) continue;
            if (require_present) {
                var supported: c.VkBool32 = 0;
                _ = i.GetPhysicalDeviceSurfaceSupportKHR.?(physical, @intCast(family_index), s.surface, &supported);
                if (supported == 0) continue;
            }
            family = @intCast(family_index);
            break;
        }
        if (family == null) continue;
        var score: i32 = switch (properties.deviceType) {
            c.VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU => 400,
            c.VK_PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU => 300,
            c.VK_PHYSICAL_DEVICE_TYPE_VIRTUAL_GPU => 200,
            c.VK_PHYSICAL_DEVICE_TYPE_CPU => if (prefer_cpu) 1000 else 50,
            else => 10,
        };
        if (explicit >= 0 and explicit == @as(i32, @intCast(index))) score = 10000;
        if (best == null or score > best.?.score) best = .{ .physical = physical, .family = family.?, .score = score, .properties = properties };
    }
    return best orelse error.NoDevice;
}

pub fn createDevice(candidate: Candidate, want_ray_tracing: bool) !void {
    s.physical = candidate.physical;
    s.family = candidate.family;
    s.properties = candidate.properties;
    i.GetPhysicalDeviceMemoryProperties.?(s.physical, &s.memory);
    s.driver = std.mem.zeroInit(c.VkPhysicalDeviceDriverProperties, .{ .sType = c.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DRIVER_PROPERTIES });
    var properties2 = std.mem.zeroInit(c.VkPhysicalDeviceProperties2, .{ .sType = c.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PROPERTIES_2, .pNext = &s.driver });
    i.GetPhysicalDeviceProperties2.?(s.physical, &properties2);

    var available_count: u32 = 0;
    _ = i.EnumerateDeviceExtensionProperties.?(s.physical, null, &available_count, null);
    const available = try common.gpa.alloc(c.VkExtensionProperties, available_count);
    defer common.gpa.free(available);
    _ = i.EnumerateDeviceExtensionProperties.?(s.physical, null, &available_count, available.ptr);
    const has = struct {
        fn f(list: []const c.VkExtensionProperties, name: [*:0]const u8) bool {
            return deviceHasExtension(null, list, std.mem.span(name));
        }
    }.f;
    s.extension_count = 0;
    for (required_device_extensions) |name| {
        if (!has(available, name)) return error.MissingSwapchain;
        s.extensions[s.extension_count] = name;
        s.extension_count += 1;
    }
    s.capabilities = .{
        .acceleration_structure = has(available, c.VK_KHR_ACCELERATION_STRUCTURE_EXTENSION_NAME) and has(available, c.VK_KHR_DEFERRED_HOST_OPERATIONS_EXTENSION_NAME),
        .ray_query = has(available, c.VK_KHR_RAY_QUERY_EXTENSION_NAME),
        .ray_tracing_pipeline = has(available, c.VK_KHR_RAY_TRACING_PIPELINE_EXTENSION_NAME),
        .shader_object = has(available, c.VK_EXT_SHADER_OBJECT_EXTENSION_NAME),
        .fragment_shading_rate = has(available, c.VK_KHR_FRAGMENT_SHADING_RATE_EXTENSION_NAME),
        .descriptor_heap = has(available, "VK_EXT_descriptor_heap"),
    };

    var features: Features = .{};
    features.chain();
    i.GetPhysicalDeviceFeatures2.?(s.physical, &features.base);
    // Enable only what the renderer uses; leaving the queried chain in place would also enable
    // unrelated optional features.
    var v13 = std.mem.zeroInit(c.VkPhysicalDeviceVulkan13Features, .{
        .sType = c.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_3_FEATURES,
        .dynamicRendering = c.VK_TRUE,
        .synchronization2 = c.VK_TRUE,
        // glslc compiles `discard` to a demote for Vulkan 1.3 targets.
        .shaderDemoteToHelperInvocation = c.VK_TRUE,
        .maintenance4 = features.v13.maintenance4,
    });
    var v12 = std.mem.zeroInit(c.VkPhysicalDeviceVulkan12Features, .{
        .sType = c.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_2_FEATURES,
        .pNext = &v13,
        .timelineSemaphore = c.VK_TRUE,
        .bufferDeviceAddress = c.VK_TRUE,
        .descriptorIndexing = c.VK_TRUE,
        .runtimeDescriptorArray = c.VK_TRUE,
        .descriptorBindingPartiallyBound = c.VK_TRUE,
        .descriptorBindingSampledImageUpdateAfterBind = c.VK_TRUE,
        // The storage set (post images, froxel volumes) is also written after binding.
        .descriptorBindingStorageImageUpdateAfterBind = c.VK_TRUE,
        .descriptorBindingVariableDescriptorCount = c.VK_TRUE,
        .shaderSampledImageArrayNonUniformIndexing = c.VK_TRUE,
        .scalarBlockLayout = features.v12.scalarBlockLayout,
    });
    var base = std.mem.zeroInit(c.VkPhysicalDeviceFeatures2, .{ .sType = c.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2, .pNext = &v12 });
    base.features.samplerAnisotropy = features.base.features.samplerAnisotropy;
    base.features.shaderInt64 = features.base.features.shaderInt64;
    // Debug probes write storage buffers from fragment shaders (r_vkDebugView 19).
    base.features.fragmentStoresAndAtomics = features.base.features.fragmentStoresAndAtomics;
    base.features.fillModeNonSolid = features.base.features.fillModeNonSolid;
    base.features.shaderClipDistance = features.base.features.shaderClipDistance;
    base.features.shaderStorageImageReadWithoutFormat = features.base.features.shaderStorageImageReadWithoutFormat;
    base.features.shaderStorageImageWriteWithoutFormat = features.base.features.shaderStorageImageWriteWithoutFormat;

    // Ray tracing tier: acceleration structures plus ray queries from ordinary shaders.
    var as_features = std.mem.zeroInit(c.VkPhysicalDeviceAccelerationStructureFeaturesKHR, .{
        .sType = c.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_ACCELERATION_STRUCTURE_FEATURES_KHR,
        .accelerationStructure = c.VK_TRUE,
    });
    var rq_features = std.mem.zeroInit(c.VkPhysicalDeviceRayQueryFeaturesKHR, .{
        .sType = c.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_RAY_QUERY_FEATURES_KHR,
        .rayQuery = c.VK_TRUE,
    });
    ray_tracing = want_ray_tracing and s.capabilities.acceleration_structure and s.capabilities.ray_query and
        features.base.features.shaderInt64 != 0;
    if (ray_tracing) {
        for ([_][*:0]const u8{ c.VK_KHR_ACCELERATION_STRUCTURE_EXTENSION_NAME, c.VK_KHR_DEFERRED_HOST_OPERATIONS_EXTENSION_NAME, c.VK_KHR_RAY_QUERY_EXTENSION_NAME }) |name| {
            s.extensions[s.extension_count] = name;
            s.extension_count += 1;
        }
        as_features.pNext = &rq_features;
        v13.pNext = &as_features;
        var as_properties = std.mem.zeroInit(c.VkPhysicalDeviceAccelerationStructurePropertiesKHR, .{ .sType = c.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_ACCELERATION_STRUCTURE_PROPERTIES_KHR });
        var properties_rt = std.mem.zeroInit(c.VkPhysicalDeviceProperties2, .{ .sType = c.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PROPERTIES_2, .pNext = &as_properties });
        i.GetPhysicalDeviceProperties2.?(s.physical, &properties_rt);
        as_scratch_alignment = @max(as_properties.minAccelerationStructureScratchOffsetAlignment, 1);
    }

    const priority: f32 = 1;
    const queue = std.mem.zeroInit(c.VkDeviceQueueCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
        .queueFamilyIndex = s.family,
        .queueCount = 1,
        .pQueuePriorities = &priority,
    });
    const create = std.mem.zeroInit(c.VkDeviceCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
        .pNext = &base,
        .queueCreateInfoCount = 1,
        .pQueueCreateInfos = &queue,
        .enabledExtensionCount = s.extension_count,
        .ppEnabledExtensionNames = @as([*c]const [*c]const u8, @ptrCast(&s.extensions)),
    });
    try check(i.CreateDevice.?(s.physical, &create, null, &s.device), "vkCreateDevice");
    loadTable(Device, &d, i.GetDeviceProcAddr.?, s.device);
    d.GetDeviceQueue.?(s.device, s.family, 0, &s.queue);

    for ([_]c.VkFormat{ c.VK_FORMAT_D32_SFLOAT, c.VK_FORMAT_X8_D24_UNORM_PACK32, c.VK_FORMAT_D16_UNORM }) |format| {
        var format_properties: c.VkFormatProperties = undefined;
        i.GetPhysicalDeviceFormatProperties.?(s.physical, format, &format_properties);
        if (format_properties.optimalTilingFeatures & c.VK_FORMAT_FEATURE_DEPTH_STENCIL_ATTACHMENT_BIT != 0) {
            s.depth_format = format;
            break;
        }
    }
}

pub fn destroyDevice() void {
    if (s.device != null) d.DestroyDevice.?(s.device, null);
    s.device = null;
}

pub fn waitIdle() void {
    if (s.device != null) _ = d.DeviceWaitIdle.?(s.device);
}

// ---------------------------------------------------------------------------------------------
// Memory: renderer resources are released together at Shutdown, so each memory type is a list
// of bump-allocated blocks. Linear (buffer) and optimal (image) resources use separate blocks,
// which keeps bufferImageGranularity out of the picture.

const block_size: u64 = 64 << 20;

const Block = struct { memory: c.VkDeviceMemory, size: u64, used: u64, mapped: ?[*]u8, type_index: u32, linear: bool, content: bool };

/// Content resources (textures, models, worlds) are released by every renderer Shutdown;
/// persistent ones (frames, targets) only when the window goes.
pub var content_arena = false;

pub const Allocation = struct { memory: c.VkDeviceMemory, offset: u64, mapped: ?[*]u8 };

var blocks: std.ArrayList(Block) = .empty;

fn memoryType(bits: u32, flags: c.VkMemoryPropertyFlags) ?u32 {
    var index: u32 = 0;
    while (index < s.memory.memoryTypeCount) : (index += 1) {
        if (bits & (@as(u32, 1) << @intCast(index)) == 0) continue;
        if (s.memory.memoryTypes[index].propertyFlags & flags == flags) return index;
    }
    return null;
}

fn allocate(requirements: c.VkMemoryRequirements, flags: c.VkMemoryPropertyFlags, linear: bool) Allocation {
    const type_index = memoryType(requirements.memoryTypeBits, flags) orelse
        memoryType(requirements.memoryTypeBits, flags & ~@as(u32, c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT)) orelse
        common.fail(c.ERR_FATAL, "Vulkan: no memory type for flags {x}", .{flags});
    for (blocks.items) |*block| {
        if (block.type_index != type_index or block.linear != linear or block.content != content_arena) continue;
        const offset = std.mem.alignForward(u64, block.used, requirements.alignment);
        if (offset + requirements.size > block.size) continue;
        block.used = offset + requirements.size;
        return .{ .memory = block.memory, .offset = offset, .mapped = if (block.mapped) |m| m + offset else null };
    }
    const size = @max(block_size, std.mem.alignForward(u64, requirements.size, 1 << 20));
    const flags_info = std.mem.zeroInit(c.VkMemoryAllocateFlagsInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_FLAGS_INFO,
        .flags = c.VK_MEMORY_ALLOCATE_DEVICE_ADDRESS_BIT,
    });
    const info = std.mem.zeroInit(c.VkMemoryAllocateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
        .pNext = if (linear) @as(?*const anyopaque, &flags_info) else null,
        .allocationSize = size,
        .memoryTypeIndex = type_index,
    });
    var memory: c.VkDeviceMemory = null;
    must(d.AllocateMemory.?(s.device, &info, null, &memory), "vkAllocateMemory");
    var mapped: ?[*]u8 = null;
    if (s.memory.memoryTypes[type_index].propertyFlags & c.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT != 0) {
        var pointer: ?*anyopaque = null;
        must(d.MapMemory.?(s.device, memory, 0, c.VK_WHOLE_SIZE, 0, &pointer), "vkMapMemory");
        mapped = @ptrCast(pointer);
    }
    blocks.append(common.gpa, .{ .memory = memory, .size = size, .used = requirements.size, .mapped = mapped, .type_index = type_index, .linear = linear, .content = content_arena }) catch @panic("OOM");
    return .{ .memory = memory, .offset = 0, .mapped = mapped };
}

/// Releases every block; resources inside them must already be destroyed.
pub fn freeMemory() void {
    for (blocks.items) |block| d.FreeMemory.?(s.device, block.memory, null);
    blocks.clearAndFree(common.gpa);
}

/// Releases the content blocks; their buffers and images must already be destroyed.
pub fn freeContentMemory() void {
    var index: usize = 0;
    while (index < blocks.items.len) {
        if (blocks.items[index].content) {
            d.FreeMemory.?(s.device, blocks.items[index].memory, null);
            _ = blocks.swapRemove(index);
        } else index += 1;
    }
}

pub const Buffer = struct {
    buffer: c.VkBuffer = null,
    address: u64 = 0,
    mapped: ?[*]u8 = null,
    size: u64 = 0,
};

pub const host_flags: u32 = c.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | c.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT;
pub const device_flags: u32 = c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT;

pub fn createBuffer(size: u64, usage: c.VkBufferUsageFlags, flags: c.VkMemoryPropertyFlags) Buffer {
    const info = std.mem.zeroInit(c.VkBufferCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
        .size = @max(size, 16),
        .usage = usage | c.VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT,
        .sharingMode = c.VK_SHARING_MODE_EXCLUSIVE,
    });
    var buffer: c.VkBuffer = null;
    must(d.CreateBuffer.?(s.device, &info, null, &buffer), "vkCreateBuffer");
    var requirements: c.VkMemoryRequirements = undefined;
    d.GetBufferMemoryRequirements.?(s.device, buffer, &requirements);
    const allocation = allocate(requirements, flags, true);
    must(d.BindBufferMemory.?(s.device, buffer, allocation.memory, allocation.offset), "vkBindBufferMemory");
    const address_info = std.mem.zeroInit(c.VkBufferDeviceAddressInfo, .{ .sType = c.VK_STRUCTURE_TYPE_BUFFER_DEVICE_ADDRESS_INFO, .buffer = buffer });
    return .{ .buffer = buffer, .address = d.GetBufferDeviceAddress.?(s.device, &address_info), .mapped = allocation.mapped, .size = size };
}

pub fn destroyBuffer(buffer: *Buffer) void {
    if (buffer.buffer != null) d.DestroyBuffer.?(s.device, buffer.buffer, null);
    buffer.* = .{};
}

/// A static device-local buffer filled from `bytes` through the frame's staging ring.
pub fn staticBuffer(bytes: []const u8, usage: c.VkBufferUsageFlags) Buffer {
    const buffer = createBuffer(bytes.len, usage | c.VK_BUFFER_USAGE_TRANSFER_DST_BIT | c.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT, device_flags);
    uploadBuffer(buffer.buffer, 0, bytes);
    return buffer;
}

// ---------------------------------------------------------------------------------------------
// Images

pub const Texture = struct {
    image: c.VkImage = null,
    view: c.VkImageView = null,
    width: u32 = 0,
    height: u32 = 0,
    levels: u32 = 1,
    slot: u32 = 0,
};

pub fn createImage(width: u32, height: u32, levels: u32, format: c.VkFormat, usage: c.VkImageUsageFlags, aspect: c.VkImageAspectFlags) Texture {
    const info = std.mem.zeroInit(c.VkImageCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
        .imageType = c.VK_IMAGE_TYPE_2D,
        .format = format,
        .extent = .{ .width = width, .height = height, .depth = 1 },
        .mipLevels = levels,
        .arrayLayers = 1,
        .samples = c.VK_SAMPLE_COUNT_1_BIT,
        .tiling = c.VK_IMAGE_TILING_OPTIMAL,
        .usage = usage,
        .sharingMode = c.VK_SHARING_MODE_EXCLUSIVE,
        .initialLayout = c.VK_IMAGE_LAYOUT_UNDEFINED,
    });
    var image: c.VkImage = null;
    must(d.CreateImage.?(s.device, &info, null, &image), "vkCreateImage");
    var requirements: c.VkMemoryRequirements = undefined;
    d.GetImageMemoryRequirements.?(s.device, image, &requirements);
    const allocation = allocate(requirements, device_flags, false);
    must(d.BindImageMemory.?(s.device, image, allocation.memory, allocation.offset), "vkBindImageMemory");
    const view_info = std.mem.zeroInit(c.VkImageViewCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
        .image = image,
        .viewType = c.VK_IMAGE_VIEW_TYPE_2D,
        .format = format,
        .subresourceRange = .{ .aspectMask = aspect, .baseMipLevel = 0, .levelCount = levels, .baseArrayLayer = 0, .layerCount = 1 },
    });
    var view: c.VkImageView = null;
    must(d.CreateImageView.?(s.device, &view_info, null, &view), "vkCreateImageView");
    return .{ .image = image, .view = view, .width = width, .height = height, .levels = levels };
}

pub fn destroyImage(texture: *Texture) void {
    if (texture.view != null) d.DestroyImageView.?(s.device, texture.view, null);
    if (texture.image != null) d.DestroyImage.?(s.device, texture.image, null);
    texture.* = .{};
}

pub fn barrier(cmd: c.VkCommandBuffer, image: c.VkImage, aspect: c.VkImageAspectFlags, old: c.VkImageLayout, new: c.VkImageLayout, src_stage: u64, src_access: u64, dst_stage: u64, dst_access: u64) void {
    const image_barrier = std.mem.zeroInit(c.VkImageMemoryBarrier2, .{
        .sType = c.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER_2,
        .srcStageMask = src_stage,
        .srcAccessMask = src_access,
        .dstStageMask = dst_stage,
        .dstAccessMask = dst_access,
        .oldLayout = old,
        .newLayout = new,
        .srcQueueFamilyIndex = c.VK_QUEUE_FAMILY_IGNORED,
        .dstQueueFamilyIndex = c.VK_QUEUE_FAMILY_IGNORED,
        .image = image,
        .subresourceRange = .{ .aspectMask = aspect, .baseMipLevel = 0, .levelCount = c.VK_REMAINING_MIP_LEVELS, .baseArrayLayer = 0, .layerCount = c.VK_REMAINING_ARRAY_LAYERS },
    });
    const dependency = std.mem.zeroInit(c.VkDependencyInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_DEPENDENCY_INFO,
        .imageMemoryBarrierCount = 1,
        .pImageMemoryBarriers = &image_barrier,
    });
    d.CmdPipelineBarrier2.?(cmd, &dependency);
}

pub fn memoryBarrier(cmd: c.VkCommandBuffer, src_stage: u64, src_access: u64, dst_stage: u64, dst_access: u64) void {
    const memory_barrier = std.mem.zeroInit(c.VkMemoryBarrier2, .{
        .sType = c.VK_STRUCTURE_TYPE_MEMORY_BARRIER_2,
        .srcStageMask = src_stage,
        .srcAccessMask = src_access,
        .dstStageMask = dst_stage,
        .dstAccessMask = dst_access,
    });
    const dependency = std.mem.zeroInit(c.VkDependencyInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_DEPENDENCY_INFO,
        .memoryBarrierCount = 1,
        .pMemoryBarriers = &memory_barrier,
    });
    d.CmdPipelineBarrier2.?(cmd, &dependency);
}

pub const stage_all = c.VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT;
pub const stage_copy = c.VK_PIPELINE_STAGE_2_COPY_BIT;
pub const stage_fragment = c.VK_PIPELINE_STAGE_2_FRAGMENT_SHADER_BIT;
pub const stage_vertex = c.VK_PIPELINE_STAGE_2_VERTEX_SHADER_BIT;
pub const access_transfer_write = c.VK_ACCESS_2_TRANSFER_WRITE_BIT;
pub const access_transfer_read = c.VK_ACCESS_2_TRANSFER_READ_BIT;
pub const access_shader_read = c.VK_ACCESS_2_SHADER_READ_BIT;
pub const access_memory_write = c.VK_ACCESS_2_MEMORY_WRITE_BIT;
pub const access_memory_read = c.VK_ACCESS_2_MEMORY_READ_BIT;

// ---------------------------------------------------------------------------------------------
// Frames. Each slot owns an upload and a draw command buffer and host-visible rings for
// staging, streamed vertices and draw records; the timeline value of the slot's last
// submission guards their reuse.

pub const Space = struct { buffer: c.VkBuffer, offset: u64, address: u64, bytes: []u8 };

/// Per-frame host-visible memory. Growable rings add chunks instead of failing, so a busy
/// frame (heavy weather, many skinned characters) never drops draws; the chunks stay for later
/// frames. The staging ring is fixed and flushes instead (see `stage`).
pub const Ring = struct {
    chunks: std.ArrayList(Buffer) = .empty,
    current: usize = 0,
    used: u64 = 0,
    chunk_size: u64 = 0,
    usage: c.VkBufferUsageFlags = 0,
    growable: bool = true,
    /// Chunks added since creation, for r_vkStats.
    grown: u32 = 0,

    pub fn init(self: *Ring, size: u64, usage: c.VkBufferUsageFlags, growable: bool) void {
        self.* = .{ .chunk_size = size, .usage = usage, .growable = growable };
        self.chunks.append(common.gpa, persistentBuffer(size, usage)) catch @panic("OOM");
    }

    pub fn deinit(self: *Ring) void {
        for (self.chunks.items) |*chunk| destroyBuffer(chunk);
        self.chunks.deinit(common.gpa);
        self.* = .{};
    }

    pub fn reset(self: *Ring) void {
        self.current = 0;
        self.used = 0;
    }

    pub fn alloc(self: *Ring, size: u64, alignment: u64) ?Space {
        while (true) {
            const chunk = &self.chunks.items[self.current];
            const offset = std.mem.alignForward(u64, self.used, alignment);
            if (offset + size <= chunk.size) {
                self.used = offset + size;
                return .{ .buffer = chunk.buffer, .offset = offset, .address = chunk.address + offset, .bytes = chunk.mapped.?[offset .. offset + size] };
            }
            if (!self.growable) return null;
            if (self.current + 1 >= self.chunks.items.len) {
                self.chunks.append(common.gpa, persistentBuffer(@max(self.chunk_size, size), self.usage)) catch return null;
                self.grown += 1;
            }
            self.current += 1;
            self.used = 0;
        }
    }

    pub fn bytesUsed(self: *const Ring) u64 {
        var total: u64 = self.used;
        for (self.chunks.items[0..self.current]) |chunk| total += chunk.size;
        return total;
    }
};

/// Frame rings outlive renderer content: allocate them from the persistent memory blocks.
fn persistentBuffer(size: u64, usage: c.VkBufferUsageFlags) Buffer {
    const saved = content_arena;
    content_arena = false;
    defer content_arena = saved;
    return createBuffer(size, usage, host_flags);
}

pub const Frame = struct {
    pool: c.VkCommandPool = null,
    upload: c.VkCommandBuffer = null,
    draw: c.VkCommandBuffer = null,
    acquired: c.VkSemaphore = null,
    value: u64 = 0,
    staging: Ring = .{},
    stream: Ring = .{},
    records: Ring = .{},
    upload_used: bool = false,
    retired: std.ArrayList(Buffer) = .empty,
};

pub var frames: [frames_in_flight]Frame = .{ .{}, .{} };
pub var frame_index: usize = 0;
pub var timeline: c.VkSemaphore = null;
pub var timeline_value: u64 = 0;

const staging_size: u64 = 48 << 20;
const stream_size: u64 = 24 << 20;
const records_size: u64 = 12 << 20;

pub fn frame() *Frame {
    return &frames[frame_index];
}

pub fn createFrames() void {
    const timeline_info = std.mem.zeroInit(c.VkSemaphoreTypeCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_TYPE_CREATE_INFO,
        .semaphoreType = c.VK_SEMAPHORE_TYPE_TIMELINE,
        .initialValue = 0,
    });
    const timeline_create = std.mem.zeroInit(c.VkSemaphoreCreateInfo, .{ .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO, .pNext = &timeline_info });
    must(d.CreateSemaphore.?(s.device, &timeline_create, null, &timeline), "vkCreateSemaphore");
    timeline_value = 0;
    const binary = std.mem.zeroInit(c.VkSemaphoreCreateInfo, .{ .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO });
    for (&frames) |*slot| {
        const pool_info = std.mem.zeroInit(c.VkCommandPoolCreateInfo, .{
            .sType = c.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
            .flags = c.VK_COMMAND_POOL_CREATE_TRANSIENT_BIT | c.VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
            .queueFamilyIndex = s.family,
        });
        must(d.CreateCommandPool.?(s.device, &pool_info, null, &slot.pool), "vkCreateCommandPool");
        var buffers: [2]c.VkCommandBuffer = undefined;
        const allocate_info = std.mem.zeroInit(c.VkCommandBufferAllocateInfo, .{
            .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
            .commandPool = slot.pool,
            .level = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
            .commandBufferCount = 2,
        });
        must(d.AllocateCommandBuffers.?(s.device, &allocate_info, &buffers), "vkAllocateCommandBuffers");
        slot.upload = buffers[0];
        slot.draw = buffers[1];
        must(d.CreateSemaphore.?(s.device, &binary, null, &slot.acquired), "vkCreateSemaphore");
        slot.staging.init(staging_size, c.VK_BUFFER_USAGE_TRANSFER_SRC_BIT, false);
        slot.stream.init(stream_size, c.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT, true);
        slot.records.init(records_size, c.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT, true);
        slot.value = 0;
    }
    frame_index = 0;
    beginUploads(frame());
}

pub fn destroyFrames() void {
    for (&frames) |*slot| {
        if (slot.pool == null) continue;
        d.DestroyCommandPool.?(s.device, slot.pool, null);
        d.DestroySemaphore.?(s.device, slot.acquired, null);
        slot.staging.deinit();
        slot.stream.deinit();
        slot.records.deinit();
        for (slot.retired.items) |*retired| destroyBuffer(retired);
        slot.retired.clearAndFree(common.gpa);
        slot.* = .{};
    }
    if (timeline != null) d.DestroySemaphore.?(s.device, timeline, null);
    timeline = null;
}

pub fn waitValue(value: u64) void {
    if (value == 0) return;
    const wait = std.mem.zeroInit(c.VkSemaphoreWaitInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_WAIT_INFO,
        .semaphoreCount = 1,
        .pSemaphores = &timeline,
        .pValues = &value,
    });
    must(d.WaitSemaphores.?(s.device, &wait, std.math.maxInt(u64)), "vkWaitSemaphores");
}

fn beginBuffer(cmd: c.VkCommandBuffer) void {
    const begin = std.mem.zeroInit(c.VkCommandBufferBeginInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        .flags = c.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
    });
    must(d.BeginCommandBuffer.?(cmd, &begin), "vkBeginCommandBuffer");
}

fn beginUploads(slot: *Frame) void {
    waitValue(slot.value);
    for (slot.retired.items) |*retired| destroyBuffer(retired);
    slot.retired.clearRetainingCapacity();
    must(d.ResetCommandPool.?(s.device, slot.pool, 0), "vkResetCommandPool");
    slot.staging.reset();
    slot.stream.reset();
    slot.records.reset();
    slot.upload_used = false;
    beginBuffer(slot.upload);
}

/// Starts recording the current slot's draw command buffer.
pub fn beginDraw() c.VkCommandBuffer {
    beginBuffer(frame().draw);
    return frame().draw;
}

pub const Present = struct { wait: c.VkSemaphore = null, signal: c.VkSemaphore = null };

/// Submits the slot's uploads then its draws, and starts the next slot.
pub fn submitFrame(present: Present) u64 {
    const slot = frame();
    must(d.EndCommandBuffer.?(slot.upload), "vkEndCommandBuffer");
    must(d.EndCommandBuffer.?(slot.draw), "vkEndCommandBuffer");
    timeline_value += 1;
    slot.value = timeline_value;
    const buffers = [_]c.VkCommandBufferSubmitInfo{
        std.mem.zeroInit(c.VkCommandBufferSubmitInfo, .{ .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_SUBMIT_INFO, .commandBuffer = slot.upload }),
        std.mem.zeroInit(c.VkCommandBufferSubmitInfo, .{ .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_SUBMIT_INFO, .commandBuffer = slot.draw }),
    };
    const wait = std.mem.zeroInit(c.VkSemaphoreSubmitInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_SUBMIT_INFO,
        .semaphore = present.wait,
        .stageMask = c.VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT,
    });
    const signals = [_]c.VkSemaphoreSubmitInfo{
        std.mem.zeroInit(c.VkSemaphoreSubmitInfo, .{ .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_SUBMIT_INFO, .semaphore = timeline, .value = timeline_value, .stageMask = stage_all }),
        std.mem.zeroInit(c.VkSemaphoreSubmitInfo, .{ .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_SUBMIT_INFO, .semaphore = present.signal, .stageMask = stage_all }),
    };
    const submit = std.mem.zeroInit(c.VkSubmitInfo2, .{
        .sType = c.VK_STRUCTURE_TYPE_SUBMIT_INFO_2,
        .waitSemaphoreInfoCount = @as(u32, if (present.wait != null) 1 else 0),
        .pWaitSemaphoreInfos = &wait,
        .commandBufferInfoCount = 2,
        .pCommandBufferInfos = &buffers,
        .signalSemaphoreInfoCount = @as(u32, if (present.signal != null) 2 else 1),
        .pSignalSemaphoreInfos = &signals,
    });
    must(d.QueueSubmit2.?(s.queue, 1, &submit, null), "vkQueueSubmit2");
    const submitted = timeline_value;
    frame_index = (frame_index + 1) % frames_in_flight;
    beginUploads(frame());
    return submitted;
}

/// Submits pending uploads now and waits for them, so the staging ring can be reused.
/// Used when a level load stages more than one ring of texture data between frames, and
/// before content resources are destroyed.
pub fn flushUploads() void {
    const slot = frame();
    must(d.EndCommandBuffer.?(slot.upload), "vkEndCommandBuffer");
    timeline_value += 1;
    const info = std.mem.zeroInit(c.VkCommandBufferSubmitInfo, .{ .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_SUBMIT_INFO, .commandBuffer = slot.upload });
    const signal = std.mem.zeroInit(c.VkSemaphoreSubmitInfo, .{ .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_SUBMIT_INFO, .semaphore = timeline, .value = timeline_value, .stageMask = stage_all });
    const submit = std.mem.zeroInit(c.VkSubmitInfo2, .{
        .sType = c.VK_STRUCTURE_TYPE_SUBMIT_INFO_2,
        .commandBufferInfoCount = 1,
        .pCommandBufferInfos = &info,
        .signalSemaphoreInfoCount = 1,
        .pSignalSemaphoreInfos = &signal,
    });
    must(d.QueueSubmit2.?(s.queue, 1, &submit, null), "vkQueueSubmit2");
    waitValue(timeline_value);
    // Only the upload buffer is reset; a draw buffer may already be recording in this slot.
    slot.staging.reset();
    slot.upload_used = false;
    beginBuffer(slot.upload);
}

/// Pauses the draw command buffer is not needed: uploads go to the slot's upload buffer,
/// which is submitted before its draws. Returns staging bytes for `size`.
pub fn stage(size: u64) struct { buffer: c.VkBuffer, offset: u64, bytes: []u8 } {
    const slot = frame();
    if (size > staging_size) {
        // One oversized copy: a dedicated staging buffer retired with this slot.
        const buffer = createBuffer(size, c.VK_BUFFER_USAGE_TRANSFER_SRC_BIT, host_flags);
        slot.retired.append(common.gpa, buffer) catch @panic("OOM");
        slot.upload_used = true;
        return .{ .buffer = buffer.buffer, .offset = 0, .bytes = buffer.mapped.?[0..size] };
    }
    if (slot.staging.alloc(size, 16)) |space| {
        slot.upload_used = true;
        return .{ .buffer = space.buffer, .offset = space.offset, .bytes = space.bytes };
    }
    flushUploads();
    const space = slot.staging.alloc(size, 16).?;
    slot.upload_used = true;
    return .{ .buffer = space.buffer, .offset = space.offset, .bytes = space.bytes };
}

pub fn uploadCommands() c.VkCommandBuffer {
    return frame().upload;
}

pub fn uploadBuffer(target: c.VkBuffer, offset: u64, bytes: []const u8) void {
    if (bytes.len == 0) return;
    const space = stage(bytes.len);
    @memcpy(space.bytes, bytes);
    const region = c.VkBufferCopy{ .srcOffset = space.offset, .dstOffset = offset, .size = bytes.len };
    const cmd = uploadCommands();
    d.CmdCopyBuffer.?(cmd, space.buffer, target, 1, &region);
    memoryBarrier(cmd, stage_copy, access_transfer_write, stage_all, access_memory_read);
}

/// Copies RGBA8 mip levels (tightly packed, level 0 first) into `texture` and leaves it
/// shader-readable. `first_use` selects UNDEFINED as the old layout.
pub fn uploadTexture(texture: *const Texture, levels: []const []const u8, first_use: bool) void {
    var total: u64 = 0;
    for (levels) |level| total += std.mem.alignForward(u64, level.len, 16);
    const space = stage(total);
    const cmd = uploadCommands();
    barrier(cmd, texture.image, c.VK_IMAGE_ASPECT_COLOR_BIT, if (first_use) c.VK_IMAGE_LAYOUT_UNDEFINED else c.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL, c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, stage_all, 0, stage_copy, access_transfer_write);
    var regions: [16]c.VkBufferImageCopy = undefined;
    var offset: u64 = 0;
    for (levels, 0..) |level, index| {
        @memcpy(space.bytes[offset .. offset + level.len], level);
        regions[index] = std.mem.zeroInit(c.VkBufferImageCopy, .{
            .bufferOffset = space.offset + offset,
            .imageSubresource = .{ .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT, .mipLevel = @as(u32, @intCast(index)), .baseArrayLayer = 0, .layerCount = 1 },
            .imageExtent = .{ .width = @max(texture.width >> @intCast(index), 1), .height = @max(texture.height >> @intCast(index), 1), .depth = 1 },
        });
        offset += std.mem.alignForward(u64, level.len, 16);
    }
    d.CmdCopyBufferToImage.?(cmd, space.buffer, texture.image, c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, @intCast(levels.len), &regions);
    barrier(cmd, texture.image, c.VK_IMAGE_ASPECT_COLOR_BIT, c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, c.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL, stage_copy, access_transfer_write, stage_fragment | stage_vertex, access_shader_read);
}

/// Copies a sub-rectangle of level 0 (RGBA8, tightly packed).
pub fn uploadRegion(texture: *const Texture, x: u32, y: u32, width: u32, height: u32, pixels: []const u8) void {
    const space = stage(pixels.len);
    @memcpy(space.bytes, pixels);
    const cmd = uploadCommands();
    barrier(cmd, texture.image, c.VK_IMAGE_ASPECT_COLOR_BIT, c.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL, c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, stage_all, 0, stage_copy, access_transfer_write);
    const region = std.mem.zeroInit(c.VkBufferImageCopy, .{
        .bufferOffset = space.offset,
        .imageSubresource = .{ .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT, .mipLevel = 0, .baseArrayLayer = 0, .layerCount = 1 },
        .imageOffset = .{ .x = @as(i32, @intCast(x)), .y = @as(i32, @intCast(y)), .z = 0 },
        .imageExtent = .{ .width = width, .height = height, .depth = 1 },
    });
    d.CmdCopyBufferToImage.?(cmd, space.buffer, texture.image, c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &region);
    barrier(cmd, texture.image, c.VK_IMAGE_ASPECT_COLOR_BIT, c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, c.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL, stage_copy, access_transfer_write, stage_fragment | stage_vertex, access_shader_read);
}

// ---------------------------------------------------------------------------------------------
// Bindless textures: one update-after-bind set of combined image samplers.

pub const SamplerKind = enum(u32) { repeat_mip, clamp_mip, repeat, clamp, nearest_clamp };

pub var samplers: [5]c.VkSampler = .{ null, null, null, null, null };
pub var set_layout: c.VkDescriptorSetLayout = null;
pub var descriptor_pool: c.VkDescriptorPool = null;
pub var descriptor_set: c.VkDescriptorSet = null;
pub var pipeline_layout: c.VkPipelineLayout = null;
pub var next_slot: u32 = 0;

pub fn createSamplers(anisotropy: f32) void {
    for (&samplers, 0..) |*sampler, index| {
        const kind: SamplerKind = @enumFromInt(index);
        const clamp = kind == .clamp_mip or kind == .clamp or kind == .nearest_clamp;
        const mip = kind == .repeat_mip or kind == .clamp_mip;
        const filter: c.VkFilter = if (kind == .nearest_clamp) c.VK_FILTER_NEAREST else c.VK_FILTER_LINEAR;
        const address: c.VkSamplerAddressMode = if (clamp) c.VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE else c.VK_SAMPLER_ADDRESS_MODE_REPEAT;
        const info = std.mem.zeroInit(c.VkSamplerCreateInfo, .{
            .sType = c.VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO,
            .magFilter = filter,
            .minFilter = filter,
            .mipmapMode = c.VK_SAMPLER_MIPMAP_MODE_LINEAR,
            .addressModeU = address,
            .addressModeV = address,
            .addressModeW = address,
            .anisotropyEnable = @as(u32, if (mip and anisotropy > 1) c.VK_TRUE else c.VK_FALSE),
            .maxAnisotropy = anisotropy,
            .minLod = 0,
            .maxLod = if (mip) c.VK_LOD_CLAMP_NONE else 0.25,
        });
        must(d.CreateSampler.?(s.device, &info, null, sampler), "vkCreateSampler");
    }
}

pub fn createBindless() void {
    const binding_flags: c.VkDescriptorBindingFlags = c.VK_DESCRIPTOR_BINDING_PARTIALLY_BOUND_BIT |
        c.VK_DESCRIPTOR_BINDING_UPDATE_AFTER_BIND_BIT | c.VK_DESCRIPTOR_BINDING_VARIABLE_DESCRIPTOR_COUNT_BIT;
    const count: u32 = @min(max_textures, s.properties.limits.maxPerStageDescriptorSamplers);
    const flags_info = std.mem.zeroInit(c.VkDescriptorSetLayoutBindingFlagsCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_BINDING_FLAGS_CREATE_INFO,
        .bindingCount = 1,
        .pBindingFlags = &binding_flags,
    });
    const binding = std.mem.zeroInit(c.VkDescriptorSetLayoutBinding, .{
        .binding = 0,
        .descriptorType = c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
        .descriptorCount = count,
        .stageFlags = all_stages,
    });
    const layout_info = std.mem.zeroInit(c.VkDescriptorSetLayoutCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
        .pNext = &flags_info,
        .flags = c.VK_DESCRIPTOR_SET_LAYOUT_CREATE_UPDATE_AFTER_BIND_POOL_BIT,
        .bindingCount = 1,
        .pBindings = &binding,
    });
    must(d.CreateDescriptorSetLayout.?(s.device, &layout_info, null, &set_layout), "vkCreateDescriptorSetLayout");
    const pool_size = c.VkDescriptorPoolSize{ .type = c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, .descriptorCount = count };
    const pool_info = std.mem.zeroInit(c.VkDescriptorPoolCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
        .flags = c.VK_DESCRIPTOR_POOL_CREATE_UPDATE_AFTER_BIND_BIT,
        .maxSets = 1,
        .poolSizeCount = 1,
        .pPoolSizes = &pool_size,
    });
    must(d.CreateDescriptorPool.?(s.device, &pool_info, null, &descriptor_pool), "vkCreateDescriptorPool");
    const variable = std.mem.zeroInit(c.VkDescriptorSetVariableDescriptorCountAllocateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_VARIABLE_DESCRIPTOR_COUNT_ALLOCATE_INFO,
        .descriptorSetCount = 1,
        .pDescriptorCounts = &count,
    });
    const allocate_info = std.mem.zeroInit(c.VkDescriptorSetAllocateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
        .pNext = &variable,
        .descriptorPool = descriptor_pool,
        .descriptorSetCount = 1,
        .pSetLayouts = &set_layout,
    });
    must(d.AllocateDescriptorSets.?(s.device, &allocate_info, &descriptor_set), "vkAllocateDescriptorSets");
    createStorageSet();
    const range = c.VkPushConstantRange{ .stageFlags = all_stages, .offset = 0, .size = push_size };
    const layouts = [_]c.VkDescriptorSetLayout{ set_layout, storage_layout };
    const pipeline_layout_info = std.mem.zeroInit(c.VkPipelineLayoutCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
        .setLayoutCount = 2,
        .pSetLayouts = &layouts,
        .pushConstantRangeCount = 1,
        .pPushConstantRanges = &range,
    });
    must(d.CreatePipelineLayout.?(s.device, &pipeline_layout_info, null, &pipeline_layout), "vkCreatePipelineLayout");
    next_slot = 0;
    slot_limit = count;
}

/// Slots below this belong to persistent targets; content slots are reused after Shutdown.
pub var persistent_slots: u32 = 0;

pub const all_stages: u32 = c.VK_SHADER_STAGE_VERTEX_BIT | c.VK_SHADER_STAGE_FRAGMENT_BIT | c.VK_SHADER_STAGE_COMPUTE_BIT;
pub const push_size: u32 = 128;
pub const max_storage_images = 128;
pub const max_volumes = 512;
pub const max_storage_volumes = 16;
pub var next_storage_volume: u32 = 0;

/// Binds a 3D storage image (froxel volumes) to the next binding-2 slot.
pub fn bindStorageVolume(view: c.VkImageView) u32 {
    if (next_storage_volume >= max_storage_volumes) common.fail(c.ERR_FATAL, "renderer_vulkan: storage volume slots exhausted", .{});
    const slot = next_storage_volume;
    next_storage_volume += 1;
    const image_info = c.VkDescriptorImageInfo{ .sampler = null, .imageView = view, .imageLayout = c.VK_IMAGE_LAYOUT_GENERAL };
    const write = std.mem.zeroInit(c.VkWriteDescriptorSet, .{
        .sType = c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
        .dstSet = storage_set,
        .dstBinding = 2,
        .dstArrayElement = slot,
        .descriptorCount = 1,
        .descriptorType = c.VK_DESCRIPTOR_TYPE_STORAGE_IMAGE,
        .pImageInfo = &image_info,
    });
    d.UpdateDescriptorSets.?(s.device, 1, &write, 0, null);
    return slot;
}

/// Binds a 3D texture in `layout` to the next sampled volume slot.
pub fn bindVolumeLayout(view: c.VkImageView, layout: c.VkImageLayout) u32 {
    if (next_volume_slot >= max_volumes) return max_volumes - 1;
    const slot = next_volume_slot;
    next_volume_slot += 1;
    const image_info = c.VkDescriptorImageInfo{ .sampler = samplers[@intFromEnum(SamplerKind.clamp)], .imageView = view, .imageLayout = layout };
    const write = std.mem.zeroInit(c.VkWriteDescriptorSet, .{
        .sType = c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
        .dstSet = storage_set,
        .dstBinding = 1,
        .dstArrayElement = slot,
        .descriptorCount = 1,
        .descriptorType = c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
        .pImageInfo = &image_info,
    });
    d.UpdateDescriptorSets.?(s.device, 1, &write, 0, null);
    return slot;
}

// Set 1: storage images for compute passes (binding 0) and 3D textures (binding 1).
pub var storage_layout: c.VkDescriptorSetLayout = null;
var storage_pool: c.VkDescriptorPool = null;
pub var storage_set: c.VkDescriptorSet = null;
pub var next_storage_slot: u32 = 0;
pub var next_volume_slot: u32 = 0;
pub var persistent_volume_slots: u32 = 0;

fn createStorageSet() void {
    const partial = c.VK_DESCRIPTOR_BINDING_PARTIALLY_BOUND_BIT | c.VK_DESCRIPTOR_BINDING_UPDATE_AFTER_BIND_BIT;
    // Binding 3 (the TLAS) is written once before any frame and rebuilt in place.
    const flags = [_]c.VkDescriptorBindingFlags{ partial, partial, partial, 0 };
    const binding_count: u32 = if (ray_tracing) 4 else 3;
    const flags_info = std.mem.zeroInit(c.VkDescriptorSetLayoutBindingFlagsCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_BINDING_FLAGS_CREATE_INFO,
        .bindingCount = binding_count,
        .pBindingFlags = &flags,
    });
    const bindings = [_]c.VkDescriptorSetLayoutBinding{
        std.mem.zeroInit(c.VkDescriptorSetLayoutBinding, .{ .binding = 0, .descriptorType = c.VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, .descriptorCount = max_storage_images, .stageFlags = all_stages }),
        std.mem.zeroInit(c.VkDescriptorSetLayoutBinding, .{ .binding = 1, .descriptorType = c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, .descriptorCount = max_volumes, .stageFlags = all_stages }),
        std.mem.zeroInit(c.VkDescriptorSetLayoutBinding, .{ .binding = 2, .descriptorType = c.VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, .descriptorCount = max_storage_volumes, .stageFlags = all_stages }),
        std.mem.zeroInit(c.VkDescriptorSetLayoutBinding, .{ .binding = 3, .descriptorType = c.VK_DESCRIPTOR_TYPE_ACCELERATION_STRUCTURE_KHR, .descriptorCount = 1, .stageFlags = all_stages }),
    };
    const layout_info = std.mem.zeroInit(c.VkDescriptorSetLayoutCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
        .pNext = &flags_info,
        .flags = c.VK_DESCRIPTOR_SET_LAYOUT_CREATE_UPDATE_AFTER_BIND_POOL_BIT,
        .bindingCount = binding_count,
        .pBindings = &bindings,
    });
    must(d.CreateDescriptorSetLayout.?(s.device, &layout_info, null, &storage_layout), "vkCreateDescriptorSetLayout");
    const sizes = [_]c.VkDescriptorPoolSize{
        .{ .type = c.VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, .descriptorCount = max_storage_images + max_storage_volumes },
        .{ .type = c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, .descriptorCount = max_volumes },
        .{ .type = c.VK_DESCRIPTOR_TYPE_ACCELERATION_STRUCTURE_KHR, .descriptorCount = 1 },
    };
    const pool_info = std.mem.zeroInit(c.VkDescriptorPoolCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
        .flags = c.VK_DESCRIPTOR_POOL_CREATE_UPDATE_AFTER_BIND_BIT,
        .maxSets = 1,
        .poolSizeCount = @as(u32, if (ray_tracing) 3 else 2),
        .pPoolSizes = &sizes,
    });
    must(d.CreateDescriptorPool.?(s.device, &pool_info, null, &storage_pool), "vkCreateDescriptorPool");
    const allocate_info = std.mem.zeroInit(c.VkDescriptorSetAllocateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
        .descriptorPool = storage_pool,
        .descriptorSetCount = 1,
        .pSetLayouts = &storage_layout,
    });
    must(d.AllocateDescriptorSets.?(s.device, &allocate_info, &storage_set), "vkAllocateDescriptorSets");
    next_storage_slot = 0;
    next_volume_slot = 0;
    next_storage_volume = 0;
}

/// Binds a storage image view (one mip level) to the next storage slot.
pub fn bindStorage(view: c.VkImageView) u32 {
    if (next_storage_slot >= max_storage_images) common.fail(c.ERR_FATAL, "renderer_vulkan: storage image slots exhausted", .{});
    const slot = next_storage_slot;
    next_storage_slot += 1;
    const image_info = c.VkDescriptorImageInfo{ .sampler = null, .imageView = view, .imageLayout = c.VK_IMAGE_LAYOUT_GENERAL };
    const write = std.mem.zeroInit(c.VkWriteDescriptorSet, .{
        .sType = c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
        .dstSet = storage_set,
        .dstBinding = 0,
        .dstArrayElement = slot,
        .descriptorCount = 1,
        .descriptorType = c.VK_DESCRIPTOR_TYPE_STORAGE_IMAGE,
        .pImageInfo = &image_info,
    });
    d.UpdateDescriptorSets.?(s.device, 1, &write, 0, null);
    return slot;
}

/// Binds a 3D texture to the next volume slot (linear clamp sampling).
pub fn bindVolume(view: c.VkImageView) u32 {
    if (next_volume_slot >= max_volumes) return max_volumes - 1;
    const slot = next_volume_slot;
    next_volume_slot += 1;
    const image_info = c.VkDescriptorImageInfo{ .sampler = samplers[@intFromEnum(SamplerKind.clamp)], .imageView = view, .imageLayout = c.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL };
    const write = std.mem.zeroInit(c.VkWriteDescriptorSet, .{
        .sType = c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
        .dstSet = storage_set,
        .dstBinding = 1,
        .dstArrayElement = slot,
        .descriptorCount = 1,
        .descriptorType = c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
        .pImageInfo = &image_info,
    });
    d.UpdateDescriptorSets.?(s.device, 1, &write, 0, null);
    return slot;
}

/// A view of one mip level of `image` (for storage writes or per-level sampling).
pub fn mipView(image: c.VkImage, format: c.VkFormat, level: u32) c.VkImageView {
    const view_info = std.mem.zeroInit(c.VkImageViewCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
        .image = image,
        .viewType = c.VK_IMAGE_VIEW_TYPE_2D,
        .format = format,
        .subresourceRange = .{ .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT, .baseMipLevel = level, .levelCount = 1, .baseArrayLayer = 0, .layerCount = 1 },
    });
    var view: c.VkImageView = null;
    must(d.CreateImageView.?(s.device, &view_info, null, &view), "vkCreateImageView");
    return view;
}

/// A 3D texture (light grids, froxel volumes) with the given format.
pub fn createVolume(width: u32, height: u32, depth_count: u32, format: c.VkFormat, usage: c.VkImageUsageFlags) Texture {
    const info = std.mem.zeroInit(c.VkImageCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
        .imageType = c.VK_IMAGE_TYPE_3D,
        .format = format,
        .extent = .{ .width = width, .height = height, .depth = depth_count },
        .mipLevels = 1,
        .arrayLayers = 1,
        .samples = c.VK_SAMPLE_COUNT_1_BIT,
        .tiling = c.VK_IMAGE_TILING_OPTIMAL,
        .usage = usage,
        .sharingMode = c.VK_SHARING_MODE_EXCLUSIVE,
        .initialLayout = c.VK_IMAGE_LAYOUT_UNDEFINED,
    });
    var image: c.VkImage = null;
    must(d.CreateImage.?(s.device, &info, null, &image), "vkCreateImage");
    var requirements: c.VkMemoryRequirements = undefined;
    d.GetImageMemoryRequirements.?(s.device, image, &requirements);
    const allocation = allocate(requirements, device_flags, false);
    must(d.BindImageMemory.?(s.device, image, allocation.memory, allocation.offset), "vkBindImageMemory");
    const view_info = std.mem.zeroInit(c.VkImageViewCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
        .image = image,
        .viewType = c.VK_IMAGE_VIEW_TYPE_3D,
        .format = format,
        .subresourceRange = .{ .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT, .baseMipLevel = 0, .levelCount = 1, .baseArrayLayer = 0, .layerCount = 1 },
    });
    var view: c.VkImageView = null;
    must(d.CreateImageView.?(s.device, &view_info, null, &view), "vkCreateImageView");
    return .{ .image = image, .view = view, .width = width, .height = height, .levels = 1 };
}

/// Uploads tightly packed texels into a whole 3D texture and leaves it shader-readable.
pub fn uploadVolume(texture: *const Texture, depth_count: u32, texels: []const u8) void {
    const space = stage(texels.len);
    @memcpy(space.bytes, texels);
    const cmd = uploadCommands();
    barrier(cmd, texture.image, c.VK_IMAGE_ASPECT_COLOR_BIT, c.VK_IMAGE_LAYOUT_UNDEFINED, c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, stage_all, 0, stage_copy, access_transfer_write);
    const region = std.mem.zeroInit(c.VkBufferImageCopy, .{
        .bufferOffset = space.offset,
        .imageSubresource = .{ .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT, .mipLevel = 0, .baseArrayLayer = 0, .layerCount = 1 },
        .imageExtent = .{ .width = texture.width, .height = texture.height, .depth = depth_count },
    });
    d.CmdCopyBufferToImage.?(cmd, space.buffer, texture.image, c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &region);
    barrier(cmd, texture.image, c.VK_IMAGE_ASPECT_COLOR_BIT, c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, c.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL, stage_copy, access_transfer_write, stage_fragment | stage_vertex | c.VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT, access_shader_read);
}

// ---------------------------------------------------------------------------------------------
// Compute pipelines, created on first use and cached by shader name.

var compute_pipelines: std.StringHashMapUnmanaged(c.VkPipeline) = .empty;

pub fn computePipeline(comptime name: []const u8) c.VkPipeline {
    if (compute_pipelines.get(name)) |existing| return existing;
    const module = createModule(spirv(name ++ ".spv"));
    defer d.DestroyShaderModule.?(s.device, module, null);
    const info = std.mem.zeroInit(c.VkComputePipelineCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO,
        .stage = std.mem.zeroInit(c.VkPipelineShaderStageCreateInfo, .{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
            .stage = c.VK_SHADER_STAGE_COMPUTE_BIT,
            .module = module,
            .pName = "main",
        }),
        .layout = pipeline_layout,
    });
    var created: c.VkPipeline = null;
    must(d.CreateComputePipelines.?(s.device, null, 1, &info, null, &created), "vkCreateComputePipelines");
    compute_pipelines.put(common.gpa, name, created) catch @panic("OOM");
    return created;
}

/// Binds `name`, pushes `constants` and dispatches enough groups to cover width x height x depth.
pub fn dispatch(cmd: c.VkCommandBuffer, comptime name: []const u8, constants: anytype, width: u32, height: u32, depth_count: u32, group: [3]u32) void {
    d.CmdBindPipeline.?(cmd, c.VK_PIPELINE_BIND_POINT_COMPUTE, computePipeline(name));
    const sets = [_]c.VkDescriptorSet{ descriptor_set, storage_set };
    d.CmdBindDescriptorSets.?(cmd, c.VK_PIPELINE_BIND_POINT_COMPUTE, pipeline_layout, 0, 2, &sets, 0, null);
    const bytes = std.mem.asBytes(&constants);
    d.CmdPushConstants.?(cmd, pipeline_layout, all_stages, 0, @intCast(bytes.len), bytes.ptr);
    d.CmdDispatch.?(cmd, (width + group[0] - 1) / group[0], (height + group[1] - 1) / group[1], (depth_count + group[2] - 1) / group[2]);
}

pub fn computeBarrier(cmd: c.VkCommandBuffer) void {
    memoryBarrier(cmd, c.VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT | c.VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT, c.VK_ACCESS_2_SHADER_WRITE_BIT | c.VK_ACCESS_2_COLOR_ATTACHMENT_WRITE_BIT, c.VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT | c.VK_PIPELINE_STAGE_2_FRAGMENT_SHADER_BIT, c.VK_ACCESS_2_SHADER_READ_BIT | c.VK_ACCESS_2_SHADER_WRITE_BIT);
}

var slot_limit: u32 = 0;

/// Binds `texture` to a new bindless slot.
pub fn bindTexture(texture: *Texture, sampler: SamplerKind) void {
    if (next_slot >= slot_limit) common.fail(c.ERR_DROP, "renderer_vulkan: more than {d} textures", .{slot_limit});
    texture.slot = next_slot;
    next_slot += 1;
    writeSlot(texture.slot, texture.view, sampler);
}

/// Binds an image view in `layout` to a new bindless sampler slot.
pub fn bindView(view: c.VkImageView, sampler: SamplerKind, layout: c.VkImageLayout) u32 {
    if (next_slot >= slot_limit) common.fail(c.ERR_DROP, "renderer_vulkan: more than {d} textures", .{slot_limit});
    const slot = next_slot;
    next_slot += 1;
    writeSlotLayout(slot, view, sampler, layout);
    return slot;
}

pub fn writeSlot(slot: u32, view: c.VkImageView, sampler: SamplerKind) void {
    writeSlotLayout(slot, view, sampler, c.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL);
}

pub fn writeSlotLayout(slot: u32, view: c.VkImageView, sampler: SamplerKind, layout: c.VkImageLayout) void {
    const image_info = c.VkDescriptorImageInfo{ .sampler = samplers[@intFromEnum(sampler)], .imageView = view, .imageLayout = layout };
    const write = std.mem.zeroInit(c.VkWriteDescriptorSet, .{
        .sType = c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
        .dstSet = descriptor_set,
        .dstBinding = 0,
        .dstArrayElement = slot,
        .descriptorCount = 1,
        .descriptorType = c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
        .pImageInfo = &image_info,
    });
    d.UpdateDescriptorSets.?(s.device, 1, &write, 0, null);
}

pub fn destroyBindless() void {
    if (pipeline_layout != null) d.DestroyPipelineLayout.?(s.device, pipeline_layout, null);
    if (storage_pool != null) d.DestroyDescriptorPool.?(s.device, storage_pool, null);
    if (storage_layout != null) d.DestroyDescriptorSetLayout.?(s.device, storage_layout, null);
    storage_pool = null;
    storage_layout = null;
    storage_set = null;
    if (descriptor_pool != null) d.DestroyDescriptorPool.?(s.device, descriptor_pool, null);
    if (set_layout != null) d.DestroyDescriptorSetLayout.?(s.device, set_layout, null);
    for (&samplers) |*sampler| {
        if (sampler.* != null) d.DestroySampler.?(s.device, sampler.*, null);
        sampler.* = null;
    }
    pipeline_layout = null;
    descriptor_pool = null;
    set_layout = null;
    descriptor_set = null;
}

// ---------------------------------------------------------------------------------------------
// Pipelines: blend and target format are baked; depth, cull, bias and viewport are dynamic.

pub const PipelineKey = struct {
    src: u8,
    dst: u8,
    format: c.VkFormat,
    program: u8,
    color_write: bool = true,
    /// Premultiplied UI overlay: alpha accumulates coverage for the final composite.
    overlay: bool = false,
    /// HDR alpha is multiplied by (1 - source alpha): taa.comp trusts the new frame there.
    mark_motion: bool = false,
};

var pipelines: std.AutoHashMapUnmanaged(PipelineKey, c.VkPipeline) = .empty;
var modules: [6]c.VkShaderModule = .{ null, null, null, null, null, null };

fn spirv(comptime name: []const u8) []const u32 {
    const bytes align(4) = @embedFile(name).*;
    return std.mem.bytesAsSlice(u32, &bytes);
}

fn createModule(code: []const u32) c.VkShaderModule {
    const info = std.mem.zeroInit(c.VkShaderModuleCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
        .codeSize = code.len * 4,
        .pCode = code.ptr,
    });
    var module: c.VkShaderModule = null;
    must(d.CreateShaderModule.?(s.device, &info, null, &module), "vkCreateShaderModule");
    return module;
}

pub fn createModules() void {
    modules[0] = createModule(spirv("stage.vert.spv"));
    // The ray-query variant of the stage shader needs the ray tracing tier's capability.
    modules[1] = if (ray_tracing) createModule(spirv("stage_rt.frag.spv")) else createModule(spirv("stage.frag.spv"));
    modules[2] = createModule(spirv("composite.vert.spv"));
    modules[3] = createModule(spirv("composite.frag.spv"));
    if (ray_tracing) {
        modules[4] = createModule(spirv("bake.vert.spv"));
        modules[5] = createModule(spirv("bake.frag.spv"));
    }
}

pub fn destroyPipelines() void {
    var iterator = pipelines.valueIterator();
    while (iterator.next()) |entry| d.DestroyPipeline.?(s.device, entry.*, null);
    pipelines.clearAndFree(common.gpa);
    var compute = compute_pipelines.valueIterator();
    while (compute.next()) |entry| d.DestroyPipeline.?(s.device, entry.*, null);
    compute_pipelines.clearAndFree(common.gpa);
    for (&modules) |*module| {
        if (module.* != null) d.DestroyShaderModule.?(s.device, module.*, null);
        module.* = null;
    }
}

pub const program_stage: u8 = 0;
pub const program_composite: u8 = 1;
/// Directional lightmap bake (ray tracing tier).
pub const program_bake: u8 = 2;

/// GL blend factor codes used by material state (`blend.zig` mapping).
pub fn blendFactor(code: u8) c.VkBlendFactor {
    return switch (code) {
        0 => c.VK_BLEND_FACTOR_ZERO,
        1 => c.VK_BLEND_FACTOR_ONE,
        2 => c.VK_BLEND_FACTOR_DST_COLOR,
        3 => c.VK_BLEND_FACTOR_ONE_MINUS_DST_COLOR,
        4 => c.VK_BLEND_FACTOR_SRC_ALPHA,
        5 => c.VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA,
        6 => c.VK_BLEND_FACTOR_DST_ALPHA,
        7 => c.VK_BLEND_FACTOR_ONE_MINUS_DST_ALPHA,
        8 => c.VK_BLEND_FACTOR_SRC_ALPHA_SATURATE,
        9 => c.VK_BLEND_FACTOR_SRC_COLOR,
        10 => c.VK_BLEND_FACTOR_ONE_MINUS_SRC_COLOR,
        else => c.VK_BLEND_FACTOR_ONE,
    };
}

pub fn pipeline(key: PipelineKey) c.VkPipeline {
    if (pipelines.get(key)) |existing| return existing;
    // Composite and bake passes have no depth attachment.
    const composite = key.program == program_composite or key.program == program_bake;
    const stages = [_]c.VkPipelineShaderStageCreateInfo{
        std.mem.zeroInit(c.VkPipelineShaderStageCreateInfo, .{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
            .stage = c.VK_SHADER_STAGE_VERTEX_BIT,
            .module = modules[@as(usize, key.program) * 2],
            .pName = "main",
        }),
        std.mem.zeroInit(c.VkPipelineShaderStageCreateInfo, .{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
            .stage = c.VK_SHADER_STAGE_FRAGMENT_BIT,
            .module = modules[@as(usize, key.program) * 2 + 1],
            .pName = "main",
        }),
    };
    const vertex_input = std.mem.zeroInit(c.VkPipelineVertexInputStateCreateInfo, .{ .sType = c.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO });
    const assembly = std.mem.zeroInit(c.VkPipelineInputAssemblyStateCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
        .topology = c.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
    });
    const viewport = std.mem.zeroInit(c.VkPipelineViewportStateCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
        .viewportCount = 1,
        .scissorCount = 1,
    });
    const raster = std.mem.zeroInit(c.VkPipelineRasterizationStateCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
        .polygonMode = c.VK_POLYGON_MODE_FILL,
        .cullMode = c.VK_CULL_MODE_NONE,
        .frontFace = c.VK_FRONT_FACE_COUNTER_CLOCKWISE,
        .lineWidth = 1,
    });
    const multisample = std.mem.zeroInit(c.VkPipelineMultisampleStateCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
        .rasterizationSamples = c.VK_SAMPLE_COUNT_1_BIT,
    });
    const depth = std.mem.zeroInit(c.VkPipelineDepthStencilStateCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
        .depthCompareOp = c.VK_COMPARE_OP_LESS_OR_EQUAL,
        .minDepthBounds = 0,
        .maxDepthBounds = 1,
    });
    const blending = key.src != 1 or key.dst != 0;
    const attachment = std.mem.zeroInit(c.VkPipelineColorBlendAttachmentState, .{
        .blendEnable = @as(u32, if (blending) c.VK_TRUE else c.VK_FALSE),
        .srcColorBlendFactor = blendFactor(key.src),
        .dstColorBlendFactor = blendFactor(key.dst),
        .colorBlendOp = c.VK_BLEND_OP_ADD,
        .srcAlphaBlendFactor = if (key.mark_motion) blendFactor(0) else if (key.overlay) blendFactor(if (key.dst == 1 or key.src == 0) 0 else 1) else blendFactor(key.src),
        .dstAlphaBlendFactor = if (key.mark_motion) blendFactor(5) else if (key.overlay) blendFactor(if (key.dst == 1) 1 else 5) else blendFactor(key.dst),
        .alphaBlendOp = c.VK_BLEND_OP_ADD,
        .colorWriteMask = @as(u32, if (key.color_write) c.VK_COLOR_COMPONENT_R_BIT | c.VK_COLOR_COMPONENT_G_BIT | c.VK_COLOR_COMPONENT_B_BIT | c.VK_COLOR_COMPONENT_A_BIT else 0),
    });
    // UNDEFINED format: depth-only pass (remaster shadow atlas).
    const depth_only = key.format == c.VK_FORMAT_UNDEFINED;
    const blend = std.mem.zeroInit(c.VkPipelineColorBlendStateCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
        .attachmentCount = @as(u32, if (depth_only) 0 else 1),
        .pAttachments = &attachment,
    });
    const dynamic_states = [_]c.VkDynamicState{
        c.VK_DYNAMIC_STATE_VIEWPORT,         c.VK_DYNAMIC_STATE_SCISSOR,           c.VK_DYNAMIC_STATE_CULL_MODE,
        c.VK_DYNAMIC_STATE_FRONT_FACE,       c.VK_DYNAMIC_STATE_DEPTH_TEST_ENABLE, c.VK_DYNAMIC_STATE_DEPTH_WRITE_ENABLE,
        c.VK_DYNAMIC_STATE_DEPTH_COMPARE_OP, c.VK_DYNAMIC_STATE_DEPTH_BIAS_ENABLE, c.VK_DYNAMIC_STATE_DEPTH_BIAS,
    };
    const dynamic = std.mem.zeroInit(c.VkPipelineDynamicStateCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO,
        .dynamicStateCount = dynamic_states.len,
        .pDynamicStates = &dynamic_states,
    });
    const formats = [_]c.VkFormat{key.format};
    const rendering = std.mem.zeroInit(c.VkPipelineRenderingCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_RENDERING_CREATE_INFO,
        .colorAttachmentCount = @as(u32, if (depth_only) 0 else 1),
        .pColorAttachmentFormats = &formats,
        .depthAttachmentFormat = if (composite) @as(c.VkFormat, c.VK_FORMAT_UNDEFINED) else s.depth_format,
    });
    const info = std.mem.zeroInit(c.VkGraphicsPipelineCreateInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
        .pNext = &rendering,
        .stageCount = 2,
        .pStages = &stages,
        .pVertexInputState = &vertex_input,
        .pInputAssemblyState = &assembly,
        .pViewportState = &viewport,
        .pRasterizationState = &raster,
        .pMultisampleState = &multisample,
        .pDepthStencilState = &depth,
        .pColorBlendState = &blend,
        .pDynamicState = &dynamic,
        .layout = pipeline_layout,
    });
    var created: c.VkPipeline = null;
    must(d.CreateGraphicsPipelines.?(s.device, null, 1, &info, null, &created), "vkCreateGraphicsPipelines");
    pipelines.put(common.gpa, key, created) catch @panic("OOM");
    return created;
}
