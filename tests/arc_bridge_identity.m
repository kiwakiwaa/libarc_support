#import <Foundation/Foundation.h>
#include "libarc_support/arc_runtime.h"

@interface BridgeTracker : NSObject {
@public
    unsigned retainCalls;
    unsigned releaseCalls;
    unsigned autoreleaseCalls;
}
@end

@implementation BridgeTracker

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

static void arc_bridge_assert(int condition, const char *message)
{
    if (!condition) {
        fprintf(stderr, "FAIL: %s\n", message);
        exit(1);
    }
}

static void test_nil(void)
{
    arc_bridge_assert(objc_retainedObject(NULL) == nil, "objc_retainedObject(NULL)");
    arc_bridge_assert(objc_unretainedObject(NULL) == nil, "objc_unretainedObject(NULL)");
    arc_bridge_assert(objc_unretainedPointer(nil) == NULL, "objc_unretainedPointer(nil)");
}

static void test_identity_and_no_lifetime_side_effects(void)
{
    BridgeTracker *object = [[BridgeTracker alloc] init];
    libarc_support_objectptr_t pointer = objc_unretainedPointer(object);

    arc_bridge_assert(pointer == (libarc_support_objectptr_t)object, "objc_unretainedPointer returns same pointer");
    arc_bridge_assert(objc_retainedObject(pointer) == object, "objc_retainedObject returns same object");
    arc_bridge_assert(objc_unretainedObject(pointer) == object, "objc_unretainedObject returns same object");

    arc_bridge_assert(object->retainCalls == 0, "bridge helpers do not retain");
    arc_bridge_assert(object->releaseCalls == 0, "bridge helpers do not release");
    arc_bridge_assert(object->autoreleaseCalls == 0, "bridge helpers do not autorelease");

    [object release];
}

int main(void)
{
    test_nil();
    test_identity_and_no_lifetime_side_effects();
    puts("PASS arc_bridge_identity");
    return 0;
}
