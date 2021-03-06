//
//  PXConnection.h
//  SStore
//
//  Created by Will Ross on 11/27/10.
//  Copyright (c) 2010 Will Ross. All rights reserved.
//
#import "PXConnection.h"

@interface PXConnection()

@property (readwrite, nonatomic, getter=isConnected) BOOL connected;
@property (readwrite, nonatomic, getter=isSecure) BOOL secure;
@property (readwrite, nonatomic, getter=isListeningForData) BOOL listeningForData;
-(void)privateListen;
@end


@implementation PXConnection

//Sockets
@synthesize mainSocket;
@synthesize port;

//SSL
@synthesize sslContext;
@synthesize sslConnection;
@synthesize bioConnection;
@synthesize pemPassword;

//Status
@synthesize delegate;
@synthesize connected;
@synthesize secure;
@synthesize listeningForData;

- (id)init {
    if ((self = [super init])) {
        //Set a default port
		//6968 is an unregistered port (but within the IANA registered port range)
		//I just chose it as it was my student number in middle school
		port = 6968;
		//Set default/sentinel values to the file handles
		mainSocket = INT_MIN;
		connected = NO;
		delegate = nil;
		
		//Initialize OpenSSL
		SSL_load_error_strings();
		ERR_load_BIO_strings();
		OpenSSL_add_all_algorithms();
		SSL_library_init();
		SSL_METHOD *method = TLSv1_method();
		sslContext = SSL_CTX_new(method);
		secure = NO;
		
		//Make the listening thread (but don't start it yet!)
		listenThread = [[NSThread alloc] initWithTarget:self selector:@selector(privateListen) object:nil];
		listeningForData = NO;
    }
    return self;
}

- (void)dealloc {
    [super dealloc];
}

-(void)send:(NSData *)data{
	//Abstract method!
	//This may seem a bit odd at first, but it's working 
	//around a limitation of Obj-C. Obj-C does not have 
	//native abstract classes. This method forces the runtime
	//to think that this methods doesn't work. Basically, 
	//it must be subclassed. _cmd is the last called selector.
	[self doesNotRecognizeSelector:_cmd];
}

-(void)sendString:(NSString *)string{
	[self send:[NSKeyedArchiver archivedDataWithRootObject:string]];
}


-(void)setRecieve{
	[self doesNotRecognizeSelector:_cmd];
}

-(void)listen{
	self.listeningForData = YES;
	[listenThread start];
}

//This method is made to run in a seperate thread
-(void)privateListen{
	//Make an autorelease pool
	NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];
	
	while(![listenThread isCancelled] && self.connected){
		//Is there stuff to read?
		fd_set listenSet;
		FD_SET(self.mainSocket, &listenSet);
		struct timeval zeroTime;
		zeroTime.tv_sec = 0;
		zeroTime.tv_usec = 50;
		int numReadySockets = select(self.mainSocket + 1, &listenSet, NULL, NULL, &zeroTime);
		BOOL isSocketReady = FD_ISSET(self.mainSocket, &listenSet) != 0? YES : NO;
		if(numReadySockets > 0 && isSocketReady && self.delegate != nil){
			//Prepare the buffers (5MB buffer)
			size_t bufferSize = 5*1024*1024;
			void *buffer = malloc(bufferSize);
			ssize_t numBytesRead;
			//Use SSL_read for secure connections
			if(self.secure){
				numBytesRead = SSL_read(self.sslConnection, buffer, bufferSize);
			}else{
				numBytesRead = read(self.mainSocket, buffer, bufferSize);
			}
			//Is the connection broken?
			if(numBytesRead == 0){
				NSLog(@"Connection Broken");
				self.connected = NO; 
				[NSThread exit];
			}
			//Give the data to the delegate
			[delegate recievedData:[NSData dataWithBytes:buffer length:numBytesRead] fromConnection:self];
			free(buffer);
		}
	}
	//Drain the pool
	[pool drain];
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
		buffer = destBuffer;
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
	//Check it
	int status = SSL_CTX_check_private_key(self.sslContext);
	if(status != 1){
		unsigned long errorNum = ERR_get_error();
		NSLog(@"There's a certificate error in library '%s', function '%s', reason: %s", ERR_lib_error_string(errorNum),ERR_func_error_string(errorNum), ERR_reason_error_string(errorNum));
	}
}


-(void)loadCertChain:(NSURL*)certificateChain{
	SSL_CTX_use_certificate_chain_file(self.sslContext, [[certificateChain path] UTF8String]);
}



-(void)prepareSSLConnection{
	//Force client verification, using the default checking
	SSL_CTX_set_verify(self.sslContext, SSL_VERIFY_FAIL_IF_NO_PEER_CERT, NULL);
	//Enable ciphers
	SSL_CTX_set_cipher_list(self.sslContext, "ALL");
	//Make the SSL object
	self.sslConnection = SSL_new(self.sslContext);
	//Make and configure the BIO object
	self.bioConnection = BIO_new(BIO_s_socket());
	BIO_set_fd(self.bioConnection, self.mainSocket, BIO_NOCLOSE);
	//Bind the BIO and SSL objects together
	SSL_set_bio(self.sslConnection, self.bioConnection, self.bioConnection);
}

-(BOOL)openSSLConnection{
	//Abstract!
	[self doesNotRecognizeSelector:_cmd];
	return NO;
}

@end
