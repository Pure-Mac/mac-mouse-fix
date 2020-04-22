//
// --------------------------------------------------------------------------
// SmoothScroll.h
// Created for Mac Mouse Fix (https://github.com/noah-nuebling/mac-mouse-fix)
// Created by Noah Nuebling in 2019
// Licensed under MIT
// --------------------------------------------------------------------------
//

#import <Cocoa/Cocoa.h>
#import "ScrollControl.h"

@interface SmoothScroll : ScrollControl

+ (void)load_Manual;

+ (void)configureWithParameters:(NSDictionary *)params;

+ (void)start;
+ (void)stop;
+ (BOOL)isRunning;

+ (void)handleInput:(CGEventRef)event info:(NSDictionary *)info;

@end

