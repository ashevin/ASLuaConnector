//
//  ASLuaConnector.m
//  LuaControllerTest
//
//  Created by Avi Shevin on 1/2/13.
//  Copyright (c) 2013 Avi Shevin. All rights reserved.
//

#import "ASLuaConnector.h"
#import "lua.h"
#import "lauxlib.h"
#import <objc/runtime.h>

// Redefine or define away attributes that don't apply unless compiled with ARC
#if ! __has_feature(objc_arc)
  #define __bridge
  #define __strong
#endif

static const NSInteger PRIVATE_CLOSURES_C = 3;
static const NSInteger PRIVATE_CLOSURES_OBJC = 5;

#pragma mark - Private Interface

@interface ASLuaConnector()

- (void) pushClosures:(NSArray *)closures;
- (void) pushLuaValueForObject:(id)object;
- (id) createObjectiveCTypeForIndexNumber:(NSNumber *)index;
- (id) createObjectiveCTypeForIndex:(int)index;
- (void) createTableFromDictionary:(NSDictionary *)dict;
- (void) createTableFromArray:(NSArray *)array;
- (NSDictionary *) createDictionaryFromTableAtIndex:(int)index;
- (NSArray *)coerceDictionaryToArray:(NSDictionary *)dict;

@end

#pragma mark - Helper functions

static int commonBridgeHandler(NSArray *results, ASLuaConnector *connector)
{
  for ( id res in results )
    [connector pushLuaValueForObject:res];

  return (int)results.count;
}

static int cFunctionBridge(lua_State *state)
{
  @autoreleasepool
  {
    ASLuaConnector *con = (__bridge ASLuaConnector*)lua_touserdata(state, lua_upvalueindex(1));
    ASLuaConnector_CFunction function = (ASLuaConnector_CFunction)lua_touserdata(state, lua_upvalueindex(2));
    NSInteger closureCount = lua_tointeger(state, lua_upvalueindex(3));
    
    NSMutableArray *closures = ( closureCount > 0 ) ? [NSMutableArray arrayWithCapacity:closureCount] : nil;
    
    for ( int i = 1; i <= closureCount; i++ )
    {
      id obj = [con createObjectiveCTypeForIndexNumber:@(lua_upvalueindex(PRIVATE_CLOSURES_C + i))];
      [closures addObject:obj];
    }

    con.closures = closures;

    int top = lua_gettop(state);
    NSMutableArray *args = ( top > 0 ) ? [NSMutableArray arrayWithCapacity:top] : nil;
    
    for ( int i = -top; i <= -1; i++ )
    {
      id obj = [con createObjectiveCTypeForIndexNumber:@(i)];
      [args addObject:obj];
    }
    
    con.args = args;
    
    return commonBridgeHandler(function(con), con);
  }
}

static int objcFunctionBridge(lua_State *state)
{
  @autoreleasepool
  {
    ASLuaConnector *con = (__bridge ASLuaConnector*)lua_touserdata(state, lua_upvalueindex(1));
    ASLuaConnector_ObjCFunction function = (ASLuaConnector_ObjCFunction)lua_touserdata(state, lua_upvalueindex(2));
    NSInteger closureCount = lua_tointeger(state, lua_upvalueindex(3));
    id instance = (__bridge id)lua_touserdata(state, lua_upvalueindex(4));
    const char *_cmd = lua_tostring(state, lua_upvalueindex(5));
    
    NSMutableArray *closures = ( closureCount > 0 ) ? [NSMutableArray arrayWithCapacity:closureCount] : nil;
    
    for ( int i = 1; i <= closureCount; i++ )
    {
      id obj = [con performSelector:@selector(createObjectiveCTypeForIndexNumber:) withObject:[NSNumber numberWithInt:lua_upvalueindex(PRIVATE_CLOSURES_OBJC + i)]];
      [closures addObject:obj];
    }
   
    con.closures = closures;

    int top = lua_gettop(state);
    NSMutableArray *args = ( top > 0 ) ? [NSMutableArray arrayWithCapacity:top] : nil;
    
    for ( int i = -top; i <= -1; i++ )
    {
      id obj = [con performSelector:@selector(createObjectiveCTypeForIndexNumber:) withObject:[NSNumber numberWithInt:i]];
      [args addObject:obj];
    }
    
    con.args = args;
    
    return commonBridgeHandler(function(instance, sel_registerName(_cmd), con), con);
  }
}

#pragma mark -

@implementation ASLuaConnector
{
  lua_State *state;
}

- (id) init
{
  self = [super init];
  if ( self )
  {
    state = luaL_newstate();
    
    if ( ! state )
      self = nil;
  }
  
  return self;
}

- (void) dealloc
{
  lua_close(state);

#if ! __has_feature(objc_arc)
  self.closures = nil;
  self.args = nil;
  
  [super dealloc];
#endif
}

#pragma mark - API

- (void) setVariableWithName:(NSString *)name andValue:(id)value
{
#ifdef ASLUACONNECTOR_STACK_DEBUG
  NSLog(@"setVariableWithName start: %d", lua_gettop(state));
#endif

  [self pushLuaValueForObject:value];
  
  lua_setglobal(state, [name UTF8String]);

#ifdef ASLUACONNECTOR_STACK_DEBUG
  NSLog(@"setVariableWithName end: %d", lua_gettop(state));
#endif
}

- (id) getVariableWithName:(NSString *)name
{
#ifdef ASLUACONNECTOR_STACK_DEBUG
  NSLog(@"getVariableWithName start: %d", lua_gettop(state));
#endif

  lua_getglobal(state, [name UTF8String]);

  id ret = [self createObjectiveCTypeForIndex:lua_gettop(state)];

  lua_pop(state, 1);

#ifdef ASLUACONNECTOR_STACK_DEBUG
  NSLog(@"getVariableWithName end: %d", lua_gettop(state));
#endif
  
  return ret;
}

- (id) getVariableAsArrayWithName:(NSString *)name
{
#ifdef ASLUACONNECTOR_STACK_DEBUG
  NSLog(@"getVariableAsArrayWithName start: %d", lua_gettop(state));
#endif

  id dict = [self getVariableWithName:name];
  
  NSArray *ret =
    ( [dict isKindOfClass:NSDictionary.class] )
    ? [self coerceDictionaryToArray:dict]
    : nil;

#ifdef ASLUACONNECTOR_STACK_DEBUG
  NSLog(@"getVariableAsArrayWithName end: %d", lua_gettop(state));
#endif
  
  return ret;
}

- (BOOL) loadCodeFromString:(NSString *)code withError:(NSError __strong **)error
{
#ifdef ASLUACONNECTOR_STACK_DEBUG
  NSLog(@"loadCodeFromString start: %d", lua_gettop(state));
#endif

  int res;
  
  if ( ( res = luaL_dostring(state, [code UTF8String]) ) != LUA_OK )
  {
    if ( error != nil )
      *error = [NSError errorWithDomain:@"ASLuaConnector" code:res userInfo:@{ @"msg" : [NSString stringWithCString:lua_tostring(state, -1) encoding:NSUTF8StringEncoding] }];

    lua_pop(state, 1);
  }
  else
    if ( error != nil )
      *error = nil;

#ifdef ASLUACONNECTOR_STACK_DEBUG
  NSLog(@"loadCodeFromString end: %d", lua_gettop(state));
#endif
  
  return ( res == LUA_OK );
}

- (BOOL) defineFunctionWithName:(NSString *)name andBody:(NSString *)body andArgs:(NSArray *)args withError:(NSError __strong **)error
{
  NSString *argStr = [args componentsJoinedByString:@","];
  argStr = ( argStr != nil ) ? argStr : @"";
  
  NSString *str = [NSString stringWithFormat:@"%@ = function (%@) %@ end", name, argStr, body];
  
  return [self loadCodeFromString:str withError:error];
}

- (BOOL) callFunctionWithName:(NSString *)name withArgs:(NSArray *)args givingResults:(NSArray __strong **)results withError:(NSError __strong **)error
{
#ifdef ASLUACONNECTOR_STACK_DEBUG
  NSLog(@"callFunctionWithName start: %d", lua_gettop(state));
#endif

  lua_getglobal(state, [name UTF8String]);

  for ( id arg in args )
  {
    if ( [arg isKindOfClass:NSNumber.class] )
      lua_pushnumber(state, [arg doubleValue]);
    
    else if ( [arg isKindOfClass:NSString.class] )
        lua_pushstring(state, [arg UTF8String]);

    else
      lua_pushlightuserdata(state, (__bridge void*)arg);
  }

  int res = lua_pcall(state, (int)args.count, LUA_MULTRET, 0);
  BOOL ret = ( ( res   ) == LUA_OK );
  
  if ( res == LUA_OK )
  {
    int top = lua_gettop(state);
      
    if (  results != nil )
    {
      *results = ( top > 0 ) ? [NSMutableArray arrayWithCapacity:top] : nil;
      
      for ( int i = top; i > 0; i-- )
      {
        id result = [self createObjectiveCTypeForIndex:-i];
        if ( result != nil )
          [(NSMutableArray*)(*results) addObject:result];
      }
    }

    lua_pop(state, top);
  
    if ( error )
      *error = nil;
  }
  else
  {
    if ( error != nil )
      *error = [NSError errorWithDomain:@"ASLuaConnector" code:res userInfo:@{ @"msg" : [NSString stringWithCString:lua_tostring(state, -1) encoding:NSUTF8StringEncoding] }];

    lua_pop(state, 1);
  }

#ifdef ASLUACONNECTOR_STACK_DEBUG
  NSLog(@"callFunctionWithName end: %d", lua_gettop(state));
#endif
  
  return ret;
}

- (void) registerCFunctionWithName:(NSString *)name andAddress:(ASLuaConnector_CFunction)address
{
  [self registerCFunctionWithName:name andAddress:address andClosures:nil];
}

- (void) registerCFunctionWithName:(NSString *)name andAddress:(ASLuaConnector_CFunction)address andClosures:(NSArray *)closures
{
#ifdef ASLUACONNECTOR_STACK_DEBUG
  NSLog(@"registerCFunctionWithName start: %d", lua_gettop(state));
#endif

  lua_pushlightuserdata(state, (__bridge void*)self);
  lua_pushlightuserdata(state, address);
  lua_pushinteger(state, closures.count);
  
  [self pushClosures:closures];
  
  lua_pushcclosure(state, cFunctionBridge, (int)closures.count + PRIVATE_CLOSURES_C);
  lua_setglobal(state, [name UTF8String]);

#ifdef ASLUACONNECTOR_STACK_DEBUG
  NSLog(@"registerCFunctionWithName end: %d", lua_gettop(state));
#endif
}

- (void) registerObjCFunctionWithName:(NSString *)name andInstance:(id)instance andSelector:(SEL)selector
{
  [self registerObjCFunctionWithName:name andInstance:instance andSelector:selector andClosures:nil];
}

- (void) registerObjCFunctionWithName:(NSString *)name andInstance:(id)instance andSelector:(SEL)selector andClosures:(NSArray *)closures
{
#ifdef ASLUACONNECTOR_STACK_DEBUG
  NSLog(@"registerObjCFunctionWithName start: %d", lua_gettop(state));
#endif

  ASLuaConnector_ObjCFunction address = (ASLuaConnector_ObjCFunction) class_getMethodImplementation(object_getClass(instance), selector);
  
  lua_pushlightuserdata(state, (__bridge void*)self);
  lua_pushlightuserdata(state, address);
  lua_pushinteger(state, closures.count);
  lua_pushlightuserdata(state, (__bridge void*)instance);
  lua_pushstring(state, [NSStringFromSelector(selector) UTF8String]);
  
  [self pushClosures:closures];
  
  lua_pushcclosure(state, objcFunctionBridge, (int)closures.count + PRIVATE_CLOSURES_OBJC);
  lua_setglobal(state, [name UTF8String]);

#ifdef ASLUACONNECTOR_STACK_DEBUG
  NSLog(@"registerObjCFunctionWithName end: %d", lua_gettop(state));
#endif
}

#pragma mark - Private Methods

- (void) pushClosures:(NSArray *)closures
{
  for ( id closure in closures )
    lua_pushlightuserdata(state, (__bridge void*)closure);
}

- (void) pushLuaValueForObject:(id)object
{
  if ( [object isKindOfClass:NSNumber.class] )
    lua_pushnumber(state, [object doubleValue]);
  
  else if ( [object isKindOfClass:NSString.class] )
    lua_pushstring(state, [object UTF8String]);
  
  else if ( [object isKindOfClass:NSDictionary.class] )
    [self createTableFromDictionary:object];
  
  else if ( [object isKindOfClass:NSArray.class] )
    [self createTableFromArray:object];

  else
    lua_pushlightuserdata(state, (__bridge void*)object);
}

// This is needed for the C Function Bridge.
- (id) createObjectiveCTypeForIndexNumber:(NSNumber *)index
{
  return [self createObjectiveCTypeForIndex:[index intValue]];
}

- (id) createObjectiveCTypeForIndex:(int)index
{
  int t = lua_type(state, index);

  id ret = nil;
  
  switch (t)
  {
    case LUA_TSTRING:
      ret = [NSString stringWithCString:lua_tostring(state, index) encoding:NSUTF8StringEncoding];
      break;

    case LUA_TBOOLEAN:
      ret = [NSNumber numberWithBool:lua_toboolean(state, index)];
      break;

    case LUA_TNUMBER:
      ret = [NSNumber numberWithDouble:lua_tonumber(state, index)];
      break;

    case LUA_TTABLE:
      ret = [self createDictionaryFromTableAtIndex:index];
      break;
      
    case LUA_TLIGHTUSERDATA:
      ret = (__bridge id)lua_touserdata(state, index);
      break;
      
    default:  // Other types are not supported.
      ret = nil;
      break;
  }
  
  return ret;
}

- (void) createTableFromDictionary:(NSDictionary *)dict
{
  lua_createtable(state, 0, (int)dict.count);
  int top = lua_gettop(state);

  NSEnumerator *keys = [dict keyEnumerator];

  id key;
  while ( ( key = [keys nextObject]) )
  {
    [self pushLuaValueForObject:key];
    
    [self pushLuaValueForObject:[dict objectForKey:key]];
    
    lua_settable(state, top);
  }
}

- (void) createTableFromArray:(NSArray *)array
{
  lua_createtable(state, 0, (int)array.count);
  int top = lua_gettop(state);

  for ( int i = 0; i < array.count; i++ )
  {
    lua_pushinteger(state, i + 1);  // Lua convention is for arrays to begin with an index of 1.

    [self pushLuaValueForObject:array[i]];

    lua_settable(state, top);
  }
}

- (NSDictionary *) createDictionaryFromTableAtIndex:(int)index
{
  NSMutableDictionary *dict = [NSMutableDictionary dictionary];
  
  lua_pushnil(state);
  
  while ( lua_next(state, index) != 0 )
  {
    dict[[self createObjectiveCTypeForIndex:lua_absindex(state, -2)]] = [self createObjectiveCTypeForIndex:lua_absindex(state, -1)];
    
    lua_pop(state, 1);
  }
  
  return dict;
}

- (NSArray *)coerceDictionaryToArray:(NSDictionary *)dict
{
  int m = 0, n = 0;

  NSArray *keys = [dict allKeys];
  
  for ( int i = 0; i < keys.count; i++ )
  {
    id val = keys[i];
    
    if ( ! [val isKindOfClass:NSNumber.class] )
      return nil;
    
    double d = [val doubleValue];
    
    if ( d < 1 && ( floor(d) != d ) )
      return nil;

    m = MAX(m, d);
    n++;
  }
  
  if ( m != n )
    return nil;
  
  // At this point we've verified that all the keys are numeric, integer and sequencial.
  
  NSMutableArray *array = [NSMutableArray arrayWithCapacity:keys.count];
  
  for ( NSNumber *n in [keys sortedArrayUsingComparator:^(id obj1, id obj2){ return [(NSNumber *)obj1 compare:(NSNumber *)obj2]; } ])
    [array addObject:[dict objectForKey:n]];
  
  return array;
}

@end

// Restore default functionality
#if ! __has_feature(objc_arc)
  #undef __bridge
  #undef __strong
#endif