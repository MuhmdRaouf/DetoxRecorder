//
//  UIView+DTXDescendants.m
//  DetoxRecorder
//
//  Created by Leo Natan (Wix) on 4/18/19.
//  Copyright © 2019 Wix. All rights reserved.
//

#import "UIView+DTXDescendants.h"

@interface UIWindowScene ()

+ (instancetype)_keyWindowScene;

@end

@implementation UIView (DTXDescendants)

+ (void)_dtx_appendViewsRecursivelyFromArray:(NSArray<UIView*>*)views passingPredicate:(NSPredicate*)predicate storage:(NSMutableArray<UIView*>*)storage
{
	if(views.count == 0)
	{
		return;
	}
	
	[views enumerateObjectsUsingBlock:^(UIView * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
		if(predicate == nil || [predicate evaluateWithObject:obj] == YES)
		{
			[storage addObject:obj];
		}
		
		if(obj.isAccessibilityElement == NO)
		{
			[self _dtx_appendViewsRecursivelyFromArray:obj.subviews passingPredicate:predicate storage:storage];
		}
	}];
}

+ (NSMutableArray<UIView*>*)dtx_findViewsInWindows:(NSArray<UIWindow*>*)windows passingPredicate:(NSPredicate*)predicate
{
	NSMutableArray<UIView*>* rv = [NSMutableArray new];
	
	[self _dtx_appendViewsRecursivelyFromArray:windows passingPredicate:predicate storage:rv];
	[self _dtx_sortViewsByCoords:rv];
	
	return rv;
}

+ (NSMutableArray<UIView*>*)dtx_findViewsInKeySceneWindowsPassingPredicate:(NSPredicate*)predicate
{
	NSArray<UIWindow*>* windows;
	if (@available(iOS 13.0, *))
	{
		windows = UIWindowScene._keyWindowScene.windows;
	}
	else
	{
		windows = UIApplication.sharedApplication.windows;
	}
	
	return [self dtx_findViewsInWindows:windows passingPredicate:predicate];
}

+ (NSMutableArray<UIView*>*)dtx_findViewsInHierarchy:(UIView*)hierarchy passingPredicate:(NSPredicate*)predicate
{
	return [self dtx_findViewsInHierarchy:hierarchy includingRoot:YES passingPredicate:predicate];
}

+ (NSMutableArray<UIView*>*)dtx_findViewsInHierarchy:(UIView*)hierarchy includingRoot:(BOOL)includingRoot passingPredicate:(NSPredicate*)predicate
{
	NSMutableArray<UIView*>* rv = [NSMutableArray new];
	
	[self _dtx_appendViewsRecursivelyFromArray:includingRoot ? @[hierarchy] : hierarchy.subviews passingPredicate:predicate storage:rv];
	[self _dtx_sortViewsByCoords:rv];
	
	return rv;
}

+ (void)_dtx_sortViewsByCoords:(NSMutableArray<UIView*>*)views
{
	[views sortUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:nil ascending:YES comparator:^NSComparisonResult(UIView* _Nonnull obj1, UIView* _Nonnull obj2) {
		CGRect frame1 = obj1.accessibilityFrame;
		CGRect frame2 = obj2.accessibilityFrame;
		
		return frame1.origin.y < frame2.origin.y ? NSOrderedAscending : frame1.origin.y > frame2.origin.y ? NSOrderedDescending : NSOrderedSame;
	}], [NSSortDescriptor sortDescriptorWithKey:nil ascending:YES comparator:^NSComparisonResult(UIView* _Nonnull obj1, UIView* _Nonnull obj2) {
		CGRect frame1 = obj1.accessibilityFrame;
		CGRect frame2 = obj2.accessibilityFrame;
		
		return frame1.origin.x < frame2.origin.x ? NSOrderedAscending : frame1.origin.x > frame2.origin.x ? NSOrderedDescending : NSOrderedSame;
	}]]];
}

@end
