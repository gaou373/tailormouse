#include "NativeHIDBridge.h"
#include <dlfcn.h>
IOHIDEventSystemClientRef TMCreatePointerClient(void) {
    typedef IOHIDEventSystemClientRef (*Create)(CFAllocatorRef);
    Create create = (Create)dlsym(RTLD_DEFAULT, "IOHIDEventSystemClientCreate");
    return create ? create(kCFAllocatorDefault) : NULL;
}
