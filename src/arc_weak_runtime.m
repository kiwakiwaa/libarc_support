#include "libarc_support/arc_runtime.h"
#include "arc_weak_table.h"

#if defined(__has_feature)
#if __has_feature(objc_arc)
#error libarc_support weak runtime wrappers must be compiled without ARC.
#endif
#endif

libarc_support_id objc_initWeak(libarc_support_id *object, libarc_support_id value)
{
    return (libarc_support_id)arc_weak_init((arc_weak_object_t *)object, value);
}

void objc_destroyWeak(libarc_support_id *object)
{
    arc_weak_destroy((arc_weak_object_t *)object);
}

libarc_support_id objc_storeWeak(libarc_support_id *object, libarc_support_id value)
{
    return (libarc_support_id)arc_weak_store((arc_weak_object_t *)object, value);
}

libarc_support_id objc_loadWeak(libarc_support_id *object)
{
    return (libarc_support_id)arc_weak_load((arc_weak_object_t *)object);
}

libarc_support_id objc_loadWeakRetained(libarc_support_id *object)
{
    return (libarc_support_id)arc_weak_load_retained((arc_weak_object_t *)object);
}

void objc_copyWeak(libarc_support_id *dest, libarc_support_id *src)
{
    arc_weak_copy((arc_weak_object_t *)dest, (arc_weak_object_t *)src);
}

void objc_moveWeak(libarc_support_id *dest, libarc_support_id *src)
{
    arc_weak_move((arc_weak_object_t *)dest, (arc_weak_object_t *)src);
}
