/*
 * Adapted from PLWeakCompatibilityCore.mm.
 * Copyright (c) 2012 Plausible Labs Cooperative, Inc.
 * Used under the BSD-3-Clause license. See vendor/PLWeakCompatibility/LICENSE.bsd-3-clause.txt.
 */

#include "arc_weak_table.h"

#if defined(__has_feature)
#if __has_feature(objc_arc)
#error libarc_support weak sources must be compiled without ARC.
#endif
#endif

#include "libarc_support/arc_runtime.h"
#include "arc_objc_compat.h"

#include <CoreFoundation/CoreFoundation.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static pthread_once_t gWeakInitOnce = PTHREAD_ONCE_INIT;
static pthread_mutex_t gWeakMutex;
static pthread_cond_t gReleasingObjectsCond;
static pthread_key_t gTLSKey;
static CFMutableDictionaryRef gObjectToAddressesMap;
static CFMutableSetRef gSwizzledClasses;
static CFMutableBagRef gReleasingObjects;
static CFMutableSetRef gDeallocatingObjects;
static SEL releaseSEL;
static SEL releaseSELSwizzled;
static SEL deallocSEL;
static SEL deallocSELSwizzled;

struct TLS
{
    CFMutableDictionaryRef lastReleaseClassTable;
    CFMutableDictionaryRef lastDeallocClassTable;
    CFMutableBagRef activeDeallocObjects;
};

static void DestroyTLS(void *ptr);
static struct TLS *GetTLS(void);
static void EnsureDeallocationTrigger(arc_weak_object_t obj);
static void UnregisterWeakLocation(arc_weak_object_t *location, arc_weak_object_t obj);
static int CurrentThreadIsDeallocatingObject(arc_weak_object_t obj);

static void WeakInitOnce(void)
{
    pthread_mutexattr_t attr;
    int err;

    pthread_mutexattr_init(&attr);
    pthread_mutexattr_settype(&attr, PTHREAD_MUTEX_RECURSIVE);
    pthread_mutex_init(&gWeakMutex, &attr);
    pthread_mutexattr_destroy(&attr);

    gObjectToAddressesMap = CFDictionaryCreateMutable(NULL, 0, NULL, &kCFTypeDictionaryValueCallBacks);
    gSwizzledClasses = CFSetCreateMutable(NULL, 0, NULL);
    gReleasingObjects = CFBagCreateMutable(NULL, 0, NULL);
    gDeallocatingObjects = CFSetCreateMutable(NULL, 0, NULL);
    pthread_cond_init(&gReleasingObjectsCond, NULL);

    err = pthread_key_create(&gTLSKey, DestroyTLS);
    if (err != 0) {
        fprintf(stderr, "libarc_support: pthread_key_create failed: %s (%d)\n", strerror(err), err);
        abort();
    }

    releaseSEL = sel_getUid("release");
    releaseSELSwizzled = sel_getUid("release_libarc_support_weak_swizzled");
    deallocSEL = sel_getUid("dealloc");
    deallocSELSwizzled = sel_getUid("dealloc_libarc_support_weak_swizzled");
}

static void WeakInit(void)
{
    pthread_once(&gWeakInitOnce, WeakInitOnce);
}

static struct TLS *GetTLS(void)
{
    struct TLS *tls = (struct TLS *)pthread_getspecific(gTLSKey);
    if (tls == NULL) {
        tls = (struct TLS *)calloc(1, sizeof(*tls));
        tls->lastReleaseClassTable = CFDictionaryCreateMutable(NULL, 0, NULL, NULL);
        tls->lastDeallocClassTable = CFDictionaryCreateMutable(NULL, 0, NULL, NULL);
        tls->activeDeallocObjects = CFBagCreateMutable(NULL, 0, NULL);
        pthread_setspecific(gTLSKey, tls);
    }
    return tls;
}

static void DestroyTLS(void *ptr)
{
    struct TLS *tls = (struct TLS *)ptr;
    if (tls != NULL) {
        if (tls->lastReleaseClassTable != NULL) {
            CFRelease(tls->lastReleaseClassTable);
        }
        if (tls->lastDeallocClassTable != NULL) {
            CFRelease(tls->lastDeallocClassTable);
        }
        if (tls->activeDeallocObjects != NULL) {
            CFRelease(tls->activeDeallocObjects);
        }
        free(tls);
    }
}

static int CurrentThreadIsDeallocatingObject(arc_weak_object_t obj)
{
    struct TLS *tls;

    if (obj == NULL) {
        return 0;
    }

    tls = GetTLS();
    return CFBagContainsValue(tls->activeDeallocObjects, obj);
}

arc_weak_object_t arc_weak_load_retained(arc_weak_object_t *location)
{
    arc_weak_object_t obj;

    WeakInit();

    pthread_mutex_lock(&gWeakMutex);
    obj = *location;
    while (obj != NULL && CFBagContainsValue(gReleasingObjects, obj)) {
        pthread_cond_wait(&gReleasingObjectsCond, &gWeakMutex);
        obj = *location;
    }
    if (obj != NULL && CFSetContainsValue(gDeallocatingObjects, obj)) {
        obj = NULL;
    }
    objc_retain((libarc_support_id)obj);
    pthread_mutex_unlock(&gWeakMutex);

    return obj;
}

arc_weak_object_t arc_weak_load(arc_weak_object_t *location)
{
    return (arc_weak_object_t)objc_autorelease((libarc_support_id)arc_weak_load_retained(location));
}

arc_weak_object_t arc_weak_init(arc_weak_object_t *location, arc_weak_object_t value)
{
    *location = NULL;
    return arc_weak_store(location, value);
}

void arc_weak_destroy(arc_weak_object_t *location)
{
    arc_weak_store(location, NULL);
}

void arc_weak_copy(arc_weak_object_t *to, arc_weak_object_t *from)
{
    arc_weak_init(to, arc_weak_load(from));
}

void arc_weak_move(arc_weak_object_t *to, arc_weak_object_t *from)
{
    arc_weak_copy(to, from);
    arc_weak_destroy(from);
}

arc_weak_object_t arc_weak_store(arc_weak_object_t *location, arc_weak_object_t obj)
{
    CFMutableSetRef addresses;
    arc_weak_object_t oldObj;

    WeakInit();

    pthread_mutex_lock(&gWeakMutex);
    oldObj = *location;
    UnregisterWeakLocation(location, oldObj);

    if (CurrentThreadIsDeallocatingObject(obj)) {
        obj = NULL;
    }

    *location = obj;

    if (obj != NULL) {
        addresses = (CFMutableSetRef)CFDictionaryGetValue(gObjectToAddressesMap, obj);
        if (addresses == NULL) {
            addresses = CFSetCreateMutable(NULL, 0, NULL);
            CFDictionarySetValue(gObjectToAddressesMap, obj, addresses);
            CFRelease(addresses);
        }

        CFSetAddValue(addresses, location);
        EnsureDeallocationTrigger(obj);
    }
    pthread_mutex_unlock(&gWeakMutex);

    return obj;
}

static void UnregisterWeakLocation(arc_weak_object_t *location, arc_weak_object_t obj)
{
    CFMutableSetRef addresses;

    if (obj == NULL) {
        return;
    }

    addresses = (CFMutableSetRef)CFDictionaryGetValue(gObjectToAddressesMap, obj);
    if (addresses == NULL) {
        return;
    }

    CFSetRemoveValue(addresses, location);
    if (CFSetGetCount(addresses) == 0) {
        CFDictionaryRemoveValue(gObjectToAddressesMap, obj);
    }
}

static Class TopClassImplementingMethod(Class start, SEL sel)
{
    IMP imp = arc_class_get_method_implementation(start, sel);
    Class previous = start;
    Class cursor = arc_class_get_superclass(previous);

    while (cursor != Nil) {
        if (imp != arc_class_get_method_implementation(cursor, sel)) {
            break;
        }
        previous = cursor;
        cursor = arc_class_get_superclass(cursor);
    }

    return previous;
}

static void SwizzledReleaseIMP(arc_weak_object_t self, SEL _cmd)
{
    struct TLS *tls = GetTLS();
    Class lastSent;
    Class targetClass;
    void (*origIMP)(arc_weak_object_t, SEL);

    pthread_mutex_lock(&gWeakMutex);
    CFBagAddValue(gReleasingObjects, self);
    pthread_mutex_unlock(&gWeakMutex);

    lastSent = (Class)CFDictionaryGetValue(tls->lastReleaseClassTable, self);
    targetClass = lastSent == Nil ? arc_object_get_class((id)self) : arc_class_get_superclass(lastSent);
    targetClass = TopClassImplementingMethod(targetClass, releaseSELSwizzled);

    if (!arc_class_responds_to_selector(targetClass, releaseSELSwizzled)) {
        targetClass = arc_object_get_class((id)self);
        targetClass = TopClassImplementingMethod(targetClass, releaseSELSwizzled);
    }

    CFDictionarySetValue(tls->lastReleaseClassTable, self, targetClass);

    origIMP = (void (*)(arc_weak_object_t, SEL))arc_class_get_method_implementation(targetClass, releaseSELSwizzled);
    origIMP(self, _cmd);

    CFDictionaryRemoveValue(tls->lastReleaseClassTable, self);

    pthread_mutex_lock(&gWeakMutex);
    CFBagRemoveValue(gReleasingObjects, self);
    if (!CFBagContainsValue(gReleasingObjects, self)) {
        CFSetRemoveValue(gDeallocatingObjects, self);
    }
    pthread_cond_broadcast(&gReleasingObjectsCond);
    pthread_mutex_unlock(&gWeakMutex);
}

static void ClearAddress(const void *value, void *context)
{
    arc_weak_object_t *address = (arc_weak_object_t *)value;
    (void)context;
    *address = NULL;
}

static void SwizzledDeallocIMP(arc_weak_object_t self, SEL _cmd)
{
    struct TLS *tls = GetTLS();
    CFSetRef addresses;
    Class lastSent;
    Class targetClass;
    void (*origIMP)(arc_weak_object_t, SEL);

    pthread_mutex_lock(&gWeakMutex);
    CFSetAddValue(gDeallocatingObjects, self);
    addresses = (CFSetRef)CFDictionaryGetValue(gObjectToAddressesMap, self);
    if (addresses != NULL) {
        CFSetApplyFunction(addresses, ClearAddress, NULL);
    }
    CFDictionaryRemoveValue(gObjectToAddressesMap, self);
    pthread_cond_broadcast(&gReleasingObjectsCond);
    pthread_mutex_unlock(&gWeakMutex);

    lastSent = (Class)CFDictionaryGetValue(tls->lastDeallocClassTable, self);
    targetClass = lastSent == Nil ? arc_object_get_class((id)self) : arc_class_get_superclass(lastSent);
    targetClass = TopClassImplementingMethod(targetClass, deallocSELSwizzled);
    CFDictionarySetValue(tls->lastDeallocClassTable, self, targetClass);

    origIMP = (void (*)(arc_weak_object_t, SEL))arc_class_get_method_implementation(targetClass, deallocSELSwizzled);
    CFBagAddValue(tls->activeDeallocObjects, self);
    origIMP(self, _cmd);
    CFBagRemoveValue(tls->activeDeallocObjects, self);

    CFDictionaryRemoveValue(tls->lastDeallocClassTable, self);

    pthread_mutex_lock(&gWeakMutex);
    if (!CFBagContainsValue(gReleasingObjects, self)) {
        CFSetRemoveValue(gDeallocatingObjects, self);
        pthread_cond_broadcast(&gReleasingObjectsCond);
    }
    pthread_mutex_unlock(&gWeakMutex);
}

static void Swizzle(Class cls, SEL orig, SEL newSel, IMP newIMP)
{
    Method exactMethod = arc_class_get_exact_instance_method(cls, orig);
    Method method = exactMethod != NULL ? exactMethod : class_getInstanceMethod(cls, orig);
    IMP origIMP = arc_method_get_implementation(method);
    const char *types = arc_method_get_type_encoding(method);

    if (method == NULL || origIMP == NULL) {
        fprintf(stderr, "libarc_support: method missing during weak swizzle\n");
        abort();
    }

    if (!arc_class_add_method(cls, newSel, origIMP, types)) {
        fprintf(stderr, "libarc_support: swizzled method already exists\n");
        abort();
    }

    if (exactMethod != NULL) {
        arc_method_set_implementation(exactMethod, newIMP);
    } else if (!arc_class_add_method(cls, orig, newIMP, types)) {
        fprintf(stderr, "libarc_support: inherited method override failed during weak swizzle\n");
        abort();
    }

    arc_class_flush_caches(cls);
}

static void EnsureDeallocationTrigger(arc_weak_object_t obj)
{
    Class cls = arc_object_get_class((id)obj);
    if (CFSetContainsValue(gSwizzledClasses, cls)) {
        return;
    }

    Swizzle(cls, releaseSEL, releaseSELSwizzled, (IMP)SwizzledReleaseIMP);
    Swizzle(cls, deallocSEL, deallocSELSwizzled, (IMP)SwizzledDeallocIMP);

    CFSetAddValue(gSwizzledClasses, cls);
}

#if defined(ARC_WEAK_TESTING)
size_t arc_weak_debug_registered_object_count(void)
{
    size_t count;

    WeakInit();

    pthread_mutex_lock(&gWeakMutex);
    count = (size_t)CFDictionaryGetCount(gObjectToAddressesMap);
    pthread_mutex_unlock(&gWeakMutex);

    return count;
}

size_t arc_weak_debug_deallocating_object_count(void)
{
    size_t count;

    WeakInit();

    pthread_mutex_lock(&gWeakMutex);
    count = (size_t)CFSetGetCount(gDeallocatingObjects);
    pthread_mutex_unlock(&gWeakMutex);

    return count;
}
#endif
