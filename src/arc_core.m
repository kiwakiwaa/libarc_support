#include "libarc_support/arc_runtime.h"

#if defined(__has_feature)
#if __has_feature(objc_arc)
#error libarc_support runtime sources must be compiled without ARC.
#endif
#endif

@protocol LibarcSupportRetainRelease
- (id)retain;
- (oneway void)release;
- (id)autorelease;
@end

extern void *_Block_copy(const void *aBlock);

libarc_support_id objc_retain(libarc_support_id value)
{
    return [(id<LibarcSupportRetainRelease>)value retain];
}

void objc_release(libarc_support_id value)
{
    [(id<LibarcSupportRetainRelease>)value release];
}

libarc_support_id objc_autorelease(libarc_support_id value)
{
    return [(id<LibarcSupportRetainRelease>)value autorelease];
}

libarc_support_id objc_retainAutorelease(libarc_support_id value)
{
    return objc_autorelease(objc_retain(value));
}

libarc_support_id objc_autoreleaseReturnValue(libarc_support_id value)
{
    return objc_autorelease(value);
}

libarc_support_id objc_retainAutoreleaseReturnValue(libarc_support_id value)
{
    return objc_autoreleaseReturnValue(objc_retain(value));
}

libarc_support_id objc_retainAutoreleasedReturnValue(libarc_support_id value)
{
    return objc_retain(value);
}

libarc_support_id objc_unsafeClaimAutoreleasedReturnValue(libarc_support_id value)
{
    return value;
}

void objc_storeStrong(libarc_support_id *object, libarc_support_id value)
{
    libarc_support_id oldValue = *object;

    if (oldValue == value) {
        return;
    }

    value = objc_retain(value);
    *object = value;
    objc_release(oldValue);
}

libarc_support_id objc_retainBlock(libarc_support_id value)
{
    return (libarc_support_id)_Block_copy(value);
}
