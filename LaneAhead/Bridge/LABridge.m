#import "LABridge.h"
#import <TargetConditionals.h>

#if TARGET_OS_SIMULATOR
// The vendor distributes device arm64 and simulator x86_64 in a fat framework.
// Local Swift features are available on Apple Silicon simulators without loading it.
@implementation LAPlatform
+ (BOOL)isSupported { return NO; }
+ (void)configureKey:(NSString *)key {}
@end
@implementation LAMapBridge
- (UIView *)view { return [UIView new]; }
- (void)setActive:(BOOL)active {}
- (void)recenter {}
- (void)selectLatitude:(double)latitude longitude:(double)longitude name:(NSString *)name {}
- (void)dispose {}
@end
@implementation LAPlaceQuery
- (void)searchKeyword:(NSString *)keyword city:(NSString *)city completion:(LAQueryCompletion)c { c(nil, @"请在 iPhone 真机上使用高德地图与搜索"); }
- (void)reverseLatitude:(double)latitude longitude:(double)longitude completion:(LAQueryCompletion)c { c(nil, @"请在 iPhone 真机上使用高德定位"); }
- (void)cancel {}
@end
@implementation LANavigationBridge
- (UIView *)view { return [UIView new]; }
- (BOOL)planLatitude:(double)latitude longitude:(double)longitude start:(NSDictionary *)start { return NO; }
- (BOOL)selectRoute:(NSInteger)route { return NO; }
- (BOOL)start { return NO; }
- (void)setForeground:(BOOL)foreground {}
- (void)finish {}
@end
#else
#import <AMapFoundationKit/AMapFoundationKit.h>
#import <AMapNaviKit/AMapNaviKit.h>
#import <AMapSearchKit/AMapSearchKit.h>

@implementation LAPlatform
+ (BOOL)isSupported { return YES; }
+ (void)configureKey:(NSString *)key {
    // Caller has obtained explicit privacy consent and location authorization.
    [AMapServices sharedServices].apiKey = key;
    [MAMapView updatePrivacyShow:AMapPrivacyShowStatusDidShow privacyInfo:AMapPrivacyInfoStatusDidContain];
    [MAMapView updatePrivacyAgree:AMapPrivacyAgreeStatusDidAgree];
    [[AMapNaviManagerConfig sharedConfig] updatePrivacyShow:AMapPrivacyShowStatusDidShow privacyInfo:AMapPrivacyInfoStatusDidContain];
    [[AMapNaviManagerConfig sharedConfig] updatePrivacyAgree:AMapPrivacyAgreeStatusDidAgree];
    [AMapSearchAPI updatePrivacyShow:AMapPrivacyShowStatusDidShow privacyInfo:AMapPrivacyInfoStatusDidContain];
    [AMapSearchAPI updatePrivacyAgree:AMapPrivacyAgreeStatusDidAgree];
}
@end

@interface LAMapBridge () <MAMapViewDelegate>
@property(nonatomic, strong) MAMapView *map;
@property(nonatomic, strong) MAPointAnnotation *destination;
@property(nonatomic) BOOL active;
@property(nonatomic) BOOL firstFix;
@end
@implementation LAMapBridge
- (instancetype)init {
    if ((self = [super init])) { _firstFix = YES; }
    return self;
}
- (UIView *)view {
    if (!_map) {
        _map = [[MAMapView alloc] initWithFrame:CGRectZero];
        _map.delegate = self; _map.showsScale = YES; _map.showsCompass = YES;
        _map.showsUserLocation = self.active;
    }
    return _map;
}
- (void)setActive:(BOOL)active { _active = active; _map.showsUserLocation = active; }
- (void)recenter {
    self.firstFix = YES;
    if (self.map.userLocation.location) { [self.map setCenterCoordinate:self.map.userLocation.coordinate animated:YES]; }
}
- (void)selectLatitude:(double)latitude longitude:(double)longitude name:(NSString *)name {
    if (self.destination) { [self.map removeAnnotation:self.destination]; }
    self.destination = [MAPointAnnotation new]; self.destination.coordinate = CLLocationCoordinate2DMake(latitude, longitude);
    self.destination.title = name; [self.map addAnnotation:self.destination];
    [self.map setCenterCoordinate:self.destination.coordinate animated:YES];
}
- (void)mapView:(MAMapView *)mapView didUpdateUserLocation:(MAUserLocation *)userLocation updatingLocation:(BOOL)updating {
    CLLocation *location = userLocation.location;
    if (!self.active || !updating || !location || location.horizontalAccuracy < 0 ||
        fabs(location.timestamp.timeIntervalSinceNow) > 120 || !CLLocationCoordinate2DIsValid(location.coordinate)) { return; }
    if (self.firstFix) { self.firstFix = NO; [mapView setZoomLevel:16 animated:NO]; [mapView setCenterCoordinate:location.coordinate animated:YES]; }
    if (self.eventHandler) self.eventHandler(@"located", @{@"latitude": @(location.coordinate.latitude),
        @"longitude": @(location.coordinate.longitude), @"accuracy": @(location.horizontalAccuracy)});
}
- (void)mapView:(MAMapView *)mapView didFailToLocateUserWithError:(NSError *)error {
    if (self.active && self.eventHandler) self.eventHandler(@"error", @{@"message": @"定位失败，请检查权限、定位开关和网络"});
}
- (void)dispose { self.active = NO; self.map.delegate = nil; self.map = nil; self.eventHandler = nil; }
@end

@interface LAPlaceQuery () <AMapSearchDelegate>
@property(nonatomic, strong) AMapSearchAPI *api;
@property(nonatomic, copy) LAQueryCompletion completion;
@property(nonatomic) BOOL finished;
@end
@implementation LAPlaceQuery
- (void)complete:(NSArray *)results error:(NSString *)error {
    if (self.finished) return;
    self.finished = YES;
    LAQueryCompletion completion = self.completion; self.completion = nil;
    self.api.delegate = nil; [self.api cancelAllRequests]; self.api = nil;
    if (completion) completion(results, error);
}
- (void)prepare:(LAQueryCompletion)completion {
    self.finished = NO; self.completion = completion; self.api = [AMapSearchAPI new]; self.api.delegate = self;
}
- (void)searchKeyword:(NSString *)keyword city:(NSString *)city completion:(LAQueryCompletion)completion {
    [self prepare:completion];
    AMapPOIKeywordsSearchRequest *request = [AMapPOIKeywordsSearchRequest new];
    request.keywords = keyword; request.city = city; request.cityLimit = YES; request.offset = 25;
    [self.api AMapPOIKeywordsSearch:request];
}
- (void)reverseLatitude:(double)latitude longitude:(double)longitude completion:(LAQueryCompletion)completion {
    [self prepare:completion];
    AMapReGeocodeSearchRequest *request = [AMapReGeocodeSearchRequest new];
    request.location = [AMapGeoPoint locationWithLatitude:latitude longitude:longitude]; request.requireExtension = NO;
    [self.api AMapReGoecodeSearch:request];
}
- (void)onPOISearchDone:(AMapPOISearchBaseRequest *)request response:(AMapPOISearchResponse *)response {
    NSMutableArray *results = [NSMutableArray new];
    for (AMapPOI *poi in response.pois) {
        if (!poi.location || !poi.name.length) continue;
        NSString *address = [NSString stringWithFormat:@"%@%@%@", poi.city ?: @"", poi.district ?: @"", poi.address ?: @""];
        [results addObject:@{@"id": poi.uid ?: NSUUID.UUID.UUIDString, @"name": poi.name, @"city": poi.city ?: @"",
            @"address": address, @"latitude": @(poi.location.latitude), @"longitude": @(poi.location.longitude)}];
    }
    [self complete:results error:nil];
}
- (void)onReGeocodeSearchDone:(AMapReGeocodeSearchRequest *)request response:(AMapReGeocodeSearchResponse *)response {
    NSString *city = response.regeocode.addressComponent.city;
    if (!city.length) city = response.regeocode.addressComponent.province;
    if (city.length) [self complete:@[@{@"city": city}] error:nil];
    else [self complete:nil error:@"无法识别城市，请手动选择搜索范围"];
}
- (void)AMapSearchRequest:(id)request didFailWithError:(NSError *)error {
    // No request URLs, keys or personal search text are included in diagnostics.
    [self complete:nil error:[NSString stringWithFormat:@"地图查询失败（%ld），请检查网络或地图服务授权", (long)error.code]];
}
- (void)cancel { [self complete:nil error:@"查询已取消"]; }
@end

@interface LANavigationBridge () <AMapNaviDriveManagerDelegate, AMapNaviDriveDataRepresentable, AMapNaviDriveViewDelegate>
@property(nonatomic, strong) AMapNaviDriveManager *manager;
@property(nonatomic, strong) AMapNaviDriveView *driveView;
@property(nonatomic) BOOL disposed;
@property(nonatomic) BOOL planning;
@property(nonatomic) BOOL starting;
@property(nonatomic) BOOL running;
@property(nonatomic) BOOL foreground;
@property(nonatomic) BOOL matched;
@property(nonatomic) BOOL weakGPS;
@property(nonatomic) NSTimeInterval matchAt;
@property(nonatomic) NSInteger matchedStep;
@property(nonatomic) NSTimeInterval speedAt;
@property(nonatomic) NSTimeInterval lastLocationAt;
@property(nonatomic) NSInteger lastFrame;
@property(nonatomic) double speed;
@property(nonatomic) double angle;
@property(nonatomic) NSTimeInterval animationAt;
@property(nonatomic, strong) NSTimer *timer;
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, UIImage *> *frames;
@property(nonatomic, strong) UIImage *atlas;
@end

@implementation LANavigationBridge
- (instancetype)init {
    if ((self = [super init])) {
        _foreground = YES; _frames = [NSMutableDictionary new]; _lastFrame = -1;
        _manager = [AMapNaviDriveManager sharedInstance];
        _manager.delegate = self; _manager.isUseInternalTTS = YES;
        _manager.allowsBackgroundLocationUpdates = YES;
        [_manager addDataRepresentative:self];
    }
    return self;
}
- (UIView *)view {
    if (!_driveView) {
        _driveView = [[AMapNaviDriveView alloc] initWithFrame:CGRectZero]; _driveView.delegate = self;
        _driveView.showMoreButton = NO;
        [self.manager addDataRepresentative:_driveView];
        [self applyCarFrame:0];
    }
    return _driveView;
}
- (void)emit:(NSString *)event data:(NSDictionary *)data {
    if (!self.disposed && self.eventHandler) self.eventHandler(event, data ?: @{});
}
- (BOOL)planLatitude:(double)latitude longitude:(double)longitude start:(NSDictionary *)start {
    if (self.disposed || self.planning || self.running) return NO;
    self.planning = YES; self.matched = NO;
    AMapNaviPoint *end = [AMapNaviPoint locationWithLatitude:latitude longitude:longitude];
    BOOL accepted;
    if (start) {
        AMapNaviPoint *begin = [AMapNaviPoint locationWithLatitude:[start[@"latitude"] doubleValue] longitude:[start[@"longitude"] doubleValue]];
        accepted = [self.manager calculateDriveRouteWithStartPoints:@[begin] endPoints:@[end] wayPoints:nil drivingStrategy:AMapNaviDrivingStrategyMultipleDefault];
    } else {
        accepted = [self.manager calculateDriveRouteWithEndPoints:@[end] wayPoints:nil drivingStrategy:AMapNaviDrivingStrategyMultipleDefault];
    }
    if (!accepted) self.planning = NO;
    return accepted;
}
- (BOOL)selectRoute:(NSInteger)route {
    if (self.disposed || self.planning || self.running || !self.manager.naviRoutes[@(route)]) return NO;
    BOOL result = [self.manager selectNaviRouteWithRouteID:route];
    if (result) { [self publishRoute]; self.driveView.showMode = AMapNaviDriveViewShowModeOverview; }
    return result;
}
- (BOOL)start {
    if (self.disposed || self.running || self.planning || !self.manager.naviRoute) return NO;
    self.starting = YES;
    BOOL result = [self.manager startGPSNavi];
    if (!result) self.starting = NO;
    return result;
}
- (NSArray *)coordinates:(NSArray<AMapNaviPoint *> *)points {
    NSMutableArray *result = [NSMutableArray new];
    for (AMapNaviPoint *p in points) [result addObject:@{@"latitude": @(p.latitude), @"longitude": @(p.longitude)}];
    return result;
}
- (void)publishRoute {
    self.matched = NO; self.matchAt = 0;
    AMapNaviRoute *route = self.manager.naviRoute;
    if (!route) return;
    NSMutableArray *segments = [NSMutableArray new];
    [route.routeSegments enumerateObjectsUsingBlock:^(AMapNaviSegment *segment, NSUInteger index, BOOL *stop) {
        NSMutableArray *links = [NSMutableArray new];
        for (AMapNaviLink *link in segment.links) {
            [links addObject:@{@"length": @(link.length), @"road": link.roadName ?: @"", @"signal": @(link.isHadTrafficLights),
                @"internalRoad": @(link.formWay == AMapNaviFormWayInternalRoad), @"coordinates": [self coordinates:link.coordinates]}];
        }
        [segments addObject:@{@"index": @(index), @"length": @(segment.length), @"icon": @(segment.iconType),
            @"signals": @(segment.trafficLightCount), @"coordinates": [self coordinates:segment.coordinates], @"links": links}];
    }];
    NSString *uid = [NSString stringWithFormat:@"%llu", (unsigned long long)route.routeUID];
    [self emit:@"route" data:@{@"routeID": uid, @"segments": segments}];
}
- (void)driveManager:(AMapNaviDriveManager *)manager onCalculateRouteSuccessWithType:(AMapNaviRoutePlanType)type {
    if (self.disposed) return;
    self.planning = NO;
    NSMutableArray *choices = [NSMutableArray new];
    for (NSNumber *rid in manager.naviRouteIDs) {
        AMapNaviRoute *r = manager.naviRoutes[rid];
        if (r.routeLength > 0 && r.routeTime > 0) [choices addObject:@{@"id": rid, @"meters": @(r.routeLength), @"seconds": @(r.routeTime), @"label": @"驾车方案"}];
    }
    [self emit:@"routes" data:@{@"routes": choices}]; [self publishRoute];
}
- (void)driveManager:(AMapNaviDriveManager *)manager onCalculateRouteFailure:(NSError *)error {
    self.planning = NO;
    [self emit:@"error" data:@{@"message": [NSString stringWithFormat:@"路线规划失败（%ld），请检查网络、定位及服务授权", (long)error.code]}];
}
- (void)driveManager:(AMapNaviDriveManager *)manager error:(NSError *)error {
    [self emit:@"error" data:@{@"message": [NSString stringWithFormat:@"导航服务异常（%ld）", (long)error.code]}];
}
- (void)driveManager:(AMapNaviDriveManager *)manager didStartNavi:(AMapNaviMode)mode {
    if (!self.starting || mode != AMapNaviModeGPS || self.disposed) { [manager stopNavi]; return; }
    self.starting = NO; self.running = YES; self.matched = NO; self.weakGPS = NO;
    self.driveView.showMode = AMapNaviDriveViewShowModeCarPositionLocked;
    [self publishRoute]; [self emit:@"started" data:@{}];
    __weak LANavigationBridge *weakSelf = self;
    self.timer = [NSTimer scheduledTimerWithTimeInterval:0.05 repeats:YES block:^(NSTimer *t) { [weakSelf animateCar]; }];
}
- (void)driveManager:(AMapNaviDriveManager *)manager updateNaviRoute:(AMapNaviRoute *)route {
    if (self.running) [self publishRoute];
}
- (void)driveManagerNeedRecalculateRouteForYaw:(AMapNaviDriveManager *)manager {
    self.matched = NO; self.speed = 0; [self emit:@"suspended" data:@{@"message": @"偏航重算中，等待新路线"}];
}
- (void)driveManagerNeedRecalculateRouteForTrafficJam:(AMapNaviDriveManager *)manager {
    self.matched = NO; self.speed = 0; [self emit:@"suspended" data:@{@"message": @"路况重算中，等待新路线"}];
}
- (void)driveManager:(AMapNaviDriveManager *)manager updateGPSSignalStrength:(AMapNaviGPSSignalStrength)strength {
    self.weakGPS = strength != AMapNaviGPSSignalStrengthStrong;
    if (self.weakGPS) { self.matched = NO; self.speed = 0; [self emit:@"suspended" data:@{@"message": @"定位信号弱，暂停车道采集"}]; }
}
- (void)driveManager:(AMapNaviDriveManager *)manager updateNaviLocation:(AMapNaviLocation *)location {
    if (!self.running || self.disposed) return;
    NSTimeInterval stamp = location.timestamp.timeIntervalSince1970;
    if (location && stamp <= self.lastLocationAt) return;
    if (location) self.lastLocationAt = stamp;
    BOOL reliable = location && location.isMatchNaviPath && !location.isNetworkNavi && location.accuracy >= 0 &&
        location.accuracy <= 50 && fabs(location.timestamp.timeIntervalSinceNow) <= 5 && !self.weakGPS;
    self.matched = reliable; self.matchedStep = location.currentSegmentIndex; self.matchAt = NSDate.date.timeIntervalSince1970;
    if (!reliable) { self.speed = 0; [self emit:@"suspended" data:@{@"message": @"等待可靠的路线匹配定位"}]; return; }
    if (self.foreground) { self.speed = MAX(0, location.speed); self.speedAt = NSDate.date.timeIntervalSince1970; }
}
- (void)driveManager:(AMapNaviDriveManager *)manager updateNaviInfo:(AMapNaviInfo *)info {
    if (!self.running || self.disposed || !self.foreground || !info || !self.matched || self.weakGPS ||
        info.naviMode != AMapNaviModeGPS || info.currentSegmentIndex != self.matchedStep ||
        NSDate.date.timeIntervalSince1970 - self.matchAt > 2.5) return;
    [self emit:@"progress" data:@{@"routeID": [NSString stringWithFormat:@"%llu", (unsigned long long)manager.naviRoute.routeUID],
        @"step": @(info.currentSegmentIndex), @"remaining": @(info.segmentRemainDistance),
        @"routeRemaining": @(info.routeRemainDistance), @"seconds": @(info.routeRemainTime), @"speed": @(self.speed)}];
}
- (void)driveManager:(AMapNaviDriveManager *)manager showLaneBackInfo:(NSString *)back laneSelectInfo:(NSString *)selection {
    if (!self.running || !self.foreground || self.disposed) return;
    if (!self.matched || self.weakGPS || NSDate.date.timeIntervalSince1970 - self.matchAt > 2.5) {
        [self emit:@"blockedLane" data:@{}]; return;
    }
    [self emit:@"lanes" data:@{@"background": back ?: @"", @"selection": selection ?: @""}];
}
- (void)driveManagerHideLaneInfo:(AMapNaviDriveManager *)manager { if (self.running) [self emit:@"hide" data:@{}]; }
- (void)driveManagerOnArrivedDestination:(AMapNaviDriveManager *)manager {
    if (self.running) { self.running = NO; self.speed = 0; [self.timer invalidate]; self.timer = nil; [self emit:@"arrived" data:@{}]; }
}
- (void)driveManager:(AMapNaviDriveManager *)manager updateNaviMode:(AMapNaviMode)mode {
    if (mode == AMapNaviModeNone && self.running) { self.running = NO; [self emit:@"stopped" data:@{}]; }
}
- (void)driveViewCloseButtonClicked:(AMapNaviDriveView *)view { [self emit:@"close" data:@{}]; }
- (void)setForeground:(BOOL)foreground {
    _foreground = foreground; self.speed = 0; self.matched = NO; self.animationAt = 0;
}
- (void)animateCar {
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    NSTimeInterval dt = self.animationAt > 0 ? now - self.animationAt : 0; self.animationAt = now;
    if (!self.running || !self.foreground || self.weakGPS || now - self.speedAt > 5 || dt <= 0 || dt > 0.5 || self.speed < 2) return;
    self.angle = fmod(self.angle + MIN(30, self.speed / 4.0) * 6 * dt, 360);
    NSInteger index = (NSInteger)(self.angle / 5) % 72;
    [self applyCarFrame:index];
}
- (void)applyCarFrame:(NSInteger)index {
    if (self.lastFrame == index) return;
    UIImage *frame = self.frames[@(index)];
    if (!frame) {
        if (!self.atlas) self.atlas = [UIImage imageNamed:@"volkswagen-car-frames.png"];
        if (!self.atlas.CGImage) return;
        CGImageRef crop = CGImageCreateWithImageInRect(self.atlas.CGImage, CGRectMake(0, index * 112, 112, 112));
        if (!crop) return;
        frame = [UIImage imageWithCGImage:crop scale:2 orientation:UIImageOrientationUp]; CGImageRelease(crop);
        self.frames[@(index)] = frame;
    }
    [self.driveView setCarImage:frame];
    self.lastFrame = index;
}
- (void)finish {
    if (self.disposed) return;
    self.disposed = YES; self.running = NO; self.eventHandler = nil;
    [self.timer invalidate]; self.timer = nil;
    self.manager.delegate = nil; self.driveView.delegate = nil;
    [self.manager removeDataRepresentative:self];
    if (self.driveView) [self.manager removeDataRepresentative:self.driveView];
    [self.manager stopNavi]; self.manager.allowsBackgroundLocationUpdates = NO;
    self.driveView = nil; self.manager = nil; self.atlas = nil; [self.frames removeAllObjects];
    [AMapNaviDriveManager destroyInstance];
}
- (void)dealloc { [self finish]; }
@end
#endif
