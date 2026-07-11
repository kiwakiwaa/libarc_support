#import <Foundation/Foundation.h>
#include "libarc_support/arc_runtime.h"
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

#define STABLE_OBJECT_COUNT 16
#define WEAK_SLOT_COUNT 8
#define STORE_THREAD_COUNT 4
#define LOAD_THREAD_COUNT 4
#define RACE_ITERATIONS 12000
#define DEALLOC_LOAD_THREAD_COUNT 6
#define MANY_OBJECT_COUNT 96
#define MANY_SLOT_COUNT 384
#define POOL_THREAD_COUNT 4
#define POOL_ITERATIONS 1200

#if defined(ARC_WEAK_TESTING)
size_t arc_weak_debug_deallocating_object_count(void);
#define ASSERT_NO_DEALLOCATING_MARKERS(message) \
    arc_concurrency_assert(arc_weak_debug_deallocating_object_count() == 0, message)
#else
#define ASSERT_NO_DEALLOCATING_MARKERS(message) ((void)0)
#endif

@interface StressObject : NSObject {
@public
    unsigned token;
}
- (id)initWithToken:(unsigned)value;
@end

static unsigned gStressDeallocs = 0;

@implementation StressObject

- (id)initWithToken:(unsigned)value
{
    self = [super init];
    if (self != nil) {
        token = value;
    }
    return self;
}

- (void)dealloc
{
    ++gStressDeallocs;
    [super dealloc];
}

@end

@interface DeallocRaceObject : StressObject
@end

static unsigned gDeallocRaceDeallocs = 0;

@implementation DeallocRaceObject

- (void)dealloc
{
    ++gDeallocRaceDeallocs;
    [super dealloc];
}

@end

@interface ReentrantWeakObject : StressObject
@end

static id gReentrantPeerSlot = nil;
static id gReentrantSelfStoreSlot = nil;
static id gReentrantSelfStoreResult = nil;
static unsigned gReentrantLoadedPeer = 0;
static unsigned gReentrantDeallocs = 0;

@implementation ReentrantWeakObject

- (void)dealloc
{
    id loaded = objc_loadWeakRetained(&gReentrantPeerSlot);
    if (loaded != nil) {
        ++gReentrantLoadedPeer;
        [loaded release];
    }

    gReentrantSelfStoreResult = objc_storeWeak(&gReentrantSelfStoreSlot, self);
    ++gReentrantDeallocs;
    [super dealloc];
}

@end

struct StartGate
{
    pthread_mutex_t mutex;
    pthread_cond_t cond;
    int ready;
    int go;
    int target;
};

struct StableRaceContext
{
    struct StartGate *gate;
    id *slots;
    StressObject **objects;
    int threadIndex;
};

struct DeallocLoadContext
{
    struct StartGate *gate;
    volatile int *stop;
    id *slot;
    id expected;
};

struct PoolChurnContext
{
    struct StartGate *gate;
    int threadIndex;
};

static pthread_mutex_t gAssertMutex = PTHREAD_MUTEX_INITIALIZER;

static void arc_concurrency_assert(int condition, const char *message)
{
    if (!condition) {
        pthread_mutex_lock(&gAssertMutex);
        fprintf(stderr, "FAIL: %s\n", message);
        fflush(stderr);
        pthread_mutex_unlock(&gAssertMutex);
        exit(1);
    }
}

static void gate_init(struct StartGate *gate, int target)
{
    pthread_mutex_init(&gate->mutex, NULL);
    pthread_cond_init(&gate->cond, NULL);
    gate->ready = 0;
    gate->go = 0;
    gate->target = target;
}

static void gate_destroy(struct StartGate *gate)
{
    pthread_cond_destroy(&gate->cond);
    pthread_mutex_destroy(&gate->mutex);
}

static void gate_wait(struct StartGate *gate)
{
    pthread_mutex_lock(&gate->mutex);
    ++gate->ready;
    if (gate->ready == gate->target) {
        pthread_cond_broadcast(&gate->cond);
    }
    while (!gate->go) {
        pthread_cond_wait(&gate->cond, &gate->mutex);
    }
    pthread_mutex_unlock(&gate->mutex);
}

static void gate_open_when_ready(struct StartGate *gate)
{
    pthread_mutex_lock(&gate->mutex);
    while (gate->ready != gate->target) {
        pthread_cond_wait(&gate->cond, &gate->mutex);
    }
    gate->go = 1;
    pthread_cond_broadcast(&gate->cond);
    pthread_mutex_unlock(&gate->mutex);
}

static int is_stable_object(StressObject **objects, id value)
{
    int i;

    for (i = 0; i < STABLE_OBJECT_COUNT; ++i) {
        if (value == objects[i]) {
            return 1;
        }
    }

    return 0;
}

static void *stable_store_thread(void *arg)
{
    struct StableRaceContext *context = (struct StableRaceContext *)arg;
    int i;

    gate_wait(context->gate);

    for (i = 0; i < RACE_ITERATIONS; ++i) {
        int slotIndex = (i + context->threadIndex) % WEAK_SLOT_COUNT;
        id value = ((i + context->threadIndex) % 5 == 0)
            ? nil
            : context->objects[(i + context->threadIndex * 3) % STABLE_OBJECT_COUNT];

        objc_storeWeak(&context->slots[slotIndex], value);
    }

    return NULL;
}

static void *stable_load_thread(void *arg)
{
    struct StableRaceContext *context = (struct StableRaceContext *)arg;
    int i;

    gate_wait(context->gate);

    for (i = 0; i < RACE_ITERATIONS; ++i) {
        int slotIndex = (i * 3 + context->threadIndex) % WEAK_SLOT_COUNT;
        id loaded = objc_loadWeakRetained(&context->slots[slotIndex]);
        if (loaded != nil) {
            arc_concurrency_assert(is_stable_object(context->objects, loaded), "stable race loaded unknown object");
            [loaded release];
        }
    }

    return NULL;
}

static void test_concurrent_weak_stores_and_loads(void)
{
    StressObject *objects[STABLE_OBJECT_COUNT];
    id slots[WEAK_SLOT_COUNT];
    pthread_t storeThreads[STORE_THREAD_COUNT];
    pthread_t loadThreads[LOAD_THREAD_COUNT];
    struct StableRaceContext storeContexts[STORE_THREAD_COUNT];
    struct StableRaceContext loadContexts[LOAD_THREAD_COUNT];
    struct StartGate gate;
    int i;

    for (i = 0; i < STABLE_OBJECT_COUNT; ++i) {
        objects[i] = [[StressObject alloc] initWithToken:(unsigned)i];
    }
    for (i = 0; i < WEAK_SLOT_COUNT; ++i) {
        slots[i] = nil;
        objc_initWeak(&slots[i], objects[i % STABLE_OBJECT_COUNT]);
    }

    gate_init(&gate, STORE_THREAD_COUNT + LOAD_THREAD_COUNT);

    for (i = 0; i < STORE_THREAD_COUNT; ++i) {
        storeContexts[i].gate = &gate;
        storeContexts[i].slots = slots;
        storeContexts[i].objects = objects;
        storeContexts[i].threadIndex = i;
        arc_concurrency_assert(pthread_create(&storeThreads[i], NULL, stable_store_thread, &storeContexts[i]) == 0, "stable store thread create");
    }
    for (i = 0; i < LOAD_THREAD_COUNT; ++i) {
        loadContexts[i].gate = &gate;
        loadContexts[i].slots = slots;
        loadContexts[i].objects = objects;
        loadContexts[i].threadIndex = i;
        arc_concurrency_assert(pthread_create(&loadThreads[i], NULL, stable_load_thread, &loadContexts[i]) == 0, "stable load thread create");
    }

    gate_open_when_ready(&gate);

    for (i = 0; i < STORE_THREAD_COUNT; ++i) {
        arc_concurrency_assert(pthread_join(storeThreads[i], NULL) == 0, "stable store thread join");
    }
    for (i = 0; i < LOAD_THREAD_COUNT; ++i) {
        arc_concurrency_assert(pthread_join(loadThreads[i], NULL) == 0, "stable load thread join");
    }

    for (i = 0; i < WEAK_SLOT_COUNT; ++i) {
        objc_destroyWeak(&slots[i]);
    }
    for (i = 0; i < STABLE_OBJECT_COUNT; ++i) {
        [objects[i] release];
    }

    gate_destroy(&gate);
    ASSERT_NO_DEALLOCATING_MARKERS("stable race left deallocating marker");
}

static void *dealloc_load_thread(void *arg)
{
    struct DeallocLoadContext *context = (struct DeallocLoadContext *)arg;

    gate_wait(context->gate);

    while (!*context->stop) {
        id loaded = objc_loadWeakRetained(context->slot);
        if (loaded != nil) {
            arc_concurrency_assert(loaded == context->expected, "dealloc race loaded unexpected object");
            [loaded release];
        }
    }

    return NULL;
}

static void test_concurrent_dealloc_while_loading(void)
{
    DeallocRaceObject *object = [[DeallocRaceObject alloc] initWithToken:777];
    id slot = nil;
    pthread_t threads[DEALLOC_LOAD_THREAD_COUNT];
    struct DeallocLoadContext contexts[DEALLOC_LOAD_THREAD_COUNT];
    struct StartGate gate;
    volatile int stop = 0;
    unsigned before = gDeallocRaceDeallocs;
    int i;

    objc_initWeak(&slot, object);
    gate_init(&gate, DEALLOC_LOAD_THREAD_COUNT);

    for (i = 0; i < DEALLOC_LOAD_THREAD_COUNT; ++i) {
        contexts[i].gate = &gate;
        contexts[i].stop = &stop;
        contexts[i].slot = &slot;
        contexts[i].expected = object;
        arc_concurrency_assert(pthread_create(&threads[i], NULL, dealloc_load_thread, &contexts[i]) == 0, "dealloc load thread create");
    }

    gate_open_when_ready(&gate);
    usleep(20000);
    [object release];
    stop = 1;

    for (i = 0; i < DEALLOC_LOAD_THREAD_COUNT; ++i) {
        arc_concurrency_assert(pthread_join(threads[i], NULL) == 0, "dealloc load thread join");
    }

    arc_concurrency_assert(gDeallocRaceDeallocs == before + 1, "dealloc race object deallocated once");
    arc_concurrency_assert(slot == nil, "dealloc race weak slot zeroed");

    gate_destroy(&gate);
    ASSERT_NO_DEALLOCATING_MARKERS("dealloc load race left deallocating marker");
}

static void test_reentrant_dealloc_touching_weak_refs(void)
{
    StressObject *peer = [[StressObject alloc] initWithToken:901];
    ReentrantWeakObject *object = [[ReentrantWeakObject alloc] initWithToken:902];
    id observeSlot = nil;
    unsigned before = gReentrantDeallocs;

    gReentrantPeerSlot = nil;
    gReentrantSelfStoreSlot = (id)0x1;
    gReentrantSelfStoreResult = (id)0x1;
    gReentrantLoadedPeer = 0;

    objc_initWeak(&gReentrantPeerSlot, peer);
    objc_initWeak(&observeSlot, object);
    [object release];

    arc_concurrency_assert(gReentrantDeallocs == before + 1, "reentrant object deallocated");
    arc_concurrency_assert(gReentrantLoadedPeer == 1, "reentrant dealloc loaded peer weak ref");
    arc_concurrency_assert(gReentrantSelfStoreResult == nil, "reentrant dealloc store returned nil for self");
    arc_concurrency_assert(gReentrantSelfStoreSlot == nil, "reentrant dealloc store wrote nil for self");
    arc_concurrency_assert(observeSlot == nil, "reentrant observe slot zeroed");

    objc_destroyWeak(&gReentrantPeerSlot);
    objc_destroyWeak(&gReentrantSelfStoreSlot);
    objc_destroyWeak(&observeSlot);
    [peer release];
    ASSERT_NO_DEALLOCATING_MARKERS("reentrant dealloc left deallocating marker");
}

static void test_many_weak_refs_many_objects(void)
{
    StressObject *objects[MANY_OBJECT_COUNT];
    id slots[MANY_SLOT_COUNT];
    int slotOwner[MANY_SLOT_COUNT];
    int i;
    int j;

    for (i = 0; i < MANY_OBJECT_COUNT; ++i) {
        objects[i] = [[StressObject alloc] initWithToken:(unsigned)(10000 + i)];
    }

    for (i = 0; i < MANY_SLOT_COUNT; ++i) {
        slotOwner[i] = i % MANY_OBJECT_COUNT;
        slots[i] = nil;
        objc_initWeak(&slots[i], objects[slotOwner[i]]);
    }

    for (i = 0; i < MANY_OBJECT_COUNT; ++i) {
        [objects[i] release];
        for (j = 0; j < MANY_SLOT_COUNT; ++j) {
            if (slotOwner[j] == i) {
                arc_concurrency_assert(slots[j] == nil, "many refs released object slot zeroed");
            }
        }
    }

    for (i = 0; i < MANY_SLOT_COUNT; ++i) {
        arc_concurrency_assert(slots[i] == nil, "many refs final slot nil");
        objc_destroyWeak(&slots[i]);
    }
    ASSERT_NO_DEALLOCATING_MARKERS("many refs left deallocating marker");
}

static void *pool_churn_thread(void *arg)
{
    struct PoolChurnContext *context = (struct PoolChurnContext *)arg;
    int i;

    gate_wait(context->gate);

    for (i = 0; i < POOL_ITERATIONS; ++i) {
        id slot = nil;
        void *pool = objc_autoreleasePoolPush();
        StressObject *object = [[[StressObject alloc] initWithToken:(unsigned)(context->threadIndex * POOL_ITERATIONS + i)] autorelease];
        id loaded;

        objc_initWeak(&slot, object);
        arc_concurrency_assert(slot == object, "pool churn weak init stores object before pop");
        loaded = objc_loadWeakRetained(&slot);
        if (loaded != object) {
#if defined(ARC_WEAK_TESTING)
            fprintf(stderr, "pool churn mismatch thread=%d iter=%d object=%p slot=%p loaded=%p deallocMarkers=%lu\n",
                context->threadIndex, i, object, slot, loaded, (unsigned long)arc_weak_debug_deallocating_object_count());
#else
            fprintf(stderr, "pool churn mismatch thread=%d iter=%d object=%p slot=%p loaded=%p\n",
                context->threadIndex, i, object, slot, loaded);
#endif
        }
        arc_concurrency_assert(loaded == object, "pool churn loaded object before pop");
        [loaded release];

        objc_autoreleasePoolPop(pool);
        arc_concurrency_assert(slot == nil, "pool churn weak slot zeroed after pop");
        objc_destroyWeak(&slot);
    }

    return NULL;
}

static void test_autorelease_pool_churn_under_threads(void)
{
    pthread_t threads[POOL_THREAD_COUNT];
    struct PoolChurnContext contexts[POOL_THREAD_COUNT];
    struct StartGate gate;
    int i;

    gate_init(&gate, POOL_THREAD_COUNT);

    for (i = 0; i < POOL_THREAD_COUNT; ++i) {
        contexts[i].gate = &gate;
        contexts[i].threadIndex = i;
        arc_concurrency_assert(pthread_create(&threads[i], NULL, pool_churn_thread, &contexts[i]) == 0, "pool churn thread create");
    }

    gate_open_when_ready(&gate);

    for (i = 0; i < POOL_THREAD_COUNT; ++i) {
        arc_concurrency_assert(pthread_join(threads[i], NULL) == 0, "pool churn thread join");
    }

    gate_destroy(&gate);
    ASSERT_NO_DEALLOCATING_MARKERS("pool churn left deallocating marker");
}

int main(void)
{
    test_concurrent_weak_stores_and_loads();
    test_concurrent_dealloc_while_loading();
    test_reentrant_dealloc_touching_weak_refs();
    test_many_weak_refs_many_objects();
    test_autorelease_pool_churn_under_threads();
    puts("PASS arc_weak_concurrency");
    return 0;
}
