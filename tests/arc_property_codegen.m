#import <Foundation/Foundation.h>

@interface PropertyCodegenHost : NSObject
{
    NSObject *_value;
    NSString *_name;
}
@property(nonatomic, strong) NSObject *value;
@property(atomic, copy) NSString *name;
@end

@implementation PropertyCodegenHost
@synthesize value = _value;
@synthesize name = _name;
@end

int main(void)
{
    @autoreleasepool {
        PropertyCodegenHost *host = [[PropertyCodegenHost alloc] init];
        NSObject *value = [[NSObject alloc] init];
        NSMutableString *name = [NSMutableString stringWithString:@"before"];
        host.value = value;
        host.name = name;
        [name appendString:@" after"];

        if (host.value != value || ![host.name isEqual:@"before"] || host.name == name) {
            return 1;
        }

    }

    puts("arc_property_codegen: PASS");
    return 0;
}
