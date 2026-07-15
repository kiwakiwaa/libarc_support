#import <Foundation/Foundation.h>

@interface BlockHarness : NSObject {
    int (^storedBlock)(void);
}
@property(nonatomic, copy) int (^storedBlock)(void);
+ (int)invokeBlock:(int (^)(void))block;
@end

static int captureDeallocations;

@interface BlockCapture : NSObject
@end

@implementation BlockCapture

- (void)dealloc
{
    ++captureDeallocations;
}

@end

@implementation BlockHarness

@synthesize storedBlock;

+ (int)invokeBlock:(int (^)(void))block
{
    return block();
}

@end

static void arc_block_assert(int condition, const char *message)
{
    if (!condition) {
        fprintf(stderr, "FAIL: %s\n", message);
        exit(1);
    }
}

static int invoke_local_block(void)
{
    int captured = 41;
    int (^block)(void) = ^{
        return captured + 1;
    };
    return block();
}

int main(void)
{
    @autoreleasepool {
        int captured = 42;
        arc_block_assert([BlockHarness invokeBlock:^{ return captured; }] == 42,
            "Objective-C block parameter");
        arc_block_assert(invoke_local_block() == 42, "strong local block");

        BlockHarness *harness = [[BlockHarness alloc] init];
        harness.storedBlock = ^{ return captured + 1; };
        arc_block_assert(harness.storedBlock() == 43, "copy block property");
        harness.storedBlock = nil;

        BlockCapture *capturedObject = [[BlockCapture alloc] init];
        harness.storedBlock = ^{ return capturedObject != nil ? 44 : 0; };
        capturedObject = nil;
        arc_block_assert(captureDeallocations == 0, "copied block retains captured object");
        arc_block_assert(harness.storedBlock() == 44, "copied block accesses captured object");
        harness.storedBlock = nil;
    }

    arc_block_assert(captureDeallocations == 1, "releasing copied block releases captured object");

    puts("PASS arc_block_codegen");
    return 0;
}
