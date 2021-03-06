/*
 *     Generated by class-dump 3.4 (64 bit).
 *
 *     class-dump is Copyright (C) 1997-1998, 2000-2001, 2004-2012 by Steve Nygard.
 */

#import <Foundation/NSObject.h>

@protocol SBIconAccessoryView <NSObject>
+ (id)checkoutAccessoryImagesForIcon:(id)arg1 location:(int)arg2;
- (void)prepareForReuse;
- (void)setAccessoryBrightness:(float)arg1;
- (BOOL)displayingAccessory;
- (struct CGPoint)accessoryOriginForIconBounds:(struct CGRect)arg1;
- (void)configureForIcon:(id)arg1 location:(int)arg2 highlighted:(BOOL)arg3;
- (void)configureAnimatedForIcon:(id)arg1 location:(int)arg2 highlighted:(BOOL)arg3 withPreparation:(id)arg4 animation:(void)arg5 completion:(id)arg6;
@end

