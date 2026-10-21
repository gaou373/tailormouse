#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/hidsystem/IOHIDEventSystemClient.h>
// Nullable runtime lookup: this exported client-creation SPI is not guaranteed
// by the public SDK. Property operations use the SDK's service APIs.
CF_RETURNS_RETAINED IOHIDEventSystemClientRef _Nullable TMCreatePointerClient(void);
