typedef struct objc_object *id;

void sink(id value);

__weak id weak_global;

void weak_store(id input)
{
    weak_global = input;
}

id weak_load(void)
{
    return weak_global;
}

void weak_local(id input)
{
    __weak id weak_value = input;
    id loaded = weak_value;
    sink(loaded);
}
