//
//  ASLuaConnector.h
//  LuaControllerTest
//
//  Created by Avi Shevin on 1/2/13.
//  Copyright (c) 2013 Avi Shevin. All rights reserved.
//

#import <Foundation/Foundation.h>

// Redefine or define away attributes that don't apply unless compiled with ARC
#if ! __has_feature(objc_arc)
  #define weak assign
  #define __bridge
  #define __strong
#endif

@class ASLuaConnector;

typedef NSArray* (*ASLuaConnector_CFunction)(ASLuaConnector *luaConnector);
typedef NSArray* (*ASLuaConnector_ObjCFunction)(id self, SEL _cmd, ASLuaConnector *luaConnector);


@interface ASLuaConnector : NSObject

- (void) setVariableWithName:(NSString *)name andValue:(id)value;
- (id) getVariableWithName:(NSString *)name;
- (id) getVariableAsArrayWithName:(NSString *)name;

- (BOOL) loadCodeFromString:(NSString *)code withError:(NSError __strong **)error;

- (BOOL) defineFunctionWithName:(NSString *)name andBody:(NSString *)body andArgs:(NSArray *)args withError:(NSError __strong **)error;
- (BOOL) callFunctionWithName:(NSString *)name withArgs:(NSArray *)args givingResults:(NSArray __strong **)results withError:(NSError __strong **)error;

- (void) registerCFunctionWithName:(NSString *)name andAddress:(ASLuaConnector_CFunction)address;
- (void) registerCFunctionWithName:(NSString *)name andAddress:(ASLuaConnector_CFunction)address andClosures:(NSArray *)closures;

- (void) registerObjCFunctionWithName:(NSString *)name andInstance:(id)instance andSelector:(SEL)selector;
- (void) registerObjCFunctionWithName:(NSString *)name andInstance:(id)instance andSelector:(SEL)selector andClosures:(NSArray *)closures;

@property (nonatomic, weak) NSArray *closures;
@property (nonatomic, weak) NSArray *args;

@end

// Restore default functionality
#if ! __has_feature(objc_arc)
  #define weak assign
  #undef __bridge
  #undef __strong
#endif