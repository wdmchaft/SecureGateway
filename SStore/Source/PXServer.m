//
//  PXServer.m
//  SStore
//
//  Created by Will Ross on 11/16/10.
//  Copyright (c) 2010 Will Ross. All rights reserved.
//

#import "PXServer.h"
#import <errno.h>

//Private methods
@interface PXServer(){
    
}

@property (readwrite, nonatomic) int incomingSocket;
@property (readwrite, nonatomic) int connection;

//SSL properties
@property (readwrite, nonatomic) SSL_METHOD *sslMethod;
@property (readwrite, nonatomic) SSL_CTX *sslContext;
@property (readwrite, nonatomic) SSL *sslConnection;
@property (readwrite, nonatomic) BIO *bioConnection;
@property (readwrite, nonatomic, retain) NSString *pemPassword;

@end


@implementation PXServer

@synthesize port;
@synthesize delegate;
@synthesize incomingSocket;
@synthesize connection;
@dynamic connected;
@synthesize sslMethod;
@synthesize sslContext;
@synthesize sslConnection;
@synthesize bioConnection;
@synthesize secured;
@synthesize pemPassword;


#pragma mark Memory Management/Housekeeping
- (id)init {
    if ((self = [super init])) {
        //Set a default port
		//6968 is an unregistered port (but within the IANA registered port range)
		//I just chose it as it was my student number in middle school
		port = 6968;
		//Set default/sentinel values to the file handles
		incomingSocket = INT_MIN;
		connection = INT_MIN;
		
		//Initialize OpenSSL
		SSL_load_error_strings();
		ERR_load_BIO_strings();
		OpenSSL_add_all_algorithms();
		SSL_library_init();
		sslMethod = TLSv1_method();
		sslContext = SSL_CTX_new(sslMethod);
		secured = NO;
    }
    return self;
}

- (void)dealloc {
	//Shut the socket down
	[self closeSocket];
    [super dealloc];
}

#pragma mark -
#pragma mark Sockets Operations

-(BOOL)openSocket{
	//Status var used for return codes
	int status;
	//Create the socket
	self.incomingSocket = socket(PF_INET, SOCK_STREAM, IPPROTO_TCP);
	if(self.incomingSocket == -1){
		//We dun goofed. Socket not created
		NSLog(@"Socket failed to allocate. Aborting Server creation. Error: %s", strerror(errno));
		return NO;
	}
	
	//We want to be able to resue the socket, as sometimes 
	// we don't exit so cleanly (like now!)
	int enabled = 1;
	setsockopt(self.incomingSocket, SOL_SOCKET, SO_REUSEPORT, &enabled, sizeof(int));
	//We do not block in this program, we poll
	fcntl(self.incomingSocket, F_SETFL, O_NONBLOCK);
	
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
		NSLog(@"Binding failed. Error: %s", strerror(errno));
		close(self.incomingSocket);
		return NO;
	}
	
	//Start listening
	//The backlog limit /should/ be user configuarable, but for now it's going to be static
	//For info: On OS X (according to the listen man page), backlog is limited to 128
	status = listen(self.incomingSocket, 25);
	if(status == -1){
		NSLog(@"Setting socket to listen failed. Error: %s", strerror(errno));
		close(self.incomingSocket);
		return NO;
	}
	
	//All done
	return YES;
}

-(void)closeSocket{
	//Close the sockets out
	shutdown(self.connection, SHUT_RDWR);
	close(self.connection);
	close(self.incomingSocket);
	//Put the sentinel values back
	self.connection = INT_MIN;
	self.incomingSocket = INT_MIN;
}

-(BOOL)checkConnection{
	//Do we have an incoming connection?
	fd_set incomingSocketSet;
	FD_SET(self.incomingSocket, &incomingSocketSet);
	struct timeval zeroTime;
	zeroTime.tv_sec = 0;
	zeroTime.tv_usec = 0;
	int numReadySockets = select(self.incomingSocket + 1, &incomingSocketSet, NULL, NULL, &zeroTime);
	BOOL isSocketReady = FD_ISSET(self.incomingSocket, &incomingSocketSet) != 0? YES : NO;
	return isSocketReady && numReadySockets > 0;
}

-(void)openConnection{
	//At this time, the socket should have an incoming connection
	struct sockaddr_in *clientAddress;
	socklen_t clientAddressLength;
	self.connection = accept(self.incomingSocket, (struct sockaddr *)clientAddress, &clientAddressLength);
	if(self.connection < 0){
		NSLog(@"Connection failed. Closing out. Error: %s", strerror(errno));
		close(self.incomingSocket);
	}
	//This can sometimes take a while to load in, as it willdo DNS resolution. So we spawn it off into a cheapo thread
	//char *addressCString = inet_ntoa(clientAddress->sin_addr);
	//self.host = [NSHost hostWithAddress:[NSString stringWithUTF8String:addressCString]];
}



-(void)send:(NSData *)data{
	if(!self.connected){
		//Fail fast, we're not connected
		return;
	}
	//If we're not connected via SSL, send in the clear
	if(!self.secured){
		//So now we're positive we're connected;
		int status = send(self.connection, [data bytes], [data length], 0);
		if(status < 0){
			NSLog(@"Error sending data : %s", strerror(errno));
		}
	}else{
		//We're secured, so use SSL_write
		int status = SSL_write(self.sslConnection, [data bytes], [data length]);
		if(status < 0){
			NSLog(@"Error sending data : %d", SSL_get_error(self.sslConnection, status));
		}
	}
}

#pragma mark -
#pragma mark SSL Methods

//This is a private method, used only in the method below it
int getPemPassword(char *buffer, int size, int rwflag, void *userdata){
	if(userdata != NULL){
		//Userdata is an NSString
		NSString *password = userdata;
		int pwLength = [password length];
		//Convert the password to a C-String
		const char *sourceBuffer = [password UTF8String];
		//Copy the temp buffer to the real buffer
		//This is because sourceBuffer will disappear when password does
		char *destBuffer = malloc(sizeof(char) * (pwLength + 1));
		memcpy((void *)sourceBuffer, (void *)destBuffer, (sizeof(char) * (pwLength + 1)));
		return pwLength;
	}else{
		return 0;
	}
}

-(void)loadKey:(NSURL*)privateKey withPassword:(NSString*)password{
	//Set userdata
	self.pemPassword = password;
	SSL_CTX_set_default_passwd_cb_userdata(self.sslContext, self.pemPassword);
	//This feels a bit hacky
	SSL_CTX_set_default_passwd_cb(self.sslContext, getPemPassword);
	//Actually load the key file in
	SSL_CTX_use_PrivateKey_file(self.sslContext, [[privateKey path] UTF8String], SSL_FILETYPE_PEM);
}

-(void)loadCA:(NSURL*)certificate{
	SSL_CTX_use_certificate_file(self.sslContext, [[certificate path] UTF8String], SSL_FILETYPE_PEM);
}



-(void)prepareSSLConnection{
	//Force client verification, using the default checking
	SSL_CTX_set_verify(self.sslContext, SSL_VERIFY_FAIL_IF_NO_PEER_CERT, NULL);
	//Make the SSL object
	self.sslConnection = SSL_new(self.sslContext);
	//Make and configure the BIO object
	self.bioConnection = BIO_new(BIO_s_socket());
	BIO_set_fd(self.bioConnection, self.connection, BIO_NOCLOSE);
	//Bind the BIO and SSL objects together
	SSL_set_bio(self.sslConnection, self.bioConnection, self.bioConnection);
}

-(BOOL)openSSLConnection{
	//Now open the SSL connection
	struct timespec sleepTime;
	sleepTime.tv_sec = 0;
	sleepTime.tv_nsec = 250000000;
	while(!self.secured){
		//Wait for incoming data
		while(![self checkConnection]){
			nanosleep(&sleepTime, NULL);
		}
		//try to open the SSL connection
		int err = SSL_accept(self.sslConnection);
		if(err == 1){
			//connection ready
			self.secured = YES;
		}
	}
	return YES;
}


#pragma mark -
#pragma mark Custom Properties

-(BOOL)isConnected{
	return (self.incomingSocket != INT_MIN && self.connection != INT_MIN);
}


@end
