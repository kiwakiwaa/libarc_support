#include "libarc_support/arc_runtime.h"

#include <pthread.h>

#import <Foundation/NSException.h>
#import <Foundation/NSString.h>

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

@protocol LibarcSupportCopying
- (id)copy;
- (id)mutableCopy;
@end

static pthread_mutex_t PropertyLock = PTHREAD_MUTEX_INITIALIZER;

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

void libarc_support_clear_copied_object_pointer(void *object)
{
    // fragile runtime copies bitwise-copy ARC object pointer slots.
    // clear the copied slot before ARC stores into it so the destination is initialised
    // instead of mistaken for an already-owned value.
    *(void **)object = 0;
}

libarc_support_id objc_getProperty(libarc_support_id object, void *selector, ptrdiff_t offset, int atomic)
{
    (void)selector;
    libarc_support_id *slot = (libarc_support_id *)((char *)object + offset);

    if (!atomic) {
        return *slot;
    }

    pthread_mutex_lock(&PropertyLock);
    libarc_support_id value = objc_retain(*slot);
    pthread_mutex_unlock(&PropertyLock);
    return objc_autorelease(value);
}

void objc_setProperty(
    libarc_support_id object,
    void *selector,
    ptrdiff_t offset,
    libarc_support_id value,
    int atomic,
    signed char copy)
{
    (void)selector;
    libarc_support_id *slot = (libarc_support_id *)((char *)object + offset);
    libarc_support_id newValue;

    if (copy == 2) {
        newValue = [(id<LibarcSupportCopying>)value mutableCopy];
    }
    else if (copy != 0) {
        newValue = [(id<LibarcSupportCopying>)value copy];
    }
    else {
        newValue = objc_retain(value);
    }

    if (atomic) {
        pthread_mutex_lock(&PropertyLock);
    }
    libarc_support_id oldValue = *slot;
    *slot = newValue;
    if (atomic) {
        pthread_mutex_unlock(&PropertyLock);
    }
    objc_release(oldValue);
}

void objc_enumerationMutation(libarc_support_id object)
{
    [NSException raise:NSGenericException format:@"Collection %@ was mutated while being enumerated.", object];
    __builtin_unreachable();
}
