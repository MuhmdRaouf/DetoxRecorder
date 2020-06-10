//
//  DTXUIInteractionRecorder.m
//  UI
//
//  Created by Leo Natan (Wix) on 4/9/19.
//  Copyright © 2019 Leo Natan. All rights reserved.
//

#import "DTXUIInteractionRecorder.h"
#import "DTXCaptureControlWindow.h"
#import "DTXRecordedAction.h"
#import "DTXAppleInternals.h"

@interface _DTXVisualizedView : UIView @end
@implementation _DTXVisualizedView @end

@implementation DTXUIInteractionRecorder

static NSMutableArray<DTXRecordedAction*>* recordedActions;
static DTXCaptureControlWindow* captureControlWindow;
static NSUInteger screenshotCounter;
static UIView* previousTextChangeVisualizer;

+ (void)load
{
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		if([NSUserDefaults.standardUserDefaults boolForKey:@"DTXRecStartRecording"] == YES)
		{
			[self beginRecording];
		}
	});
}

+ (void)beginRecording
{
	recordedActions = [NSMutableArray new];
	screenshotCounter = 1;
	
	captureControlWindow = [[DTXCaptureControlWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
}

+ (void)endRecording
{
	NSString* testNamePath = [NSUserDefaults.standardUserDefaults stringForKey:@"DTXRecTestOutputPath"];
	NSString* testName = [NSUserDefaults.standardUserDefaults stringForKey:@"DTXRecTestName"] ?: @"My Recorded Test";
	
	[NSFileManager.defaultManager createFileAtPath:testNamePath contents:nil attributes:nil];
	NSFileHandle* file = [NSFileHandle fileHandleForWritingAtPath:testNamePath];
	
	[file writeData:[[NSString stringWithFormat:@"describe('Recorded suite', () => {\n\tit('%@', async () => {\n", testName] dataUsingEncoding:NSUTF8StringEncoding]];
	
	[recordedActions enumerateObjectsUsingBlock:^(DTXRecordedAction * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
		[file writeData:[[NSString stringWithFormat:@"\t\t%@\n", obj.detoxDescription] dataUsingEncoding:NSUTF8StringEncoding]];
	}];
	
	[file writeData:[@"\t}\n}" dataUsingEncoding:NSUTF8StringEncoding]];
	[file closeFile];
	
	recordedActions = nil;
	captureControlWindow.hidden = YES;
	captureControlWindow = nil;
	
	if([NSUserDefaults.standardUserDefaults boolForKey:@"DTXRecNoExit"] == NO)
	{
		exit(0);
	}
}

static NSTimeInterval lastRecordedEventTimestamp;
#define IGNORE_IF_FROM_LAST_EVENT if(event != nil && event.timestamp == lastRecordedEventTimestamp) { return; } else { lastRecordedEventTimestamp = event.timestamp; }

+ (UIView*)_visualizerViewForView:(UIView*)view action:(DTXRecordedAction*)action systemImageName:(NSString*)systemImageName
{
	return [self _visualizerViewForView:view action:action systemImageName:systemImageName imageViewTransform:CGAffineTransformIdentity];
}

static void _traverseElementMatchersAndFill(DTXRecordedElement* element, BOOL* anyById, BOOL* anyByLabel, BOOL* anyByClass, BOOL* anyByIndex, BOOL* hasAncestorChain)
{
	if(element == nil)
	{
		return;
	}
	
	*anyByIndex |= element.requiresAtIndex;
	
	[element.matchers enumerateObjectsUsingBlock:^(DTXRecordedElementMatcher * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
		*anyById |= (obj.matcherType == DTXRecordedElementMatcherTypeById);
		*anyByLabel |= (obj.matcherType == DTXRecordedElementMatcherTypeByLabel);
		*anyByClass |= (obj.matcherType == DTXRecordedElementMatcherTypeByType);
	}];
	
	*hasAncestorChain |= (element.ancestorElement != nil);
	
	_traverseElementMatchersAndFill(element.ancestorElement, anyById, anyByLabel, anyByClass, anyByIndex, hasAncestorChain);
}

+ (UIView*)_visualizerViewForView:(UIView*)view action:(DTXRecordedAction*)action systemImageName:(NSString*)systemImageName imageViewTransform:(CGAffineTransform)transform
{
	_DTXVisualizedView* visualizer = [_DTXVisualizedView new];
	
	UIColor* color;
	
	BOOL anyById = NO;
	BOOL anyByLabel = NO;
	BOOL anyByClass = NO;
	BOOL anyByIndex = NO;
	BOOL hasAncestorChain = NO;
	
	_traverseElementMatchersAndFill(action.element, &anyById, &anyByLabel, &anyByClass, &anyByIndex, &hasAncestorChain);
	
	if(anyById == YES && anyByIndex == NO)
	{
		color = UIColor.systemGreenColor;
	}
	else if((anyByLabel == YES || anyByClass == YES) && anyByIndex == NO)
	{
		color = UIColor.systemOrangeColor;
	}
		
	if(color == nil)
	{
		color = UIColor.systemRedColor;
	}
	
//	if(action.element.matchers.count == 1 && action.element.matchers.firstObject.matcherType == DTXRecordedElementMatcherTypeById)
//	{
//		;
//	}
//	else if(action.element.matchers.count == 1 && action.element.matchers.firstObject.matcherType == DTXRecordedElementMatcherTypeByLabel)
//	{
//		color = UIColor.systemOrangeColor;
//	}
//	else
//	{
//		color = UIColor.systemRedColor;
//	}
	
	CGRect frame = [view.window convertRect:view.bounds fromView:view];
	
	visualizer.userInteractionEnabled = NO;
	visualizer.alpha = 1.0;
	visualizer.backgroundColor = [color colorWithAlphaComponent:0.4];
	visualizer.frame = frame;
	visualizer.layer.cornerRadius = MIN(8, MIN(visualizer.frame.size.width, visualizer.frame.size.height) / 2);
	visualizer.layer.borderWidth = 2.0;
	visualizer.layer.borderColor = color.CGColor;
	[captureControlWindow.rootViewController.view addSubview:visualizer];
	
	if(systemImageName)
	{
		CGFloat minImageSize = MIN(30, MIN(CGRectGetWidth(frame) * 0.75, CGRectGetHeight(frame) * 0.75));
		
		UIImage* image = [UIImage systemImageNamed:systemImageName withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:MAX(minImageSize, MIN(CGRectGetWidth(frame) * 0.45, CGRectGetHeight(frame) * 0.45)) weight:UIImageSymbolWeightMedium]];
		UIImageView* imageView = [[UIImageView alloc] initWithImage:image];
		imageView.translatesAutoresizingMaskIntoConstraints = NO;
		imageView.tintColor = UIColor.whiteColor;
		imageView.transform = transform;
		
		if(CGRectContainsRect(CGRectMake(0, 0, CGRectGetWidth(frame), CGRectGetHeight(frame)), (CGRect){0, 0, image.size}))
		{
			imageView.contentMode = UIViewContentModeCenter;
		}
		else
		{
			imageView.contentMode = UIViewContentModeScaleAspectFit;
		}
		
		[visualizer addSubview:imageView];
		
		[NSLayoutConstraint activateConstraints:@[
			[imageView.topAnchor constraintEqualToAnchor:visualizer.topAnchor],
			[imageView.bottomAnchor constraintEqualToAnchor:visualizer.bottomAnchor],
			[imageView.leadingAnchor constraintEqualToAnchor:visualizer.leadingAnchor],
			[imageView.trailingAnchor constraintEqualToAnchor:visualizer.trailingAnchor],
		]];
	}
	
	if(systemImageName == nil && action.actionType == DTXRecordedActionTypeReplaceText)
	{
		visualizer.alpha = 0.5;
		visualizer.backgroundColor = [color colorWithAlphaComponent:0.1];
		UIView* sq1 = [UIView new];
		sq1.translatesAutoresizingMaskIntoConstraints = NO;
		sq1.alpha = 0.7;
		sq1.layer.cornerRadius = MIN(4, MIN(visualizer.frame.size.width, visualizer.frame.size.height) / 2);
		sq1.layer.borderWidth = 2.0;
		sq1.layer.borderColor = color.CGColor;
		
		UIView* sq2 = [UIView new];
		sq2.translatesAutoresizingMaskIntoConstraints = NO;
		sq2.alpha = 0.7;
		sq2.layer.cornerRadius = MIN(4, MIN(visualizer.frame.size.width, visualizer.frame.size.height) / 2);
		sq2.layer.borderWidth = 2.0;
		sq2.layer.borderColor = color.CGColor;
		
		UIView* sq3 = [UIView new];
		sq3.translatesAutoresizingMaskIntoConstraints = NO;
		sq3.alpha = 0.7;
		sq3.layer.cornerRadius = MIN(4, MIN(visualizer.frame.size.width, visualizer.frame.size.height) / 2);
		sq3.layer.borderWidth = 2.0;
		sq3.layer.borderColor = color.CGColor;
		
		UIStackView* sv = [UIStackView new];
		sv.translatesAutoresizingMaskIntoConstraints = NO;
		[sv addArrangedSubview:sq1];
		[sv addArrangedSubview:sq2];
		[sv addArrangedSubview:sq3];
		sv.distribution = UIStackViewDistributionFillEqually;
		sv.alignment = UIStackViewAlignmentCenter;
		sv.spacing = 4;
	
		[visualizer addSubview:sv];
		
		[NSLayoutConstraint activateConstraints:@[
												  [sv.centerXAnchor constraintEqualToAnchor:visualizer.centerXAnchor],
												  [sv.centerYAnchor constraintEqualToAnchor:visualizer.centerYAnchor],
												  [sq1.widthAnchor constraintEqualToConstant:10],
												  [sq1.heightAnchor constraintEqualToConstant:10],
												  [sq2.widthAnchor constraintEqualToAnchor:sq1.widthAnchor],
												  [sq2.heightAnchor constraintEqualToAnchor:sq1.heightAnchor],
												  [sq3.widthAnchor constraintEqualToAnchor:sq1.widthAnchor],
												  [sq3.heightAnchor constraintEqualToAnchor:sq1.heightAnchor],
												  ]];
	}
	
//	[visualizer layoutIfNeeded];
	
	return visualizer;
}

+ (void)_blinkVisualizerView:(UIView*)view
{
	static const CGFloat initialAlpha = 1.0;
	[UIView performWithoutAnimation:^{
		view.alpha = initialAlpha;
	}];
	
	[UIView animateKeyframesWithDuration:0.4 delay:0.0 options:UIViewKeyframeAnimationOptionBeginFromCurrentState | UIViewKeyframeAnimationOptionCalculationModeCubicPaced animations:^{
		[UIView addKeyframeWithRelativeStartTime:0.0 relativeDuration:1.0 / 3.0 animations:^{
			view.alpha = 0.0;
		}];
		[UIView addKeyframeWithRelativeStartTime:1.0 / 3.0 relativeDuration:2.0 / 3.0 animations:^{
			view.alpha = initialAlpha * 0.8;
		}];
		[UIView addKeyframeWithRelativeStartTime:2.0 / 3.0 relativeDuration:1.0 animations:^{
			view.alpha = 0.0;
		}];
	} completion:^(BOOL finished) {
		[view removeFromSuperview];
	}];
}

+ (void)_flashVisualizerView:(UIView*)view
{
	static const CGFloat initialAlpha = 0.8;
	[UIView performWithoutAnimation:^{
		view.alpha = initialAlpha;
	}];
	[UIView animateWithDuration:0.3 delay:0.0 options:0 animations:^{
		view.alpha = 0.0;
	} completion:^(BOOL finished) {
		[view removeFromSuperview];
	}];
}

+ (void)_slowFlashVisualizerView:(UIView*)view
{
	static const CGFloat initialAlpha = 0.8;
	[UIView performWithoutAnimation:^{
		view.alpha = initialAlpha;
	}];
	[UIView animateWithDuration:0.8 delay:0.0 options:0 animations:^{
		view.alpha = 0.0;
	} completion:^(BOOL finished) {
		[view removeFromSuperview];
	}];
}

+ (void)_fadeVisualizerView:(UIView*)view direction:(CGFloat)dir
{
	CGFloat y = dir < 0 ? CGRectGetMinY(view.frame) : CGRectGetMaxY(view.frame);
	CGRect newFrame = CGRectMake(CGRectGetMinX(view.frame), y, CGRectGetWidth(view.frame), 0);
	
	[UIView performWithoutAnimation:^{
		[view layoutIfNeeded];
	}];
	
	[UIView animateWithDuration:0.5 delay:0.0 options:UIViewAnimationOptionBeginFromCurrentState animations:^{
		view.frame = newFrame;
		view.alpha = 0.0;
		[view layoutIfNeeded];
	} completion:^(BOOL finished) {
		[view removeFromSuperview];
	}];
}

+ (void)_systemDeleteVisualizerView:(UIView*)view
{
	[UIView performSystemAnimation:UISystemAnimationDelete onViews:@[view] options:UIViewAnimationOptionBeginFromCurrentState animations:nil completion:^(BOOL finished) {
		[view removeFromSuperview];
	}];
}

+ (void)_visualizeTapAtView:(UIView*)view withAction:(DTXRecordedAction*)action
{
	BOOL xy = NSUserDefaults.standardUserDefaults.dtx_attemptXYRecording;
	UIView* visualizer = [self _visualizerViewForView:view action:action systemImageName:xy ? @"hand.draw.fill" : @"hand.point.right.fill" imageViewTransform:xy ? CGAffineTransformIdentity : CGAffineTransformMakeRotation(-M_PI_2)];
	
	[self _blinkVisualizerView:visualizer];
}

+ (void)_visualizeLongPressAtView:(UIView*)view withAction:(DTXRecordedAction*)action
{
	UIView* visualizer = [self _visualizerViewForView:view action:action systemImageName:@"hand.point.left.fill" imageViewTransform:CGAffineTransformMakeRotation(-M_PI_2)];
	
	[self _slowFlashVisualizerView:visualizer];
}


+ (void)_visualizeDatePickerChangeDate:(UIDatePicker*)view withAction:(DTXRecordedAction*)action
{
	UIView* visualizer = [self _visualizerViewForView:view action:action systemImageName:@"calendar"];
	
	[self _blinkVisualizerView:visualizer];
}

+ (void)_addTapWithView:(UIView*)view event:(UIEvent*)event fromRN:(BOOL)fromRN
{
	IGNORE_IF_FROM_LAST_EVENT
	
	DTXRecordedAction* action = [DTXRecordedAction tapActionWithView:view event:event isFromRN:fromRN];
	if(action != nil)
	{
		[self _enhanceLastScrollEventIfNeededForElement:action.element];
		
		[recordedActions addObject:action];
//		NSLog(@"📣 Tapped control: %@", control.class);
		
		[self _visualizeTapAtView:view withAction:action];
	}
}

+ (void)addControlTapWithControl:(UIControl*)control withEvent:(UIEvent*)event
{
	[self _addTapWithView:control event:event fromRN:NO];
}

+ (void)addTapWithView:(UIView*)view withEvent:(UIEvent*)event
{
	[self _addTapWithView:view event:event fromRN:NO];
}

+ (void)addGestureRecognizerTap:(UIGestureRecognizer*)tgr withEvent:(UIEvent*)event
{
	[self _addTapWithView:tgr.view event:event fromRN:NO];
}

+ (void)addRNGestureRecognizerTapTouch:(UITouch*)touch withEvent:(UIEvent*)event;
{
	[self _addTapWithView:touch.view event:event fromRN:YES];
}

+ (void)addGestureRecognizerLongPress:(UIGestureRecognizer*)tgr duration:(NSTimeInterval)duration withEvent:(UIEvent*)event
{
	DTXRecordedAction* action = [DTXRecordedAction longPressActionWithView:tgr.view duration:duration event:event];
	if(action != nil)
	{
		[self _enhanceLastScrollEventIfNeededForElement:action.element];
		
		[recordedActions addObject:action];
		
		[self _visualizeLongPressAtView:tgr.view withAction:action];
	}
}

+ (void)_enhanceLastScrollEventIfNeededForElement:(DTXRecordedElement*)element
{
	DTXRecordedAction* prevAction = recordedActions.lastObject;
	
	if(prevAction.allowsUpdates == NO ||
	   prevAction.actionType != DTXRecordedActionTypeScroll)
	{
		return;
	}
	
	[prevAction enhanceScrollActionWithTargetElement:element];
}

+ (BOOL)_coalesceScrollViewEvent:(UIScrollView*)scrollView fromDeltaOriginOffset:(CGPoint)deltaOriginOffset toNewOffset:(CGPoint)newOffset
{
	DTXRecordedAction* prevAction = recordedActions.lastObject;
	
	if(prevAction.allowsUpdates == NO || prevAction.actionType != DTXRecordedActionTypeScroll || [prevAction.element isReferencingView:scrollView] == NO)
	{
		return NO;
	}
	
	if([prevAction updateScrollActionWithScrollView:scrollView fromDeltaOriginOffset:deltaOriginOffset toNewOffset:newOffset] == NO)
	{
		//The coalescing operation resulted in zero change, so remove the entire scroll action.
		[recordedActions removeLastObject];
		
		return YES;
	}
	
	return YES;
}

+ (void)addScrollEvent:(UIScrollView*)scrollView fromOriginOffset:(CGPoint)originOffset withEvent:(UIEvent *)event
{
	[self addScrollEvent:scrollView fromOriginOffset:originOffset toNewOffset:scrollView.contentOffset withEvent:event];
}

static inline CGFloat DTXDirectionOfScroll(DTXRecordedAction* action)
{
	if([action.actionArgs.lastObject isEqualToString:@"up"])
	{
		return -1;
	}
	
	return 1;
}

+ (void)_visualizeScrollOfView:(UIView*)view action:(DTXRecordedAction*)action
{
	CGFloat direction = DTXDirectionOfScroll(action);
	
	UIView* visualizer = [self _visualizerViewForView:view action:action systemImageName:direction < 0 ? @"arrow.up" : @"arrow.down"];
	
	[self _fadeVisualizerView:visualizer direction:direction];
}

+ (void)_visualizeScrollToTopOfView:(UIView*)view action:(DTXRecordedAction*)action
{
	UIView* visualizer = [self _visualizerViewForView:view action:action systemImageName:@"arrow.up.to.line"];
	
	[self _fadeVisualizerView:visualizer direction:-1];
}

+ (void)_visualizeScrollCancelOfView:(UIView*)view action:(DTXRecordedAction*)action
{
	UIView* visualizer = [self _visualizerViewForView:view action:action systemImageName:@"arrow.2.circlepath"];
	
	[self _systemDeleteVisualizerView:visualizer];
}

+ (void)addScrollEvent:(UIScrollView*)scrollView fromOriginOffset:(CGPoint)originOffset toNewOffset:(CGPoint)newOffset withEvent:(UIEvent *)event
{
//	NSLog(@"📣 %@->%@", @(originOffset), @(newOffset));
	
	DTXRecordedAction* action = [DTXRecordedAction scrollActionWithView:scrollView originOffset:originOffset newOffset:newOffset event:event];
	
	if(action == nil)
	{
		return;
	}
	
	if(action.isCancelled)
	{
		[self _visualizeScrollCancelOfView:scrollView action:action];
		
		return;
	}
	
	[self _visualizeScrollOfView:scrollView action:action];
	
//	if([self _coalesceScrollViewEvent:scrollView fromDeltaOriginOffset:originOffset toNewOffset:newOffset] == YES)
//	{
//		return;
//	}
	
	[recordedActions addObject:action];
}

+ (void)addDatePickerDateChangeEvent:(UIDatePicker*)datePicker withEvent:(UIEvent*)event
{
	DTXRecordedAction* action = [DTXRecordedAction datePickerDateChangeActionWithView:datePicker event:event];
	if(action != nil)
	{
		[recordedActions addObject:action];
		
		[self _visualizeDatePickerChangeDate:datePicker withAction:action];
	}
}

+ (void)_visualizePickerValueChangeAtView:(UIPickerView*)pickerView component:(NSInteger)component withAction:(DTXRecordedAction*)action
{
	UIView* container = [[pickerView tableViewForColumn:component] _containerView];
	CGRect frame = [pickerView.coordinateSpace convertRect:container.accessibilityFrame toCoordinateSpace:captureControlWindow.coordinateSpace];
	UIView* fakeView = [[UIView alloc] initWithFrame:frame];
	[captureControlWindow addSubview:fakeView];
	
	UIView* visualizer = [self _visualizerViewForView:fakeView action:action systemImageName:@"rectangle.fill.badge.checkmark"];
	
	[self _blinkVisualizerView:visualizer];
	
	[fakeView removeFromSuperview];
}

+ (void)addPickerViewValueChangeEvent:(UIPickerView*)pickerView component:(NSInteger)component withEvent:(UIEvent*)event
{
	DTXRecordedAction* action = [DTXRecordedAction pickerViewValueChangeActionWithView:pickerView component:component event:event];
	if(action != nil)
	{
		[recordedActions addObject:action];

		[self _visualizePickerValueChangeAtView:pickerView component:component withAction:action];
	}
}

+ (void)_visualizeSliderAdjust:(UISlider*)view withAction:(DTXRecordedAction*)action
{
	UIView* visualizer = [self _visualizerViewForView:view action:action systemImageName:@"slider.horizontal.3"];
	
	[self _blinkVisualizerView:visualizer];
}

+ (void)addSliderAdjustEvent:(UISlider*)slider withEvent:(UIEvent*)event
{
	DTXRecordedAction* action = [DTXRecordedAction sliderAdjustActionWithView:slider event:event];
	if(action != nil)
	{
		[recordedActions addObject:action];

		[self _visualizeSliderAdjust:slider withAction:action];
	}
}

+ (void)addScrollToTopEvent:(UIScrollView*)scrollView withEvent:(UIEvent*)event
{
	DTXRecordedAction* action = [DTXRecordedAction scrollToTopActionWithView:scrollView event:event];
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)([[scrollView valueForKeyPath:@"animation.duration"] doubleValue] * 0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		[self _visualizeScrollToTopOfView:scrollView action:action];
	});
	
	[recordedActions addObject:action];
}

+ (void)_visualizeTextChangeOfView:(UIView*)view action:(DTXRecordedAction*)action
{
	if(previousTextChangeVisualizer == nil || previousTextChangeVisualizer.superview == nil)
	{
		previousTextChangeVisualizer = [self _visualizerViewForView:view action:action systemImageName:@"text.cursor"];
	}
	
	[self _flashVisualizerView:previousTextChangeVisualizer];
}

+ (void)_visualizeReturnTapInView:(UIView*)view action:(DTXRecordedAction*)action
{
	if(previousTextChangeVisualizer == nil || previousTextChangeVisualizer.superview == nil)
	{
		previousTextChangeVisualizer = [self _visualizerViewForView:view action:action systemImageName:@"return"];
	}
	
	[self _flashVisualizerView:previousTextChangeVisualizer];
}

+ (void)addTextChangeEvent:(UIView<UITextInput>*)textInput
{
	NSString* text = [textInput textInRange:[textInput textRangeFromPosition:textInput.beginningOfDocument toPosition:textInput.endOfDocument]];
	DTXRecordedAction* action = [DTXRecordedAction replaceTextActionWithView:textInput text:text event:nil];
	if(action == nil)
	{
		return;
	}
	
	[recordedActions addObject:action];
	[self _visualizeTextChangeOfView:textInput action:action];
}

+ (void)addTextReturnKeyEvent:(UIView<UITextInput>*)textInput
{
	DTXRecordedAction* action = [DTXRecordedAction returnKeyTextActionWithView:textInput event:nil];
	if(action == nil)
	{
		return;
	}
	
	[recordedActions addObject:action];
	[self _visualizeReturnTapInView:textInput action:action];
}

+ (void)addTakeScreenshot
{
	[recordedActions addObject:[DTXRecordedAction takeScreenshotAction]];
}

@end
