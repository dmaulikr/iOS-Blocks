/*
//
// Curago
//
// Take control.
//
// (c) Matt Clarke, 2014.
//
// 
// curago.xm - 25/5/2014
//
*/

#import <SpringBoard7.0/SBIconController.h>
#import <SpringBoard7.0/SBFolder.h>
#import <SpringBoard7.0/SBRootFolder.h>
#import <SpringBoard7.0/SBIconListModel.h>
#import <SpringBoard7.0/SBIconModel.h>
#import <SpringBoard7.0/SBIconListView.h>
#import <SpringBoard7.0/SBIconImageView.h>
#import <SpringBoard7.0/SBIconView.h>
#import <SpringBoard7.0/SBApplicationIcon.h>
#import <SpringBoard7.0/SBFolderIcon.h>
#import <SpringBoard7.0/SBIconIndexMutableList.h>
#import <SpringBoard7.0/SBIconViewMap.h>
#import <SpringBoard7.0/SBIconScrollView.h>
#import <SpringBoard7.0/SBIconBadgeView.h>
#import <SpringBoard7.0/SBRootFolderController.h>
#import <SpringBoard7.0/SBRootFolderView.h>
//#import <SpringBoard8.1/SBFolderView.h>
#import <objc/runtime.h>

#import <QuartzCore/QuartzCore.h>
#import <BulletinBoard/BBServer.h>
#import <BulletinBoard/BBBulletin.h>

#import "IBKResources.h"
#import "IBKWidgetViewController.h"

#define isPad (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad)

@interface SBFAnimationSettings : NSObject
@property double duration;
+ (id)settingsControllerModule;
@end

// Structs

typedef struct SBIconCoordinate {
    NSUInteger row;
    NSUInteger col;
} SBIconCoordinate;

// Class additions

@interface SBIconListView (Additions)
-(SBIconCoordinate)coordinateForIconWithIndex:(unsigned int)index andOriginalCoordinate:(SBIconCoordinate)orig;
-(SBIcon*)modifiedIconForIcon:(SBIcon*)icon;
@end

@interface SBIconModel (iOS8)
- (void)saveIconStateIfNeeded;
@end

@interface IBKIconView : SBIconView

+(IBKWidgetViewController*)getWidgetViewControllerForIcon:(SBIcon*)arg1 orBundleID:(NSString*)arg2;

@end

// Globals

NSMutableDictionary *cachedIndexes;
NSMutableSet *movedIndexPaths;
NSMutableDictionary *widgetViewControllers;

int icons = 0;
int currentOrientation = 1;

BOOL animatingIn = NO;
BOOL rearrangingIcons = NO;
BOOL iWidgets = NO;

static BBServer* __weak IBKBBServer;

// Hooks

#pragma mark Icon co-ordinate placements

%hook SBIconListView

- (_Bool)isFull {
    int count = 1;
    
    for (SBIcon *icon in [self icons]) {
        if ([[IBKResources widgetBundleIdentifiers] containsObject:[icon applicationBundleID]]) {
            count += 3;
        }
        
        count++;
    }
    
    return (count >= [objc_getClass("SBIconListView") maxIcons]);
}

- (void)prepareToRotateToInterfaceOrientation:(int)arg1 {
    // Ensure that icons are uncached
    [cachedIndexes removeAllObjects];
    currentOrientation = arg1;
    NSLog(@"******** Cached icons removed to prepare for orientation change, and current or == %d", currentOrientation);
    
    %orig;
}

// Deal with editing mode. The *AtPoint: methods are here for logging purposes only.

- (unsigned int)rowAtPoint:(struct CGPoint)arg1 {
    unsigned int orig = %orig;
    NSLog(@"*** [Curago] :: designating row %d for point %@", orig, NSStringFromCGPoint(arg1));

    return orig;
}

- (unsigned int)columnAtPoint:(struct CGPoint)arg1 {
    unsigned int column = %orig;
    NSLog(@"*** [Curago] :: designating column %d for point %@", column, NSStringFromCGPoint(arg1));
    
    return column;
}

- (unsigned int)indexForCoordinate:(struct SBIconCoordinate)arg1 forOrientation:(int)arg2 {
    unsigned int orig = %orig;
    NSLog(@"Old index == %u", orig);
    
    NSLog(@"arg1 == {col: %lu, row: %lu}", (unsigned long)arg1.col, (unsigned long)arg1.row);
    
    // This motherfucker is always wrong when there's widgets!
    
    // Alright. We calculate precisely how many widget spaces are before us.
    unsigned int i = 0;
    
    for (NSString *bundleIdentifier in [IBKResources widgetBundleIdentifiers]) {
        if ([(SBIconListModel*)[self model] containsLeafIconWithIdentifier:bundleIdentifier]) {
            // Oh cool. Take it's co-ordinate.
            int a = (int)[[self model] indexForLeafIconWithIdentifier:bundleIdentifier];
            SBIconCoordinate widget = [self iconCoordinateForIndex:a forOrientation:arg2];
            
            NSLog(@"Widget's co-ordinate == {col: %lu, row: %lu}", (unsigned long)widget.col, (unsigned long)widget.row);
        
            // Top right.
            if ((widget.col+1) == arg1.col && widget.row == arg1.row) {
                NSLog(@"INVALID LOCATION");
                return -1;
            } else {
                if (widget.row < arg1.row)
                    i++;
                else if ((widget.col+1) < arg1.col && widget.row == arg1.row)
                    i++;
            }
            
            // Bottom left
            if (widget.col == arg1.col && (widget.row+1) == arg1.row) {
                NSLog(@"INVALID LOCATION");
                return -1;
            } else {
                if ((widget.row+1) < arg1.row)
                    i++;
                else if (widget.col < arg1.col && (widget.row+1) == arg1.row)
                    i++;
            }
            
            // Bottom right
            if ((widget.col+1) == arg1.col && (widget.row+1) == arg1.row) {
                NSLog(@"INVALID LOCATION");
                return -1;
            } else {
                if ((widget.row+1) < arg1.row)
                    i++;
                else if ((widget.col+1) < arg1.col && (widget.row+1) == arg1.row)
                    i++;
            }
            
        }
    }
    
    orig -= i;
    
    //NSLog(@"i ended up being == %u", i);
    //NSLog(@"Final index == %u", orig);
    
    return orig;
}

// Calculate the position of icons.

- (struct SBIconCoordinate)iconCoordinateForIndex:(unsigned int)arg1 forOrientation:(int)arg2 {
    SBIconCoordinate orig = %orig;
    
    if (![[self class] isEqual:[objc_getClass("SBDockIconListView") class]] && ![[self class] isEqual:[objc_getClass("SBFolderIconListView") class]]) {
        // Deal with row underneath widget
        orig = [self coordinateForIconWithIndex:arg1 andOriginalCoordinate:orig];
        
        //NSLog(@"Resultant co-ordinates are row: %lu and column: %lu", (unsigned long)orig.row, (unsigned long)orig.col);
    }
    
    return orig;
}

%new

-(SBIconCoordinate)coordinateForIconWithIndex:(unsigned int)index andOriginalCoordinate:(SBIconCoordinate)orig {
   // NSLog(@"*** [Curago] :: Creating new coordinate for icon %d", index);
    
    /*
     //
     // Widget setup is as so:
     //
     // +--------+ -- -- - +
     // |row+col |         |
     // |for this|         |
     // | icon   |         |
     // |        |         |
     // +--------+         +
     // |                  |
     // |                  |
     // |                  |
     // |                  |
     // + -- -- -- -- -- - +
     //
    */
    
    if (!cachedIndexes)
        cachedIndexes = [NSMutableDictionary dictionary];
    
    SBApplicationIcon *icon = [[self model] iconAtIndex:index];
    NSString *bundleIdentifier = [icon leafIdentifier];
        
    if (!bundleIdentifier) {
        // Using this will cause issues occasionally.
        bundleIdentifier = [(SBFolderIcon*)icon nodeDescriptionWithPrefix:@"IBK"];
    }
        
    NSIndexPath *path = [cachedIndexes objectForKey:bundleIdentifier];
    if (path && !rearrangingIcons) {
        // Awesome, we've already calculated it.
        
        orig.row = (NSInteger)path.row;
        orig.col = (NSInteger)path.section;
        
        return orig;
    }
    
    NSLog(@"Getting icon co-ordinates");
    
    if (!movedIndexPaths) {
        //NSLog(@"Creating an NSSet for temporary index holding");
        movedIndexPaths = [NSMutableSet set];
    }
    
    BOOL invalid = YES;
    
    // Here, we check whether our icon is in the enabled array, and if so, we add it's coordinates to the indexPath array.
    if ([[IBKResources widgetBundleIdentifiers] containsObject:bundleIdentifier]) {
        // Awesome! Now, we calculate the new coordinates, and add to the array
        //NSLog(@"That one is a widget");
        
        while (invalid) {
            // Check against indexPaths. If it matches, move along column 1, or as needed, then check again
            // Else, set invalid to yes and get the fuck out of this loop.
            
            NSIndexPath *testpath = [NSIndexPath indexPathForRow:orig.row inSection:orig.col];
            
            if (![movedIndexPaths containsObject:testpath]) {
                // Sweet, it's a valid location
                invalid = NO;
            } else {
                // Damn. Try again.
                
                orig.col += 1;
                if (orig.col > [objc_getClass("SBIconListView") iconColumnsForInterfaceOrientation:currentOrientation]) {
                    // TODO: Double check it's not going to put the icon underneath the dock.
                    
                    orig.row += 1;
                    orig.col = 1;
                }
            }
        }
        
        NSUInteger widgetRow = orig.row;
        NSUInteger widgetCol = orig.col;
        
       // NSIndexPath *path1 = [NSIndexPath indexPathForRow:widgetRow inSection:widgetCol]; -> This is calculated later on
        NSIndexPath *path2 = [NSIndexPath indexPathForRow:widgetRow inSection:widgetCol+1];
        NSIndexPath *path3 = [NSIndexPath indexPathForRow:widgetRow+1 inSection:widgetCol];
        NSIndexPath *path4 = [NSIndexPath indexPathForRow:widgetRow+1 inSection:widgetCol+1];
        
        // Be aware though you will need to adjust the co-ordinates if right on the edge?
        
        //[movedIndexPaths addObject:path1];
        [movedIndexPaths addObject:path2];
        [movedIndexPaths addObject:path3];
        [movedIndexPaths addObject:path4];
    }
    
    while (invalid) {
        // Check against indexPaths. If it matches, move along column 1, or as needed, then check again
        // Else, set invalid to yes and get the fuck out of this loop.
        
        NSIndexPath *testpath = [NSIndexPath indexPathForRow:orig.row inSection:orig.col];
        
        if (![movedIndexPaths containsObject:testpath]) {
            // Sweet, it's a valid location
            invalid = NO;
        } else {
            // Damn. Try again.
            
            orig.col += 1;
            if (orig.col > [objc_getClass("SBIconListView") iconColumnsForInterfaceOrientation:currentOrientation]) {
                // TODO: Double check it's not going to put the icon underneath the dock.
                
                orig.row += 1;
                orig.col = 1;
            }
        }
    }
    
    // Add to moved index paths
    NSIndexPath *pathz = [NSIndexPath indexPathForRow:orig.row inSection:orig.col];
    [movedIndexPaths addObject:pathz];
    
    // Cache this index path - do this on another thread
    if (![[objc_getClass("SBIconController") sharedInstance] isEditing]) {
       // NSLog(@"Caching index path");
        [cachedIndexes setObject:pathz forKey:bundleIdentifier];
    }
    
    // Clear array if needed
    if (index == [(NSArray*)[self icons] count]-1) {
        NSLog(@"Killing array");
        [movedIndexPaths removeAllObjects];
    }
    
    return orig;
}

%new

-(SBIcon*)modifiedIconForIcon:(SBIcon*)icon {
    // Calculate how many widget slots before this one.
    
    int index = 0;
    
    if ([[self icons] containsObject:icon]) {
        NSLog(@"We have the icon, and it's index is %lu", (unsigned long)[[self icons] indexOfObject:icon]);
        index = (int)[[self icons] indexOfObject:icon];
    } else {
        NSLog(@"Wtf. the icon is %@", icon);
    }
    
    NSLog(@"Old index == %d", index);
    
    int i = 0;
    int columns = [objc_getClass("SBIconListView") iconColumnsForInterfaceOrientation:currentOrientation];
     
     for (NSString *bundleIdentifier in [IBKResources widgetBundleIdentifiers]) {
     
         if ([(SBIconListModel*)[self model] containsLeafIconWithIdentifier:bundleIdentifier]) {
             // Calculate indexes for this icon.
             
             int a = (int)[[self model] indexForLeafIconWithIdentifier:bundleIdentifier];
             if (a < index)
                 i++;
             if (a+1 < index)
                 i++;
             
             int b = a + columns;
             if (b < index)
                 i++;
             if (b+1 < index)
                 i++;
         }
     }
     
    index -= (i == 0 ? 0 : i-1);
    
    NSLog(@"New index == %d", index);
     
    return [(SBIconListModel*)[self model] iconAtIndex:index];
    
    
    // Minus that from our original index.
    
    // return icon for the new index.
}

%end

#pragma mark App switcher detection

BOOL inSwitcher = NO;

%hook SBAppSliderController

- (void)switcherWasDismissed:(BOOL)arg1 {
    %orig;
    inSwitcher = NO;
}
- (void)animatePresentationFromDisplayIdentifier:(id)arg1 withViews:(id)arg2 fromSide:(int)arg3 withCompletion:(id)arg4 {
    inSwitcher = YES;
    %orig;
}

%end

// iOS 8

%hook SBAppSwitcherController

- (void)switcherWasDismissed:(BOOL)arg1 {
    %orig;
    inSwitcher = NO;
}

- (void)animatePresentationFromDisplayLayout:(id)arg1 withViews:(id)arg2 withCompletion:(id)arg3 {
    inSwitcher = YES;
    %orig;
}

%end

#import <SpringBoard7.0/SBApplication.h>

%hook SBApplication

- (void)willAnimateDeactivation:(_Bool)arg1 {
    NSLog(@"*** WILL ANIMATE DEACTIVATION");
    
    IBKWidgetViewController *widgetController = [widgetViewControllers objectForKey:[self bundleIdentifier]];
    
    [UIView animateWithDuration:[IBKResources adjustedAnimationSpeed:0.3] animations:^{
        widgetController.view.alpha = 1.0;
    }];
    
    %orig;
}

- (void)didAnimateDeactivation {
    %orig;
    
    IBKWidgetViewController *widgetController = [widgetViewControllers objectForKey:[self bundleIdentifier]];
    [(UIImageView*)[widgetController.correspondingIconView _iconImageView] setAlpha:0.0];
}

- (void)willActivateWithTransactionID:(unsigned long long)arg1 {
    NSLog(@"*** WILL ACTIVATE WITH TRANSACTION ID");
    
    IBKWidgetViewController *widgetController = [widgetViewControllers objectForKey:[self bundleIdentifier]];
    
    [UIView animateWithDuration:[IBKResources adjustedAnimationSpeed:0.3] animations:^{
        widgetController.view.alpha = 0.0;
    }];
    
    %orig;
}

%end

#pragma mark Injection into icon views

%hook SBIconView

// hack - I wanted to play about with the Obj-C runtime and make a subclass to keep things neat.
- (id)initWithDefaultSize {
    SBIconView *original = %orig;
    if (![[original class] isEqual:[objc_getClass("IBKIconView") class]] && ![[original class] isEqual:[objc_getClass("SBFolderIconView") class]])
        object_setClass(original, objc_getClass("IBKIconView"));
    return original;
}

%end

CGSize defaultIconSizing;

#import <SpringBoard8.1/SBIconImageCrossfadeView.h>

BOOL sup;

%hook SBIconImageCrossfadeView

- (id)initWithImageView:(id)arg1 crossfadeView:(id)arg2 {
    SBIconImageCrossfadeView *view = %orig;
    
    NSLog(@"******* Subviews are %@", view.subviews);
    
    return view;
}

%end

%hook SBIconImageView

- (CGRect)visibleBounds {
    if ([[IBKResources widgetBundleIdentifiers] containsObject:[self.icon applicationBundleID]] && !inSwitcher && sup) {
        CGRect frame = %orig;
        IBKWidgetViewController *widgetController = [widgetViewControllers objectForKey:[self.icon applicationBundleID]];
        frame.size = CGSizeMake(widgetController.view.frame.size.width, widgetController.view.frame.size.height);
        
        return frame;
    }
    
    return %orig;
}

%end

%hook IBKIconView

- (CGPoint)iconImageCenter {
    if ([[IBKResources widgetBundleIdentifiers] containsObject:[self.icon applicationBundleID]] && !inSwitcher) {
        CGPoint point = %orig;
        IBKWidgetViewController *widgetController = [widgetViewControllers objectForKey:[self.icon applicationBundleID]];
        point = CGPointMake(widgetController.view.frame.size.width/2, widgetController.view.frame.size.height/2);
        
        return point;
    }
    
    return %orig;
}

- (CGRect)iconImageFrame {
    if ([[IBKResources widgetBundleIdentifiers] containsObject:[self.icon applicationBundleID]] && !inSwitcher) {
        CGRect frame = %orig;
        IBKWidgetViewController *widgetController = [widgetViewControllers objectForKey:[self.icon applicationBundleID]];
        frame.size = CGSizeMake(widgetController.view.frame.size.width, widgetController.view.frame.size.height);
        
        return frame;
    }
    
    return %orig;
}

- (void)prepareToCrossfadeImageWithView:(id)arg1 maskCorners:(_Bool)arg2 trueCrossfade:(_Bool)arg3 anchorPoint:(struct CGPoint)arg4 {
    sup = YES;
    
    %orig;
    
    sup = NO;
}

- (id)iconImageSnapshot {
    if ([[IBKResources widgetBundleIdentifiers] containsObject:[self.icon applicationBundleID]] && !inSwitcher) {
        IBKWidgetViewController *widgetController = [widgetViewControllers objectForKey:[self.icon applicationBundleID]];
        UIView *view = widgetController.view;
        
        UIGraphicsBeginImageContextWithOptions(view.bounds.size, view.opaque, 0.0);
        [view.layer renderInContext:UIGraphicsGetCurrentContext()];
    
        UIImage * img = UIGraphicsGetImageFromCurrentImageContext();
    
        UIGraphicsEndImageContext();
    
        return img;
    } else {
        return %orig;
    }
}

-(CGRect)frame {
    if ([[IBKResources widgetBundleIdentifiers] containsObject:[self.icon applicationBundleID]] && !inSwitcher && !animatingIn && (iWidgets || sup)) {
        CGRect frame = %orig;
        defaultIconSizing = frame.size;
        IBKWidgetViewController *widgetController = [widgetViewControllers objectForKey:[self.icon applicationBundleID]];
        frame.size = CGSizeMake(widgetController.view.frame.size.width, widgetController.view.frame.size.height + [self _frameForLabel].size.height);
        
        return frame;
    }
    
    return %orig;
}

- (void)_setIcon:(id)arg1 animated:(BOOL)arg2 { // Deal with adding a widget view onto those icons that are already expanded
    %orig;
    
    SBApplicationIcon *icon = (SBApplicationIcon*)arg1;
    
    if (!icon) {
        icon = (SBApplicationIcon*)self.icon;
    }
    
    NSLog(@"It's an icon. %@", [icon applicationBundleID]);
    
    if (!inSwitcher) {
        if ([[IBKResources widgetBundleIdentifiers] containsObject:[icon applicationBundleID]]) {
            NSLog(@"It's a widget! Inserting our UI. %@", [icon applicationBundleID]);
        
            // Widget view controllers will be deallocated when the icon is recycled.
            IBKWidgetViewController *widgetController;
            if (![widgetViewControllers objectForKey:[icon applicationBundleID]])
                widgetController = [[IBKWidgetViewController alloc] init];
            else
                widgetController = [widgetViewControllers objectForKey:[icon applicationBundleID]];
            widgetController.applicationIdentifer = [icon applicationBundleID];
            
            // Add the small UI onto the icon - we can be sure this will not be a folder icon
            [self addSubview:widgetController.view];
            
            [widgetController layoutViewForPreExpandedWidget]; // No need to set center position
            
            if (!widgetViewControllers)
                widgetViewControllers = [NSMutableDictionary dictionary];
                
            if ([icon applicationBundleID])
                [widgetViewControllers setObject:widgetController forKey:[icon applicationBundleID]]; // Ensure that a pointer remains to that widget controller.
            
            // Hide original icon
            [(UIImageView*)[self _iconImageView] setAlpha:0.0];
            widgetController.correspondingIconView = self;
            
            widgetController.view.layer.shadowOpacity = 0.0;
            widgetController.shimIcon.alpha = 0.0;
            widgetController.shimIcon.hidden = YES;
        }
        
        // Testing
        //NSLog(@"Resultant count == %lu", (unsigned long)[widgetViewControllers count]);
    }
}

- (struct CGRect)_frameForLabel {
    CGRect orig = %orig;
    
    if ([[IBKResources widgetBundleIdentifiers] containsObject:[self.icon applicationBundleID]] && !inSwitcher) {
        orig.origin = CGPointMake(8, [IBKResources heightForWidget] + 2);
    }
    
    return orig;
}

-(void)prepareForRecycling {
    %orig;
    
    IBKWidgetViewController *cont = [objc_getClass("IBKIconView") getWidgetViewControllerForIcon:self.icon orBundleID:nil];
    [cont unloadWidgetInterface];
    
    NSLog(@"**** [Curago] :: recycling view");
    
    if ([self.icon applicationBundleID])
        [widgetViewControllers removeObjectForKey:[self.icon applicationBundleID]];
}

// Hook hittest to allow for widget to recieve all touch.

- (BOOL)pointInside:(struct CGPoint)arg1 withEvent:(id)arg2 {
    BOOL orig = %orig;
    
    if ([[IBKResources widgetBundleIdentifiers] containsObject:[self.icon applicationBundleID]] && !inSwitcher) {
        // Check if point will be inside our thing.
        orig = [[[widgetViewControllers objectForKey:[self.icon applicationBundleID]] view] pointInside:arg1 withEvent:arg2];
    }
    
    return orig;
}

%new

+(IBKWidgetViewController*)getWidgetViewControllerForIcon:(SBIcon*)arg1 orBundleID:(NSString*)arg2 {
    NSString *bundleIdentifier;
    if (arg1)
        bundleIdentifier = [arg1 applicationBundleID];
    else
        bundleIdentifier = arg2;
        
    return [widgetViewControllers objectForKey:bundleIdentifier];
}

%end

// Fix up fading to app on launch

#pragma mark Handle de-caching indexes when in editing mode, and switcher detection

%hook SBIconController

- (void)setIsEditing:(BOOL)arg1 {
    %orig;
    
    if (arg1)
        [cachedIndexes removeAllObjects];
    
    rearrangingIcons = arg1;
}

%new

-(BOOL)ibkIsInSwitcher {
    return inSwitcher;
}

%new

-(void)removeIdentifierFromWidgets:(NSString*)identifier {
    [widgetViewControllers removeObjectForKey:identifier];
}

%new

-(void)removeAllCachedIcons {
    [cachedIndexes removeAllObjects];
}

%end

#pragma mark Handle pinching of icons

IBKWidgetViewController *widget;
SBIcon *widgetIcon;

// handle main scrolling icons

@interface SBIconScrollView (Additions2)
-(void)handlePinchGesture:(UIPinchGestureRecognizer*)pinch;
@end

@interface SBIconScrollView (Additions)
-(SBIconListView *)IBKListViewForIdentifierTwo:(NSString*)identifier;
@end

%hook SBIconScrollView

-(UIScrollView*)initWithFrame:(CGRect)frame {
    UIScrollView *orig = %orig;
    
    NSLog(@"*** [Curago] :: Adding pinch gesture onto SBIconScrollView");

    UIPinchGestureRecognizer *pinch = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(handlePinchGesture:)];
    [(UIView*)orig addGestureRecognizer:pinch];
    
    for (UIGestureRecognizer *arg in [self gestureRecognizers]) {
        if ([[arg class] isEqual:[objc_getClass("UIScrollViewDelayedTouchesBeganGestureRecognizer") class]]) {
            [self removeGestureRecognizer:arg];
        }
    }
    
    return orig;
}

%new

int scale = 0;
NSInteger page = 0;
-(void)handlePinchGesture:(UIPinchGestureRecognizer*)pinch {
    // You must return if we're in a folder. for now
    if ([[objc_getClass("SBIconController") sharedInstance] hasOpenFolder]) return;
    
    if (pinch.state == UIGestureRecognizerStateBegan) {
         NSLog(@"Pinching began");
        // Handle setting up the view.
        
        // calculate mid-point of pinch
        CGFloat width = self.frame.size.width;
        page = (self.contentOffset.x + (0.5f * width)) / width;
        CGPoint rawMidpoint = [pinch locationInView:(UIView*)self];
        CGPoint finalMidpoint = CGPointMake(rawMidpoint.x - (page * width), rawMidpoint.y);
        NSLog(@"*** final midpoint == %@", NSStringFromCGPoint(finalMidpoint));
        
        // Get the icon at this point in the current list view
        SBIconListView *listView;
        [[objc_getClass("SBIconController") sharedInstance] getListView:&listView folder:nil relativePath:nil forIndexPath:[NSIndexPath indexPathForRow:1 inSection:page] createIfNecessary:NO];
        
        //SBIconListView *listView = [self.subviews objectAtIndex:(page+1)]; // Spotlight is still page 0. WTF Apple.
        unsigned int index;
        widgetIcon = [listView iconAtPoint:finalMidpoint index:&index];
        NSLog(@"Widget icon == %@", widgetIcon);
        
        // Extra check for folders
        
        if ([[widgetIcon class] isEqual:[objc_getClass("SBFolderIcon") class]]) {
            widget = nil;
            return;
        }
        
        // Ah shit. If this widget is already open, don't do anything!
        if ([widgetViewControllers objectForKey:[widgetIcon applicationBundleID]]) {
            widget = nil;
            return;
        }
        
        // We need to make this icon's view to be the highest subview. Oh shit. We can add in all our widget controllers here!
        widget = [[IBKWidgetViewController alloc] init];
        widget.applicationIdentifer = [widgetIcon applicationBundleID];
        
        if (!widgetViewControllers)
            widgetViewControllers = [NSMutableDictionary dictionary];
            
        if ([widgetIcon applicationBundleID])
            [widgetViewControllers setObject:widget forKey:[widgetIcon applicationBundleID]];
        
        // Add widget view onto icon.
        IBKIconView *view = [[objc_getClass("SBIconViewMap") homescreenMap] iconViewForIcon:widgetIcon];
        [view addSubview:widget.view];
        [view.superview addSubview:view]; // Move the view to be the top most subview
        
        widget.correspondingIconView = view;
        
        [[(SBIconView*)view _iconImageView] setAlpha:0.0];
     
        widget.view.transform = CGAffineTransformMakeScale(1.0, 1.0);
        
        [widget loadWidgetInterface];
        
        widget.view.center = CGPointMake(([(UIView*)[view _iconImageView] frame].size.width/2)-1, ([(UIView*)[view _iconImageView] frame].size.height/2)-1);
        
        CGFloat widgetWidth = widget.view.bounds.size.width;
        CGFloat iconSize = (isPad ? 72 : 58);
        CGFloat scale = (iconSize/widgetWidth);
        
        widget.view.transform = CGAffineTransformMakeScale(scale, scale);
    } else if (pinch.state == UIGestureRecognizerStateChanged && widget) {
         NSLog(@"Pinching changed");
        if ([[widgetIcon class] isEqual:[objc_getClass("SBFolderIcon") class]]) return;
        
        // Set scale of our widget view, using scale/velocity as our time duration for animation
        
        CGFloat duration = (pinch.scale/pinch.velocity);
        
        if ([[[UIDevice currentDevice] systemVersion] floatValue] >= 8.0) {
            duration = (pinch.scale-1)/pinch.velocity;
            //NSLog(@"pinch.scale == %f, pinch.velocity == %f, duration == %f", pinch.scale, pinch.velocity, duration);
        }
        
        if (duration < 0)
            duration = -duration;
     
        scale = pinch.scale;
        
        [widget setScaleForView:pinch.scale withDuration:0.1];
    } else if (pinch.state == UIGestureRecognizerStateEnded && widget) {
         NSLog(@"Pinching ended");
        if ([[widgetIcon class] isEqual:[objc_getClass("SBFolderIcon") class]]) return;
         // Handle end of touch. If scale greater than a set value, drop down regardless of time spent held in place.
        // Also, we need to check whether we'll be overlapping another widget, and if so, don't drop /the bass/
         // We should add onto the homescreen now.
        
        if ((scale-1.0) > 0.75) { // Scale is 1.0 onwards, but we expect 0.0 onwards
            [widget setScaleForView:8.0 withDuration:0.3];
            [IBKResources addNewIdentifier:[widgetIcon applicationBundleID]];
            
            // Relayout icons.
            [cachedIndexes removeAllObjects];
            
            // Move icons to next page if needed.
            
            SBIconListView *lst = [self IBKListViewForIdentifierTwo:widget.applicationIdentifer];
            
            // Add three dummy icons onto the listView?
            
            // Count how many widgets on listView
            int count = 0;
            
            for (SBIcon *icon in [lst icons]) {
                if ([[IBKResources widgetBundleIdentifiers] containsObject:[icon applicationBundleID]])
                    count += 3;
            }
            
            if ([lst icons].count + count > [objc_getClass("SBIconListView") maxIcons]) {
                // Move last three onto thing
                
                count = ((int)[lst icons].count + count) - (int)[objc_getClass("SBIconListView") maxIcons];
                
                // Get array of last three!
                
                rearrangingIcons = YES;
                
                NSMutableArray *arr = [NSMutableArray array];
                
                for (int i = (int)[lst icons].count - 1; i > (int)[lst icons].count - 1 - count; --i) {
                    [arr addObject:[[lst icons] objectAtIndex:i]];
                }
                
                NSLog(@"Arr is %@", arr);
                
                // Figure out where we should move icons along to.
                
                SBIconListView *listView;
                [[objc_getClass("SBIconController") sharedInstance] getListView:&listView folder:nil relativePath:nil forIndexPath:[NSIndexPath indexPathForRow:0 inSection:page + 1] createIfNecessary:YES];
                
                for (SBIcon *icon in arr) {
                    NSLog(@"Icon is %@", icon);
                    
                    [[lst model] removeIcon:icon];
                    //[[lst model] compactIcons];
                    
                    [listView insertIcon:icon atIndex:0 moveNow:YES pop:YES];
                    //[[listView model] placeIcon:icon atIndex:0];
                    //[[listView model] compactIcons];
                    
                    [listView setIconsNeedLayout];
                    [listView layoutIconsIfNeeded:0.0 domino:NO];
                    
                    //[[objc_getClass("SBIconController") sharedInstance] placeIcon:icon atIndexPath:[NSIndexPath indexPathForRow:0 inSection:page + 1] moveNow:YES layoutNow:YES pop:YES];
                    
                    //[lst removeIcon:icon];
                }
                    
                if ([[[objc_getClass("SBIconController") sharedInstance] model] respondsToSelector:@selector(saveIconStateIfNeeded)])
                    [(SBIconModel*)[[objc_getClass("SBIconController") sharedInstance] model] saveIconStateIfNeeded];
                else
                    [(SBIconModel*)[[objc_getClass("SBIconController") sharedInstance] model] saveIconState];
                
                rearrangingIcons = NO;
            }
            
            if ([[[UIDevice currentDevice] systemVersion] floatValue] >= 8.0) {
                //[(SBIconController*)[objc_getClass("SBIconController") sharedInstance] layoutIconLists:0.3 domino:NO forceRelayout:YES];
                [lst setIconsNeedLayout];
                [lst layoutIconsIfNeeded:0.3 domino:NO];
            } else
                [(SBIconController*)[objc_getClass("SBIconController") sharedInstance] layoutIconLists:0.3 domino:NO forceRelayout:YES];
            
            // Move frame of widget into new position.
            CGRect widgetViewFrame = widget.correspondingIconView.frame;
            widgetViewFrame.size = CGSizeMake([IBKResources widthForWidget], [IBKResources heightForWidget]);
            [UIView animateWithDuration:0.3 animations:^{
                widget.view.frame = CGRectMake(0, 0, [IBKResources widthForWidget], [IBKResources heightForWidget]);
                widget.view.layer.shadowOpacity = 0.0;
                
                [(SBIconImageView*)[widget.correspondingIconView _iconImageView] setFrame:widgetViewFrame];
                
                // Icon's label?
            }];
        } else {
            CGFloat iconScale = ((UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) ? 72 : 58) / widget.shimIcon.frame.size.width;
            
            iconScale = 0.41;
            
            CGFloat red, green, blue;
            [widget.view.backgroundColor getRed:&red green:&green blue:&blue alpha:nil];
            
            [UIView animateWithDuration:0.25 animations:^{
                widget.view.transform = CGAffineTransformMakeScale(iconScale, iconScale);
                widget.shimIcon.alpha = 1.0;
                widget.viw.alpha = 0.0;
                widget.view.backgroundColor = [UIColor colorWithRed:red green:green blue:blue alpha:0.0];
            } completion:^(BOOL finished) {
                [widget unloadFromPinchGesture];
                if (widget && widget.applicationIdentifer) [widgetViewControllers removeObjectForKey:widget.applicationIdentifer];
                [[(SBIconView*)widget.correspondingIconView _iconImageView] setAlpha:1.0];
            }];
        }
    } else if (pinch.state == UIGestureRecognizerStateCancelled) {
        CGFloat widgetWidth = widget.view.bounds.size.width;
        CGFloat iconSize = (isPad ? 72 : 58);
        CGFloat scale = (iconSize/widgetWidth);
        
        [UIView animateWithDuration:0.3 animations:^{
            widget.view.transform = CGAffineTransformMakeScale(scale, scale);
            widget.view.center = CGPointMake(([(UIView*)[widget.correspondingIconView _iconImageView] frame].size.width/2)-1, ([(UIView*)[widget.correspondingIconView _iconImageView] frame].size.height/2)-1);
            widget.shimIcon.alpha = 1.0;
            
            widget.iconImageView.alpha = 0.0;
        } completion:^(BOOL finished) {
            [[widget.correspondingIconView _iconImageView] setAlpha:1.0];
            widget.view.hidden = YES;
            [widget unloadFromPinchGesture];
            
            if (widget && widget.applicationIdentifer) [widgetViewControllers removeObjectForKey:widget.applicationIdentifer];
        }];

    }
}

%new

-(SBIconListView *)IBKListViewForIdentifierTwo:(NSString*)identifier {
    SBIconController *viewcont = [objc_getClass("SBIconController") sharedInstance];
    SBIconModel *model = [viewcont model];
    SBIcon *icon = [model expectedIconForDisplayIdentifier:identifier];
    
    SBIconController *controller = [objc_getClass("SBIconController") sharedInstance];
    SBRootFolder *rootFolder = [controller valueForKeyPath:@"rootFolder"];
    NSIndexPath *indexPath = [rootFolder indexPathForIcon:icon];
    SBIconListView *listView = nil;
    [controller getListView:&listView folder:NULL relativePath:NULL forIndexPath:indexPath createIfNecessary:YES];
    return listView;
}

%end

%hook SBIconBadgeView

static SBIcon *temp;

- (void)configureForIcon:(SBIcon*)arg1 location:(int)arg2 highlighted:(BOOL)arg3 {
    temp = arg1;
    
    %orig;
    
    if ([[IBKResources widgetBundleIdentifiers] containsObject:[arg1 applicationBundleID]] && !inSwitcher) {
        // Calculate x for center
        [[self superview] addSubview:self]; // Bring to front.
    }
    
}

- (struct CGPoint)accessoryOriginForIconBounds:(CGRect)arg1 {
    if ([[IBKResources widgetBundleIdentifiers] containsObject:[temp applicationBundleID]] && !inSwitcher) {
        // Calculate x for center
        IBKWidgetViewController *contr = [widgetViewControllers objectForKey:[temp applicationBundleID]];
        arg1 = contr.view.bounds;
        
        [[self superview] addSubview:self]; // Bring to front.
    }
    
    return %orig(arg1);
}

%end

#pragma mark BBServer hooks for notification tables

%hook BBServer

-(id)init {
    BBServer *orig = %orig;
    IBKBBServer = orig;
    return orig;
}

- (void)_addBulletin:(BBBulletin*)arg1 {
    IBKWidgetViewController *contr = [widgetViewControllers objectForKey:[arg1 sectionID]];
    if (contr)
        [contr addBulletin:arg1];
    
    %orig;
}

- (void)_removeBulletin:(id)arg1 rescheduleTimerIfAffected:(BOOL)arg2 shouldSync:(BOOL)arg3 {
    for (NSString *key in widgetViewControllers) {
        if ([[(IBKWidgetViewController*)[widgetViewControllers objectForKey:key] applicationIdentifer] isEqual:[arg1 sectionID]])
            [(IBKWidgetViewController*)[widgetViewControllers objectForKey:key] removeBulletin:arg1];
    }
    
    %orig;
}

%new

+(id)sharedIBKBBServer {
    return IBKBBServer;
}

%end

// iOS 8 shit.

#include <MediaRemote/MediaRemote.h>

@interface MPUNowPlayingController : NSObject
@property(readonly) UIImage * currentNowPlayingArtwork;
@property(readonly) NSDictionary * currentNowPlayingInfo;

+(id)sharedMPU;
- (BOOL)isPlaying;
-(void)update;
@end

MPUNowPlayingController *sharedMPU;

%group iOS8

%hook SBIconImageView

%new
-(id)alternateIconView {
    return nil; // Small fix for Auxo of all things (?!)
}

%end

%hook MPUNowPlayingController

- (id)init {
    sharedMPU = %orig;
    
    return sharedMPU;
}

%new

+(id)ibksharedMPU {
    return sharedMPU;
}

%end

%hook SBMediaController

-(void)_nowPlayingInfoChanged {
    %orig;
    
    // Give it a sec.
    [[NSNotificationCenter defaultCenter] postNotificationName:@"IBK-UpdateMusic" object:nil];
}

-(BOOL)isPlaying {
    return [sharedMPU isPlaying];
}

%new

-(NSString*)ibkNowPlayingArtist {
    NSDictionary *dict = sharedMPU.currentNowPlayingInfo;
    return [dict objectForKey:(__bridge NSString*)kMRMediaRemoteNowPlayingInfoArtist];
}

%new

-(NSString*)ibkNowPlayingAlbum {
    NSDictionary *dict = sharedMPU.currentNowPlayingInfo;
    return [dict objectForKey:(__bridge NSString*)kMRMediaRemoteNowPlayingInfoAlbum];
}

%new

-(NSString*)ibkNowPlayingTitle {
    NSDictionary *dict = sharedMPU.currentNowPlayingInfo;
    return [dict objectForKey:(__bridge NSString*)kMRMediaRemoteNowPlayingInfoTitle];
}

%new

-(UIImage*)ibkArtwork {
    NSDictionary *dict = sharedMPU.currentNowPlayingInfo;
    NSData *data = [dict objectForKey:(__bridge NSString*)kMRMediaRemoteNowPlayingInfoArtworkData];
    return [UIImage imageWithData:data];
}

%new

-(BOOL)ibkTrackSupports15SecondFF {
    NSDictionary *dict = sharedMPU.currentNowPlayingInfo;
    return [[dict objectForKey:(__bridge NSString*)kMRMediaRemoteNowPlayingInfoSupportsFastForward15Seconds] boolValue];
}

%new

-(BOOL)ibkTrackSupports15SecondRewind {
    NSDictionary *dict = sharedMPU.currentNowPlayingInfo;
    return [[dict objectForKey:(__bridge NSString*)kMRMediaRemoteNowPlayingInfoSupportsRewind15Seconds] boolValue];
}

%end

%end

%group iWidgets

%hook IWWidgetsView

- (_Bool)pointInside:(struct CGPoint)arg1 withEvent:(id)arg2 {
    iWidgets = YES;
    BOOL original = %orig;
    iWidgets = NO;
    
    return original;
}

%end

%end



#pragma mark Constructor and anti-piracy code

@interface ISIconSupport : NSObject
+(instancetype)sharedInstance;
-(void)addExtension:(NSString*)arg1;
@end

%ctor {
    
    // Subclass SBIconView at runtime.
    Class $IBKIconView = objc_allocateClassPair(objc_getClass("SBIconView"), "IBKIconView", 0);
    //class_addIvar($IBKIconView, "_widgetViewController", sizeof(UIView*), rint(log2(sizeof(UIView*))), @encode(UIView*));
    
    objc_registerClassPair($IBKIconView);
    
    // We're done. Load!
    %init;
    
    dlopen("/Library/MobileSubstrate/DynamicLibraries/IconSupport.dylib", RTLD_NOW);
    dlopen("/Library/MobileSubstrate/DynamicLibraries/iWidgets.dylib", RTLD_NOW);
    [[objc_getClass("ISIconSupport") sharedInstance] addExtension:@"com.matchstic.curago"];
    
    // Load custom stuff for certain versions of iOS.
    
    if ([[[UIDevice currentDevice] systemVersion] floatValue] >= 8.0)
        %init(iOS8);
        
    %init(iWidgets);
}
