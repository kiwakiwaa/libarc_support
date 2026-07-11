#import <Foundation/Foundation.h>
#include "libarc_support/arc_runtime.h"

static unsigned gAllocCalls;
static unsigned gAllocWithZoneCalls;
static unsigned gInitCalls;

@interface AllocTracker : NSObject
@end

@implementation AllocTracker

+ (id)alloc
{
    ++gAllocCalls;
    return [super alloc];
}

+ (id)allocWithZone:(NSZone *)zone
{
    if (zone == NULL) {
        ++gAllocWithZoneCalls;
    }
    return [super allocWithZone:zone];
}

- (id)init
{
    ++gInitCalls;
    return [super init];
}

@end

static void arc_alloc_assert(int condition, const char *message)
{
    if (!condition) {
        fprintf(stderr, "FAIL: %s\n", message);
        exit(1);
    }
}

static void reset_counts(void)
{
    gAllocCalls = 0;
    gAllocWithZoneCalls = 0;
    gInitCalls = 0;
}

static void test_nil_class(void)
{
    arc_alloc_assert(objc_alloc(Nil) == nil, "objc_alloc(Nil) returns nil");
    arc_alloc_assert(objc_allocWithZone(Nil) == nil, "objc_allocWithZone(Nil) returns nil");
    arc_alloc_assert(objc_alloc_init(Nil) == nil, "objc_alloc_init(Nil) returns nil");
}

static void test_alloc_message(void)
{
    reset_counts();

    id object = objc_alloc([AllocTracker class]);
    arc_alloc_assert(object != nil, "objc_alloc returns object");
    arc_alloc_assert(gAllocCalls == 1, "objc_alloc sends +alloc");
    arc_alloc_assert(gInitCalls == 0, "objc_alloc does not send -init");

    [object release];
}

static void test_alloc_with_zone_message(void)
{
    reset_counts();

    id object = objc_allocWithZone([AllocTracker class]);
    arc_alloc_assert(object != nil, "objc_allocWithZone returns object");
    arc_alloc_assert(gAllocCalls == 0, "objc_allocWithZone does not send +alloc");
    arc_alloc_assert(gAllocWithZoneCalls == 1, "objc_allocWithZone sends +allocWithZone:nil");
    arc_alloc_assert(gInitCalls == 0, "objc_allocWithZone does not send -init");

    [object release];
}

static void test_alloc_init_message(void)
{
    reset_counts();

    id object = objc_alloc_init([AllocTracker class]);
    arc_alloc_assert(object != nil, "objc_alloc_init returns object");
    arc_alloc_assert(gAllocCalls == 1, "objc_alloc_init sends +alloc");
    arc_alloc_assert(gInitCalls == 1, "objc_alloc_init sends -init");

    [object release];
}

int main(void)
{
    test_nil_class();
    test_alloc_message();
    test_alloc_with_zone_message();
    test_alloc_init_message();
    puts("PASS arc_alloc_lifetime");
    return 0;
}
