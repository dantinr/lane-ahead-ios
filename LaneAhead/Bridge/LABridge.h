#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN
typedef void (^LAEventHandler)(NSString *event, NSDictionary<NSString *, id> *payload);
typedef void (^LAQueryCompletion)(NSArray<NSDictionary<NSString *, id> *> * _Nullable results, NSString * _Nullable error);

@interface LAPlatform : NSObject
+ (BOOL)isSupported;
+ (void)configureKey:(NSString *)key NS_SWIFT_NAME(configure(key:));
@end

@interface LAMapBridge : NSObject
@property(nonatomic, copy, nullable) LAEventHandler eventHandler;
@property(nonatomic, readonly) UIView *view;
- (void)setActive:(BOOL)active;
- (void)recenter;
- (void)selectLatitude:(double)latitude longitude:(double)longitude name:(NSString *)name NS_SWIFT_NAME(select(latitude:longitude:name:));
- (void)dispose;
@end

@interface LAPlaceQuery : NSObject
- (void)searchKeyword:(NSString *)keyword city:(NSString *)city completion:(LAQueryCompletion)completion NS_SWIFT_NAME(search(keyword:city:completion:));
- (void)reverseLatitude:(double)latitude longitude:(double)longitude completion:(LAQueryCompletion)completion NS_SWIFT_NAME(reverse(latitude:longitude:completion:));
- (void)cancel;
@end

@interface LANavigationBridge : NSObject
@property(nonatomic, copy, nullable) LAEventHandler eventHandler;
@property(nonatomic, readonly) UIView *view;
- (BOOL)planLatitude:(double)latitude longitude:(double)longitude start:(nullable NSDictionary *)start NS_SWIFT_NAME(plan(latitude:longitude:start:));
- (BOOL)selectRoute:(NSInteger)route;
- (BOOL)start;
- (void)setForeground:(BOOL)foreground;
- (void)finish;
@end
NS_ASSUME_NONNULL_END
