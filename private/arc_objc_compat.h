#ifndef LIBARC_SUPPORT_ARC_OBJC_COMPAT_H
#define LIBARC_SUPPORT_ARC_OBJC_COMPAT_H

#include <AvailabilityMacros.h>

#if defined(MAC_OS_X_VERSION_10_5)
#include <objc/message.h>
#include <objc/runtime.h>
#define ARC_OBJC_COMPAT_MODERN 1
#else
#include <objc/objc-runtime.h>
#define ARC_OBJC_COMPAT_MODERN 0
#endif

#include <stdlib.h>
#include <string.h>

#if ARC_OBJC_COMPAT_MODERN

extern void _objc_flush_caches(Class cls);

static inline Class arc_object_get_class(id obj)
{
    return object_getClass(obj);
}

static inline Class arc_class_get_superclass(Class cls)
{
    return class_getSuperclass(cls);
}

static inline IMP arc_class_get_method_implementation(Class cls, SEL sel)
{
    return class_getMethodImplementation(cls, sel);
}

static inline int arc_class_responds_to_selector(Class cls, SEL sel)
{
    return class_respondsToSelector(cls, sel);
}

static inline Method arc_class_get_exact_instance_method(Class cls, SEL sel)
{
    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    Method result = NULL;
    unsigned int i;

    for (i = 0; i < count; ++i) {
        if (method_getName(methods[i]) == sel) {
            result = methods[i];
            break;
        }
    }

    free(methods);
    return result;
}

static inline IMP arc_method_get_implementation(Method method)
{
    return method_getImplementation(method);
}

static inline const char *arc_method_get_type_encoding(Method method)
{
    return method_getTypeEncoding(method);
}

static inline void arc_method_set_implementation(Method method, IMP imp)
{
    method_setImplementation(method, imp);
}

static inline int arc_class_add_method(Class cls, SEL sel, IMP imp, const char *types)
{
    return class_addMethod(cls, sel, imp, types);
}

static inline IMP arc_class_replace_method(Class cls, SEL sel, IMP imp, const char *types)
{
    return class_replaceMethod(cls, sel, imp, types);
}

static inline void arc_class_flush_caches(Class cls)
{
#if defined(__clang__)
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
#endif
    _objc_flush_caches(cls);
#if defined(__clang__)
#pragma clang diagnostic pop
#endif
}

#else

extern void _objc_flush_caches(Class cls);

static inline Class arc_object_get_class(id obj)
{
#if defined(__clang__)
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-objc-isa-usage"
#endif
    return obj == nil ? Nil : obj->isa;
#if defined(__clang__)
#pragma clang diagnostic pop
#endif
}

static inline Class arc_class_get_superclass(Class cls)
{
    return cls == Nil ? Nil : cls->super_class;
}

static inline Method arc_class_get_exact_instance_method(Class cls, SEL sel)
{
    void *iterator = NULL;
    struct objc_method_list *list;

    while ((list = class_nextMethodList(cls, &iterator)) != NULL) {
        int i;
        for (i = 0; i < list->method_count; ++i) {
            if (list->method_list[i].method_name == sel) {
                return &list->method_list[i];
            }
        }
    }

    return NULL;
}

static inline IMP arc_class_get_method_implementation(Class cls, SEL sel)
{
    Method method = class_getInstanceMethod(cls, sel);
    return method == NULL ? NULL : method->method_imp;
}

static inline int arc_class_responds_to_selector(Class cls, SEL sel)
{
    return class_getInstanceMethod(cls, sel) != NULL;
}

static inline IMP arc_method_get_implementation(Method method)
{
    return method == NULL ? NULL : method->method_imp;
}

static inline const char *arc_method_get_type_encoding(Method method)
{
    return method == NULL ? NULL : method->method_types;
}

static inline void arc_method_set_implementation(Method method, IMP imp)
{
    if (method != NULL) {
        method->method_imp = imp;
    }
}

static inline struct objc_method_list *arc_create_method_list(SEL sel, IMP imp, const char *types)
{
    struct objc_method_list *list = (struct objc_method_list *)calloc(1, sizeof(struct objc_method_list));
    if (list == NULL) {
        abort();
    }

    list->method_count = 1;
    list->method_list[0].method_name = sel;
    list->method_list[0].method_types = types == NULL ? NULL : strdup(types);
    list->method_list[0].method_imp = imp;
    return list;
}

static inline int arc_class_add_method(Class cls, SEL sel, IMP imp, const char *types)
{
    if (arc_class_get_exact_instance_method(cls, sel) != NULL) {
        return 0;
    }

    class_addMethods(cls, arc_create_method_list(sel, imp, types));
    _objc_flush_caches(cls);
    return 1;
}

static inline IMP arc_class_replace_method(Class cls, SEL sel, IMP imp, const char *types)
{
    Method method = arc_class_get_exact_instance_method(cls, sel);
    IMP oldImp;

    if (method == NULL) {
        arc_class_add_method(cls, sel, imp, types);
        return NULL;
    }

    oldImp = method->method_imp;
    method->method_imp = imp;
    _objc_flush_caches(cls);
    return oldImp;
}

static inline void arc_class_flush_caches(Class cls)
{
    _objc_flush_caches(cls);
}

#endif

#endif
