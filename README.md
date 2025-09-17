



### Setup Vulkan Env
```bash
# Vulkan
export VULKAN_SDK="/usr/local/vulkan/macOS"
export PATH="$PATH:$VULKAN_SDK/bin"
export DYLD_LIBRARY_PATH="$VULKAN_SDK/lib:${DYLD_LIBRARY_PATH:-}"
```
