#include "libarc_support/arc_runtime.h"

#if defined(__has_feature)
#if __has_feature(objc_arc)
#error libarc_support runtime sources must be compiled without ARC.
#endif
#endif

#include "arc_objc_compat.h"

#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>

static Class sAutoreleasePoolClass = Nil;
static SEL sNewSelector = NULL;
static SEL sDrainSelector = NULL;
static pthread_once_t sAutoreleasePoolOnce = PTHREAD_ONCE_INIT;

static void libarc_support_init_autorelease_pool(void)
{
    sAutoreleasePoolClass = objc_lookUpClass("NSAutoreleasePool");
    if (sAutoreleasePoolClass == Nil) {
        fprintf(stderr, "libarc_support: NSAutoreleasePool is unavailable\n");
        abort();
    }

    sNewSelector = sel_getUid("new");
    sDrainSelector = sel_getUid("drain");
}

void *objc_autoreleasePoolPush(void)
{
    pthread_once(&sAutoreleasePoolOnce, libarc_support_init_autorelease_pool);
    return (void *)objc_msgSend((id)sAutoreleasePoolClass, sNewSelector);
}

void objc_autoreleasePoolPop(void *pool)
{
    pthread_once(&sAutoreleasePoolOnce, libarc_support_init_autorelease_pool);
    objc_msgSend((id)pool, sDrainSelector);
}
