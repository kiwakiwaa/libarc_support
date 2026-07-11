#import <Foundation/Foundation.h>
#include "libarc_support/arc_runtime.h"
#include <pthread.h>

@interface WeakTracker : NSObject {
@public
    unsigned retainCalls;
    unsigned releaseCalls;
    unsigned autoreleaseCalls;
    unsigned deallocCalls;
}
@end

static unsigned gWeakTrackerDeallocs = 0;
static id gDeallocStoreSlot = nil;
static id gDeallocStoreResult = nil;

@implementation WeakTracker

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

- (void)dealloc
{
    ++deallocCalls;
    ++gWeakTrackerDeallocs;
    [super dealloc];
}

@end

@interface DeallocStoreTracker : NSObject
@end

@implementation DeallocStoreTracker

- (void)dealloc
{
    gDeallocStoreResult = objc_storeWeak(&gDeallocStoreSlot, self);
    [super dealloc];
}

@end

static void arc_weak_assert(int condition, const char *message)
{
    if (!condition) {
        fprintf(stderr, "FAIL: %s\n", message);
        exit(1);
    }
}

static void test_init_store_load_destroy(void)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    WeakTracker *object = [[WeakTracker alloc] init];
    id slot = (id)0x1;

    arc_weak_assert(objc_initWeak(&slot, object) == object, "objc_initWeak returns object");
    arc_weak_assert(slot == object, "objc_initWeak stores object");
    arc_weak_assert(object->retainCalls == 0, "objc_initWeak does not retain");

    arc_weak_assert(objc_loadWeakRetained(&slot) == object, "objc_loadWeakRetained returns object");
    arc_weak_assert(object->retainCalls == 1, "objc_loadWeakRetained retains");
    [object release];

    arc_weak_assert(objc_loadWeak(&slot) == object, "objc_loadWeak returns object");
    arc_weak_assert(object->retainCalls == 2, "objc_loadWeak retains before autorelease");
    arc_weak_assert(object->autoreleaseCalls == 1, "objc_loadWeak autoreleases");

    objc_destroyWeak(&slot);
    arc_weak_assert(slot == nil, "objc_destroyWeak clears slot");

    [pool drain];
    [object release];
}

static void test_store_replaces_and_clears(void)
{
    WeakTracker *first = [[WeakTracker alloc] init];
    WeakTracker *second = [[WeakTracker alloc] init];
    id slot = nil;

    arc_weak_assert(objc_storeWeak(&slot, first) == first, "objc_storeWeak returns first");
    arc_weak_assert(slot == first, "objc_storeWeak stores first");
    arc_weak_assert(objc_storeWeak(&slot, second) == second, "objc_storeWeak returns second");
    arc_weak_assert(slot == second, "objc_storeWeak replaces slot");
    arc_weak_assert(objc_storeWeak(&slot, nil) == nil, "objc_storeWeak nil returns nil");
    arc_weak_assert(slot == nil, "objc_storeWeak clears slot");

    [first release];
    [second release];
}

static void test_copy_and_move(void)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    WeakTracker *object = [[WeakTracker alloc] init];
    id source = nil;
    id copy = nil;
    id moved = nil;

    objc_initWeak(&source, object);
    objc_copyWeak(&copy, &source);
    arc_weak_assert(copy == object, "objc_copyWeak copies object");
    arc_weak_assert(source == object, "objc_copyWeak leaves source");

    objc_moveWeak(&moved, &copy);
    arc_weak_assert(moved == object, "objc_moveWeak moves object");
    arc_weak_assert(copy == nil, "objc_moveWeak clears source");

    objc_destroyWeak(&source);
    objc_destroyWeak(&moved);
    [pool drain];
    [object release];
}

static void test_zeroes_on_dealloc(void)
{
    id slot = nil;
    unsigned before = gWeakTrackerDeallocs;
    WeakTracker *object = [[WeakTracker alloc] init];

    objc_initWeak(&slot, object);
    arc_weak_assert(slot == object, "weak slot set before dealloc");
    [object release];
    arc_weak_assert(gWeakTrackerDeallocs == before + 1, "object deallocated");
    arc_weak_assert(slot == nil, "weak slot zeroed by dealloc");
}

static void test_store_during_dealloc_stores_nil(void)
{
    id swizzleSlot = nil;
    DeallocStoreTracker *object = [[DeallocStoreTracker alloc] init];

    gDeallocStoreSlot = (id)0x1;
    gDeallocStoreResult = (id)0x1;

    objc_initWeak(&swizzleSlot, object);
    [object release];

    arc_weak_assert(swizzleSlot == nil, "existing weak slot zeroed before dealloc body store");
    arc_weak_assert(gDeallocStoreResult == nil, "objc_storeWeak returns nil for deallocating target");
    arc_weak_assert(gDeallocStoreSlot == nil, "objc_storeWeak stores nil for deallocating target");
}

struct WeakRaceContext
{
    id slot;
    WeakTracker *object;
};

static void *weak_race_store_thread(void *ptr)
{
    struct WeakRaceContext *context = (struct WeakRaceContext *)ptr;
    int i;

    for (i = 0; i < 1000; ++i) {
        objc_storeWeak(&context->slot, (i & 1) ? context->object : nil);
    }

    return NULL;
}

static void *weak_race_load_thread(void *ptr)
{
    struct WeakRaceContext *context = (struct WeakRaceContext *)ptr;
    int i;

    for (i = 0; i < 1000; ++i) {
        id loaded = objc_loadWeakRetained(&context->slot);
        if (loaded != nil) {
            arc_weak_assert(loaded == context->object, "weak race loaded expected object");
            [loaded release];
        }
    }

    return NULL;
}

static void test_store_load_race_smoke(void)
{
    struct WeakRaceContext context;
    pthread_t storeThread;
    pthread_t loadThread;

    context.slot = nil;
    context.object = [[WeakTracker alloc] init];
    objc_initWeak(&context.slot, context.object);

    arc_weak_assert(pthread_create(&storeThread, NULL, weak_race_store_thread, &context) == 0, "weak race store thread create");
    arc_weak_assert(pthread_create(&loadThread, NULL, weak_race_load_thread, &context) == 0, "weak race load thread create");
    arc_weak_assert(pthread_join(storeThread, NULL) == 0, "weak race store thread join");
    arc_weak_assert(pthread_join(loadThread, NULL) == 0, "weak race load thread join");

    objc_destroyWeak(&context.slot);
    [context.object release];
}

int main(void)
{
    test_init_store_load_destroy();
    test_store_replaces_and_clears();
    test_copy_and_move();
    test_zeroes_on_dealloc();
    test_store_during_dealloc_stores_nil();
    test_store_load_race_smoke();
    puts("PASS arc_weak_lifetime");
    return 0;
}
