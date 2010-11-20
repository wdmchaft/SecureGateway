//
//  PXServer.h
//  SStore
//
//  Created by Will Ross on 11/16/10.
//  Copyright (c) 2010 Naval Research Lab. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "PXConnection.h"
#import "PXConnectionDelegate.h"
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <netdb.h>

@interface PXServer : NSObject {
@private
	int port;
	NSHost *host;
	id<PXConnectionDelegate> delegate;
	
	CFReadStreamRef readStream;
	CFWriteStreamRef writeStream;
}

@property (readwrite, nonatomic) int port;
@property (readwrite, nonatomic) NSHost *host;
@property (readwrite, nonatomic) id<PXConnectionDelegate> delegate;
@property (readwrite, nonatomic) CFReadStreamRef readStream;
@property (readwrite, nonatomic) CFWriteStreamRef writeStream;

-(BOOL)openSocket;
-(void)send:(NSData *)data;

@end
