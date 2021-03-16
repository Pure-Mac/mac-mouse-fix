//
// --------------------------------------------------------------------------
// ModifierManager.m
// Created for Mac Mouse Fix (https://github.com/noah-nuebling/mac-mouse-fix)
// Created by Noah Nuebling in 2020
// Licensed under MIT
// --------------------------------------------------------------------------
//

#import "Constants.h"

#import "ModifierManager.h"
#import "ButtonTriggerGenerator.h"
#import "TransformationManager.h"
#import "ModifiedDrag.h"
#import "DeviceManager.h"


@implementation ModifierManager

/// Trigger driven modification -> when the trigger to be modified comes in, we check how we want to modify it
/// Modifier driven modification -> when the modification becomes active, we preemtively modify the triggers which it modifies
#pragma mark - Load

/// This used to be initialize but  that didn't execute until the first mouse buttons were pressed
+ (void)load {
    if (self == [ModifierManager class]) {
        // Create keyboard modifier event tap
        CGEventMask mask = CGEventMaskBit(kCGEventFlagsChanged);
        _keyboardModifierEventTap = CGEventTapCreate(kCGHIDEventTap, kCGTailAppendEventTap, kCGEventTapOptionDefault, mask, handleKeyboardModifiersHaveChanged, NULL);
        CFRunLoopSourceRef runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, _keyboardModifierEventTap, 0);
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, kCFRunLoopDefaultMode);
        CFRelease(runLoopSource);
        
        // Toggle keyboard modifier callbacks based on TransformationManager.remaps
        toggleModifierEventTapBasedOnRemaps(TransformationManager.remaps);
        
        // Re-toggle keyboard modifier callbacks whenever TransformationManager.remaps changes
        // TODO:! Test if this works
        [NSNotificationCenter.defaultCenter addObserverForName:kMFNotificationNameRemapsChanged
                                                        object:nil
                                                         queue:nil
                                                    usingBlock:^(NSNotification * _Nonnull note) {
    #if DEBUG
            NSLog(@"Received notification that remaps have changed");
    #endif
            toggleModifierEventTapBasedOnRemaps(TransformationManager.remaps);
        }];
    }
}
#pragma mark - Modifier driven modification

#pragma mark Keyboard modifiers

static CFMachPortRef _keyboardModifierEventTap;
static void toggleModifierEventTapBasedOnRemaps(NSDictionary *remaps) {

    // If a modification collection exists such that it contains a proactive modification and its precondition contains a keyboard modifier, then activate the event tap.
    for (NSDictionary *modificationPrecondition in remaps) {
        NSDictionary *modificationCollection = remaps[modificationPrecondition];
        BOOL collectionContainsProactiveModification = modificationCollection[kMFTriggerDrag] != nil;
            // ^ proactive modification === modifier driven modification !== trigger driven modification
        if (collectionContainsProactiveModification) {
            BOOL modificationDependsOnKeyboardModifier = modificationPrecondition[kMFModificationPreconditionKeyKeyboard] != nil;
            if (modificationDependsOnKeyboardModifier) {
                CGEventTapEnable(_keyboardModifierEventTap, true);
                return;
            }
        }
    }
    CGEventTapEnable(_keyboardModifierEventTap, false);
}

CGEventRef _Nullable handleKeyboardModifiersHaveChanged(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *userInfo) {
    
    CGEventTapPostEvent(proxy, event);
    
    NSArray<MFDevice *> *devs = DeviceManager.attachedDevices;
    for (MFDevice *dev in devs) {
        NSDictionary *activeModifiers = [ModifierManager getActiveModifiersForDevice:dev.uniqueID filterButton:nil event:event];
        // ^ Need to pass in event here as source for keyboard modifers, otherwise the returned kb-modifiers won't be up-to-date.
        
//        // The keyboard component of activeModifiers doesn't update fast enough so we have to update it again here using the event.
//        // This is kinofa hack we should clean this up
//        NSMutableDictionary *activeModifiersNew = activeModifiers.mutableCopy;
//        CGEventFlags flags = [ModifierManager getActiveKeyboardModifiersWithEvent:event];
////        if (flags != 0) { // Why check for 0 here?
//            activeModifiersNew[kMFModificationPreconditionKeyKeyboard] = @(flags);
////        }
        
        reactToModifierChange(activeModifiers, dev);
    }
    return nil;
}

#pragma mark Button modifiers

NSArray *_prevButtonModifiers;
+ (void)handleButtonModifiersMightHaveChangedWithDevice:(MFDevice *)device {
    NSArray *buttonModifiers = [ButtonTriggerGenerator getActiveButtonModifiersForDevice:device.uniqueID];
    if (![buttonModifiers isEqual:_prevButtonModifiers]) {
        handleButtonModifiersHaveChangedWithDevice(device);
    }
    _prevButtonModifiers = buttonModifiers;
}
static void handleButtonModifiersHaveChangedWithDevice(MFDevice *device) {
    NSDictionary *activeModifiers = [ModifierManager getActiveModifiersForDevice:device.uniqueID filterButton:nil event:nil];
    reactToModifierChange(activeModifiers, device);
}

#pragma mark Helper

static void reactToModifierChange(NSDictionary *_Nonnull activeModifiers, MFDevice * _Nonnull device) {
    
#if DEBUG
    NSLog(@"MODIFERS HAVE CHANGED TO - %@", activeModifiers);
#endif
    
    // Kill the currently active modified drag
    //      (or any other effects which are modifier driven, but currently modified drag is the only one)
    // \note The precondition for any currently active modifications can't be true anymore because
    //      we know that the activeModifers have changed (that's why this function was called)
    //      Because of this we can simply kill everything without any further checks
    [ModifiedDrag deactivate];
    
    // Get active modifications and initialize any which are modifier driven
    NSDictionary *activeModifications = TransformationManager.remaps[activeModifiers];
    // Do weird stuff if AddMode is active.
    if (TransformationManager.remaps[@{kMFAddModeModificationPrecondition:@YES}] != nil) { // This means AddMode is active
            if (activeModifiers.allKeys.count != 0) { // We activate modifications, if activeModifiers isn't _completely_ empty
                activeModifications = TransformationManager.remaps[@{kMFAddModeModificationPrecondition: @YES}];
            }
    }
    if (activeModifications) {
#if DEBUG
        NSLog(@"ACTIVE MODIFICATIONS - %@", activeModifications);
#endif
        // Initialize effects which are modifier driven (only modified drag)
        NSMutableDictionary *modifiedDragEffect = activeModifications[kMFTriggerDrag]; // Probably not truly mutable at this point
        if (modifiedDragEffect) {
            // Add modificationPrecondition info for addMode. See TransformationManager -> AddMode for context
            if ([modifiedDragEffect[kMFModifiedDragDictKeyType] isEqualToString:kMFModifiedDragTypeAddModeFeedback]) {
                modifiedDragEffect = modifiedDragEffect.mutableCopy;
                modifiedDragEffect[kMFRemapsKeyModificationPrecondition] = activeModifiers;
            }
            [ModifiedDrag initializeDragWithModifiedDragDict:modifiedDragEffect onDevice:device];
        }
    }
}

#pragma mark Send Feedback

+ (void)handleModifiersHaveHadEffect:(NSNumber *)devID {
    
    NSDictionary *activeModifiers = [self getActiveModifiersForDevice:devID filterButton:nil event:nil];
        
    // Notify all active button modifiers that they have had an effect
    for (NSDictionary *buttonPrecondDict in activeModifiers[kMFModificationPreconditionKeyButtons]) {
        NSNumber *precondButtonNumber = buttonPrecondDict[kMFButtonModificationPreconditionKeyButtonNumber];
        [ButtonTriggerGenerator handleButtonHasHadEffectAsModifierWithDevice:devID button:precondButtonNumber];
    }
}

#pragma mark - Trigger driven modification
// Explanation: Modification of most triggers is *trigger driven*.
//      That means only once the trigger comes in, we'll check for active modifiers and then apply those to the incoming trigger.
//      But sometimes its not feasible to always listen for triggers (for example in the case of modified drags, for performance reasons)
//      In those cases we'll use *modifier driven* modification.
//      That means we listen for changes to the active modifiers and when they match a modifications' precondition, we'll initialize the modification components which are modifier driven.
//      Then, when they do send their first trigger, they'll call modifierDrivenModificationHasBeenUsedWithDevice which will in turn notify the modifying buttons that they've had an effect
// \discussion If you pass in an a CGEvent via the `event` argument, the returned keyboard modifiers will be more up-to-date. This is sometimes necessary to get correct data when calling this right after the keyboard modifiers have changes.

+ (NSDictionary *)getActiveModifiersForDevice:(NSNumber *)devID filterButton:(NSNumber * _Nullable)filteredButton event:(CGEventRef _Nullable) event {
    
    NSMutableDictionary *outDict = [NSMutableDictionary dictionary];
    
    NSUInteger kb = [self getActiveKeyboardModifiersWithEvent:nil];
    NSMutableArray *btn = [ButtonTriggerGenerator getActiveButtonModifiersForDevice:devID].mutableCopy;
    if (filteredButton != nil && btn.count != 0) {
        NSIndexSet *filterIndexes = [btn indexesOfObjectsPassingTest:^BOOL(NSDictionary *_Nonnull dict, NSUInteger idx, BOOL * _Nonnull stop) {
            return [dict[kMFButtonModificationPreconditionKeyButtonNumber] isEqualToNumber:filteredButton];
        }];
        [btn removeObjectsAtIndexes:filterIndexes];
    }
    // ^ filteredButton is used by `handleButtonTriggerWithButton:trigger:level:device:` to remove modification state caused by the button causing the current input trigger.
        // Don't fully understand this but I think a button shouldn't modify its own triggers.
        // You can't even produce a mouse down trigger without activating the button as a modifier... Just doesn't make sense.
    
    if (kb != 0) {
        outDict[kMFModificationPreconditionKeyKeyboard] = @(kb);
    }
    if (btn.count != 0) {
        outDict[kMFModificationPreconditionKeyButtons] = btn;
    }
    
    return outDict;
}
+ (NSUInteger) getActiveKeyboardModifiersWithEvent:(CGEventRef _Nullable) event {
    
    if (event == nil) {
        event = CGEventCreate(nil);
    }
    
    uint64_t mask = 0xFF0000; // Only lets bits 16-23 through
    // NSEventModifierFlagDeviceIndependentFlagsMask == 0xFFFF0000 -> it only allows bits 16 - 31.
    //  But bits 24 - 31 contained weird stuff which messed up the return value and modifiers are only on bits 16-23, so we defined our own mask
    
    CGEventFlags modifierFlags = CGEventGetFlags(event) & mask;
    return modifierFlags;
}

@end
