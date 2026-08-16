#include "test_entries.h"
#import <Foundation/Foundation.h>

int main(void)
{
    return libarc_test_block_codegen()
        || libarc_test_property_codegen();
}
