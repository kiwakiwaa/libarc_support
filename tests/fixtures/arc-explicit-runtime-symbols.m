typedef struct objc_object *id;
typedef struct objc_class *Class;

void objc_copyWeak(id *dest, id *src);
void objc_moveWeak(id *dest, id *src);
id objc_storeWeak(id *object, id value);
id objc_loadWeakRetained(id *object);
id objc_unsafeClaimAutoreleasedReturnValue(id value);
id objc_alloc(Class cls);
id objc_allocWithZone(Class cls);
id objc_alloc_init(Class cls);
void *objc_autoreleasePoolPush(void);
void objc_autoreleasePoolPop(void *pool);
id objc_retainedObject(const void *object);
id objc_unretainedObject(const void *object);
const void *objc_unretainedPointer(id object);

void force_runtime_symbols(id *dest, id *src, id value)
{
    void *pool = objc_autoreleasePoolPush();
    objc_copyWeak(dest, src);
    objc_moveWeak(dest, src);
    objc_storeWeak(dest, value);
    objc_loadWeakRetained(src);
    objc_unsafeClaimAutoreleasedReturnValue(value);
    objc_alloc((Class)value);
    objc_allocWithZone((Class)value);
    objc_alloc_init((Class)value);
    objc_retainedObject(objc_unretainedPointer(value));
    objc_unretainedObject(objc_unretainedPointer(value));
    objc_autoreleasePoolPop(pool);
}
