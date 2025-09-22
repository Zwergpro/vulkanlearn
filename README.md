
# vulkanlearn

A small learning project using Zig and Vulkan (with GLFW) to explore the basics of creating a Vulkan instance, selecting devices/queues, and opening a window.

## Prerequisites
- Zig 0.15.1 or newer
- Vulkan SDK installed and available on your system
  - macOS uses MoltenVK (included in the Vulkan SDK)

## Build
```bash
zig build
```

## Run
```bash
zig build run
```

## Setting up the Vulkan SDK

### macOS
[Docs](https://vulkan.lunarg.com/doc/sdk/1.4.321.0/mac/getting_started.html)
```bash
export VULKAN_SDK="$HOME/VulkanSDK/1.3.x.x/macOS"
export PATH="$PATH:$VULKAN_SDK/bin"
export DYLD_LIBRARY_PATH="$VULKAN_SDK/lib:${DYLD_LIBRARY_PATH:-}"
```


Notes
- This is a personal learning project; things may change frequently.
