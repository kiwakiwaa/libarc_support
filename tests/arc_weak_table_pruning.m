#import <Foundation/Foundation.h>
#include "libarc_support/arc_runtime.h"
#include "arc_objc_compat.h"
#include <stddef.h>

size_t arc_weak_debug_registered_object_count(void);
size_t arc_weak_debug_deallocating_object_count(void);

@interface PruneTracker : NSObject
@end

@implementation PruneTracker
@end

@interface PruneSubTracker : PruneTracker
@end

@implementation PruneSubTracker
@end

@interface SwizzleBaseTracker : NSObject
@end

@implementation SwizzleBaseTracker

- (oneway void)release
{
    [super release];
}

- (void)dealloc
{
    [super dealloc];
}

@end

@interface SwizzleInheritedTracker : SwizzleBaseTracker
@end

@implementation SwizzleInheritedTracker
@end

static void arc_prune_assert(int condition, const char *message)
{
    if (!condition) {
        fprintf(stderr, "FAIL: %s\n", message);
        exit(1);
    }
}

static void test_empty_address_sets_are_pruned(void)
{
    PruneTracker *first = [[PruneTracker alloc] init];
    PruneTracker *second = [[PruneTracker alloc] init];
    id slot = nil;
    size_t before = arc_weak_debug_registered_object_count();

    objc_storeWeak(&slot, first);
    arc_prune_assert(arc_weak_debug_registered_object_count() == before + 1, "first weak target registered");

    objc_storeWeak(&slot, second);
    arc_prune_assert(arc_weak_debug_registered_object_count() == before + 1, "replaced target pruned");

    objc_storeWeak(&slot, nil);
    arc_prune_assert(arc_weak_debug_registered_object_count() == before, "cleared target pruned");

    [first release];
    [second release];
}

static void test_deallocating_marker_is_removed_after_release(void)
{
    id slot = nil;
    PruneTracker *object = [[PruneTracker alloc] init];

    objc_initWeak(&slot, object);
    arc_prune_assert(arc_weak_debug_deallocating_object_count() == 0, "no deallocating markers before release");

    [object release];
    arc_prune_assert(slot == nil, "weak slot zeroed");
    arc_prune_assert(arc_weak_debug_deallocating_object_count() == 0, "deallocating marker removed after release");
}

static void test_deallocating_marker_is_removed_after_subclass_release(void)
{
    id slot = nil;
    PruneSubTracker *object = [[PruneSubTracker alloc] init];

    objc_initWeak(&slot, object);
    arc_prune_assert(arc_weak_debug_deallocating_object_count() == 0, "no deallocating markers before subclass release");

    [object release];
    arc_prune_assert(slot == nil, "subclass weak slot zeroed");
    arc_prune_assert(arc_weak_debug_deallocating_object_count() == 0, "deallocating marker removed after subclass release");
}

static IMP exact_imp(Class cls, SEL sel)
{
    return arc_method_get_implementation(arc_class_get_exact_instance_method(cls, sel));
}

static void test_inherited_swizzle_does_not_mutate_superclass(void)
{
    Class baseClass = [SwizzleBaseTracker class];
    Class subclass = [SwizzleInheritedTracker class];
    IMP baseReleaseIMP = exact_imp(baseClass, @selector(release));
    IMP baseDeallocIMP = exact_imp(baseClass, @selector(dealloc));
    id slot = nil;
    SwizzleInheritedTracker *object = [[SwizzleInheritedTracker alloc] init];

    arc_prune_assert(baseReleaseIMP != NULL, "base class has exact release before subclass swizzle");
    arc_prune_assert(baseDeallocIMP != NULL, "base class has exact dealloc before subclass swizzle");
    arc_prune_assert(exact_imp(subclass, @selector(release)) == NULL, "subclass inherits release before swizzle");
    arc_prune_assert(exact_imp(subclass, @selector(dealloc)) == NULL, "subclass inherits dealloc before swizzle");

    objc_initWeak(&slot, object);

    arc_prune_assert(exact_imp(baseClass, @selector(release)) == baseReleaseIMP, "subclass swizzle does not replace superclass release");
    arc_prune_assert(exact_imp(baseClass, @selector(dealloc)) == baseDeallocIMP, "subclass swizzle does not replace superclass dealloc");
    arc_prune_assert(exact_imp(subclass, @selector(release)) != NULL, "subclass gets exact release override");
    arc_prune_assert(exact_imp(subclass, @selector(dealloc)) != NULL, "subclass gets exact dealloc override");

    [object release];
    arc_prune_assert(slot == nil, "inherited swizzle still zeroes weak slot");
}

int main(void)
{
    test_empty_address_sets_are_pruned();
    test_deallocating_marker_is_removed_after_release();
    test_deallocating_marker_is_removed_after_subclass_release();
    test_inherited_swizzle_does_not_mutate_superclass();
    puts("PASS arc_weak_table_pruning");
    return 0;
}
