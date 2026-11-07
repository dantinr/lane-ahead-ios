#import "LARoutePayload.h"

NSDictionary<NSString *, id> *LAEncodeRouteLink(
    NSInteger length, NSString *road, BOOL signal, BOOL internalRoad,
    NSArray<NSDictionary<NSString *, NSNumber *> *> *coordinates) {
    return @{@"length": @(length), @"road": road, @"signal": @(signal),
             @"internalRoad": @(internalRoad), @"coordinates": coordinates};
}
