//
//  Created by Shuichiro Suzuki on 2/19/12.
//  Copyright (c) 2012 JugglerShu.Net. All rights reserved.
//

#import "XVimInsertEvaluator.h"
#import "XVimVisualEvaluator.h"
#import "XVimWindow.h"
#import "XVimKeyStroke.h"
#import "Logger.h"
#import "XVimEqualEvaluator.h"
#import "XVimDeleteEvaluator.h"
#import "XVimYankEvaluator.h"
#import "XVimKeymapProvider.h"
#import "XVimTextObjectEvaluator.h"
#import "XVimGVisualEvaluator.h"
#import "XVimRegisterEvaluator.h"
#import "XVimCommandLineEvaluator.h"
#import "XVimMarkSetEvaluator.h"
#import "XVimExCommand.h"
#import "XVimSearch.h"
#import "XVimOptions.h"
#import "XVim.h"

static NSString* MODE_STRINGS[] = {@"", @"-- VISUAL --", @"-- VISUAL LINE --", @"-- VISUAL BLOCK --"};

@interface XVimVisualEvaluator(){
    BOOL _waitForArgument;
	NSRange _operationRange;
    XVIM_VISUAL_MODE _visual_mode;
}
@property XVimPosition initialFromPos;
@property XVimPosition initialToPos;
@end

@implementation XVimVisualEvaluator 
- (id)initWithLastVisualStateWithWindow:(XVimWindow *)window{
    if( self = [self initWithWindow:window mode:[XVim instance].lastVisualMode] ){
        self.initialFromPos = [XVim instance].lastVisualSelectionBegin;
        self.initialToPos = [XVim instance].lastVisualPosition;
    }
    return self;
}
    
- (id)initWithWindow:(XVimWindow *)window mode:(XVIM_VISUAL_MODE)mode {
	if (self = [self initWithWindow:window]) {
        _waitForArgument = NO;
        _visual_mode = mode;
        self.initialFromPos = XVimMakePosition(NSNotFound, NSNotFound);;
        self.initialToPos = XVimMakePosition(NSNotFound, NSNotFound);;
	}
    return self;
}

- (NSString*)modeString {
	return MODE_STRINGS[_visual_mode];
}

- (XVIM_MODE)mode{
    return XVIM_MODE_VISUAL;
}

- (void)becameHandler{
    [super becameHandler];
    if( self.initialToPos.line != NSNotFound ){
        [self.sourceView xvim_moveToPosition:self.initialFromPos];
        [self.sourceView xvim_changeSelectionMode:_visual_mode];
        [self.sourceView xvim_moveToPosition:self.initialToPos];
    }else{
        [self.sourceView xvim_changeSelectionMode:_visual_mode];
    }
}

- (void)didEndHandler{
    if( !_waitForArgument ){
        [super didEndHandler];
        [self.sourceView xvim_changeSelectionMode:XVIM_VISUAL_NONE];
        // TODO:
        //[[[XVim instance] repeatRegister] setVisualMode:_mode withRange:_operationRange];
    }
}

- (XVimKeymap*)selectKeymapWithProvider:(id<XVimKeymapProvider>)keymapProvider {
	return [keymapProvider keymapForMode:XVIM_MODE_VISUAL];
}

- (void)drawRect:(NSRect)rect{
    NSTextView* sourceView = [self sourceView];
	
	NSUInteger glyphIndex = [sourceView insertionPoint];
	NSRect glyphRect = [sourceView xvim_boundingRectForGlyphIndex:glyphIndex];
	
	[[[sourceView insertionPointColor] colorWithAlphaComponent:0.5] set];
	NSRectFillUsingOperation(glyphRect, NSCompositeSourceOver);
}

- (XVimEvaluator*)eval:(XVimKeyStroke*)keyStroke{
    [XVim instance].lastVisualMode = self.sourceView.selectionMode;
    [XVim instance].lastVisualPosition = self.sourceView.insertionPosition;
    [XVim instance].lastVisualSelectionBegin = self.sourceView.selectionBeginPosition;
    
    XVimEvaluator *nextEvaluator = [super eval:keyStroke];
    /**
     * The folloing code is to draw insertion point when its visual mode.
     * Original NSTextView does not draw insertion point so we have to do it manually.
     **/
    [self.sourceView lockFocus];
    [self drawRect:[self.sourceView xvim_boundingRectForGlyphIndex:self.sourceView.insertionPoint]];
    [self.sourceView setNeedsDisplayInRect:[self.sourceView visibleRect] avoidAdditionalLayout:NO];
    [self.sourceView unlockFocus];
    
    return nextEvaluator;
}

- (XVimEvaluator*)a{
    [self.argumentString appendString:@"a"];
	return [[[XVimTextObjectEvaluator alloc] initWithWindow:self.window inner:NO] autorelease];
}

// TODO: There used to be "b:" and "B:" methods here. Take a look how they have been.

- (XVimEvaluator*)i{
    [self.argumentString appendString:@"i"];
    return [[[XVimTextObjectEvaluator alloc] initWithWindow:self.window inner:YES] autorelease];
}

- (XVimEvaluator*)c{
    XVimMotion* m = XVIM_MAKE_MOTION(MOTION_NONE, CHARACTERWISE_EXCLUSIVE, MOTION_OPTION_NONE, 1);
    [[self sourceView] xvim_change:m];
    return [[[XVimInsertEvaluator alloc] initWithWindow:self.window] autorelease];
}

- (XVimEvaluator*)C_b{
    [[self sourceView] xvim_scrollPageBackward:[self numericArg]];
    return self;
}

- (XVimEvaluator*)C_d{
    [[self sourceView] xvim_scrollHalfPageForward:[self numericArg]];
    return self;
}

- (XVimEvaluator*)d{
    [[self sourceView] xvim_delete:XVIM_MAKE_MOTION(MOTION_NONE, CHARACTERWISE_INCLUSIVE, MOTION_OPTION_NONE, 0)];
    return nil;
}

- (XVimEvaluator*)D{
    [[self sourceView] xvim_delete:XVIM_MAKE_MOTION(MOTION_NONE, LINEWISE, MOTION_OPTION_NONE, 0)];
    return nil;
}

- (XVimEvaluator*)C_f{
    [[self sourceView] xvim_scrollPageForward:[self numericArg]];
    return self;
}

- (XVimEvaluator*)g{
    [self.argumentString appendString:@"g"];
	return [[[XVimGVisualEvaluator alloc] initWithWindow:self.window] autorelease];
}

- (XVimEvaluator*)J{
	[[self sourceView] xvim_join:[self numericArg]];
    return nil;
}

- (XVimEvaluator*)m{
    // 'm{letter}' sets a local mark.
    [self.argumentString appendString:@"m"];
    self.onChildCompleteHandler = @selector(m_completed:);
	return [[[XVimMarkSetEvaluator alloc] initWithWindow:self.window] autorelease];
}

- (XVimEvaluator*)m_completed:(XVimEvaluator*)childEvaluator{
    // Vim does not escape from Visual mode after makr is set by m command
    self.onChildCompleteHandler = nil;
    return self;
}
    
- (XVimEvaluator*)p{
    NSTextView* view = [self sourceView];
    XVimRegister* reg = [[[XVim instance] registerManager] registerByName:self.yankRegister];
    [view xvim_put:reg.string withType:reg.type afterCursor:YES count:[self numericArg]];
    return nil;
}

- (XVimEvaluator*)P{
    // Looks P works as p in Visual Mode.. right?
    return [self p];
}

- (XVimEvaluator*)s{
	// As far as I can tell this is equivalent to change
	return [self c];
}

- (XVimEvaluator*)u{
	NSTextView *view = [self sourceView];
    [view xvim_makeLowerCase:XVIM_MAKE_MOTION(MOTION_NONE, CHARACTERWISE_EXCLUSIVE, MOTION_OPTION_NONE, [self numericArg])];
	return nil;
}

- (XVimEvaluator*)U{
	NSTextView *view = [self sourceView];
    [view xvim_makeUpperCase:XVIM_MAKE_MOTION(MOTION_NONE, CHARACTERWISE_EXCLUSIVE, MOTION_OPTION_NONE, [self numericArg])];
	return nil;
}

- (XVimEvaluator*)C_u{
    [[self sourceView] xvim_scrollHalfPageBackward:[self numericArg]];
    return self;
}

- (XVimEvaluator*)v{
	NSTextView *view = [self sourceView];
    if( view.selectionMode == XVIM_VISUAL_CHARACTER ){
        return  [self ESC];
    }
    [view xvim_changeSelectionMode:XVIM_VISUAL_CHARACTER];
    return self;
}

- (XVimEvaluator*)V{
	NSTextView *view = [self sourceView];
    if( view.selectionMode == XVIM_VISUAL_LINE){
        return  [self ESC];
    }
    [view xvim_changeSelectionMode:XVIM_VISUAL_LINE];
    return self;
}

- (XVimEvaluator*)C_v{
	NSTextView *view = [self sourceView];
    if( view.selectionMode == XVIM_VISUAL_BLOCK){
        return  [self ESC];
    }
    [view xvim_changeSelectionMode:XVIM_VISUAL_BLOCK];
    return self;
}

- (XVimEvaluator*)x{
    return [self d];
}

- (XVimEvaluator*)X{
    return [self D];
}

- (XVimEvaluator*)y{
    [[self sourceView] xvim_yank:nil];
    return nil;
}

- (XVimEvaluator*)DQUOTE{
    [self.argumentString appendString:@"\""];
    self.onChildCompleteHandler = @selector(onComplete_DQUOTE:);
    _waitForArgument = YES;
    return  [[[XVimRegisterEvaluator alloc] initWithWindow:self.window] autorelease];
}

- (XVimEvaluator*)onComplete_DQUOTE:(XVimRegisterEvaluator*)childEvaluator{
    NSString *xregister = childEvaluator.reg;
    if( [[[XVim instance] registerManager] isValidForYank:xregister] ){
        self.yankRegister = xregister;
        [self.argumentString appendString:xregister];
        self.onChildCompleteHandler = @selector(onChildComplete:);
    }
    else{
        return [XVimEvaluator invalidEvaluator];
    }
    _waitForArgument = NO;
    return self;
}

- (XVimEvaluator*)Y{
    [[self sourceView] xvim_changeSelectionMode:XVIM_VISUAL_LINE];
    [[self sourceView] xvim_yank:nil];
    return nil;
}

/*
TODO: This block is from commit 42498.
      This is not merged. This is about percent register
- (XVimEvaluator*)DQUOTE:(XVimWindow*)window{
    XVimEvaluator* eval = [[XVimRegisterEvaluator alloc] initWithContext:[XVimEvaluatorContext contextWithArgument:@"\""]
																  parent:self
															  completion:^ XVimEvaluator* (NSString* rname, XVimEvaluatorContext *context)  
						   {
							   XVimRegister *xregister = [[XVim instance] findRegister:rname];
							   if (xregister.isReadOnly == NO || [xregister.displayName isEqualToString:@"%"] ){
								   [context setYankRegister:xregister];
								   [context appendArgument:rname];
								   return [self withNewContext:context];
							   }
							   
							   [[XVim instance] ringBell];
							   return nil;
						   }];
	return eval;
}
*/

- (XVimEvaluator*)EQUAL{
    [[self sourceView] xvim_filter:XVIM_MAKE_MOTION(MOTION_NONE, CHARACTERWISE_EXCLUSIVE, MOTION_OPTION_NONE, [self numericArg])];
    return nil;
}

- (XVimEvaluator*)ESC{
    [[self sourceView] xvim_changeSelectionMode:XVIM_VISUAL_NONE];
    return nil;
}

- (XVimEvaluator*)C_c{
    return [self ESC];
}

- (XVimEvaluator*)C_LSQUAREBRACKET{
    return [self ESC];
}

- (XVimEvaluator*)COLON{
	XVimEvaluator *eval = [[XVimCommandLineEvaluator alloc] initWithWindow:self.window
                                                                firstLetter:@":'<,'>"
                                                                    history:[[XVim instance] exCommandHistory]
                                                                 completion:^ XVimEvaluator* (NSString* command, id* result)
                           {
                               XVimExCommand *excmd = [[XVim instance] excmd];
                               [excmd executeCommand:command inWindow:self.window];
                               
							   //NSTextView *sourceView = [window sourceView];
                               [[self sourceView] xvim_changeSelectionMode:XVIM_VISUAL_NONE];
                               return nil;
                           }
                                                                 onKeyPress:nil];
	
	return eval;
}

- (XVimEvaluator*)GREATERTHAN{
    [[self sourceView] xvim_shiftRight:XVIM_MAKE_MOTION(MOTION_NONE, CHARACTERWISE_INCLUSIVE, MOTION_OPTION_NONE, [self numericArg])];
    return nil;
}


- (XVimEvaluator*)LESSTHAN{
    [[self sourceView] xvim_shiftLeft:XVIM_MAKE_MOTION(MOTION_NONE, CHARACTERWISE_INCLUSIVE, MOTION_OPTION_NONE, [self numericArg])];
    return nil;
}

- (XVimEvaluator*)executeSearch:(XVimWindow*)window firstLetter:(NSString*)firstLetter {
    /*1
	XVimEvaluator *eval = [[XVimCommandLineEvaluator alloc] initWithContext:[[XVimEvaluatorContext alloc] init]
																	 parent:self 
															   firstLetter:firstLetter
																   history:[[XVim instance] searchHistory]
																completion:^ XVimEvaluator* (NSString *command)
						   {
							   XVimSearch *searcher = [[XVim instance] searcher];
							   NSTextView *sourceView = [window sourceView];
							   NSRange found = [searcher executeSearch:command 
															   display:[command substringFromIndex:1]
																  from:[window insertionPoint] 
															  inWindow:window];
							   //Move cursor and show the found string
							   if (found.location != NSNotFound) {
                                   unichar firstChar = [command characterAtIndex:0];
                                   if (firstChar == '?'){
                                       _insertion = found.location;
                                   }else if (firstChar == '/'){
                                       _insertion = found.location + command.length - 1;
                                   }
                                   [self updateSelectionInWindow:window];
								   [sourceView scrollTo:[window insertionPoint]];
								   [sourceView showFindIndicatorForRange:found];
							   } else {
								   [window errorMessage:[NSString stringWithFormat: @"Cannot find '%@'",searcher.lastSearchDisplayString] ringBell:TRUE];
							   }
                               return self;
						   }
                                                                onKeyPress:^void(NSString *command)
                           {
                               XVimOptions *options = [[XVim instance] options];
                               if (options.incsearch){
                                   XVimSearch *searcher = [[XVim instance] searcher];
                                   NSTextView *sourceView = [window sourceView];
                                   NSRange found = [searcher executeSearch:command 
																   display:[command substringFromIndex:1]
																	  from:[window insertionPoint] 
																  inWindow:window];
                                   //Move cursor and show the found string
                                   if (found.location != NSNotFound) {
                                       // Update the selection while preserving the current insertion point
                                       // The insertion point will be finalized if we complete a search
                                       NSUInteger prevInsertion = _insertion;
                                       unichar firstChar = [command characterAtIndex:0];
                                       if (firstChar == '?'){
                                           _insertion = found.location;
                                       }else if (firstChar == '/'){
                                           _insertion = found.location + command.length - 1;
                                       }
                                       [self updateSelectionInWindow:window];
                                       _insertion = prevInsertion;
                                       
                                       [sourceView scrollTo:found.location];
                                       [sourceView showFindIndicatorForRange:found];
                                   }
                               }
                           }];
	return eval;
     */
    return [self ESC]; // Temprarily this feture is turned off
}

- (XVimEvaluator*)QUESTION{
	return [self executeSearch:self.window firstLetter:@"?"];
}

- (XVimEvaluator*)SLASH{
	return [self executeSearch:self.window firstLetter:@"/"];
}

- (XVimEvaluator*)TILDE{
	NSTextView *view = [self sourceView];
    [view xvim_swapCase:XVIM_MAKE_MOTION(MOTION_NONE, CHARACTERWISE_EXCLUSIVE, MOTION_OPTION_NONE, [self numericArg])];
	return nil;
}

/*
- (XVimEvaluator*)motionFixedFrom:(NSUInteger)from To:(NSUInteger)to Type:(MOTION_TYPE)type{
    XVimMotion* m = XVIM_MAKE_MOTION(MOTION_POSITION, CHARACTERWISE_EXCLUSIVE, MOTION_OPTION_NONE, 1);
    m.position = to;
    [[self sourceView] xvim_move:m];
    return self;
}
 */

- (XVimEvaluator*)motionFixed:(XVimMotion *)motion{
    [[self sourceView] xvim_move:motion];
    [self resetNumericArg];
    return self;
}

@end
