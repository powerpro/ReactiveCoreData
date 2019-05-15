//
//  RACManagedObjectFetchSpecs.m
//  ReactiveCoreData
//
//  Created by Jacob Gorban on 25/04/2013.
//  Copyright (c) 2013 Apparent Software. All rights reserved.
//

#import <Specta.h>
#define EXP_SHORTHAND
#import <Expecta.h>
#import <ReactiveObjC/ReactiveObjC.h>
#import "NSManagedObject+ReactiveCoreData.h"
#import "NSManagedObjectContext+ReactiveCoreData.h"
#import "Parent.h"
#import "RACSignal+ReactiveCoreData.h"

NSManagedObjectContext * contextForTest(BOOL setAsMain)
{
    NSPersistentStoreCoordinator *psc = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:[NSManagedObjectModel mergedModelFromBundles:nil]];
    NSError *error = nil;
    NSPersistentStore *persistentStore = [psc addPersistentStoreWithType:NSInMemoryStoreType configuration:nil URL:nil options:nil error:&error];
    if (!persistentStore) {
        [[NSApplication sharedApplication] presentError:error];
        return nil;
    }
    NSManagedObjectContext *ctx = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSConfinementConcurrencyType];
    [ctx setPersistentStoreCoordinator:psc];
    [ctx setUndoManager:nil];
    if (setAsMain) {
        [NSManagedObjectContext setMainContext:ctx];
    }
    [ctx save:NULL];
    return ctx;
}

SpecBegin(RACMagagedObjectFetch)

__block NSManagedObjectContext *ctx = nil;
__block BOOL completed = NO;

beforeEach(^{
    ctx = contextForTest(YES);
    completed = NO;
});

afterEach(^{
    ctx = nil;
    [NSManagedObjectContext setMainContext:nil];
});

describe(@"NSManagedObject", ^{
    __block BOOL executed;

    beforeEach(^{
        executed = NO;
    });

    it(@"creates a fetch request signal", ^{
        RACSignal *signal = Parent.findAll;
        [signal subscribeNext:^(NSFetchRequest *req) {
            expect(req).toNot.beNil();
            expect(req.entityName).to.equal(@"Parent");
            executed = YES;
        }];
        expect(executed).to.beTruthy();
    });

    it(@"inserts into context", ^{
        Parent *parent = [Parent insert];
        expect(parent).toNot.beNil();
        expect(parent.managedObjectContext).to.equal(ctx);
    });

    it(@"inserts with config block", ^{
        Parent *parent = [Parent insert:^(Parent *obj) {
            obj.name = @"Daddy";
            obj.age = 35;
        }];
        expect(parent.name).to.equal(@"Daddy");
        expect(parent.age).to.equal(35);
    });

    it(@"findOne's fetch passes nil for empty result", ^{
        [[[Parent findOne] fetch] subscribeNext:^(Parent *parent) {
            expect(parent).to.beNil();
            completed = YES;
        }];
        expect(completed).equal(YES);
    });

    it(@"findOne's fetch passes object for non-empty result", ^{
        [Parent insert:^(Parent *parent) {
            parent.name = @"One";
        }];

        [[[Parent findOne] fetch] subscribeNext:^(Parent *parent) {
            expect([parent name]).to.equal(@"One");
            completed = YES;
        }];
        expect(completed).equal(YES);
    });
});

describe(@"RACSignal", ^{
    it(@"counts results", ^{
        [Parent insert];
        expect([[[Parent findAll] count] first]).to.equal(@1);
    });

    it(@"fetches results", ^{
        Parent *p1 = [Parent insert];
        Parent *p2 = [Parent insert];
        NSArray *result = [[[Parent findAll] fetch] first];
        expect(result).to.contain(p1);
        expect(result).to.contain(p2);
    });

    it(@"fetches with trigger", ^{
        [Parent insert];
        RACSubject *trigger = [RACSubject subject];
        __block NSArray *actual;
        [[[[Parent findOne] fetchWithTrigger:trigger] collect]
            subscribeNext:^(id x) {
                actual = x;
                completed = YES;
            }];
        [trigger sendNext:@1];
        [trigger sendNext:@1];
        [trigger sendCompleted];
        expect(completed).to.beTruthy();
        expect(actual).to.haveCountOf(2);
    });

    it(@"starts a findAll fetch request for entity name", ^{
        __block NSFetchRequest *actual;
        [[[RACSignal return:@1] findAll:Parent.entityName]
            subscribeNext:^(id x){
                completed = YES;
                actual = x;
            }];
        expect(completed).to.beTruthy();
        expect(actual).to.beKindOf([NSFetchRequest class]);
        expect([actual entityName]).to.equal([Parent entityName]);
    });

    it(@"starts a findOne fetch request for entity name", ^{
        __block NSFetchRequest *actual;
        [[[RACSignal return:@1] findOne:Parent.entityName]
            subscribeNext:^(id x){
                completed = YES;
                actual = x;
            }];
        expect(completed).to.beTruthy();
        expect(actual).to.beKindOf([NSFetchRequest class]);
        expect([actual entityName]).to.equal([Parent entityName]);
        expect([actual fetchLimit]).to.equal(1);
    });

});

describe(@"FetchRequest operations:", ^{
    __block Parent *Joe;
    __block Parent *Jane;
    beforeEach(^{
        Joe = [Parent insert];
        Jane = [Parent insert];
        Joe.name = @"Joe";
        Jane.name = @"Jane";
        Joe.age = 40;
        Jane.age = 35;
    });
	
	it(@"updates fetch request with a constant predicate", ^{
        NSPredicate *predicate = [NSPredicate predicateWithFormat:@"name == 'Jane'"];
        NSArray *result = [[[[Parent findAll] where:predicate] fetch] first];
        expect(result).to.equal(@[ Jane ]);
	});
	
	it(@"updates fetch request with a predicate signal", ^{
        RACSubject *predicateSignal = [RACSubject subject];
        __block id final_result;
        
        [[[[[Parent findAll] where:predicateSignal] fetch] collect] subscribeNext:^(id x) {
            final_result = x;
        }];
        
        [predicateSignal sendNext:[NSPredicate predicateWithFormat:@"name == 'Jane'"]];
        [predicateSignal sendNext:[NSPredicate predicateWithFormat:@"name == 'Joe'"]];
        [predicateSignal sendCompleted];
        
        expect(final_result).to.equal((@[ @[ Jane ], @[ Joe ] ]));
	});

    it(@"where for property constant value", ^{
        NSArray *result = [[[Parent.findAll where:@"name" equals:@"Jane"] fetch] first];
        expect(result).to.equal(@[Jane]);
    });

    it(@"where for property signal", ^{
        RACSubject *nameSignal = [RACSubject subject];
        __block id final_result;
        [[[[Parent.findAll where:@"name == %@" args:@[nameSignal]] fetch] collect]
            subscribeNext:^(id x) {
                final_result = x;
            }];

        [nameSignal sendNext:@"Jane"];
        [nameSignal sendNext:@"Joe"];
        [nameSignal sendCompleted];

        NSArray *exp = @[@[Jane], @[Joe]];
        expect(final_result).to.equal(exp);
    });

    it(@"creates a correct fetch in where:contains:options: with nil options", ^{
        __block NSFetchRequest *actual;
        [[[Parent findAll] where:@"name" contains:@"value" options:nil] subscribeNext:^(id x) {
                actual = x;
                completed = YES;
            }];
        expect(completed).to.beTruthy();
        expect(actual.predicate.predicateFormat).to.equal(@"name CONTAINS \"value\"");
    });

    it(@"returns fetch without a predicate in where:contains:options: with an empty value", ^{
        __block NSFetchRequest *actual;
        [[[Parent findAll] where:@"name" contains:@"" options:nil] subscribeNext:^(id x) {
            actual = x;
            completed = YES;
        }];
        expect(completed).to.beTruthy();
        expect(actual.predicate).to.beNil();
    });

    it(@"returns a correct fetch predicate in where:contains:options: with an non-nil options", ^{
        __block NSFetchRequest *actual;
        [[[Parent findAll] where:@"name" contains:@"value" options:@"cd"] subscribeNext:^(id x) {
            actual = x;
            completed = YES;
        }];
        expect(completed).to.beTruthy();
        expect(actual.predicate.predicateFormat).to.equal(@"name CONTAINS[cd] \"value\"");
    });


    it(@"sends complete", ^{
        [[Parent.findAll fetch]
            subscribeNext:^(id x) {
            }
            completed:^{
                completed = YES;
            }];
        expect(completed).to.beTruthy();
    });

    it(@"handles predicates for constants", ^{
        NSArray *result = [[[Parent.findAll where:@"name == %@" args:@[@"Jane"]] fetch] first];
        expect(result).to.equal(@[Jane]);
    });

    context(@"check limits", ^{
        beforeEach(^{
            for (NSUInteger i=0; i<50; i++) {
                [Parent insert];
            }
        });

        it(@"number limits", ^{
            [[[Parent.findAll limit:@10] fetch]
                subscribeNext:^(id x) {
                    expect(x).to.haveCountOf(10);
                    completed = YES;
                }];
            expect(completed).to.beTruthy();
        });

        it(@"limit signals", ^{
            RACSubject *limitSignal = [RACSubject subject];
            __block NSArray *final_result;
            [[[[Parent.findAll limit:limitSignal] fetch] collect]
                subscribeNext:^(id x) {
                    final_result = x;
                }];
            [limitSignal sendNext:@10];
            [limitSignal sendNext:@30];
            [limitSignal sendCompleted];
            expect(final_result).to.haveCountOf(2);
            expect(final_result[0]).to.haveCountOf(10);
            expect(final_result[1]).to.haveCountOf(30);
        });
    });

    it(@"can return NSManagedObjectIDResultType", ^{
        [[[[Parent findAll] IDResultType] fetch] subscribeNext:^(NSArray *result) {
            expect(result).to.haveCountOf(2);
            expect([result lastObject]).to.beKindOf([NSManagedObjectID class]);
            completed = YES;
        }];
        expect(completed).to.beTruthy();
    });

    it(@"converts an ObjectID-type fetched array result to objects", ^{
        [[[[[Parent findAll] IDResultType] fetch] objectIDsToObjects] subscribeNext:^(NSArray *result) {
            expect(result).to.contain(Joe);
            expect(result).to.contain(Jane);
            completed = YES;
        }];
        expect(completed).to.beTruthy();
    });

    it(@"updates the sort of a fetch request for one constant sort descriptor", ^{
        NSSortDescriptor *sortDescriptor = [NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES];
        [[[Parent findAll] sortBy:sortDescriptor] subscribeNext:^(NSFetchRequest *actual) {
            expect(actual.sortDescriptors).to.equal(@[sortDescriptor]);
            completed = YES;
        }];
        expect(completed).to.beTruthy();
    });

    it(@"updates the sort of a fetch request for an array of sort descriptors", ^{
        NSSortDescriptor *sortByName = [NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES];
        NSSortDescriptor *sortByAge = [NSSortDescriptor sortDescriptorWithKey:@"age" ascending:YES];
        NSArray *sortDescriptors = @[ sortByName, sortByAge ];
        [[[Parent findAll] sortBy:sortDescriptors] subscribeNext:^(NSFetchRequest *actual) {
            expect(actual.sortDescriptors).to.equal(sortDescriptors);
            completed = YES;
        }];
        expect(completed).to.beTruthy();
    });

    it(@"updates the sort of a fetch request for a signal with an array of sort descriptors", ^{
        NSSortDescriptor *sortByName = [NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES];
        NSSortDescriptor *sortByAge = [NSSortDescriptor sortDescriptorWithKey:@"age" ascending:YES];
        NSArray *sortDescriptors1 = @[ sortByName, sortByAge ];
        NSArray *sortDescriptors2 = @[ sortByAge, sortByName ];
        RACSubject *sortDescriptors = [RACSubject subject];
        [[[[[Parent findAll] sortBy:sortDescriptors]
            map:^id(NSFetchRequest *request) {
                return request.sortDescriptors;
            }]
            collect]
            subscribeNext:^(NSArray *actual) {
                expect(actual[0]).to.equal(sortDescriptors1);
                expect(actual[1]).to.equal(sortDescriptors2);
                expect([actual[2][0] ascending]).to.beFalsy();
                expect([actual[2][0] key]).to.equal(@"name");
                completed = YES;
            }];
        [sortDescriptors sendNext:sortDescriptors1];
        [sortDescriptors sendNext:sortDescriptors2];
        [sortDescriptors sendNext:@"-name"];
        [sortDescriptors sendCompleted];
        expect(completed).to.beTruthy();
    });

    it(@"updates the sort of a fetch request ascending for a key string value", ^{
        NSSortDescriptor *sortDescriptor = [NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES];
        [[[Parent findAll] sortBy:@"name"] subscribeNext:^(NSFetchRequest *actual) {
            expect(actual.sortDescriptors).to.equal(@[sortDescriptor]);
            completed = YES;
        }];
        expect(completed).to.beTruthy();
    });

    it(@"updates the sort of a fetch request descending for a -key string value", ^{
        NSSortDescriptor *sortDescriptor = [NSSortDescriptor sortDescriptorWithKey:@"name" ascending:NO];
        [[[Parent findAll] sortBy:@"-name"] subscribeNext:^(NSFetchRequest *actual) {
            expect(actual.sortDescriptors).to.equal(@[sortDescriptor]);
            completed = YES;
        }];
        expect(completed).to.beTruthy();
    });

});

describe(@"Cross-Thread functionality", ^{
    it(@"Creates a new background context", ^{
        [[[RACSignal empty]
            performInBackgroundContext]
            subscribeCompleted:^{
                NSManagedObjectContext *moc = [NSManagedObjectContext currentContext];
                expect(moc).toNot.equal(ctx);
                completed = YES;
            }];
        expect(completed).will.beTruthy();
    });

    it(@"Merges changes from background context", ^AsyncBlock{
        [[[[[[RACSignal return:@"empty"]
            performInBackgroundContext]
            doNext:^(id _) {
                Parent *dad = [Parent insert];
                dad.name = @"Dad";
            }]
            saveContext]
            deliverOn:RACScheduler.mainThreadScheduler]
            subscribeNext:^(id _){
                [[[Parent findAll] fetch]
                    subscribeNext:^(NSArray *result) {
                        expect([[result lastObject] name]).to.equal(@"Dad");
                        completed = YES;
                        done();
                    }];
            }];
        expect(completed).will.beTruthy();
    });

    it(@"Has a signal that sends after a merge", ^AsyncBlock{
        __block BOOL local_completed = NO;
        id d1 = [[[[RACSignal return:@"empty"]
            performInBackgroundContext:^(NSManagedObjectContext *context) {
                [Parent insert];
            }]
            saveContext]
            subscribeNext:^(id x) {
            }];
        id d2 = [ctx.rcd_merged subscribeNext:^(NSNotification *note){
            local_completed = YES;
            expect([note userInfo][NSInsertedObjectsKey]).to.haveCountOf(1);
            done();
        }];
        expect(local_completed).will.beTruthy();
        expect(d1).toNot.beNil();
        expect(d2).toNot.beNil();
    });

    it(@"Has a signal that sends after a save", ^{
        NSManagedObjectContext *context = ctx;
        [ctx.rcd_saved subscribeNext:^(id x) {
            expect([x object]).to.equal(context);
            completed = YES;
        }];

        [Parent insert];
        [ctx save:NULL];
        expect(completed).will.beTruthy();
    });
});

describe(@"Document-based contexts", ^{
    __block NSManagedObjectContext *doc1ctx = nil;
    __block NSManagedObjectContext *doc2ctx = nil;

    beforeEach(^{
        doc1ctx = contextForTest(NO);
        doc2ctx = contextForTest(NO);
    });

    it(@"can perform on specific context", ^{
        expect([NSManagedObjectContext currentContext]).to.equal(ctx);
        [[doc1ctx perform]
            subscribeNext:^(NSManagedObjectContext *context1) {
                expect(context1).to.equal(doc1ctx);
                expect([NSManagedObjectContext currentContext]).to.equal(doc1ctx);
                completed = YES;
            }];
        expect([NSManagedObjectContext currentContext]).to.equal(ctx);
        expect(completed).to.beTruthy();
    });

    it(@"can perform on two specific contexts", ^{
        expect([NSManagedObjectContext currentContext]).to.equal(ctx);
        [[[doc1ctx perform]
            doNext:^(id _) {
                Parent *dad = [Parent insert];
                dad.name = @"dad";
            }]
            subscribeNext:^(NSManagedObjectContext *context1) {
            }];

        [[[doc2ctx perform]
            doNext:^(id _) {
                Parent *mom = [Parent insert];
                mom.name = @"mom";
            }]
            subscribeNext:^(NSManagedObjectContext *context1) {
            }];
        expect([NSManagedObjectContext currentContext]).to.equal(ctx);
        NSFetchRequest *req1 = [NSFetchRequest fetchRequestWithEntityName:[Parent entityName]];
        NSFetchRequest *req2 = [NSFetchRequest fetchRequestWithEntityName:[Parent entityName]];
        NSArray *parents1 = [doc1ctx executeFetchRequest:req1 error:NULL];
        NSArray *parents2 = [doc2ctx executeFetchRequest:req2 error:NULL];
        expect([parents1.lastObject name]).to.equal(@"dad");
        expect([parents2.lastObject name]).to.equal(@"mom");
    });

    it(@"deallocate the perform chain", ^{
        __block BOOL deallocated = NO;
        @autoreleasepool {
            RACDisposable *disposable  = [[doc1ctx perform]
            subscribeNext:^(NSManagedObjectContext *context1) {
                expect(deallocated).to.beFalsy();
            }];
        [disposable.rac_deallocDisposable addDisposable:[RACDisposable disposableWithBlock:^{
            deallocated = YES;
        }]];
        }
        expect(deallocated).to.beTruthy();
    });

    it(@"creates a child of a document context", ^{
        __block volatile uint32_t done = 0;
        NSMutableDictionary *expected = [[NSMutableDictionary alloc] initWithCapacity:5];
        [[[[[doc1ctx perform]
            doNext:^(id x) {
                Parent *dad = [Parent insert];
                dad.name = @"dad";
            }]
            saveContext]
            performInBackgroundContext]
            subscribeNext:^(id x){
                NSManagedObjectContext *currentContext = [NSManagedObjectContext currentContext];
                [expected setValue:currentContext forKey:@"context"];
                [expected setValue:[currentContext mainContext] forKey:@"mainContext"];
                [[[Parent findAll] fetch]
                    subscribeNext:^(NSArray *result) {
                        [expected setValue:result forKey:@"result"];
                        OSAtomicOr32Barrier(1, &done);
                    }];
            }];
        while (OSAtomicAnd32Barrier(1, &done) == 0) { usleep(10000);  };
        expect(expected[@"context"]).toNot.beNil();
        expect(expected[@"mainContext"]).to.equal(doc1ctx);
        NSArray *result = expected[@"result"];
        expect(result).to.haveCountOf(1);
        expect([[result lastObject] name]).to.equal(@"dad");
    });

    it(@"has performInBackground for context instance", ^AsyncBlock {
        __block NSManagedObjectContext *actualMain;
        [[doc1ctx performInBackground]
            subscribeNext:^(id x) {
                actualMain = [[NSManagedObjectContext currentContext] mainContext];
                done();
            }];
        expect(actualMain).will.equal(doc1ctx);
    });

    it(@"has performInContext", ^{
        [[[RACSignal return:@1]
            performInContext:doc1ctx]
            subscribeNext:^(id x) {
                Parent *dad = [Parent insert];
                dad.name = @"dad";
            }];

        __block NSArray *actual;
        [[[Parent findAll] fetchInMOC:doc1ctx]
            subscribeNext:^(NSArray *result) {
                actual = result;
            }];

        expect(actual).to.haveCountOf(1);
        expect([[actual lastObject] name]).to.equal(@"dad");
    });
});

SpecEnd

