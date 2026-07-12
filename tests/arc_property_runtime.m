#import <Foundation/Foundation.h>

#include "libarc_support/arc_runtime.h"

@interface ProbeValue : NSObject <NSCopying, NSMutableCopying>
{
    int *_deallocations;
    NSString *_kind;
}
- (id)initWithDeallocations:(int *)deallocations kind:(NSString *)kind;
@property(nonatomic, readonly) NSString *kind;
@end

@implementation ProbeValue
- (id)initWithDeallocations:(int *)deallocations kind:(NSString *)kind
{
    if ((self = [super init])) {
        _deallocations = deallocations;
        _kind = [kind copy];
    }
    return self;
}
- (NSString *)kind { return _kind; }
- (id)copyWithZone:(NSZone *)zone { return [[ProbeValue allocWithZone:zone] initWithDeallocations:_deallocations kind:@"copy"]; }
- (id)mutableCopyWithZone:(NSZone *)zone { return [[ProbeValue allocWithZone:zone] initWithDeallocations:_deallocations kind:@"mutableCopy"]; }
- (void)dealloc { ++*_deallocations; [_kind release]; [super dealloc]; }
@end

@interface PropertyHost : NSObject
{
@public
    id _value;
}
@end
@implementation PropertyHost
- (void)dealloc { [_value release]; [super dealloc]; }
@end

static void test_assert(BOOL condition, NSString *message)
{
    if (!condition) {
        NSLog(@"FAIL: %@", message);
        exit(1);
    }
}

int main(void)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    PropertyHost *host = [[PropertyHost alloc] init];
    ptrdiff_t offset = (char *)&host->_value - (char *)host;
    int deallocations = 0;
    ProbeValue *first = [[ProbeValue alloc] initWithDeallocations:&deallocations kind:@"original"];

    objc_setProperty(host, 0, offset, first, 0, 0);
    [first release];
    test_assert(objc_getProperty(host, 0, offset, 0) == host->_value, @"nonatomic get");
    objc_setProperty(host, 0, offset, host->_value, 0, 0);
    test_assert(deallocations == 0, @"self assignment lifetime");

    ProbeValue *source = [[ProbeValue alloc] initWithDeallocations:&deallocations kind:@"source"];
    objc_setProperty(host, 0, offset, source, 1, 1);
    test_assert([[(ProbeValue *)host->_value kind] isEqual:@"copy"], @"atomic copy");
    objc_setProperty(host, 0, offset, source, 1, 2);
    test_assert([[(ProbeValue *)host->_value kind] isEqual:@"mutableCopy"], @"atomic mutable copy");
    [source release];
    test_assert(objc_getProperty(host, 0, offset, 1) == host->_value, @"atomic get");
    objc_setProperty(host, 0, offset, nil, 1, 0);
    test_assert(host->_value == nil, @"nil assignment");

    BOOL mutationRaised = NO;
    @try { objc_enumerationMutation(host); }
    @catch (NSException *exception) { mutationRaised = [[exception name] isEqual:NSGenericException]; }
    test_assert(mutationRaised, @"enumeration mutation exception");

    [host release];
    [pool drain];
    puts("arc_property_runtime: PASS");
    return 0;
}
