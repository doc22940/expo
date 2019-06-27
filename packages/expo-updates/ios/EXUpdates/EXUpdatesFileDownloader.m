//  Copyright © 2018 650 Industries. All rights reserved.

#import <EXUpdates/EXUpdatesFileDownloader.h>

NS_ASSUME_NONNULL_BEGIN

NSString * const kEXUpdatesFileDownloaderErrorDomain = @"EXUpdatesFileDownloader";
NSTimeInterval const kEXUpdatesDefaultTimeoutInterval = 60;

@interface EXUpdatesFileDownloader () <NSURLSessionDataDelegate>

@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong) NSURLSessionConfiguration *sessionConfiguration;

@end

@implementation EXUpdatesFileDownloader

- (instancetype)init
{
  if (self = [super init]) {
    _sessionConfiguration = NSURLSessionConfiguration.defaultSessionConfiguration;
    _session = [NSURLSession sessionWithConfiguration:_sessionConfiguration delegate:self delegateQueue:nil];
  }
  return self;
}

- (instancetype)initWithURLSessionConfiguration:(NSURLSessionConfiguration *)sessionConfiguration
{
  if (self = [super init]) {
    _sessionConfiguration = sessionConfiguration ?: NSURLSessionConfiguration.defaultSessionConfiguration;
    _session = [NSURLSession sessionWithConfiguration:_sessionConfiguration delegate:self delegateQueue:nil];
  }
  return self;
}

- (void)dealloc
{
  [_session finishTasksAndInvalidate];
}

- (void)downloadFileFromURL:(NSURL *)url
                     toPath:(NSString *)destinationPath
               successBlock:(EXUpdatesFileDownloaderSuccessBlock)successBlock
                 errorBlock:(EXUpdatesFileDownloaderErrorBlock)errorBlock
{
  [self downloadDataFromURL:url successBlock:^(NSData *data, NSURLResponse *response) {
    if ([NSFileManager.defaultManager createFileAtPath:destinationPath contents:data attributes:nil]) {
      successBlock(data, response);
    } else {
      errorBlock([NSError errorWithDomain:kEXUpdatesFileDownloaderErrorDomain code:-1 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Could not write to path: %@", destinationPath]}], response);
    }
  } errorBlock:errorBlock];
}

- (void)downloadDataFromURL:(NSURL *)url
               successBlock:(EXUpdatesFileDownloaderSuccessBlock)successBlock
                 errorBlock:(EXUpdatesFileDownloaderErrorBlock)errorBlock
{
  // pass any custom cache policy onto this specific request
  NSURLRequestCachePolicy cachePolicy = _sessionConfiguration ? _sessionConfiguration.requestCachePolicy : NSURLRequestUseProtocolCachePolicy;

  NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url cachePolicy:cachePolicy timeoutInterval:kEXUpdatesDefaultTimeoutInterval];
  [self _setHTTPHeaderFields:request];

  __weak typeof(self) weakSelf = self;
  NSURLSessionDataTask *task = [_session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
    if (!error && [response isKindOfClass:[NSHTTPURLResponse class]]) {
      NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
      if (httpResponse.statusCode != 200) {
        NSStringEncoding encoding = [weakSelf _encodingFromResponse:response];
        NSString *body = [[NSString alloc] initWithData:data encoding:encoding];
        error = [weakSelf _errorFromResponse:httpResponse body:body];
      }
    }

    if (error) {
      errorBlock(error, response);
    } else {
      successBlock(data, response);
    }
  }];
  [task resume];
}

- (void)_setHTTPHeaderFields:(NSMutableURLRequest *)request
{
  // TODO(eric): add more fields here
  [request setValue:@"ios" forHTTPHeaderField:@"Expo-Platform"];

  NSString *binaryVersion = NSBundle.mainBundle.infoDictionary[@"CFBundleShortVersionString"];
  [request setValue:binaryVersion forHTTPHeaderField:@"Expo-Binary-Version"];

  NSString *releaseChannel = [EXUpdatesConfig sharedInstance].releaseChannel;
  if (releaseChannel) {
    [request setValue:releaseChannel forHTTPHeaderField:@"Expo-Release-Channel"];
  }
}

#pragma mark - NSURLSessionTaskDelegate

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task willPerformHTTPRedirection:(NSHTTPURLResponse *)response newRequest:(NSURLRequest *)request completionHandler:(void (^)(NSURLRequest *))completionHandler
{
  completionHandler(request);
}

#pragma mark - NSURLSessionDataDelegate

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask willCacheResponse:(NSCachedURLResponse *)proposedResponse completionHandler:(void (^)(NSCachedURLResponse *cachedResponse))completionHandler
{
  completionHandler(proposedResponse);
}

#pragma mark - Parsing the response

- (NSStringEncoding)_encodingFromResponse:(NSURLResponse *)response
{
  if (response.textEncodingName) {
    CFStringRef cfEncodingName = (__bridge CFStringRef)response.textEncodingName;
    CFStringEncoding cfEncoding = CFStringConvertIANACharSetNameToEncoding(cfEncodingName);
    if (cfEncoding != kCFStringEncodingInvalidId) {
      return CFStringConvertEncodingToNSStringEncoding(cfEncoding);
    }
  }
  // Default to UTF-8
  return NSUTF8StringEncoding;
}

- (NSError *)_errorFromResponse:(NSHTTPURLResponse *)response body:(NSString *)body
{
  NSDictionary *userInfo = @{
                             NSLocalizedDescriptionKey: body,
                             };
  return [NSError errorWithDomain:kEXUpdatesFileDownloaderErrorDomain code:response.statusCode userInfo:userInfo];
}

@end

NS_ASSUME_NONNULL_END