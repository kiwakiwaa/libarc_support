#ifndef LIBARC_SUPPORT_ARC_RUNTIME_H
#define LIBARC_SUPPORT_ARC_RUNTIME_H

#ifdef __cplusplus
extern "C" {
#endif

#if defined(__GNUC__)
#define LIBARC_SUPPORT_EXPORT __attribute__((visibility("default")))
#else
#define LIBARC_SUPPORT_EXPORT
#endif

#if defined(__OBJC__)
typedef id libarc_support_id;
#else
typedef struct objc_object *libarc_support_id;
#endif
typedef struct objc_class *libarc_support_class;
typedef const void *libarc_support_objectptr_t;

LIBARC_SUPPORT_EXPORT libarc_support_id objc_retain(libarc_support_id value);
LIBARC_SUPPORT_EXPORT void objc_release(libarc_support_id value);
LIBARC_SUPPORT_EXPORT libarc_support_id objc_autorelease(libarc_support_id value);

LIBARC_SUPPORT_EXPORT libarc_support_id objc_retainAutorelease(libarc_support_id value);
LIBARC_SUPPORT_EXPORT libarc_support_id objc_retainAutoreleaseReturnValue(libarc_support_id value);
LIBARC_SUPPORT_EXPORT libarc_support_id objc_autoreleaseReturnValue(libarc_support_id value);
LIBARC_SUPPORT_EXPORT libarc_support_id objc_retainAutoreleasedReturnValue(libarc_support_id value);
LIBARC_SUPPORT_EXPORT libarc_support_id objc_unsafeClaimAutoreleasedReturnValue(libarc_support_id value);

LIBARC_SUPPORT_EXPORT void objc_storeStrong(libarc_support_id *object, libarc_support_id value);
LIBARC_SUPPORT_EXPORT libarc_support_id objc_retainBlock(libarc_support_id value);
LIBARC_SUPPORT_EXPORT void libarc_support_clear_copied_object_pointer(void *object);

LIBARC_SUPPORT_EXPORT libarc_support_id objc_alloc(libarc_support_class cls);
LIBARC_SUPPORT_EXPORT libarc_support_id objc_allocWithZone(libarc_support_class cls);
LIBARC_SUPPORT_EXPORT libarc_support_id objc_alloc_init(libarc_support_class cls);

LIBARC_SUPPORT_EXPORT void *objc_autoreleasePoolPush(void);
LIBARC_SUPPORT_EXPORT void objc_autoreleasePoolPop(void *pool);

LIBARC_SUPPORT_EXPORT libarc_support_id objc_initWeak(libarc_support_id *object, libarc_support_id value);
LIBARC_SUPPORT_EXPORT void objc_destroyWeak(libarc_support_id *object);
LIBARC_SUPPORT_EXPORT libarc_support_id objc_storeWeak(libarc_support_id *object, libarc_support_id value);
LIBARC_SUPPORT_EXPORT libarc_support_id objc_loadWeak(libarc_support_id *object);
LIBARC_SUPPORT_EXPORT libarc_support_id objc_loadWeakRetained(libarc_support_id *object);
LIBARC_SUPPORT_EXPORT void objc_copyWeak(libarc_support_id *dest, libarc_support_id *src);
LIBARC_SUPPORT_EXPORT void objc_moveWeak(libarc_support_id *dest, libarc_support_id *src);

LIBARC_SUPPORT_EXPORT libarc_support_id objc_retainedObject(libarc_support_objectptr_t object);
LIBARC_SUPPORT_EXPORT libarc_support_id objc_unretainedObject(libarc_support_objectptr_t object);
LIBARC_SUPPORT_EXPORT libarc_support_objectptr_t objc_unretainedPointer(libarc_support_id object);

#undef LIBARC_SUPPORT_EXPORT

#ifdef __cplusplus
}
#endif

#endif
