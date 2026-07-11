#import <Foundation/Foundation.h>
#include "libarc_support/arc_runtime.h"

@interface RVTracker : NSObject {
@public
    unsigned retainCalls;
    unsigned releaseCalls;
    unsigned autoreleaseCalls;
}
@end

@implementation RVTracker

- (id)retain
{
    ++retainCalls;
    return [super retain];
}

- (oneway void)release
{
    ++releaseCalls;
    [super release];
}

- (id)autorelease
{
    ++autoreleaseCalls;
    return [super autorelease];
}

@end

static void arc_rv_assert(int condition, const char *message)
{
    if (!condition) {
        fprintf(stderr, "FAIL: %s\n", message);
        exit(1);
    }
}

static void test_nil(void)
{
    arc_rv_assert(objc_retainAutorelease(nil) == nil, "objc_retainAutorelease(nil)");
    arc_rv_assert(objc_autoreleaseReturnValue(nil) == nil, "objc_autoreleaseReturnValue(nil)");
    arc_rv_assert(objc_retainAutoreleaseReturnValue(nil) == nil, "objc_retainAutoreleaseReturnValue(nil)");
    arc_rv_assert(objc_retainAutoreleasedReturnValue(nil) == nil, "objc_retainAutoreleasedReturnValue(nil)");
    arc_rv_assert(objc_unsafeClaimAutoreleasedReturnValue(nil) == nil, "objc_unsafeClaimAutoreleasedReturnValue(nil)");
}

static RVTracker *new_tracker(void)
{
    return [[RVTracker alloc] init];
}

static void test_retain_autorelease(void)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    RVTracker *object = new_tracker();

    arc_rv_assert(objc_retainAutorelease(object) == object, "objc_retainAutorelease returns object");
    arc_rv_assert(object->retainCalls == 1, "objc_retainAutorelease retains once");
    arc_rv_assert(object->autoreleaseCalls == 1, "objc_retainAutorelease autoreleases once");
    arc_rv_assert(object->releaseCalls == 0, "objc_retainAutorelease does not release immediately");

    [pool drain];
    [object release];
}

static void test_autorelease_return_value(void)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    RVTracker *object = new_tracker();

    arc_rv_assert(objc_autoreleaseReturnValue(object) == object, "objc_autoreleaseReturnValue returns object");
    arc_rv_assert(object->retainCalls == 0, "objc_autoreleaseReturnValue does not retain fallback");
    arc_rv_assert(object->autoreleaseCalls == 1, "objc_autoreleaseReturnValue autoreleases fallback");
    arc_rv_assert(object->releaseCalls == 0, "objc_autoreleaseReturnValue does not release immediately");

    [pool drain];
}

static void test_retain_autorelease_return_value(void)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    RVTracker *object = new_tracker();

    arc_rv_assert(objc_retainAutoreleaseReturnValue(object) == object, "objc_retainAutoreleaseReturnValue returns object");
    arc_rv_assert(object->retainCalls == 1, "objc_retainAutoreleaseReturnValue retains once");
    arc_rv_assert(object->autoreleaseCalls == 1, "objc_retainAutoreleaseReturnValue autoreleases fallback");
    arc_rv_assert(object->releaseCalls == 0, "objc_retainAutoreleaseReturnValue does not release immediately");

    [pool drain];
    [object release];
}

static void test_retain_autoreleased_return_value(void)
{
    RVTracker *object = new_tracker();

    arc_rv_assert(objc_retainAutoreleasedReturnValue(object) == object, "objc_retainAutoreleasedReturnValue returns object");
    arc_rv_assert(object->retainCalls == 1, "objc_retainAutoreleasedReturnValue retains fallback");
    arc_rv_assert(object->autoreleaseCalls == 0, "objc_retainAutoreleasedReturnValue does not autorelease fallback");
    arc_rv_assert(object->releaseCalls == 0, "objc_retainAutoreleasedReturnValue does not release immediately");

    [object release];
    [object release];
}

static void test_unsafe_claim_autoreleased_return_value(void)
{
    RVTracker *object = new_tracker();

    arc_rv_assert(objc_unsafeClaimAutoreleasedReturnValue(object) == object, "objc_unsafeClaimAutoreleasedReturnValue returns object");
    arc_rv_assert(object->retainCalls == 0, "objc_unsafeClaimAutoreleasedReturnValue fallback does not retain");
    arc_rv_assert(object->autoreleaseCalls == 0, "objc_unsafeClaimAutoreleasedReturnValue fallback does not autorelease");
    arc_rv_assert(object->releaseCalls == 0, "objc_unsafeClaimAutoreleasedReturnValue fallback does not release");

    [object release];
}

int main(void)
{
    test_nil();
    test_retain_autorelease();
    test_autorelease_return_value();
    test_retain_autorelease_return_value();
    test_retain_autoreleased_return_value();
    test_unsafe_claim_autoreleased_return_value();
    puts("PASS arc_return_value_lifetime");
    return 0;
}
