// Copyright 2019 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#import "FLTMobileAd.h"
#import "FLTFirebaseAdMobPlugin.h"
#import "FLTRequestFactory.h"

static NSMutableDictionary *allAds = nil;
static NSDictionary *statusToString = nil;

@interface FLTMobileAd ()

@property(nonatomic, assign) FLTMobileAdStatus status;

@end

@implementation FLTMobileAd {
  NSNumber *_mobileAdId;
}
FlutterMethodChannel *_channel;
//FLTMobileAdStatus _status;
double _anchorOffset;
double _horizontalCenterOffset;
int _anchorType;

+ (void)initialize {
  if (allAds == nil) {
    allAds = [[NSMutableDictionary alloc] init];
  }
  _anchorType = 0;
  _anchorOffset = 0;
  _horizontalCenterOffset = 0;

  if (statusToString == nil) {
    statusToString = @{
      @(CREATED) : @"CREATED",
      @(LOADING) : @"LOADING",
      @(FAILED) : @"FAILED",
      @(PENDING) : @"PENDING",
      @(LOADED) : @"LOADED"
    };
  }
}

+ (void)configureWithAppId:(NSString *)appId {
  [GADMobileAds configureWithApplicationID:appId];
  [GADMobileAds sharedInstance].applicationVolume = 0.0;
}

+ (FLTMobileAd *)getAdForId:(NSNumber *)mobileAdId {
  return allAds[mobileAdId];
}

+ (UIViewController *)rootViewController {
  return [UIApplication sharedApplication].delegate.window.rootViewController;
}

- (instancetype)initWithId:(NSNumber *)mobileAdId channel:(FlutterMethodChannel *)channel {
  self = [super init];
  if (self) {
    _mobileAdId = mobileAdId;
    _channel = channel;
    self.status = CREATED;
    _anchorOffset = 0;
    _horizontalCenterOffset = 0;
    _anchorType = 0;
    allAds[mobileAdId] = self;
  }
  return self;
}

- (FLTMobileAdStatus)status {
  return _status;
}

- (void)loadWithAdUnitId:(NSString *)adUnitId targetingInfo:(NSDictionary *)targetingInfo {
  // Implemented by the Banner and Interstitial subclasses
}

- (void)showAtOffset:(double)anchorOffset
       hCenterOffset:(double)horizontalCenterOffset
          fromAnchor:(int)anchorType {
  _anchorType = anchorType;
  _anchorOffset = anchorOffset;
  if (_anchorType == 0) {
    _anchorOffset = -_anchorOffset;
  }
  _horizontalCenterOffset = horizontalCenterOffset;
  [self show];
}

- (void)show {
  // Implemented by the Banner and Interstitial subclasses
}

- (void)dispose {
  [allAds removeObjectForKey:_mobileAdId];
}

- (NSDictionary *)argumentsMap {
  return @{@"id" : _mobileAdId};
}

- (NSString *)description {
  NSString *statusString = (NSString *)statusToString[[NSNumber numberWithInt:self.status]];
  return [NSString
      stringWithFormat:@"%@ %@ mobileAdId:%@", super.description, statusString, _mobileAdId];
}
@end

@implementation FLTBannerAd
GADBannerView *_banner;
GADAdSize _adSize;

+ (instancetype)withId:(NSNumber *)mobileAdId
                adSize:(GADAdSize)adSize
               channel:(FlutterMethodChannel *)channel {
  FLTMobileAd *ad = [FLTMobileAd getAdForId:mobileAdId];
  return ad != nil ? (FLTBannerAd *)ad
                   : [[FLTBannerAd alloc] initWithId:mobileAdId adSize:adSize channel:channel];
}

- (instancetype)initWithId:mobileAdId
                    adSize:(GADAdSize)adSize
                   channel:(FlutterMethodChannel *)channel {
  self = [super initWithId:mobileAdId channel:channel];
  if (self) {
    _adSize = adSize;
    return self;
  }

  return nil;
}

- (void)loadWithAdUnitId:(NSString *)adUnitId targetingInfo:(NSDictionary *)targetingInfo {
  if (self.status != CREATED) return;
  self.status = LOADING;
  _banner = [[GADBannerView alloc] initWithAdSize:_adSize];
  _banner.delegate = self;
  _banner.adUnitID = adUnitId;
  _banner.rootViewController = [FLTMobileAd rootViewController];
  FLTRequestFactory *factory = [[FLTRequestFactory alloc] initWithTargetingInfo:targetingInfo];
  [_banner loadRequest:[factory createRequest]];
}

- (void)show {
  if (self.status == LOADING) {
    self.status = PENDING;
    return;
  }

  if (self.status != LOADED) return;

  _banner.translatesAutoresizingMaskIntoConstraints = NO;
  UIView *screen = [FLTMobileAd rootViewController].view;
  [screen addSubview:_banner];

#if defined(__IPHONE_11_0) && (__IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_11_0)
  if (@available(ios 11.0, *)) {
    UILayoutGuide *guide = screen.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
      [_banner.centerXAnchor constraintEqualToAnchor:guide.centerXAnchor
                                            constant:_horizontalCenterOffset],
      [_banner.bottomAnchor
          constraintEqualToAnchor:_anchorType == 0 ? guide.bottomAnchor : guide.topAnchor
                         constant:_anchorOffset]
    ]];
  } else {
    [self placeBannerPreIos11];
  }
#else
  [self placeBannerPreIos11];
#endif
}

- (void)placeBannerPreIos11 {
  UIView *screen = [FLTMobileAd rootViewController].view;
  CGFloat x = screen.frame.size.width / 2 - _banner.frame.size.width / 2 + _horizontalCenterOffset;
  CGFloat y;
  if (_anchorType == 0) {
    y = screen.frame.size.height - _banner.frame.size.height + _anchorOffset;
  } else {
    y = _anchorOffset;
  }
  _banner.frame = (CGRect){{x, y}, _banner.frame.size};
  [screen addSubview:_banner];
}

- (void)adViewDidReceiveAd:(GADBannerView *)adView {
  bool statusWasPending = self.status == PENDING;
  self.status = LOADED;
  [_channel invokeMethod:@"onAdLoaded" arguments:[self argumentsMap]];
  if (statusWasPending) [self show];
}

- (void)adView:(GADBannerView *)adView didFailToReceiveAdWithError:(GADRequestError *)error {
  FLTLogWarning(@"adView:didFailToReceiveAdWithError: %@ (MobileAd %@)",
                [error localizedDescription], self);
  [_channel invokeMethod:@"onAdFailedToLoad" arguments:[self argumentsMap]];
}

- (void)adViewWillPresentScreen:(GADBannerView *)adView {
  [_channel invokeMethod:@"onAdClicked" arguments:[self argumentsMap]];
}

- (void)adViewWillDismissScreen:(GADBannerView *)adView {
  [_channel invokeMethod:@"onAdImpression" arguments:[self argumentsMap]];
}

- (void)adViewDidDismissScreen:(GADBannerView *)adView {
  [_channel invokeMethod:@"onAdClosed" arguments:[self argumentsMap]];
}

- (void)adViewWillLeaveApplication:(GADBannerView *)adView {
  [_channel invokeMethod:@"onAdLeftApplication" arguments:[self argumentsMap]];
}

- (void)dispose {
  if (_banner.superview) [_banner removeFromSuperview];
  _banner = nil;
  [super dispose];
}

- (NSString *)description {
  return [NSString stringWithFormat:@"%@ for: %@", super.description, _banner];
}
@end

@implementation FLTInterstitialAd
GADInterstitial *_interstitial;

+ (instancetype)withId:(NSNumber *)mobileAdId channel:(FlutterMethodChannel *)channel {
  FLTMobileAd *ad = [FLTMobileAd getAdForId:mobileAdId];
  return ad != nil ? (FLTInterstitialAd *)ad
                   : [[FLTInterstitialAd alloc] initWithId:mobileAdId channel:channel];
}

- (void)loadWithAdUnitId:(NSString *)adUnitId targetingInfo:(NSDictionary *)targetingInfo {
  if (self.status != CREATED) return;
  self.status = LOADING;

  _interstitial = [[GADInterstitial alloc] initWithAdUnitID:adUnitId];
  _interstitial.delegate = self;
  FLTRequestFactory *factory = [[FLTRequestFactory alloc] initWithTargetingInfo:targetingInfo];
  [_interstitial loadRequest:[factory createRequest]];
}

- (void)show {
  if (self.status == LOADING) {
    self.status = PENDING;
    return;
  }
  if (self.status != LOADED) return;

  [_interstitial presentFromRootViewController:[FLTMobileAd rootViewController]];
}

- (void)interstitialDidReceiveAd:(GADInterstitial *)ad {
  bool statusWasPending = self.status == PENDING;
  self.status = LOADED;
  [_channel invokeMethod:@"onAdLoaded" arguments:[self argumentsMap]];
  if (statusWasPending) [self show];
}

- (void)interstitial:(GADInterstitial *)ad didFailToReceiveAdWithError:(GADRequestError *)error {
  FLTLogWarning(@"interstitial:didFailToReceiveAdWithError: %@ (MobileAd %@)",
                [error localizedDescription], self);
  [_channel invokeMethod:@"onAdFailedToLoad" arguments:[self argumentsMap]];
}

- (void)interstitialWillPresentScreen:(GADInterstitial *)ad {
  [_channel invokeMethod:@"onAdClicked" arguments:[self argumentsMap]];
}

- (void)interstitialWillDismissScreen:(GADInterstitial *)ad {
  [_channel invokeMethod:@"onAdImpression" arguments:[self argumentsMap]];
}

- (void)interstitialDidDismissScreen:(GADInterstitial *)ad {
  [_channel invokeMethod:@"onAdClosed" arguments:[self argumentsMap]];
}

- (void)interstitialWillLeaveApplication:(GADInterstitial *)ad {
  [_channel invokeMethod:@"onAdLeftApplication" arguments:[self argumentsMap]];
}

- (void)dispose {
  // It is not possible to hide/remove/destroy an AdMob interstitial Ad.
  _interstitial = nil;
  [super dispose];
}

- (NSString *)description {
  return [NSString stringWithFormat:@"%@ for: %@", super.description, _interstitial];
}
@end
