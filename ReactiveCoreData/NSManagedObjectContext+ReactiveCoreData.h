//
//  NSManagedObjectContext+ReactiveCoreData.h
//  ReactiveCoreData
//
//  Created by Jacob Gorban on 25/04/2013.
//  Copyright (c) 2013 Apparent Software. All rights reserved.
//

#import <CoreData/CoreData.h>

@interface NSManagedObjectContext (ReactiveCoreData)

// Returns a signal that sends result of executing a fetch request (or sends error)
- (RACSignal *)executeRequest:(NSFetchRequest *)request;

@end