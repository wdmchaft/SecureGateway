//
//  PXServer.m
//  SStore
//
//  Created by Will Ross on 11/16/10.
//  Copyright (c) 2010 Naval Research Lab. All rights reserved.
//

#import "PXServer.h"

//Private methods
@interface PXServer(){
    
}

@property (readwrite, nonatomic) int incomingSocket;
@property (readwrite, nonatomic) int connectedSocket;

-(void)checkConnection;
-(void)openConnection;
@end


@implementation PXServer

@synthesize port;
@synthesize delegate;
@synthesize host;
@synthesize incomingSocket;
@synthesize connectedSocket;


#pragma mark Memory Management/Housekeeping
- (id)init {
    if ((self = [super init])) {
        //Set a default port
		//6968 is an unregistered port (but within the IANA registered port range)
		//I just chose it as it was my student number in middle school
		port = 6968;
		//Set a defualt Host.
		//Host is nil at first, as the server will accept connections form anywhere
		host = nil;
    }
    
    return self;
}

- (void)dealloc {
    // Clean-up code here.
    
    [super dealloc];
}

#pragma mark -
#pragma mark Sockets fun

-(BOOL)openSocket{
	//Status var used for return codes
	int status;
	//Create the socket
	self.incomingSocket = socket(PF_INET, SOCK_STREAM, IPPROTO_TCP);
	if(self.incomingSocket == -1){
		//We dun goofed. Socket not created
		NSLog(@"Socket failed to allocate. Aborting Server creation");
		return NO;
	}
	
	//Set up the address
	struct sockaddr_in serverAddress;
	//Clear the memory out
	memset(&serverAddress, 0, sizeof(serverAddress));
	//Set up the server address
	serverAddress.sin_family = AF_INET;
	//Since this is the default constructor, we have to set a default port
	serverAddress.sin_port = htons(self.port);
	//Accept any connection
	serverAddress.sin_addr.s_addr = INADDR_ANY;
	
	//Bind the socket
	status = bind(self.incomingSocket, (const struct sockaddr*)(&serverAddress), sizeof(serverAddress));
	if(status == -1){
		NSLog(@"Binding failed.");
		return NO;
	}
	
	//Start listening
	//The backlog limit /should/ be user configuarable, but for now it's going to be static
	//For info: On OS X (according to the listen man page), abcklog is limited to 128
	status = listen(self.incomingSocket, 25);
	if(status == -1){
		NSLog(@"Setting socket to listen failed.");
		return NO;
	}
	
	//Watch for an incoming connection in the run loop
	NSRunLoop *runLoop = [NSRunLoop currentRunLoop];
	[runLoop performSelector:@selector(checkConnection) target:self argument:nil order:0 modes:[NSArray arrayWithObject:NSDefaultRunLoopMode]];
	
	//All done
	return YES;
}

-(void)checkConnection{
	//Do we have an incoming connection?
	fd_set incomingSocketSet;
	FD_SET(self.incomingSocket, &incomingSocketSet);
	struct timeval zeroTime;
	zeroTime.tv_sec = 0;
	zeroTime.tv_usec = 0;
	if(select(2, &incomingSocketSet, NULL, NULL, &zeroTime)){
		//Cancel this job form the run loop
		[[NSRunLoop currentRunLoop] cancelPerformSelector:@selector(checkConnection) target:self argument:nil];
		[self openConnection];
	}
}

-(void)openConnection{
	//At this time, the socket should have an incoming connection
	struct sockaddr *clientAddress;
	socklen_t clientAddressLength;
	self.connectedSocket = accept(self.incomingSocket, clientAddress, &clientAddressLength);
	if(self.connectedSocket < 0){
		NSLog(@"Connection failed. Closing out.");
		close(self.incomingSocket);
	}
	//TODO: Add NSHost filling in here with port and host address
}



-(void)send:(NSData *)data{
	
}


@end