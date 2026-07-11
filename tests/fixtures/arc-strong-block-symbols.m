typedef struct objc_object *id;

id make(void);
void sink(id value);

id global;

id strong_case(id input)
{
    id local = make();
    global = local;
    sink(input);
    return local;
}

id block_case(id input)
{
    id (^block)(void) = ^{
        return input;
    };
    return block();
}
