#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
// BOOL parameters preserve true/false when bridging C comparison results into JSON.
FOUNDATION_EXPORT NSDictionary<NSString *, id> *LAEncodeRouteLink(
    NSInteger length, NSString *road, BOOL signal, BOOL internalRoad,
    NSArray<NSDictionary<NSString *, NSNumber *> *> *coordinates);
NS_ASSUME_NONNULL_END
