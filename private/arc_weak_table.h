#ifndef LIBARC_SUPPORT_ARC_WEAK_TABLE_H
#define LIBARC_SUPPORT_ARC_WEAK_TABLE_H

#ifdef __cplusplus
extern "C" {
#endif

typedef void *arc_weak_object_t;

#if defined(__GNUC__)
#define ARC_WEAK_INTERNAL __attribute__((visibility("hidden")))
#else
#define ARC_WEAK_INTERNAL
#endif

ARC_WEAK_INTERNAL arc_weak_object_t arc_weak_init(arc_weak_object_t *location, arc_weak_object_t value);
ARC_WEAK_INTERNAL void arc_weak_destroy(arc_weak_object_t *location);
ARC_WEAK_INTERNAL arc_weak_object_t arc_weak_store(arc_weak_object_t *location, arc_weak_object_t value);
ARC_WEAK_INTERNAL arc_weak_object_t arc_weak_load(arc_weak_object_t *location);
ARC_WEAK_INTERNAL arc_weak_object_t arc_weak_load_retained(arc_weak_object_t *location);
ARC_WEAK_INTERNAL void arc_weak_copy(arc_weak_object_t *to, arc_weak_object_t *from);
ARC_WEAK_INTERNAL void arc_weak_move(arc_weak_object_t *to, arc_weak_object_t *from);

#undef ARC_WEAK_INTERNAL

#ifdef __cplusplus
}
#endif

#endif
