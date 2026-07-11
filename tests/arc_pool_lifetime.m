#import <Foundation/Foundation.h>
#include "libarc_support/arc_runtime.h"

enum {
    PoolTrackerOuter = 1,
    PoolTrackerInner = 2
};

@interface PoolTracker : NSObject {
@public
    unsigned kind;
    unsigned autoreleaseCalls;
}
- (id)initWithKind:(unsigned)value;
@end

static unsigned gOuterDeallocs = 0;
static unsigned gInnerDeallocs = 0;

@implementation PoolTracker

- (id)initWithKind:(unsigned)value
{
    self = [super init];
    if (self != nil) {
        kind = value;
    }
    return self;
}

- (id)autorelease
{
    ++autoreleaseCalls;
    return [super autorelease];
}

- (void)dealloc
{
    if (kind == PoolTrackerOuter) {
        ++gOuterDeallocs;
    } else if (kind == PoolTrackerInner) {
        ++gInnerDeallocs;
    }
    [super dealloc];
}

@end

static void arc_pool_assert(int condition, const char *message)
{
    if (!condition) {
        fprintf(stderr, "FAIL: %s\n", message);
        exit(1);
    }
}

static PoolTracker *autoreleased_tracker(unsigned kind)
{
    return [[[PoolTracker alloc] initWithKind:kind] autorelease];
}

static void test_push_pop_drains_pool(void)
{
    unsigned outerBefore = gOuterDeallocs;
    void *pool = objc_autoreleasePoolPush();
    PoolTracker *object = autoreleased_tracker(PoolTrackerOuter);

    arc_pool_assert(pool != NULL, "objc_autoreleasePoolPush returns pool token");
    arc_pool_assert(object->autoreleaseCalls == 1, "object was autoreleased into pushed pool");
    arc_pool_assert(gOuterDeallocs == outerBefore, "object is alive before pop");

    objc_autoreleasePoolPop(pool);
    arc_pool_assert(gOuterDeallocs == outerBefore + 1, "object deallocated by pop");
}

static void test_nested_pools_drain_inside_out(void)
{
    unsigned outerBefore = gOuterDeallocs;
    unsigned innerBefore = gInnerDeallocs;
    void *outerPool = objc_autoreleasePoolPush();

    autoreleased_tracker(PoolTrackerOuter);

    void *innerPool = objc_autoreleasePoolPush();
    autoreleased_tracker(PoolTrackerInner);

    objc_autoreleasePoolPop(innerPool);
    arc_pool_assert(gInnerDeallocs == innerBefore + 1, "inner object deallocated by inner pop");
    arc_pool_assert(gOuterDeallocs == outerBefore, "outer object survives inner pop");

    objc_autoreleasePoolPop(outerPool);
    arc_pool_assert(gOuterDeallocs == outerBefore + 1, "outer object deallocated by outer pop");
}

int main(void)
{
    test_push_pop_drains_pool();
    test_nested_pools_drain_inside_out();
    puts("PASS arc_pool_lifetime");
    return 0;
}
