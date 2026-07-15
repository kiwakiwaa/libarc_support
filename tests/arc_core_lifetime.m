#import <Foundation/Foundation.h>
#include "libarc_support/arc_runtime.h"

extern void _Block_release(const void *aBlock);

@interface Tracker : NSObject {
@public
    unsigned retainCalls;
    unsigned releaseCalls;
    unsigned autoreleaseCalls;
}
@end

@implementation Tracker

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

static int blockValue = 0;

static void arc_test_assert(int condition, const char *message)
{
    if (!condition) {
        fprintf(stderr, "FAIL: %s\n", message);
        exit(1);
    }
}

static void test_nil(void)
{
    arc_test_assert(objc_retain(nil) == nil, "objc_retain(nil) returns nil");
    objc_release(nil);
    arc_test_assert(objc_autorelease(nil) == nil, "objc_autorelease(nil) returns nil");
}

static void test_forwarding(void)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    Tracker *object = [[Tracker alloc] init];

    arc_test_assert(objc_retain(object) == object, "objc_retain returns receiver");
    arc_test_assert(object->retainCalls == 1, "objc_retain forwards retain once");

    objc_release(object);
    arc_test_assert(object->releaseCalls == 1, "objc_release forwards release once");

    arc_test_assert(objc_autorelease(object) == object, "objc_autorelease returns receiver");
    arc_test_assert(object->autoreleaseCalls == 1, "objc_autorelease forwards autorelease once");

    [pool drain];
}

static void test_store_strong_empty_slot(void)
{
    Tracker *object = [[Tracker alloc] init];
    id slot = nil;

    objc_storeStrong(&slot, object);
    arc_test_assert(slot == object, "objc_storeStrong stores object");
    arc_test_assert(object->retainCalls == 1, "objc_storeStrong retains new object");
    arc_test_assert(object->releaseCalls == 0, "objc_storeStrong does not release nil old value");

    objc_release(object);
    objc_storeStrong(&slot, nil);
}

static void test_store_strong_replace(void)
{
    Tracker *oldObject = [[Tracker alloc] init];
    Tracker *newObject = [[Tracker alloc] init];
    id slot = oldObject;

    objc_storeStrong(&slot, newObject);
    arc_test_assert(slot == newObject, "objc_storeStrong replaces slot");
    arc_test_assert(newObject->retainCalls == 1, "objc_storeStrong retains replacement");
    arc_test_assert(oldObject->releaseCalls == 1, "objc_storeStrong releases old value");

    objc_release(newObject);
    objc_storeStrong(&slot, nil);
}

static void test_store_strong_clear(void)
{
    Tracker *object = [[Tracker alloc] init];
    id slot = object;

    objc_storeStrong(&slot, nil);
    arc_test_assert(slot == nil, "objc_storeStrong clears slot");
    arc_test_assert(object->releaseCalls == 1, "objc_storeStrong releases cleared value");
}

static void test_store_strong_self_assignment(void)
{
    Tracker *object = [[Tracker alloc] init];
    id slot = object;

    objc_storeStrong(&slot, object);
    arc_test_assert(slot == object, "objc_storeStrong self-assignment keeps slot");
    arc_test_assert(object->retainCalls == 0, "objc_storeStrong self-assignment does not retain");
    arc_test_assert(object->releaseCalls == 0, "objc_storeStrong self-assignment does not release");

    [object release];
}

static void test_retain_block_nil(void)
{
    arc_test_assert(objc_retainBlock(nil) == nil, "objc_retainBlock(nil) returns nil");
}

static id make_copied_block(void)
{
    int captured = 41;
    int (^stackBlock)(void) = ^{
        return captured + 1;
    };

    return objc_retainBlock((id)stackBlock);
}

static void test_retain_block_copies_stack_block(void)
{
    int (^copiedBlock)(void) = (int (^)(void))make_copied_block();

    arc_test_assert(copiedBlock != nil, "objc_retainBlock returns copied block");
    arc_test_assert(copiedBlock() == 42, "objc_retainBlock copied block remains callable");

    blockValue = copiedBlock();
    arc_test_assert(blockValue == 42, "objc_retainBlock copied block captured value");

    _Block_release(copiedBlock);
}

static void test_generic_retain_release_block(void)
{
    int captured = 42;
    int (^stackBlock)(void) = ^{
        return captured;
    };

    int (^retainedBlock)(void) = (int (^)(void))objc_retain((id)stackBlock);
    arc_test_assert(retainedBlock != stackBlock, "objc_retain copies stack block");
    arc_test_assert(retainedBlock() == 42, "generic retained block remains callable");
    objc_release((id)retainedBlock);
}

static void test_generic_global_block(void)
{
    int (^globalBlock)(void) = ^{
        return 43;
    };

    id retainedBlock = objc_retain((id)globalBlock);
    arc_test_assert(retainedBlock == (id)globalBlock, "objc_retain preserves global block identity");
    arc_test_assert(((int (^)(void))retainedBlock)() == 43, "generic retained global block remains callable");
    objc_release(retainedBlock);
}

static void test_generic_block_autorelease(void)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    int captured = 44;
    int (^stackBlock)(void) = ^{
        return captured;
    };

    int (^retainedBlock)(void) = (int (^)(void))objc_retain((id)stackBlock);
    arc_test_assert(objc_autorelease((id)retainedBlock) == (id)retainedBlock, "objc_autorelease preserves block identity");
    arc_test_assert(retainedBlock() == 44, "autoreleased block remains callable before pool drains");
    [pool drain];
}

static void test_copy_property_block(void)
{
    struct {
        id slot;
    } storage = { nil };
    int captured = 45;
    int (^stackBlock)(void) = ^{
        return captured;
    };

    objc_setProperty((id)&storage, NULL, offsetof(typeof(storage), slot), (id)stackBlock, 0, 1);
    arc_test_assert(storage.slot != (id)stackBlock, "copy property copies stack block");
    arc_test_assert(((int (^)(void))storage.slot)() == 45, "copy property block remains callable");
    objc_release(storage.slot);
}

int main(void)
{
    test_nil();
    test_forwarding();
    test_store_strong_empty_slot();
    test_store_strong_replace();
    test_store_strong_clear();
    test_store_strong_self_assignment();
    test_retain_block_nil();
    test_retain_block_copies_stack_block();
    test_generic_retain_release_block();
    test_generic_global_block();
    test_generic_block_autorelease();
    test_copy_property_block();
    puts("PASS arc_core_lifetime");
    return 0;
}
