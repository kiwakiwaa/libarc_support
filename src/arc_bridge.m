#include "libarc_support/arc_runtime.h"

#if defined(__has_feature)
#if __has_feature(objc_arc)
#error libarc_support runtime sources must be compiled without ARC.
#endif
#endif

libarc_support_id objc_retainedObject(libarc_support_objectptr_t object)
{
    return (libarc_support_id)object;
}

libarc_support_id objc_unretainedObject(libarc_support_objectptr_t object)
{
    return (libarc_support_id)object;
}

libarc_support_objectptr_t objc_unretainedPointer(libarc_support_id object)
{
    return (libarc_support_objectptr_t)object;
}
