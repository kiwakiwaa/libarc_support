#include "test_entries.h"
#import <Foundation/Foundation.h>

int main(void)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    setbuf(stdout, NULL);

#define RUN_TEST(test)              \
    do {                            \
        printf("RUN  %s\n", #test); \
        if (test() != 0) {          \
            [pool drain];           \
            return 1;               \
        }                           \
    } while (0)

    RUN_TEST(libarc_test_core_lifetime);
    RUN_TEST(libarc_test_alloc_lifetime);
    RUN_TEST(libarc_test_bridge_identity);
    RUN_TEST(libarc_test_pool_lifetime);
    RUN_TEST(libarc_test_property_runtime);
    RUN_TEST(libarc_test_return_value_lifetime);
    RUN_TEST(libarc_test_weak_concurrency);
    RUN_TEST(libarc_test_weak_lifetime);
    RUN_TEST(libarc_test_weak_table_pruning);

#undef RUN_TEST

    [pool drain];
    return 0;
}
