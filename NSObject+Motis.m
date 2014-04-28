//
//  NSObject+Motis.m
//  Copyright 2014 Mobile Jazz
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.

#import "NSObject+Motis.h"
#import <objc/runtime.h>

#define MOTIS_DEBUG 0 // <-- set 1 to get debug logs

#if MOTIS_DEBUG
#define MJLog(format, ...) NSLog(@"%@",[NSString stringWithFormat:format, ## __VA_ARGS__]);
#else
#define MJLog(format, ...)
#endif


// ------------------------------------------------------------------------------------------------------------------------------------------------------------------ //
// ------------------------------------------------------------------------------------------------------------------------------------------------------------------ //
// ------------------------------------------------------------------------------------------------------------------------------------------------------------------ //


#pragma mark - Motis_Private

/**
 * Stores a KeyPath and its path components.
 **/
@interface MTSKeyPath : NSObject

/**
 * Default initializer
 **/
- (id)initWithKeyPath:(NSString*)keyPath;

/**
 * The key (or KeyPath).
 **/
@property (nonatomic, strong, readonly) NSString *key;

/**
 * The KeyPath components.
 **/
@property (nonatomic, strong, readonly) NSArray *components;

@end

@implementation MTSKeyPath

- (id)initWithKeyPath:(NSString*)keyPath
{
    self = [super init];
    if (self)
    {
        _key = keyPath;
        _components = [keyPath componentsSeparatedByString:@"."];
    }
    return self;
}

@end

#pragma mark -
// ------------------------------------------------------------------------------------------------------------------------------------------------------------------ //
// ------------------------------------------------------------------------------------------------------------------------------------------------------------------ //
// ------------------------------------------------------------------------------------------------------------------------------------------------------------------ //

@interface NSObject (Motis_Private)

/** ---------------------------------------------- **
 * @name Mappings
 ** ---------------------------------------------- **/

/**
 * Collects all the mappings from each subclass layer.
 * @return The Motis Object Mapping.
 **/
+ (NSDictionary*)mts_cachedMapping;

/**
 * Collects all the array class mappings from each subclass layer.
 * @return The Motis Array Class Mapping.
 **/
+ (NSDictionary*)mts_cachedArrayClassMapping;

/**
 * KVC KeyPath support. 
 * @return Dictionary of keyPaths.
 * @discussion This method is grouping mts_mapping keys per each "first key path key". For example: {"keyA":["keyA.key1.key2", "keyA.key3", "keyA.key4.key5", ...], "keyB":["keyB.key6.key7", "keyB.key8", ...], ...}. Each array object is a mts_mapping key. 
 **/
+ (NSDictionary*)mts_keyPaths;

/** ---------------------------------------------- **
 * @name Object Class Introspection
 ** ---------------------------------------------- **/

/**
 * Returns the attribute type string for the given key.
 * @param key The name of property.
 * @return The attribute type string.
 */
- (NSString*)mts_typeAttributeForKey:(NSString*)key;

/**
 * YES if the attribute type can be converted into a Class object, NO otherwise.
 * @param typeAttribute The value returned by `-mts_typeAttributeForKey:`.
 * @return YES if it represents an object (therefore, exists a related class object).
 */
- (BOOL)mts_isClassTypeTypeAttribute:(NSString*)typeAttribute;

/**
 * Retrieve the class name and the array of protocols that the property implements.
 * @param className The returning class name.
 * @param protocols The returning array of protocols.
 * @param typeAttribute The value returned by `-mts_typeAttributeForKey:`.
 */
- (void)mts_getClassName:(out NSString *__autoreleasing*)className protocols:(out NSArray *__autoreleasing*)protocols fromTypeAttribute:(NSString*)typeAttribute;

/** ---------------------------------------------- **
 * @name Automatic Validation
 ** ---------------------------------------------- **/

/**
 * Return YES if the value has been automatically validated. The newer value is setted in the pointer.
 * @param ioValue The value to be validated.
 * @param key The property key in which the validated value is going to be assigned.
 * @return YES if automatic validation has been done, NO otherwise.
 * @discussion A return value of NO only indicates that the value couldn't be validated automatically.
 **/
- (BOOL)mts_validateAutomaticallyValue:(inout __autoreleasing id *)ioValue forKey:(NSString*)key;

/**
 * Return YES if the value has been automatically validated. The newer value is setted in the pointer.
 * @param ioValue The value to be validated.
 * @param typeClass The final class for the value.
 * @param key The property key in which the validated value will be assigned, either directly or as part of an array.
 * @return YES if automatic validation has been done, NO otherwise.
 * @discussion A return value of NO only indicates that the value couldn't be validated automatically.
 **/
- (BOOL)mts_validateAutomaticallyValue:(inout __autoreleasing id *)ioValue toClass:(Class)typeClass forKey:(NSString*)key;

@end


// ------------------------------------------------------------------------------------------------------------------------------------------------------------------ //
// ------------------------------------------------------------------------------------------------------------------------------------------------------------------ //
// ------------------------------------------------------------------------------------------------------------------------------------------------------------------ //


#pragma mark - Motis

@implementation NSObject (Motis)

#pragma mark Public Methods

- (void)mts_setValue:(id)value forKey:(NSString *)key
{
    NSString *mappedKey = [self mts_mapKey:key];
    
    if (!mappedKey)
    {
        [self mts_ignoredSetValue:value forUndefinedMappingKey:key];
        return;
    }
    
    if (value == [NSNull null])
        value = nil;
    
    if ([value isKindOfClass:NSArray.class])
    {
        __block NSMutableArray *modifiedArray = nil;
        
        [value enumerateObjectsWithOptions:NSEnumerationReverse usingBlock:^(id object, NSUInteger idx, BOOL *stop) {
            
            id validatedObject = object;
            
            NSError *error = nil;
            BOOL validated = [self mts_validateArrayObject:&validatedObject forArrayKey:mappedKey error:&error];
            
            // Automatic validation only if the value has not been manually validated
            if (object == validatedObject && validated)
            {
                Class typeClass = [self.class mts_cachedArrayClassMapping][mappedKey];
                if (typeClass)
                    validated = [self mts_validateAutomaticallyValue:&validatedObject toClass:typeClass forKey:mappedKey];
            }
            
            if (validated)
            {
                if (validatedObject != object)
                {
                    if (!modifiedArray)
                        modifiedArray = [value mutableCopy];
                    
                    modifiedArray[idx] = validatedObject;
                }
            }
            else
            {
                if (!modifiedArray)
                    modifiedArray = [value mutableCopy];
                
                [modifiedArray removeObjectAtIndex:idx];
                
                [self mts_invalidValue:validatedObject forArrayKey:mappedKey error:error];
            }
        }];
        
        if (modifiedArray)
            value = modifiedArray;
    }
    
    id originalValue = value;
    
    NSError *error = nil;
    BOOL validated = [self validateValue:&value forKey:mappedKey error:&error];
    
    // Automatic validation only if the value has not been manually validated
    if (originalValue == value && validated)
        validated = [self mts_validateAutomaticallyValue:&value forKey:mappedKey];
    
    if (validated)
    {
        [self setValue:value forKey:mappedKey];
    }
    else
        [self mts_invalidValue:value forKey:mappedKey error:error];
}

- (void)mts_setValuesForKeysWithDictionary:(NSDictionary *)keyedValues
{
    for (NSString *key in keyedValues)
    {
        // For each key-value pair in the dictionary
        
        NSArray *allKeyPath = [self.class mts_keyPaths][key];
        
        for (MTSKeyPath *keyPath in allKeyPath)
        {
            // For each key related keyPath
            
            BOOL validKeyPath = NO;
            id value = keyedValues;
            
            NSUInteger count = keyPath.components.count;
            
            for (NSInteger i=0; i<count; ++i)
            {
                // For each keyPath component
                
                NSString *path = keyPath.components[i];
                value = [value valueForKey:path];
                
                if (i < count - 1)
                {
                    if (![value isKindOfClass:NSDictionary.class]) // <-- Checking that the KeyPath is only accessing dictionary objects.
                        break;
                }
                else
                {
                    validKeyPath = YES;
                }
            }
            
            if (value && validKeyPath)
                [self mts_setValue:value forKey:keyPath.key];
            
//            id value = [keyedValues valueForKeyPath:keyPath.key];
//            if (value)
//                [self mts_setValue:value forKey:keyPath.key];
        }
    }
}

- (id)mts_valueForKey:(NSString*)key
{
    NSString *mappedKey = [self mts_mapKey:key];
    
    if (!mappedKey)
        return nil;
    
    id value = [self valueForKey:mappedKey];
        
    return value;
}

- (NSDictionary*)mts_dictionaryWithValuesForKeys:(NSArray *)keys
{
    NSMutableDictionary *dictionary = [NSMutableDictionary dictionaryWithCapacity:keys.count];
    
    for (NSString *key in keys)
    {
        id value = [self mts_valueForKey:key];
        if (!value)
            value = [NSNull null];
        
        dictionary[key] = value;
    }
    
    return [dictionary copy];
}

- (NSString*)mts_extendedObjectDescription
{
    NSString *description = self.description;
    NSArray *keys = [[self.class mts_cachedMapping] allValues];
    if (keys.count > 0)
    {
        NSDictionary *keyValues = [self dictionaryWithValuesForKeys:keys];
        return [NSString stringWithFormat:@"%@ - Mapped Values: %@", description, [keyValues description]];
    }
    return description;
}

#pragma mark Private Methods

- (NSString*)mts_mapKey:(NSString*)key
{
    NSString *mappedKey = [self.class mts_cachedMapping][key];
    
    if (mappedKey)
        return mappedKey;
    
    if ([self.class mts_shouldSetUndefinedKeys])
        return key;
    
    return nil;
}

@end


// ------------------------------------------------------------------------------------------------------------------------------------------------------------------ //
// ------------------------------------------------------------------------------------------------------------------------------------------------------------------ //
// ------------------------------------------------------------------------------------------------------------------------------------------------------------------ //


#pragma mark - Motis_Subclassing

@implementation NSObject (Motis_Subclassing)

+ (NSDictionary*)mts_mapping
{
    // Subclasses must override, always adding super to the mapping!
    return @{};
}

+ (BOOL)mts_shouldSetUndefinedKeys
{
    // Subclasses might override.
    return YES;
}

+ (NSDictionary*)mts_arrayClassMapping
{
    // Subclasses might override.
    return @{};
}

- (id)mts_willCreateObjectOfClass:(Class)typeClass withDictionary:(NSDictionary*)dictionary forKey:(NSString*)key abort:(BOOL*)abort;
{
    // Subclasses might override.
    return nil;
}

- (void)mts_didCreateObject:(id)object forKey:(NSString *)key
{
    // Subclasses might override.
}

+ (NSDateFormatter*)mts_validationDateFormatter
{
    // Subclasses may override and return a custom formatter.
    
    static NSDateFormatter *dateFormatter = nil;
    
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        dateFormatter = [[NSDateFormatter alloc] init];
        dateFormatter.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    });
    
    return dateFormatter;
}

- (BOOL)mts_validateArrayObject:(inout __autoreleasing id *)ioValue forArrayKey:(NSString *)arrayKey error:(out NSError *__autoreleasing *)outError
{
    // Subclasses might override.
    return YES;
}

- (void)mts_ignoredSetValue:(id)value forUndefinedMappingKey:(NSString*)key
{
    // Subclasses might override.
    MJLog(@"Undefined Mapping Key <%@> in class %@.", key, [self.class description]);
}

- (void)mts_invalidValue:(id)value forKey:(NSString *)key error:(NSError*)error
{
    // Subclasses might override.
    MJLog(@"Value for Key <%@> is not valid in class %@. Error: %@", key, [self.class description], error);
}

- (void)mts_invalidValue:(id)value forArrayKey:(NSString *)key error:(NSError*)error
{
    // Subclasses might override.
    MJLog(@"Item for ArrayKey <%@> is not valid in class %@. Error: %@", key, [self.class description], error);
}

@end


// ------------------------------------------------------------------------------------------------------------------------------------------------------------------ //
// ------------------------------------------------------------------------------------------------------------------------------------------------------------------ //
// ------------------------------------------------------------------------------------------------------------------------------------------------------------------ //


#pragma mark - Motis_Private

@implementation NSObject (Motis_Private)

+ (NSDictionary*)mts_cachedMapping
{
    static NSMutableDictionary *mappings = nil;
    
    static dispatch_once_t onceToken1;
    dispatch_once(&onceToken1, ^{
        mappings = [NSMutableDictionary dictionary];
    });
    
    NSString *className = NSStringFromClass(self);
    NSDictionary *mapping = mappings[className];
    
    if (!mapping)
    {
        Class superClass = [self superclass];
        
        NSMutableDictionary *dictionary = nil;
        
        if ([superClass isSubclassOfClass:NSObject.class])
            dictionary = [[superClass mts_cachedMapping] mutableCopy];
        else
            dictionary = [NSMutableDictionary dictionary];
        
        [dictionary addEntriesFromDictionary:[self mts_mapping]];
        
        mapping = [dictionary copy];
        mappings[className] = mapping;
    }

    return mapping;
}

+ (NSDictionary*)mts_cachedArrayClassMapping
{
    static NSMutableDictionary *arrayClassMappings = nil;
    
    static dispatch_once_t onceToken1;
    dispatch_once(&onceToken1, ^{
        arrayClassMappings = [NSMutableDictionary dictionary];
    });
    
    NSString *className = NSStringFromClass(self);
    NSDictionary *arrayClassMapping = arrayClassMappings[className];
    
    if (!arrayClassMapping)
    {
        Class superClass = [self superclass];
        
        NSMutableDictionary *mapping = nil;
        
        if ([superClass isSubclassOfClass:NSObject.class])
            mapping = [[superClass mts_cachedArrayClassMapping] mutableCopy];
        else
            mapping = [NSMutableDictionary dictionary];
        
        [mapping addEntriesFromDictionary:[self mts_arrayClassMapping]];
        
        arrayClassMapping = [mapping copy];
        arrayClassMappings[className] = arrayClassMapping;
    }
    
    return arrayClassMapping;
}

+ (NSDictionary*)mts_keyPaths
{
    static NSMutableDictionary *classKeyPaths = nil;
    
    static dispatch_once_t onceToken1;
    dispatch_once(&onceToken1, ^{
        classKeyPaths = [NSMutableDictionary dictionary];
    });
    
    NSString *className = NSStringFromClass(self);
    NSDictionary *keyPaths = classKeyPaths[className];
    
    if (!keyPaths)
    {
        Class superClass = [self superclass];
        
        NSMutableDictionary *dict = nil;
        
        if ([superClass isSubclassOfClass:NSObject.class])
            dict = [[superClass mts_keyPaths] mutableCopy];
        else
            dict = [NSMutableDictionary dictionary];
        
        NSDictionary *mapping = [self mts_mapping];
        for (NSString *key in mapping)
        {
            MTSKeyPath *keyPath = [[MTSKeyPath alloc] initWithKeyPath:key];
            NSString *firstPath = keyPath.components[0];
            
            NSMutableArray *listOfKeyPaths = dict[firstPath];
            if (!listOfKeyPaths)
            {
                listOfKeyPaths = [NSMutableArray array];
                dict[firstPath] = listOfKeyPaths;
            }
            
            [listOfKeyPaths addObject:keyPath];
        }
        
        keyPaths = [dict copy];
        classKeyPaths[className] = keyPaths;
    }
    
    return keyPaths;
}

- (NSString*)mts_typeAttributeForKey:(NSString*)key
{
    static NSMutableDictionary *typeAttributes = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        typeAttributes = [NSMutableDictionary dictionary];
    });
    
    NSMutableDictionary *classTypeAttributes = typeAttributes[NSStringFromClass(self.class)];
    if (!classTypeAttributes)
    {
        classTypeAttributes = [NSMutableDictionary dictionary];
        typeAttributes[NSStringFromClass(self.class)] = classTypeAttributes;
    }
    
    NSString *typeAttribute = classTypeAttributes[key];
    if (typeAttribute)
        return typeAttribute;
    
    objc_property_t property = class_getProperty(self.class, key.UTF8String);
    
    if (!property)
        return nil;
    
    const char * type = property_getAttributes(property);
    
    NSString * typeString = @(type);
    NSArray * attributes = [typeString componentsSeparatedByString:@","];
    typeAttribute = attributes[0];
    
    classTypeAttributes[key] = typeAttribute;
    
    return typeAttribute;
}

- (BOOL)mts_isClassTypeTypeAttribute:(NSString*)typeAttribute
{
    return [typeAttribute hasPrefix:@"T@"] && ([typeAttribute length] > 1);
}

- (void)mts_getClassName:(out NSString *__autoreleasing*)className protocols:(out NSArray *__autoreleasing*)protocols fromTypeAttribute:(NSString*)typeAttribute
{
    if ([self mts_isClassTypeTypeAttribute:typeAttribute])
    {
        typeAttribute = [typeAttribute substringWithRange:NSMakeRange(3, typeAttribute.length-4)];
        
        NSString *protocolNames = nil;
        
        NSScanner *scanner = [NSScanner scannerWithString:typeAttribute];
        [scanner scanUpToString:@"<" intoString:className];
        [scanner scanUpToString:@">" intoString:&protocolNames];
        
        if (*className == nil)
            *className = @"";
        
        if (protocolNames.length > 0)
        {
            protocolNames = [protocolNames substringFromIndex:1];
            protocolNames = [protocolNames stringByReplacingOccurrencesOfString:@" " withString:@""];
            *protocols = [protocolNames componentsSeparatedByString:@","];
        }
    }
}

- (BOOL)mts_validateAutomaticallyValue:(inout __autoreleasing id *)ioValue forKey:(NSString*)key
{
    if (*ioValue == nil)
        return YES;
    
    NSString * typeAttribute = [self mts_typeAttributeForKey:key];
    
    if (!typeAttribute) // <-- If no attribute, abort automatic validation
        return YES;
    
    NSString * propertyType = [typeAttribute substringFromIndex:1];
    const char * rawPropertyType = [propertyType UTF8String];
    
    if ([self mts_isClassTypeTypeAttribute:typeAttribute])
    {
        NSString *className = nil;
        NSArray *protocols = nil;
        
        [self mts_getClassName:&className protocols:&protocols fromTypeAttribute:typeAttribute];
        
        if (className.length == 0)
        {
            // It's an "id".
            
            // Actually, we should make a compare like this:
            // if (strcmp(rawPropertyType, @encode(id)) == 0)
            //    return YES;
            //
            // However, becuase of the "if" statements, we know that our typeAttribute begins with a "@" and
            // if "className.length" == 0 means that the "rawPropertyType" to be compared is exactly an @encode(id).
            //
            // Therefore, we return directly YES.
            
            return YES;
        }
        else
        {
            Class typeClass = NSClassFromString(className);
            
            if (typeClass)
            {
                MJLog(@"%@ --> %@", key, NSStringFromClass(typeClass));
                return [self mts_validateAutomaticallyValue:ioValue toClass:typeClass forKey:key];
            }
        }
        
        return NO;
    }
    else // because it is not a class, the property must be a basic type
    {
        if ([*ioValue isKindOfClass:NSNumber.class])
        {
#if defined(__LP64__) && __LP64__
            // Nothing to do
#else
            if (strcmp(rawPropertyType, @encode(BOOL)) == 0)
            {
                *ioValue = @([*ioValue boolValue]);
                return *ioValue != nil;
            }
#endif
            // Conversion from NSNumber to basic types is already handled by the system.
            return YES;
        }
        else if ([*ioValue isKindOfClass:NSString.class])
        {
            if (strcmp(rawPropertyType, @encode(BOOL)) == 0)
            {
                if ([*ioValue isKindOfClass:NSString.class])
                {
                    NSNumber *number = [[self.class mts_decimalFormatterAllowFloats] numberFromString:*ioValue];
                    
                    if (number)
                        *ioValue = @(number.boolValue);
                    else
                        *ioValue = @([*ioValue boolValue]);
                    
                    return *ioValue != nil;
                }
            }
            else if (strcmp(rawPropertyType, @encode(unsigned long long)) == 0)
            {
                if ([*ioValue isKindOfClass:NSString.class])
                {
                    *ioValue = [[self.class mts_decimalFormatterNoFloats] numberFromString:*ioValue];
                    return *ioValue != nil;
                }
            }
            
            // Other conversions from NSString to basic types are already handled by the system.
            
            //            else if (strcmp(rawPropertyType, @encode(char)) == 0)
            //            {
            //                if ([*ioValue isKindOfClass:NSString.class])
            //                {
            //                    NSNumber *number = [[self.class mts_decimalFormatter] numberFromString:*ioValue];
            //                    *ioValue = @(number.charValue);
            //                    return *ioValue != nil;
            //                }
            //            }
            //            else if (strcmp(rawPropertyType, @encode(unsigned char)) == 0)
            //            {
            //                if ([*ioValue isKindOfClass:NSString.class])
            //                {
            //                    NSNumber *number = [[self.class mts_decimalFormatter] numberFromString:*ioValue];
            //                    *ioValue = @(number.unsignedCharValue);
            //                    return *ioValue != nil;
            //                }
            //            }
            //            else if (strcmp(rawPropertyType, @encode(short)) == 0)
            //            {
            //                if ([*ioValue isKindOfClass:NSString.class])
            //                {
            //                    NSNumber *number = [[self.class mts_decimalFormatter] numberFromString:*ioValue];
            //                    *ioValue = @(number.shortValue);
            //                    return *ioValue != nil;
            //                }
            //            }
            //            else if (strcmp(rawPropertyType, @encode(unsigned short)) == 0)
            //            {
            //                if ([*ioValue isKindOfClass:NSString.class])
            //                {
            //                    NSNumber *number = [[self.class mts_decimalFormatter] numberFromString:*ioValue];
            //                    *ioValue = @(number.unsignedShortValue);
            //                    return *ioValue != nil;
            //                }
            //            }
            //            else if (strcmp(rawPropertyType, @encode(long)) == 0)
            //            {
            //                if ([*ioValue isKindOfClass:NSString.class])
            //                {
            //                    NSNumber *number = [[self.class mts_decimalFormatter] numberFromString:*ioValue];
            //                    *ioValue = @(number.longValue);
            //                    return *ioValue != nil;
            //                }
            //            }
            //            else if (strcmp(rawPropertyType, @encode(unsigned long)) == 0)
            //            {
            //                if ([*ioValue isKindOfClass:NSString.class])
            //                {
            //                    NSNumber *number = [[self.class mts_decimalFormatter] numberFromString:*ioValue];
            //                    *ioValue = @(number.unsignedLongValue);
            //                    return *ioValue != nil;
            //                }
            //            }
            
            return YES;
        }
        else // If not a number and not a string, types cannot match.
        {
            return NO;
        }
    }
}

- (BOOL)mts_validateAutomaticallyValue:(inout __autoreleasing id *)ioValue toClass:(Class)typeClass forKey:(NSString*)key
{
    // If types match, just return
    if ([*ioValue isKindOfClass:typeClass])
        return YES;
    
    // Otherwise, lets try to fit the desired class type
    // Because *ioValue comes frome a JSON deserialization, it can only be a string, number, array or dictionary.
    
    if ([*ioValue isKindOfClass:NSString.class]) // <-- STRINGS
    {
        if ([typeClass isSubclassOfClass:NSURL.class])
        {
            *ioValue = [NSURL URLWithString:*ioValue];
            return *ioValue != nil;
        }
        else if ([typeClass isSubclassOfClass:NSData.class])
        {
            *ioValue = [[NSData alloc] initWithBase64EncodedString:*ioValue options:NSDataBase64DecodingIgnoreUnknownCharacters];
            return *ioValue != nil;
        }
        else if ([typeClass isSubclassOfClass:NSNumber.class])
        {
            NSNumberFormatter *formatter = [NSObject mts_decimalFormatterAllowFloats];
            *ioValue = [formatter numberFromString:*ioValue];
            return *ioValue != nil;
        }
        if ([typeClass isSubclassOfClass:NSDate.class])
        {
            NSDateFormatter *dateFormatter = [self.class mts_validationDateFormatter];
            *ioValue = [dateFormatter dateFromString:*ioValue];
            return *ioValue != nil;
        }
    }
    else if ([*ioValue isKindOfClass:NSNumber.class]) // <-- NUMBERS
    {
        if ([typeClass isSubclassOfClass:NSDate.class])
        {
            *ioValue = [NSDate dateWithTimeIntervalSince1970:[*ioValue doubleValue]];
            return *ioValue != nil;
        }
        else if ([typeClass isSubclassOfClass:NSString.class])
        {
            *ioValue = [*ioValue stringValue];
            return *ioValue != nil;
        }
    }
    else if ([*ioValue isKindOfClass:NSArray.class]) // <-- ARRAYS
    {
        if ([typeClass isSubclassOfClass:NSMutableArray.class])
        {
            *ioValue = [NSMutableArray arrayWithArray:*ioValue];
            return *ioValue != nil;
        }
        else if ([typeClass isSubclassOfClass:NSMutableSet.class])
        {
            *ioValue = [NSMutableSet setWithArray:*ioValue];
            return *ioValue != nil;
        }
        else if ([typeClass isSubclassOfClass:NSSet.class])
        {
            *ioValue = [NSSet setWithArray:*ioValue];
            return *ioValue != nil;
        }
        else if ([typeClass isSubclassOfClass:NSMutableOrderedSet.class])
        {
            *ioValue = [NSMutableOrderedSet orderedSetWithArray:*ioValue];
            return *ioValue != nil;
        }
        else if ([typeClass isSubclassOfClass:NSOrderedSet.class])
        {
            *ioValue = [NSOrderedSet orderedSetWithArray:*ioValue];
            return *ioValue != nil;
        }
    }
    else if ([*ioValue isKindOfClass:NSDictionary.class]) // <-- DICTIONARIES
    {
        if ([typeClass isSubclassOfClass:NSMutableDictionary.class])
        {
            *ioValue = [NSMutableDictionary dictionaryWithDictionary:*ioValue];
            return *ioValue != nil;
        }
        else if ([typeClass isSubclassOfClass:NSObject.class])
        {
            BOOL abort = NO;
            id instance = [self mts_willCreateObjectOfClass:typeClass withDictionary:*ioValue forKey:key abort:&abort];
            
            if (abort)
                return NO;
            
            if (!instance)
            {
                instance = [[typeClass alloc] init];
                [instance mts_setValuesForKeysWithDictionary:*ioValue];
            }
            
            [self mts_didCreateObject:instance forKey:key];
            
            *ioValue = instance;
            return *ioValue != nil;
        }
    }
    
    return NO;
}

#pragma mark Private Helpers

+ (NSNumberFormatter*)mts_decimalFormatterAllowFloats
{
    static NSNumberFormatter *decimalFormatter = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        decimalFormatter = [NSNumberFormatter new];
        decimalFormatter.numberStyle = NSNumberFormatterDecimalStyle;
        decimalFormatter.allowsFloats = YES;
    });
    return decimalFormatter;
}

+ (NSNumberFormatter*)mts_decimalFormatterNoFloats
{
    static NSNumberFormatter *decimalFormatter = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        decimalFormatter = [NSNumberFormatter new];
        decimalFormatter.numberStyle = NSNumberFormatterDecimalStyle;
        decimalFormatter.allowsFloats = NO;
    });
    return decimalFormatter;
}

@end
