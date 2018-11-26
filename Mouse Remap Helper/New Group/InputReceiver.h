//
//  InputReceiver.h
//  Mouse Remap Helper
//
//  Created by Noah Nübling on 19.11.18.
//  Copyright © 2018 Noah Nuebling Enterprises Ltd. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface InputReceiver : NSObject
+ (BOOL)relevantDevicesAreAttached;
+ (void)start;
@end
NS_ASSUME_NONNULL_END