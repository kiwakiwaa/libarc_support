#include "libarc_support/arc_runtime.h"

#if defined(__has_feature)
#if __has_feature(objc_arc)
#error libarc_support allocation runtime wrappers must be compiled without ARC.
#endif
#endif

#include "arc_objc_compat.h"

#include <pthread.h>

static SEL sAllocSelector = NULL;
static SEL sAllocWithZoneSelector = NULL;
static SEL sInitSelector = NULL;
static pthread_once_t sAllocSelectorsOnce = PTHREAD_ONCE_INIT;

static void libarc_support_init_alloc_selectors(void)
{
    sAllocSelector = sel_getUid("alloc");
    sAllocWithZoneSelector = sel_getUid("allocWithZone:");
    sInitSelector = sel_getUid("init");
}

libarc_support_id objc_alloc(libarc_support_class cls)
{
    pthread_once(&sAllocSelectorsOnce, libarc_support_init_alloc_selectors);
    return ((libarc_support_id (*)(id, SEL))objc_msgSend)((id)cls, sAllocSelector);
}

libarc_support_id objc_allocWithZone(libarc_support_class cls)
{
    pthread_once(&sAllocSelectorsOnce, libarc_support_init_alloc_selectors);
    return ((libarc_support_id (*)(id, SEL, void *))objc_msgSend)((id)cls, sAllocWithZoneSelector, NULL);
}

libarc_support_id objc_alloc_init(libarc_support_class cls)
{
    libarc_support_id object = objc_alloc(cls);

    pthread_once(&sAllocSelectorsOnce, libarc_support_init_alloc_selectors);
    return ((libarc_support_id (*)(id, SEL))objc_msgSend)((id)object, sInitSelector);
}
