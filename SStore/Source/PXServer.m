//
//  PXServer.m
//  SStore
//
//  Created by Will Ross on 11/16/10.
//  Copyright (c) 2010 Naval Research Lab. All rights reserved.
//

#import "PXServer.h"


@implementation PXServer

@synthesize port;
@synthesize delegate;
@synthesize host;
- (id)init {
    if ((self = [super init])) {
        // Initialization code here.
    }
    
    return self;
}

- (void)dealloc {
    // Clean-up code here.
    
    [super dealloc];
}

-(void)send:(NSData *)data{
	
}

@end
