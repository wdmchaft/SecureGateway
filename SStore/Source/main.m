//
//  main.m
//  SStore
//
//  Created by Will Ross on 11/10/10.
//  Copyright (c) 2010 William Ross. All rights reserved.
//

#import <objc/objc-auto.h>
#import <unistd.h>


#import "PXServer.h"
#import "PXFaculty.h"

void testServer(int argc, const char **argv);

int main (int argc, const char * argv[]) {
	//Start Garbage Collection
	objc_startCollectorThread();
	
	//Test the SQLite objects
	NSLog(@"%@ variables:%@", [PXFaculty getName], [PXFaculty getProperties]);
	NSLog(@"%@ variables:%@", [PXPerson getName], [PXPerson getProperties]);
	NSLog(@"%@ variables:%@", [PXSQLiteObject getName], [PXSQLiteObject getProperties]);
	NSLog(@"%@", [PXFaculty getParents]);
	
	//testServer;
	
}

void testServer(int argc, const char **argv){
	//If no path given, set the default one
	NSString *configPath;
	if(argc == 2){
		configPath = [NSString stringWithUTF8String:argv[1]];
	}else{
		configPath = @"./config.plist";
	}
	//Read in the configuration variables
	NSDictionary *configuration = [NSDictionary dictionaryWithContentsOfFile:configPath];
	if(configuration == nil){
		//The configuration is invalid.
		NSLog(@"Invalid Cnfiguration file. Either place a proper plist named 'config.plist' in the current directory, or specify one following the command.");
		exit(1);
	}
	int port = [[configuration objectForKey:@"portNumber"] intValue];
	NSURL *certURL = [NSURL URLWithString:[configuration objectForKey:@"CACertificate"]];
	NSURL *keyURL = [NSURL URLWithString:[configuration objectForKey:@"keyFile"]];
	NSString *keyPassword = [configuration objectForKey:@"keyPassword"];
	
	//Testing:
	//Start a server
	PXServer *testServer = [[PXServer alloc] init];
	testServer.port = port;
	if(![testServer openSocket]){
		NSLog(@"Fatal error in opening socket. Try re-running the program");
		exit(1);
	}
	
	//Loop, waiting a quarter of a second between polling
	struct timespec sleepTime;
	sleepTime.tv_sec = 0;
	sleepTime.tv_nsec = 250000000;
	while(![testServer checkConnection]){
		nanosleep(&sleepTime, NULL);
	}
	NSLog(@"Connection ready");
	[testServer openConnection];
	
	NSString *testString = @"Testing output\n";
	[testServer send:[NSData dataWithBytes:[testString UTF8String] length:([testString length] + 1)]];
	
	//Try setting up SSL
	[testServer prepareSSLConnection];
	[testServer loadCA:certURL];
	[testServer loadKey:keyURL withPassword:keyPassword];
	[testServer openSSLConnection];
	
	//Close the connection
	[testServer closeSocket];
}

