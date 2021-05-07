
// Copyright © Blockchain Luxembourg S.A. All rights reserved.

@import CommonCryptoKit;
@import WalletPayloadKit;
@import FirebaseAnalytics;
@import NetworkKit;
@import ToolKit;
#import <CommonCrypto/CommonKeyDerivation.h>
#import <JavaScriptCore/JavaScriptCore.h>
#import "Wallet.h"
#import "Assets.h"
#import "Blockchain-Swift.h"
#import "BTCAddress.h"
#import "BTCData.h"
#import "BTCKey.h"
#import "crypto_scrypt.h"
#import "KeychainItemWrapper+Credentials.h"
#import "ModuleXMLHttpRequest.h"
#import "NSArray+EncodedJSONString.h"
#import "NSData+Hex.h"
#import "NSNumberFormatter+Currencies.h"
#import "NSString+JSONParser_NSString.h"
#import "NSURLRequest+SRWebSocket.h"

#define DICTIONARY_KEY_CURRENCY @"currency"

NSString * const kAccountInvitations = @"invited";
NSString * const kLockboxInvitation = @"lockbox";

@interface Wallet ()

@property (nonatomic, strong) JSContext *context;
@property (nonatomic, assign) BOOL isSettingDefaultAccount;
@property (nonatomic, strong) NSMutableDictionary *timers;
@property (nonatomic, copy) NSDictionary *bitcoinCashExchangeRates;

@end

@implementation Wallet

@synthesize delegate;

- (instancetype)init
{
    self = [super init];
    if (self) {
        _bitcoin = [[BitcoinWallet alloc] initWithLegacyWallet:self];
        _ethereum = [[EthereumWallet alloc] initWithLegacyWallet:self];
        _crypto = [[WalletCryptoJS alloc] init];
        _isSyncing = YES;
    }
    return self;
}

- (NSString *)getJSSource
{
    NSString *walletJSPath = [[NSBundle mainBundle] pathForResource:JAVASCRIPTCORE_RESOURCE_MY_WALLET ofType:JAVASCRIPTCORE_TYPE_JS];
    NSString *walletiOSPath = [[NSBundle mainBundle] pathForResource:JAVASCRIPTCORE_RESOURCE_WALLET_IOS ofType:JAVASCRIPTCORE_TYPE_JS];
    NSString *walletJSSource = [NSString stringWithContentsOfFile:walletJSPath encoding:NSUTF8StringEncoding error:nil];
    NSString *walletiOSSource = [NSString stringWithContentsOfFile:walletiOSPath encoding:NSUTF8StringEncoding error:nil];

    NSString *jsSource = [NSString stringWithFormat:@"%@\n%@\n%@", JAVASCRIPTCORE_PREFIX_JS_SOURCE, walletJSSource, walletiOSSource];

    return jsSource;
}

- (NSString *)getConsoleScript
{
    return @"var console = {};";
}

- (id)getExceptionHandler
{
    return ^(JSContext *context, JSValue *exception) {
        NSString *stacktrace = [[exception objectForKeyedSubscript:JAVASCRIPTCORE_STACK] toString];
        // type of Number
        NSString *lineNumber = [[exception objectForKeyedSubscript:JAVASCRIPTCORE_LINE] toString];

        DLog(@"%@ \nstack: %@\nline number: %@", [exception toString], stacktrace, lineNumber);
    };
}

- (NSSet *)getConsoleFunctionNames
{
    return [[NSSet alloc] initWithObjects:@"log", @"debug", @"info", @"warn", @"error", @"assert", @"dir", @"dirxml", @"group", @"groupEnd", @"time", @"timeEnd", @"count", @"trace", @"profile", @"profileEnd", nil];
}

- (NSMutableDictionary *)timers
{
    if (!_timers) {
        _timers = [NSMutableDictionary new];
    }

    return _timers;
}

- (id)getSetTimeout
{
    __weak Wallet *weakSelf = self;

    return ^(JSValue* callback, double timeout) {

        NSString *uuid = [[NSUUID alloc] init].UUIDString;

        NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:timeout/1000
                                                          target:[NSBlockOperation blockOperationWithBlock:^{
            dispatch_async(dispatch_get_main_queue(), ^{
                if ([weakSelf.timers objectForKey:uuid]) {
                    [callback callWithArguments:nil];
                }
            });
        }]
                                                        selector:@selector(main)
                                                        userInfo:nil
                                                         repeats:NO];

        weakSelf.timers[uuid] = timer;
        [timer fire];

        return uuid;
    };
}

- (id)getClearTimeout
{
    __weak Wallet *weakSelf = self;

    return ^(NSString *identifier) {
        NSTimer *timer = (NSTimer *)[weakSelf.timers objectForKey:identifier];
        [timer invalidate];
        [weakSelf.timers removeObjectForKey:identifier];
    };
}

- (id)getSetInterval
{
    __weak Wallet *weakSelf = self;

    return ^(JSValue *callback, double timeout) {

        NSString *uuid = [[NSUUID alloc] init].UUIDString;

        NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:timeout/1000
                                                          target:[NSBlockOperation blockOperationWithBlock:^{
            dispatch_async(dispatch_get_main_queue(), ^{
                if ([weakSelf.timers objectForKey:uuid]) {
                    [callback callWithArguments:nil];
                }
            });
        }]
                                                        selector:@selector(main)
                                                        userInfo:nil
                                                         repeats:YES];
        weakSelf.timers[uuid] = timer;
        [timer fire];

        return uuid;
    };
}

- (id)getClearInterval
{
    __weak Wallet *weakSelf = self;

    return ^(NSString *identifier) {
        NSTimer *timer = (NSTimer *)[weakSelf.timers objectForKey:identifier];
        [timer invalidate];
        [weakSelf.timers removeObjectForKey:identifier];
    };
}

- (JSContext *)loadContextIfNeeded {
    [self loadJSIfNeeded];
    return self.context;
}

- (void)loadJSIfNeeded {
    if (self.context) {
        return;
    }
    [self loadJS];
}

- (void)loadJS {
    self.context = [[JSContext alloc] init];

    [self.context evaluateScriptCheckIsOnMainQueue:[self getConsoleScript]];

    NSSet *names = [self getConsoleFunctionNames];

    for (NSString *name in names) {
        self.context[@"console"][name] = ^(NSString *message) {
            DLog(@"Javascript %@: %@", name, message);
        };
    }

    __weak Wallet *weakSelf = self;

    self.context.exceptionHandler = [self getExceptionHandler];

    self.context[JAVASCRIPTCORE_SET_TIMEOUT] = [self getSetTimeout];
    self.context[JAVASCRIPTCORE_CLEAR_TIMEOUT] = [self getClearTimeout];
    self.context[JAVASCRIPTCORE_SET_INTERVAL] = [self getSetInterval];
    self.context[JAVASCRIPTCORE_CLEAR_INTERVAL] = [self getClearInterval];

#pragma mark Decryption

    self.context[@"objc_message_sign"] = ^(JSValue *privateKey, NSString *message, BOOL compressed) {
        NSData *data = [[NSData alloc] initWithBase64EncodedString:[privateKey toString] options:kNilOptions];
        BTCKey *btcKey = [[BTCKey alloc] initWithPrivateKey:data];
        [btcKey setPublicKeyCompressed:compressed];
        return [[btcKey signatureForMessage:message] hexadecimalString];
    };

    self.context[@"objc_message_verify"] = ^(NSString *address, NSString *signature, NSString *message) {
        NSData *signatureData = BTCDataFromHex(signature);
        NSData *messageData = [message dataUsingEncoding:NSUTF8StringEncoding];
        BTCKey *key = [BTCKey verifySignature:signatureData forBinaryMessage:messageData];
        return [key.address.string isEqualToString:address];
    };
    
    self.context[@"objc_pbkdf2_sync"] = ^(NSString *mnemonicBuffer, NSString *saltBuffer, int iterations, int keylength) {
        return [JSCrypto derivePBKDF2SHA512HexStringWithPassword:mnemonicBuffer
                                                            salt:saltBuffer
                                                      iterations:iterations
                                                    keySizeBytes:keylength];
    };

    self.context[@"objc_sjcl_misc_pbkdf2"] = ^(NSString *_password, id _salt, int iterations, int keylength) {
        uint8_t * _saltBuff = NULL;
        size_t _saltBuffLen = 0;

        if ([_salt isKindOfClass:[NSArray class]]) {
            _saltBuff = alloca([_salt count]);
            _saltBuffLen = [_salt count];

            {
                int ii = 0;
                for (NSNumber * number in _salt) {
                    _saltBuff[ii] = [number unsignedCharValue];
                    ++ii;
                }
            }
        } else if ([_salt isKindOfClass:[NSString class]]) {
            _saltBuff = (uint8_t*)[_salt UTF8String];
            _saltBuffLen = [_salt length];
        } else {
            DLog(@"Scrypt salt unsupported type");
            return [[NSData new] hexadecimalString];
        }
        
        NSData * _Nonnull saltData = [NSData dataWithBytes:_saltBuff length:_saltBuffLen];
        return [JSCrypto derivePBKDF2SHA1HexStringWithPassword:_password
                                                      saltData:saltData
                                                    iterations:iterations
                                                  keySizeBytes:keylength];
    };

    self.context[@"objc_on_error_creating_new_account"] = ^(NSString *error) {
        [weakSelf on_error_creating_new_account:error];
    };

    self.context[@"objc_loading_start_download_wallet"] = ^(){
        [weakSelf loading_start_download_wallet];
    };

    self.context[@"objc_loading_stop"] = ^(){
        [weakSelf loading_stop];
    };

    self.context[@"objc_did_load_wallet"] = ^(){
        [weakSelf did_load_wallet];
    };

    self.context[@"objc_did_decrypt"] = ^(){
        [weakSelf did_decrypt];
    };

    self.context[@"objc_error_other_decrypting_wallet"] = ^(NSString *error, NSString *stack) {
        [weakSelf error_other_decrypting_wallet:[NSString stringWithFormat:@"TypeError:%@", [LocalizationConstantsObjcBridge errorDecryptingWallet]] stack:stack];
    };

    self.context[@"objc_loading_start_decrypt_wallet"] = ^(){
        [weakSelf loading_start_decrypt_wallet];
    };

    self.context[@"objc_loading_start_build_wallet"] = ^(){
        [weakSelf loading_start_build_wallet];
    };

    self.context[@"objc_loading_start_multiaddr"] = ^(){
        [weakSelf loading_start_multiaddr];
    };

#pragma mark Multiaddress

    self.context[@"objc_did_multiaddr"] = ^(){
        [weakSelf did_multiaddr];
    };

    self.context[@"objc_loading_start_get_history"] = ^(){
        [weakSelf loading_start_get_history];
    };

    self.context[@"objc_on_get_history_success"] = ^(){
        [weakSelf on_get_history_success];
    };

    self.context[@"objc_on_error_get_history"] = ^(NSString *error) {
        [weakSelf on_error_get_history:error];
    };

#pragma mark Wallet Creation/Pairing

    self.context[@"objc_on_create_new_account_sharedKey_password"] = ^(NSString *_guid, NSString *_sharedKey, NSString *_password) {
        [weakSelf on_create_new_account:_guid sharedKey:_sharedKey password:_password];
    };

    self.context[@"objc_error_restoring_wallet"] = ^(){
        [weakSelf error_restoring_wallet];
    };

    self.context[@"objc_get_second_password"] = ^(JSValue *secondPassword, JSValue *dismiss, JSValue *helperText) {
        [weakSelf getSecondPasswordSuccess:secondPassword dismiss:dismiss error:nil helperText:[helperText isUndefined] ? nil :  [helperText toString]];
    };

    self.context[@"objc_get_private_key_password"] = ^(JSValue *privateKeyPassword) {
        [weakSelf getPrivateKeyPasswordSuccess:privateKeyPassword error:nil];
    };

#pragma mark Accounts/Addresses

    self.context[@"objc_getRandomValues"] = ^(JSValue *intArray) {
        DLog(@"objc_getRandomValues");

        NSFileHandle *fileHandle = [NSFileHandle fileHandleForReadingAtPath:@"/dev/urandom"];

        if (!fileHandle) {
            @throw [NSException exceptionWithName:@"GetRandomValues Exception"
                                           reason:@"fileHandleForReadingAtPath:/dev/urandom returned nil" userInfo:nil];
        }

        NSUInteger length = [[intArray toArray] count];
        NSData *data = [fileHandle readDataOfLength:length];

        if ([data length] != length) {
            @throw [NSException exceptionWithName:@"GetRandomValues Exception"
                                           reason:@"Data length is not equal to intArray length" userInfo:nil];
        }

        return [data hexadecimalString];
    };

    self.context[@"objc_crypto_scrypt_salt_n_r_p_dkLen"] = ^(id _password, id salt, NSNumber *N, NSNumber *r, NSNumber *p, NSNumber *derivedKeyLen, JSValue *success, JSValue *error) {
        [weakSelf crypto_scrypt:_password salt:salt n:N r:r p:p dkLen:derivedKeyLen success:success error:error];
    };

    self.context[@"objc_loading_start_create_new_address"] = ^() {
        [weakSelf loading_start_create_new_address];
    };

    self.context[@"objc_on_error_creating_new_address"] = ^(NSString *error) {
        [weakSelf on_error_creating_new_address:error];
    };

    self.context[@"objc_on_generate_key"] = ^() {
        [weakSelf on_generate_key];
    };

    self.context[@"objc_on_add_new_account"] = ^() {
        [weakSelf on_add_new_account];
    };

    self.context[@"objc_on_error_add_new_account"] = ^(NSString *error) {
        [weakSelf on_error_add_new_account:error];
    };

    self.context[@"objc_loading_start_new_account"] = ^() {
        [weakSelf loading_start_new_account];
    };

    self.context[@"objc_on_add_private_key_start"] = ^() {
        [weakSelf on_add_private_key_start];
    };

    self.context[@"objc_on_add_incorrect_private_key"] = ^(NSString *address) {
        [weakSelf on_add_incorrect_private_key:address];
    };

    self.context[@"objc_on_add_private_key_to_legacy_address"] = ^(NSString *address) {
        [weakSelf on_add_private_key_to_legacy_address:address];
    };

    self.context[@"objc_on_add_key"] = ^(NSString *key) {
        [weakSelf on_add_key:key];
    };

    self.context[@"objc_on_error_adding_private_key"] = ^(NSString *error) {
        [weakSelf on_error_adding_private_key:error];
    };

    self.context[@"objc_on_add_incorrect_private_key"] = ^(NSString *key) {
        [weakSelf on_add_incorrect_private_key:key];
    };

    self.context[@"objc_on_error_adding_private_key_watch_only"] = ^(NSString *key) {
        [weakSelf on_error_adding_private_key_watch_only:key];
    };

    self.context[@"objc_did_archive_or_unarchive"] = ^() {
        [weakSelf did_archive_or_unarchive];
    };

    self.context[@"objc_did_get_btc_swipe_addresses"] = ^(NSArray *swipeAddresses) {
        [weakSelf did_get_swipe_addresses:swipeAddresses asset_type:LegacyAssetTypeBitcoin];
    };

#pragma mark State

    self.context[@"objc_reload"] = ^() {
        [weakSelf reload];
    };

    self.context[@"objc_on_backup_wallet_start"] = ^() {
        [weakSelf on_backup_wallet_start];
    };

    self.context[@"objc_on_backup_wallet_success"] = ^() {
        [weakSelf on_backup_wallet_success];
    };

    self.context[@"objc_on_backup_wallet_error"] = ^() {
        [weakSelf on_backup_wallet_error];
    };

    self.context[@"objc_ws_on_open"] = ^() {
        [weakSelf ws_on_open];
    };

    self.context[@"objc_on_tx_received"] = ^() {
        [weakSelf on_tx_received];
    };

    self.context[@"objc_makeNotice_id_message"] = ^(NSString *type, NSString *_id, NSString *message) {
        [weakSelf makeNotice:type id:_id message:message];
    };

#pragma mark Recovery

    self.context[@"objc_loading_start_generate_uuids"] = ^() {
        [weakSelf loading_start_generate_uuids];
    };

    self.context[@"objc_loading_start_recover_wallet"] = ^() {
        [weakSelf loading_start_recover_wallet];
    };

    self.context[@"objc_on_success_recover_with_passphrase"] = ^(NSDictionary *recoveredWalletDictionary) {
        [weakSelf on_success_recover_with_passphrase:recoveredWalletDictionary];
    };

    self.context[@"objc_on_error_recover_with_passphrase"] = ^(NSString *error) {
        [weakSelf on_error_recover_with_passphrase:error];
    };

    self.context[@"objc_on_progress_recover_with_passphrase_finalBalance"] = ^(NSString *totalReceived, NSString *finalBalance) {
        [weakSelf on_progress_recover_with_passphrase:totalReceived finalBalance:finalBalance];
    };

#pragma mark Settings
    
    self.context[@"objc_on_get_account_info_and_exchange_rates"] = ^() {
        [weakSelf on_get_account_info_and_exchange_rates];
    };
    
    self.context[@"objc_on_get_account_info_success"] = ^(NSString *accountInfo) {
        [weakSelf on_get_account_info_success:accountInfo];
    };

    self.context[@"objc_on_get_btc_exchange_rates_success"] = ^(NSString *currencies) {
        [weakSelf on_get_btc_exchange_rates_success:currencies];
    };

    self.context[@"objc_on_change_local_currency_success"] = ^() {
        [weakSelf on_change_local_currency_success];
    };

#pragma mark Ethereum

    self.context[@"objc_eth_socket_send"] = ^(JSValue *message) {
        [weakSelf eth_socket_send:[message toString]];
    };

    [self.ethereum setupWith:self.context];

#pragma mark Bitcoin
    
    [self.bitcoin setupWith:self.context];

#pragma mark Wallet Crypto
    
    [self.crypto setupWith:self.context];
    
#pragma mark Bitcoin Cash

    self.context[@"objc_on_fetch_bch_history_success"] = ^() {
        [weakSelf did_fetch_bch_history];
    };

    self.context[@"objc_on_fetch_bch_history_error"] = ^(JSValue *error) {
        [FIRAnalytics logEventWithName:@"bch_history_error" parameters:@{@"error": [error toString]}];
        [AlertViewPresenter.shared standardNotifyWithTitle:BC_STRING_ERROR message:[LocalizationConstantsObjcBridge balancesErrorGeneric] in:nil handler: nil];
    };
    
    self.context[@"objc_did_get_bitcoin_cash_exchange_rates"] = ^(JSValue *result) {
        [weakSelf did_get_bitcoin_cash_exchange_rates:[result toDictionary]];
    };

    self.context[@"objc_did_get_bch_swipe_addresses"] = ^(NSArray *swipeAddresses) {
        [weakSelf did_get_swipe_addresses:swipeAddresses asset_type:LegacyAssetTypeBitcoinCash];
    };

#pragma mark Other

    [self.context evaluateScriptCheckIsOnMainQueue:[self getJSSource]];

    self.context[@"XMLHttpRequest"] = [ModuleXMLHttpRequest class];

    [self useDebugSettingsIfSet];

    if ([delegate respondsToSelector:@selector(walletJSReady)]) {
        [delegate walletJSReady];
    } else {
        DLog(@"Error: delegate of class %@ does not respond to selector walletJSReady!", [delegate class]);
    }

    if ([delegate respondsToSelector:@selector(walletDidLoad)]) {
        [delegate walletDidLoad];
    } else {
        DLog(@"Error: delegate of class %@ does not respond to selector walletDidLoad!", [delegate class]);
    }

}

- (NSMutableArray *)pendingEthSocketMessages
{
    if (!_pendingEthSocketMessages) _pendingEthSocketMessages = [NSMutableArray new];
    return _pendingEthSocketMessages;
}

- (void)setupEthSocket
{
    _ethSocket = [[SRWebSocket alloc] initWithURLRequest:[self getWebSocketRequest:LegacyAssetTypeEther]];
    _ethSocket.delegate = self;
}

- (void)setupSocket:(LegacyAssetType)assetType
{
    if (assetType == LegacyAssetTypeBitcoin) {
        self.btcSocket = [[SRWebSocket alloc] initWithURLRequest:[self getWebSocketRequest:LegacyAssetTypeBitcoin]];
        self.btcSocket.delegate = self;

        [self.btcSocketTimer invalidate];
        self.btcSocketTimer = nil;
        self.btcSocketTimer = [NSTimer scheduledTimerWithTimeInterval:15.0
                                                               target:self
                                                             selector:@selector(pingBtcSocket)
                                                             userInfo:nil
                                                              repeats:YES];

        [self.btcSocket open];
    } else {
        self.bchSocket = [[SRWebSocket alloc] initWithURLRequest:[self getWebSocketRequest:LegacyAssetTypeBitcoinCash]];
        self.bchSocket.delegate = self;

        [self.bchSocketTimer invalidate];
        self.bchSocketTimer = nil;
        self.bchSocketTimer = [NSTimer scheduledTimerWithTimeInterval:15.0
                                                               target:self
                                                             selector:@selector(pingBchSocket)
                                                             userInfo:nil
                                                              repeats:YES];

        [self.bchSocket open];
    }
}

- (NSURLRequest *)getWebSocketRequest:(LegacyAssetType)assetType
{
    NSString *websocketURL;

    if (assetType == LegacyAssetTypeBitcoin) {
        websocketURL = [BlockchainAPI.shared webSocketUri];
    } else if (assetType == LegacyAssetTypeEther) {
        websocketURL = [BlockchainAPI.shared ethereumWebSocketUri];
    } else if (assetType == LegacyAssetTypeBitcoinCash) {
        websocketURL = [BlockchainAPI.shared bitcoinCashWebSocketUri];
    } else {
        return nil;
    }

    NSMutableURLRequest *webSocketRequest = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:websocketURL]];
    [webSocketRequest addValue:[BlockchainAPI.shared walletUrl] forHTTPHeaderField:@"Origin"];

    if (BlockchainAPI.shared.shouldPinCertificate) {
        // TODO: migrate to CertificatePinner class
        // Note: All `DEV` and `STAGING` builds should disable certificate pinning
        // so as QA can see network requests.
        NSData *certificateData = NetworkDependenciesObjc.certificatePinner.certificateData;
        SecCertificateRef certRef = SecCertificateCreateWithData(kCFAllocatorDefault, (__bridge CFDataRef)certificateData);
        id certificate = (__bridge id)certRef;
        [webSocketRequest setSR_SSLPinnedCertificates:@[certificate]];
        [webSocketRequest setSR_comparesPublicKeys:YES];
        CFRelease(certRef);
    }
    return webSocketRequest;
}

- (void)pingBtcSocket
{
    if (self.btcSocket.readyState == 1) {
        NSError *error;
        [self.btcSocket sendPing:[@"{ op: \"ping\" }" dataUsingEncoding:NSUTF8StringEncoding] error:&error];
        if (error) DLog(@"Error sending ping: %@", [error localizedDescription]);
    } else {
        DLog(@"reconnecting websocket");
        [self setupSocket:LegacyAssetTypeBitcoin];
    }
}

- (void)pingBchSocket
{
    if (self.bchSocket.readyState == 1) {
        NSError *error;
        [self.bchSocket sendPing:[@"{ op: \"ping\" }" dataUsingEncoding:NSUTF8StringEncoding] error:&error];
        if (error) DLog(@"Error sending ping: %@", [error localizedDescription]);
    } else {
        DLog(@"reconnecting websocket");
        [self setupSocket:LegacyAssetTypeBitcoinCash];
    }
}

- (void)subscribeToXPub:(NSString *)xPub assetType:(LegacyAssetType)assetType
{
    SRWebSocket *socket = assetType == LegacyAssetTypeBitcoin ? self.btcSocket : self.bchSocket;

    if (socket && socket.readyState == 1) {
        NSError *error;
        [socket sendString:[NSString stringWithFormat:@"{\"op\":\"xpub_sub\",\"xpub\":\"%@\"}", xPub] error:&error];
        if (error) DLog(@"Error subscribing to xpub: %@", [error localizedDescription]);
    } else {
        [self setupSocket:assetType];
    }
}

- (void)subscribeToAddress:(NSString *)address assetType:(LegacyAssetType)assetType
{
    SRWebSocket *socket = assetType == LegacyAssetTypeBitcoin ? self.btcSocket : self.bchSocket;

    if (socket && socket.readyState == 1) {
        NSError *error;
        [socket sendString:[NSString stringWithFormat:@"{\"op\":\"addr_sub\",\"addr\":\"%@\"}", address] error:&error];
        if (error) DLog(@"Error subscribing to address: %@", [error localizedDescription]);
    } else {
        [self setupSocket:assetType];
    }
}

- (void)subscribeToSwipeAddress:(NSString *)address assetType:(LegacyAssetType)assetType
{
    if (assetType == LegacyAssetTypeBitcoin) {
        self.btcSwipeAddressToSubscribe = address;
    } else if (assetType == LegacyAssetTypeBitcoinCash) {
        self.bchSwipeAddressToSubscribe = address;
    }

    [self subscribeToAddress:address assetType:assetType];
}

/// Called after recovering wallet with mnemonic
- (void)loadWalletWithGuid:(NSString*)guid sharedKey:(NSString*)sharedKey password:(NSString*)password {
    [self loadJSIfNeeded];

    self.repository.legacyPassword = password;
    
    DLog(@"Fetch Wallet");
    
    NSString *escapedSharedKey = sharedKey == nil ? @"" : [sharedKey escapedForJS];
    NSString *escapedGuid = guid == nil ? @"" : [guid escapedForJS];
    NSString *escapedPassword = password == nil ? @"" : [password escapedForJS];
    
    NSString *sessionToken = self.repository.legacySessionToken;
    sessionToken = sessionToken == nil ? @"" : [sessionToken escapedForJS];

    NSString *script = [NSString stringWithFormat:@"MyWalletPhone.login(\"%@\", \"%@\", false, \"%@\", \"%@\")", escapedGuid, escapedSharedKey, escapedPassword, sessionToken];
    [self.context evaluateScriptCheckIsOnMainQueue:script];
}

- (void)fetchWalletWith:(nonnull NSString *)password {
    DLog(@"Fetching wallet");

    self.repository.legacyPassword = password;

    [self loadJSIfNeeded];

    NSString *escapedPassword = [password escapedForJS];
    [self.context evaluateScriptCheckIsOnMainQueue:[NSString stringWithFormat:@"MyWalletPhone.loginAfterPairing(\"%@\")", escapedPassword]];
}

- (void)resetSyncStatus
{
    // Some changes to the wallet requiring syncing afterwards need only specific updates to the UI; reloading the entire Receive screen, for example, is not necessary when setting the default account. Unfortunately information about the specific function that triggers backup is lost by the time multiaddress is called.

    self.isSettingDefaultAccount = NO;
}

# pragma mark - Socket Delegate

- (void)webSocketDidOpen:(SRWebSocket *)webSocket
{
    if (webSocket == self.ethSocket) {
        DLog(@"eth websocket opened");
        for (NSString *message in [self.pendingEthSocketMessages reverseObjectEnumerator]) {
            DLog(@"Sending queued eth socket message %@", message);
            [self sendEthSocketMessage:message];
        }
        [self.pendingEthSocketMessages removeAllObjects];
    } else if (webSocket == self.btcSocket) {
        DLog(@"btc websocket opened");
        NSString *message = self.btcSwipeAddressToSubscribe ? [NSString stringWithFormat:@"{\"op\":\"addr_sub\",\"addr\":\"%@\"}", [self.btcSwipeAddressToSubscribe escapedForJS]] : [[self.context evaluateScriptCheckIsOnMainQueue:@"MyWallet.getSocketOnOpenMessage()"] toString];

        NSError *error;
        [webSocket sendString:message error:&error];
        if (error) DLog(@"Error subscribing to address: %@", [error localizedDescription]);
    } else if (webSocket == self.bchSocket) {
        DLog(@"bch websocket opened");
        NSString *message = self.bchSwipeAddressToSubscribe ? [NSString stringWithFormat:@"{\"op\":\"addr_sub\",\"addr\":\"%@\"}", [self fromBitcoinCash:[self.bchSwipeAddressToSubscribe escapedForJS]]] : [[self.context evaluateScriptCheckIsOnMainQueue:@"MyWalletPhone.bch.getSocketOnOpenMessage()"] toString];
        NSError *error;
        [webSocket sendString:message error:&error];
        if (error) DLog(@"Error subscribing to address: %@", [error localizedDescription]);
    }
}

- (void)webSocket:(SRWebSocket *)webSocket didFailWithError:(NSError *)error
{
    DLog(@"%@ failed with error: %@", webSocket == self.ethSocket ? @"eth socket" : @"web socket", [error localizedDescription]);
    if ([error.localizedDescription isEqualToString:WEBSOCKET_ERROR_INVALID_SERVER_CERTIFICATE]) {
        // TODO: add failedToValidateCertificate function
        // [app failedToValidateCertificate:[error localizedDescription]];
    }
}

- (void)webSocket:(SRWebSocket *)webSocket didCloseWithCode:(NSInteger)code reason:(NSString *)reason wasClean:(BOOL)wasClean
{
    if (webSocket == self.ethSocket) {
        DLog(@"eth websocket closed: code %li, reason: %@", code, reason);
    } else if (webSocket == self.btcSocket || webSocket == self.bchSocket) {
        if (code == WEBSOCKET_CODE_BACKGROUNDED_APP || code == WEBSOCKET_CODE_LOGGED_OUT || code == WEBSOCKET_CODE_RECEIVED_TO_SWIPE_ADDRESS) {
            // Socket will reopen when app becomes active and after decryption
            return;
        }

        DLog(@"websocket closed: code %li, reason: %@", code, reason);
        if ([[UIApplication sharedApplication] applicationState] == UIApplicationStateActive) {
            if (self.btcSocket.readyState != 1) {
                DLog(@"reconnecting websocket");
                [self setupSocket:LegacyAssetTypeBitcoin];
            }
            if (self.bchSocket.readyState != 1) {
                DLog(@"reconnecting websocket");
                [self setupSocket:LegacyAssetTypeBitcoinCash];
            }
        }
    }
}

- (void)webSocket:(SRWebSocket *)webSocket didReceiveMessageWithString:(NSString *)string
{
    if (webSocket == self.ethSocket) {
        DLog(@"received eth socket message string");
        [self.context evaluateScriptCheckIsOnMainQueue:[NSString stringWithFormat:@"MyWalletPhone.didReceiveEthSocketMessage(\"%@\")", [string escapedForJS]]];
    } else {
        DLog(@"received websocket message string");

        if (webSocket == self.btcSocket) {
            [self.context evaluateScriptCheckIsOnMainQueue:[NSString stringWithFormat:@"MyWallet.getSocketOnMessage(\"%@\", { checksum: null })", [string escapedForJS]]];
        } else if (webSocket == self.bchSocket) {
            [self.context evaluateScriptCheckIsOnMainQueue:@"MyWalletPhone.bch.didGetTxMessage()"];
        }

        NSDictionary *message = [string getJSONObject];
        NSDictionary *transaction = message[@"x"];

        if (webSocket == self.btcSocket && self.btcSwipeAddressToSubscribe) {
            NSString *hash = transaction[DICTIONARY_KEY_HASH];
            [self getAmountReceivedForTransactionHash:hash socket:webSocket];
        } else if (webSocket == self.bchSocket && self.bchSwipeAddressToSubscribe) {
            NSArray *outputs = transaction[DICTIONARY_KEY_OUT];
            NSString *address = [self fromBitcoinCash:self.bchSwipeAddressToSubscribe];
            uint64_t amountReceived = 0;
            for (NSDictionary *output in outputs) {
                if ([[output objectForKey:DICTIONARY_KEY_ADDRESS_OUTPUT] isEqualToString:address]) amountReceived = amountReceived + [[output objectForKey:DICTIONARY_KEY_VALUE] longLongValue];
            };

            if (amountReceived > 0) {
                if ([delegate respondsToSelector:@selector(paymentReceivedOnPINScreen:assetType:address:)]) {
                    if ([[UIApplication sharedApplication] applicationState] == UIApplicationStateActive) {
                        NSString *amountString = [NSNumberFormatter formatBCHAmount:amountReceived includeSymbol:YES inLocalCurrency:NO];
                        [delegate paymentReceivedOnPINScreen:amountString assetType:LegacyAssetTypeBitcoinCash address: self.bchSwipeAddressToSubscribe];
                    }
                } else {
                    DLog(@"Error: delegate of class %@ does not respond to selector paymentReceivedOnPINScreen:!", [delegate class]);
                }
            }

            self.bchSwipeAddressToSubscribe = nil;

            [webSocket closeWithCode:WEBSOCKET_CODE_RECEIVED_TO_SWIPE_ADDRESS reason:WEBSOCKET_CLOSE_REASON_RECEIVED_TO_SWIPE_ADDRESS];
        }
    }
}

- (void)getAmountReceivedForTransactionHash:(NSString *)txHash socket:(SRWebSocket *)webSocket
{
    NSURL *URL = [NSURL URLWithString:[[BlockchainAPI.shared walletUrl] stringByAppendingString:[NSString stringWithFormat:TRANSACTION_RESULT_URL_SUFFIX_HASH_ARGUMENT_ADDRESS_ARGUMENT, txHash, self.btcSwipeAddressToSubscribe]]];
    NSURLRequest *request = [NSURLRequest requestWithURL:URL];

    NSURLSessionDataTask *task = [NetworkDependenciesObjc.session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {

        if (error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                // TODO: add alert for error here
            });
            return;
        }

        uint64_t amountReceived = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] longLongValue];

        NSString *amountString = [NSNumberFormatter formatMoney:amountReceived localCurrency:NO];

        if (amountReceived > 0) {
            if ([self->delegate respondsToSelector:@selector(paymentReceivedOnPINScreen:assetType:address:)]) {
                if ([[UIApplication sharedApplication] applicationState] == UIApplicationStateActive) {
                    [self->delegate paymentReceivedOnPINScreen:amountString assetType:LegacyAssetTypeBitcoin address: self.btcSwipeAddressToSubscribe];
                }
            } else {
                DLog(@"Error: delegate of class %@ does not respond to selector paymentReceivedOnPINScreen:!", [self->delegate class]);
            }
        }
        
        self.btcSwipeAddressToSubscribe = nil;

        [webSocket closeWithCode:WEBSOCKET_CODE_RECEIVED_TO_SWIPE_ADDRESS reason:WEBSOCKET_CLOSE_REASON_RECEIVED_TO_SWIPE_ADDRESS];
    }];

    [task resume];
}

# pragma mark - Calls from Obj-C to JS

- (BOOL)isInitialized
{
    // Initialized when the webView is loaded and the wallet is initialized (decrypted and in-memory wallet built)
    BOOL isInitialized = [[self.context evaluateScriptCheckIsOnMainQueue:@"MyWallet.getIsInitialized()"] toBool];
    if (!isInitialized) {
        DLog(@"Warning: Wallet not initialized!");
    }
    
    return isInitialized;
}

- (float)getStrengthForPassword:(NSString *)passwordString
{
    return [[self.context evaluateScriptCheckIsOnMainQueue:[NSString stringWithFormat:@"MyWalletPhone.getPasswordStrength(\"%@\")", [passwordString escapedForJS]]] toDouble];
}

- (void)loadMetadata
{
    if ([self isInitialized]) {
        [self.context evaluateScriptCheckIsOnMainQueue:@"MyWalletPhone.loadMetadata()"];
    }
}

- (void)getHistory
{
    if ([self isInitialized]) {
        [self.context evaluateScriptCheckIsOnMainQueue:@"MyWalletPhone.get_history()"];
    }
}

- (void)getHistoryForAllAssets
{
    if ([self isInitialized]) {
        [self.context evaluateScriptCheckIsOnMainQueue:@"MyWalletPhone.getHistoryForAllAssets()"];
    }
}

- (int)getAllTransactionsCount
{
    if (![self isInitialized]) {
        return 0;
    }

    return [[[self.context evaluateScriptCheckIsOnMainQueue:@"MyWalletPhone.getAllTransactionsCount()"] toNumber] intValue];
}

- (void)changeLocalCurrency:(NSString *)currencyCode
{
    if (![self isInitialized]) {
        return;
    }

    [self.context evaluateScriptCheckIsOnMainQueue:[NSString stringWithFormat:@"MyWalletPhone.changeLocalCurrency(\"%@\")", [currencyCode escapedForJS]]];
}

- (void)getAccountInfoAndExchangeRates
{
    if (![self isInitialized]) {
        return;
    }
    [self.context evaluateScriptCheckIsOnMainQueue:@"MyWalletPhone.getAccountInfoAndExchangeRates()"];
}


- (void)newAccount:(NSString*)__password email:(NSString *)__email
{
    NSString *walletName = [LocalizationConstantsObjcBridge myBitcoinWallet];
    NSString *passwordEscaped = [__password escapedForJS];
    NSString *emailEscaped = [__email escapedForJS];
    NSString *scriptFormat = @"MyWalletPhone.newAccount(\"%@\", \"%@\", \"%@\")";
    NSString *script = [NSString stringWithFormat:scriptFormat, passwordEscaped, emailEscaped, walletName];
    [self.context evaluateScriptCheckIsOnMainQueue:script];
}

- (BOOL)needsSecondPassword
{
    if (![self isInitialized]) {
        return NO;
    }

    return [[self.context evaluateScriptCheckIsOnMainQueue:[NSString stringWithFormat:@"MyWallet.wallet.isDoubleEncrypted"]] toBool];
}

- (BOOL)validateSecondPassword:(NSString*)secondPassword
{
    if (![self isInitialized]) {
        return NO;
    }

    return [[self.context evaluateScriptCheckIsOnMainQueue:[NSString stringWithFormat:@"MyWallet.wallet.validateSecondPassword(\"%@\")", [secondPassword escapedForJS]]] toBool];
}

- (BOOL)isWatchOnlyLegacyAddress:(NSString*)address
{
    if (![self isInitialized]) {
        return NO;
    }

    if ([self checkIfWalletHasAddress:address]) {
        return [[self.context evaluateScriptCheckIsOnMainQueue:[NSString stringWithFormat:@"MyWallet.wallet.key(\"%@\").isWatchOnly", [address escapedForJS]]] toBool];
    } else {
        return NO;
    }
}

- (NSString*)labelForLegacyAddress:(NSString*)address assetType:(LegacyAssetType)assetType
{
    if (![self isInitialized]) {
        return nil;
    }

    if (assetType == LegacyAssetTypeBitcoin) {
        if ([[self allLegacyAddresses:assetType] containsObject:address]) {
            NSString *label = [self checkIfWalletHasAddress:address] ? [[self.context evaluateScriptCheckIsOnMainQueue:[NSString stringWithFormat:@"MyWalletPhone.labelForLegacyAddress(\"%@\")", [address escapedForJS]]] toString] : nil;
            if (label && ![label isEqualToString:@""])
                return label;
        }
        return address;
    } else if (assetType == LegacyAssetTypeBitcoinCash) {
        return address;
    }
    return nil;
}

- (BOOL)isAddressArchived:(NSString *)address
{
    if (![self isInitialized] || !address) {
        return FALSE;
    }

    return [[self.context evaluateScriptCheckIsOnMainQueue:[NSString stringWithFormat:@"MyWalletPhone.isArchived(\"%@\")", [address escapedForJS]]] toBool];
}

- (BOOL)isAccountArchived:(int)account assetType:(LegacyAssetType)assetType
{
    if (![self isInitialized]) {
        return NO;
    }

    if (assetType == LegacyAssetTypeBitcoin) {
        return [[self.context evaluateScriptCheckIsOnMainQueue:[NSString stringWithFormat:@"MyWalletPhone.isArchived(%d)", account]] toBool];
    } else if (assetType == LegacyAssetTypeBitcoinCash) {
        return [[self.context evaluateScriptCheckIsOnMainQueue:[NSString stringWithFormat:@"MyWalletPhone.bch.isArchived(%d)", account]] toBool];
    }
    return NO;
}

- (NSArray*)allLegacyAddresses:(LegacyAssetType)assetType
{
    if (![self isInitialized]) {
        return nil;
    }

    NSString *allAddressesJSON;
    if (assetType == LegacyAssetTypeBitcoin) {
        allAddressesJSON = [[self.context evaluateScriptCheckIsOnMainQueue:@"JSON.stringify(MyWallet.wallet.addresses)"] toString];
        return [allAddressesJSON getJSONObject];
    } else if (assetType == LegacyAssetTypeBitcoinCash) {
        allAddressesJSON = [[self.context evaluateScriptCheckIsOnMainQueue:@"JSON.stringify(MyWalletPhone.bch.getActiveLegacyAddresses())"] toString];
        return [allAddressesJSON getJSONObject];
    }
    return nil;
}

- (NSArray*)activeLegacyAddresses:(LegacyAssetType)assetType
{
    if (![self isInitialized]) {
        return nil;
    }

    NSString *activeAddressesJSON;
    if (assetType == LegacyAssetTypeBitcoin) {
        activeAddressesJSON = [[self.context evaluateScriptCheckIsOnMainQueue:@"JSON.stringify(MyWallet.wallet.activeAddresses)"] toString];
    } else if (assetType == LegacyAssetTypeBitcoinCash) {
        activeAddressesJSON = [[self.context evaluateScriptCheckIsOnMainQueue:@"JSON.stringify(MyWalletPhone.bch.getActiveLegacyAddresses())"] toString];
    }

    return [activeAddressesJSON getJSONObject];
}

- (void)setLabel:(NSString*)label forLegacyAddress:(NSString*)address
{
    if (![self isInitialized]) {
        return;
    }

    if (!Reachability.hasInternetConnection) {
        [AlertViewPresenter.shared internetConnection];
        return;
    }

    self.isSyncing = YES;

    [self.context evaluateScriptCheckIsOnMainQueue:[NSString stringWithFormat:@"MyWalletPhone.setLabelForAddress(\"%@\", \"%@\")", [address escapedForJS], [label escapedForJS]]];
}

- (void)toggleArchiveLegacyAddress:(NSString*)address
{
    if (![self isInitialized]) {
        return;
    }

    if (!Reachability.hasInternetConnection) {
        [AlertViewPresenter.shared internetConnection];
        return;
    }

    self.isSyncing = YES;

    [self.context evaluateScriptCheckIsOnMainQueue:[NSString stringWithFormat:@"MyWalletPhone.toggleArchived(\"%@\")", [address escapedForJS]]];
}

- (void)toggleArchiveAccount:(int)account assetType:(LegacyAssetType)assetType
{
    if (![self isInitialized]) {
        return;
    }

    if (!Reachability.hasInternetConnection) {
        [AlertViewPresenter.shared internetConnection];
        return;
    }

    self.isSyncing = YES;

    if (assetType == LegacyAssetTypeBitcoin) {
        [self.context evaluateScriptCheckIsOnMainQueue:[NSString stringWithFormat:@"MyWalletPhone.toggleArchived(%d)", account]];
    } else if (assetType == LegacyAssetTypeBitcoinCash) {
        [self.context evaluateScriptCheckIsOnMainQueue:[NSString stringWithFormat:@"MyWalletPhone.bch.toggleArchived(%d)", account]];
        [self reload];
    }
}

- (id)getLegacyAddressBalance:(NSString*)address assetType:(LegacyAssetType)assetType
{
    NSNumber *errorBalance = @0;
    if (![self isInitialized]) {
        return errorBalance;
    }

    if (assetType == LegacyAssetTypeBitcoin) {
        if ([self checkIfWalletHasAddress:address]) {
            return [[self.context evaluateScriptCheckIsOnMainQueue:[NSString stringWithFormat:@"MyWallet.wallet.key(\"%@\").balance", [address escapedForJS]]] toNumber];
        } else {
            DLog(@"Wallet error: Tried to get balance of address %@, which was not found in this wallet", address);
            return errorBalance;
        }
    } else if (assetType == LegacyAssetTypeBitcoinCash) {
        return [[self.context evaluateScriptCheckIsOnMainQueue:[NSString stringWithFormat:@"MyWalletPhone.bch.getBalanceForAddress(\"%@\")", [address escapedForJS]]] toNumber];
    }
    return 0;
}

- (BOOL)addKey:(NSString*)privateKeyString
{
    if (![self isInitialized]) {
        return NO;
    }

    return [[self.context evaluateScriptCheckIsOnMainQueue:[NSString stringWithFormat:@"MyWalletPhone.addKey(\"%@\")", [privateKeyString escapedForJS]]] toBool];
}

- (BOOL)addKey:(NSString*)privateKeyString toWatchOnlyAddress:(NSString *)watchOnlyAddress
{
    if (![self isInitialized]) {
        return NO;
    }

    return [[self.context evaluateScriptCheckIsOnMainQueue:[NSString stringWithFormat:@"MyWalletPhone.addKeyToLegacyAddress(\"%@\", \"%@\")", [privateKeyString escapedForJS], [watchOnlyAddress escapedForJS]]] toBool];
}

- (NSString*)detectPrivateKeyFormat:(NSString*)privateKeyString
{
    if (![self isInitialized]) {
        return nil;
    }

    return [[self.context evaluateScriptCheckIsOnMainQueue:[NSString stringWithFormat:@"MyWalletPhone.detectPrivateKeyFormat(\"%@\")", [privateKeyString escapedForJS]]] toString];
}

- (void)generateNewKey
{
    if (![self isInitialized]) {
        return;
    }

    [self.context evaluateScriptCheckIsOnMainQueue:@"MyWalletPhone.generateNewAddress()"];
}

- (BOOL)checkIfWalletHasAddress:(NSString *)address
{
    if (![self isInitialized]) {
        return NO;
    }

    return [[self.context evaluateScriptCheckIsOnMainQueue:[NSString stringWithFormat:@"MyWalletPhone.checkIfWalletHasAddress(\"%@\")", [address escapedForJS]] ] toBool];
}

- (void)recoverWithEmail:(nonnull NSString *)email password:(nonnull NSString *)recoveryPassword mnemonicPassphrase:(nonnull NSString *)mnemonicPassphrase
{
    [self useDebugSettingsIfSet];
    self.emptyAccountIndex = 0;
    self.recoveredAccountIndex = 0;
    [self.context evaluateScriptCheckIsOnMainQueue:[NSString stringWithFormat:@"MyWalletPhone.recoverWithPassphrase(\"%@\",\"%@\",\"%@\")", [email escapedForJS], [recoveryPassword escapedForJS], [mnemonicPassphrase escapedForJS]]];
}

- (void)recoverFromMetadataWithMnemonicPassphrase:(nonnull NSString *)mnemonicPassphrase
{
    [self useDebugSettingsIfSet];
    self.emptyAccountIndex = 0;
    self.recoveredAccountIndex = 0;
    [self.context evaluateScriptCheckIsOnMainQueue:[NSString stringWithFormat:@"MyWalletPhone.recoverWithMetadata(\"%@\")", [mnemonicPassphrase escapedForJS]]];
}

- (void)updateServerURL:(NSString *)newURL
{
    [self.context evaluateScriptCheckIsOnMainQueue:[NSString stringWithFormat:@"MyWalletPhone.updateServerURL(\"%@\")", [newURL escapedForJS]]];
}

- (void)updateWebSocketURL:(NSString *)newURL
{
    [self.context evaluateScriptCheckIsOnMainQueue:[NSString stringWithFormat:@"MyWalletPhone.updateWebsocketURL(\"%@\")", [newURL escapedForJS]]];
}

- (void)updateAPIURL:(NSString *)newURL
{
    [self.context evaluateScriptCheckIsOnMainQueue:[NSString stringWithFormat:@"MyWalletPhone.updateAPIURL(\"%@\")", [newURL escapedForJS]]];
}

- (NSString *)getXpubForAccount:(int)accountIndex assetType:(LegacyAssetType)assetType
{
    if (![self isInitialized]) {
        return nil;
    }

    if (assetType == LegacyAssetTypeBitcoin) {
        return [[self.context evaluateScriptCheckIsOnMainQueue:[NSString stringWithFormat:@"MyWalletPhone.getXpubForAccount(%d)", accountIndex]] toString];
    } else if (assetType == LegacyAssetTypeBitcoinCash) {
        return [[self.context evaluateScriptCheckIsOnMainQueue:[NSString stringWithFormat:@"MyWalletPhone.bch.getXpubForAccount(%d)", accountIndex]] toString];
    }
    return nil;
}

- (BOOL)isAccountNameValid:(NSString *)name
{
    if (![self isInitialized]) {
        return NO;
    }

    return [[self.context evaluateScriptCheckIsOnMainQueue:[NSString stringWithFormat:@"MyWalletPhone.isAccountNameValid(\"%@\")", [name escapedForJS]]] toBool];
}

- (int)getIndexOfActiveAccount:(int)account assetType:(LegacyAssetType)assetType
{
    if (![self isInitialized]) {
        return 0;
    }

    if (assetType == LegacyAssetTypeBitcoin) {
        return [[[self.context evaluateScriptCheckIsOnMainQueue:[NSString stringWithFormat:@"MyWalletPhone.getIndexOfActiveAccount(%d)", account]] toNumber] intValue];
    } else if (assetType == LegacyAssetTypeBitcoinCash) {
        return [[[self.context evaluateScriptCheckIsOnMainQueue:[NSString stringWithFormat:@"MyWalletPhone.bch.getIndexOfActiveAccount(%d)", account]] toNumber] intValue];
    }
    return 0;
}

- (void)getSwipeAddresses:(NSInteger)numberOfAddresses assetType:(LegacyAssetType)assetType
{

    NSString *script;
    if (assetType == LegacyAssetTypeBitcoin) {
        script = [NSString stringWithFormat:@"MyWalletPhone.getBtcSwipeAddresses(%ld)", (long)numberOfAddresses];
    } else if (assetType == LegacyAssetTypeBitcoinCash) {
        script = [NSString stringWithFormat:@"MyWalletPhone.bch.getSwipeAddresses(%ld)", (long)numberOfAddresses];
    } else {
        return;
    }
    [self.context evaluateScriptCheckIsOnMainQueue:script];
}

- (int)getDefaultAccountLabelledAddressesCount
{
    return [[[self.context evaluateScriptCheckIsOnMainQueue:@"MyWalletPhone.getDefaultAccountLabelledAddressesCount()"] toNumber] intValue];
}

- (BOOL)isLockboxEnabled
{
    if ([self.accountInfo objectForKey:kAccountInvitations]) {
        NSDictionary *invitations = [self.accountInfo objectForKey:kAccountInvitations];
        BOOL enabled = [[invitations objectForKey:kLockboxInvitation] boolValue];
        return enabled;
    } else {
        return NO;
    }
}

- (NSString *)getMobileMessage
{
    if ([self isInitialized]) {
        JSValue *message = [self.context evaluateScriptCheckIsOnMainQueue:[NSString stringWithFormat:@"MyWalletPhone.getMobileMessage(\"%@\")", [[NSLocale currentLocale] objectForKey:NSLocaleLanguageCode]]];
        if ([message isUndefined] || [message isNull]) return nil;
        return [message toString];
    }

    return nil;
}

# pragma mark - Lockbox

- (NSArray *_Nonnull)getLockboxDevices
{
    if (!self.isInitialized) {
        return [[NSArray alloc] init];
    }
    JSValue *devicesJsValue = [self.context evaluateScriptCheckIsOnMainQueue:@"MyWalletPhone.lockbox.devices()"];
    return [devicesJsValue toArray];
}

#pragma mark - XLM

- (NSArray *_Nullable)getXlmAccounts
{
    if (!self.isInitialized) {
        return [[NSArray alloc] init];
    }
    JSValue *xlmAccountsValue = [self.context evaluateScriptCheckIsOnMainQueue:@"MyWalletPhone.xlm.accounts()"];
    return [xlmAccountsValue toArray];
}

- (void)saveXlmAccount:(NSString *_Nonnull)publicKey label:(NSString *_Nullable)label success:(void (^ _Nonnull)(void))success error:(void (^)(NSString *_Nonnull))error
{
    if (!self.isInitialized) {
        DLog(@"Cannot save XLM account. Wallet is not yet initialized.");
        return;

    }
    [self.context invokeOnceWithFunctionBlock:success forJsFunctionName:@"objc_xlmSaveAccount_success"];
    [self.context invokeOnceWithStringFunctionBlock:error forJsFunctionName:@"objc_xlmSaveAccount_error"];
    [self.context evaluateScriptCheckIsOnMainQueue:[NSString stringWithFormat:@"MyWalletPhone.xlm.saveAccount(\"%@\", \"%@\")", [publicKey escapedForJS], [label escapedForJS]]];
}

# pragma mark - Ethereum

- (nullable NSString *)getEtherAddress
{
    if ([self isInitialized]) {
        NSString *setupHelperText = [LocalizationConstantsObjcBridge etherSecondPasswordPrompt];
        JSValue *result = [self.context evaluateScriptCheckIsOnMainQueue:[NSString stringWithFormat:@"MyWalletPhone.getEtherAddress(\"%@\")", [setupHelperText escapedForJS]]];
        if ([result isUndefined]) return nil;
        NSString *etherAddress = [result toString];
        return etherAddress;
    }

    return nil;
}

- (BOOL)hasEthAccount
{
    if ([self isInitialized]) {
        return [[self.context evaluateScriptCheckIsOnMainQueue:@"MyWalletPhone.hasEthAccount()"] toBool];
    }

    return NO;
}

# pragma mark - Bitcoin cash

- (NSString *)fromBitcoinCash:(NSString *)address
{
    return [[self.context evaluateScriptCheckIsOnMainQueue:[NSString stringWithFormat:@"MyWalletPhone.bch.fromBitcoinCash(\"%@\")", [address escapedForJS]]] toString];
}

- (void)getBitcoinCashHistoryAndRates
{
    if ([self isInitialized]) {
        [self.context evaluateScriptCheckIsOnMainQueue:@"MyWalletPhone.bch.getHistoryAndRates()"];
    }
}

- (void)fetchBitcoinCashExchangeRates
{
    if ([self isInitialized]) {
        [self.context evaluateScriptCheckIsOnMainQueue:@"MyWalletPhone.bch.fetchExchangeRates()"];
    }
}

- (NSString *)bitcoinCashExchangeRate
{
    if ([self isInitialized]) {
        if (self.bitcoinCashExchangeRates) {
            NSString *currency = self.accountInfo[DICTIONARY_KEY_CURRENCY];
            double lastPrice = [self.bitcoinCashExchangeRates[currency][DICTIONARY_KEY_LAST] doubleValue];
            return [NSString stringWithFormat:@"%.2f", lastPrice];
        }
    }

    return nil;
}

- (BOOL)hasBchAccount
{
    if ([self isInitialized]) {
        return [[self.context evaluateScriptCheckIsOnMainQueue:@"MyWalletPhone.bch.hasAccount()"] toBool];
    }
    return NO;
}

- (uint64_t)getBchBalance
{
    if ([self isInitialized] && [self hasBchAccount]) {
        return [[[self.context evaluateScriptCheckIsOnMainQueue:@"MyWalletPhone.bch.getBalance()"] toNumber] longLongValue];
    }
    DLog(@"Warning: getting bch balance when not initialized - returning 0");
    return 0;
}

#pragma mark - Callbacks from JS to Obj-C dealing with loading texts

- (void)loading_start_download_wallet
{
    [LoadingViewPresenter.shared showCircularWith:LocalizationConstantsObjcBridge.loadingWallet];
}

- (void)loading_start_decrypt_wallet
{
    [LoadingViewPresenter.shared showCircularWith:LocalizationConstantsObjcBridge.loadingWallet];
}

- (void)loading_start_build_wallet
{
    [LoadingViewPresenter.shared showCircularWith:LocalizationConstantsObjcBridge.loadingWallet];
}

- (void)loading_start_multiaddr
{
    [LoadingViewPresenter.shared showCircularWith:LocalizationConstantsObjcBridge.loadingWallet];
}

- (void)loading_start_get_history
{
    [LoadingViewPresenter.shared showWith:BC_STRING_LOADING_LOADING_TRANSACTIONS];
}

- (void)loading_start_create_account
{
    [LoadingViewPresenter.shared showWith:BC_STRING_LOADING_CREATING];
}

- (void)loading_start_new_account
{
    [LoadingViewPresenter.shared showCircularWith:LocalizationConstantsObjcBridge.loadingWallet];
}

- (void)loading_start_create_new_address
{
    [LoadingViewPresenter.shared showWith:BC_STRING_LOADING_CREATING_NEW_ADDRESS];
}

- (void)loading_start_generate_uuids
{
    [LoadingViewPresenter.shared showCircularWith:LocalizationConstantsObjcBridge.loadingWallet];
}

- (void)loading_start_recover_wallet
{
    [LoadingViewPresenter.shared showWith:BC_STRING_LOADING_RECOVERING_WALLET];
}

- (void)loading_stop
{
    DLog(@"Stop loading");
    [LoadingViewPresenter.shared hide];
}

#pragma mark - Callbacks from JS to Obj-C

- (void)log:(NSString*)message
{
    DLog(@"console.log: %@", [message description]);
}

- (void)ws_on_open
{
    DLog(@"ws_on_open");
}

- (void)ws_on_close
{
    DLog(@"ws_on_close");
}

- (void)did_multiaddr
{
    if (![self isInitialized]) {
        return;
    }

    DLog(@"did_multiaddr");

    if (!self.isSyncing) {
        [self loading_stop];
    }

    if ([delegate respondsToSelector:@selector(didGetMultiAddressResponse:)]) {
        [delegate didGetMultiAddressResponse:[MultiAddressResponse new]];
    } else {
        DLog(@"Error: delegate of class %@ does not respond to selector didGetMultiAddressResponse:!", [delegate class]);
    }
}

- (void)on_tx_received
{
    DLog(@"on_tx_received");

    if ([delegate respondsToSelector:@selector(receivedTransactionMessage)]) {
        [delegate receivedTransactionMessage];
    } else {
        DLog(@"Error: delegate of class %@ does not respond to selector receivedTransactionMessage!", [delegate class]);
    }
}

- (void)getPrivateKeyPasswordSuccess:(JSValue *)success error:(void(^)(id))_error
{
    if ([delegate respondsToSelector:@selector(getPrivateKeyPasswordWithSuccess:)]) {
        [delegate getPrivateKeyPasswordWithSuccess:success];
    } else {
        DLog(@"Error: delegate of class %@ does not respond to selector getPrivateKeyPassword!", [delegate class]);
    }
}

- (void)getSecondPasswordSuccess:(JSValue *)success dismiss:(JSValue *)dismiss error:(void(^)(id))_error helperText:(NSString *)helperText
{
    if ([delegate respondsToSelector:@selector(getSecondPasswordWithSuccess:dismiss:)]) {
        [delegate getSecondPasswordWithSuccess:success dismiss:dismiss];
    } else {
        DLog(@"Error: delegate of class %@ does not respond to selector getSecondPassword!", [delegate class]);
    }
}

- (void)makeNotice:(NSString*)type id:(NSString*)_id message:(NSString*)message
{
    // This is kind of ugly. When the wallet fails to load, usually because of a connection problem, wallet.js throws two errors in the setGUID function and we only want to show one. This filters out the one we don't want to show.
    if ([message isEqualToString:@"Error changing wallet identifier"]) {
        return;
    }

    // Don't display an error message for this notice, instead show a note in the sideMenu
    if ([message isEqualToString:@"For Improved security add an email address to your account."]) {
        return;
    }

    NSRange invalidEmailStringRange = [message rangeOfString:@"update-email-error" options:NSCaseInsensitiveSearch range:NSMakeRange(0, message.length) locale:[NSLocale currentLocale]];
    if (invalidEmailStringRange.location != NSNotFound) {
        [self performSelector:@selector(on_update_email_error) withObject:nil afterDelay:DELAY_KEYBOARD_DISMISSAL];
        return;
    }

    NSRange updateCurrencyErrorStringRange = [message rangeOfString:@"currency-error" options:NSCaseInsensitiveSearch range:NSMakeRange(0, message.length) locale:[NSLocale currentLocale]];
    if (updateCurrencyErrorStringRange.location != NSNotFound) {
        [self performSelector:@selector(on_change_currency_error) withObject:nil afterDelay:0.1f];
        return;
    }

    NSRange updateSMSErrorStringRange = [message rangeOfString:@"sms-error" options:NSCaseInsensitiveSearch range:NSMakeRange(0, message.length) locale:[NSLocale currentLocale]];
    if (updateSMSErrorStringRange.location != NSNotFound) {
        return;
    }

    NSRange incorrectPasswordErrorStringRange = [message rangeOfString:@"please check that your password is correct" options:NSCaseInsensitiveSearch range:NSMakeRange(0, message.length) locale:[NSLocale currentLocale]];
    if (incorrectPasswordErrorStringRange.location != NSNotFound && ![KeychainItemWrapper guid]) {
        // Error message shown in error_other_decrypting_wallet without guid
        return;
    }

    NSRange errorSavingWalletStringRange = [message rangeOfString:@"Error Saving Wallet" options:NSCaseInsensitiveSearch range:NSMakeRange(0, message.length) locale:[NSLocale currentLocale]];
    if (errorSavingWalletStringRange.location != NSNotFound) {
        [AlertViewPresenter.shared standardNotifyWithTitle:BC_STRING_ERROR message:BC_STRING_ERROR_SAVING_WALLET_CHECK_FOR_OTHER_DEVICES in:nil handler:nil];
        return;
    }

    if ([type isEqualToString:@"error"]) {
        [AlertViewPresenter.shared standardNotifyWithTitle:BC_STRING_ERROR message:message in:nil handler: nil];
    } else if ([type isEqualToString:@"info"]) {
        [AlertViewPresenter.shared standardNotifyWithTitle:BC_STRING_ERROR message:[LocalizationConstantsObjcBridge information] in:nil handler: nil];
    }
}

- (void)error_other_decrypting_wallet:(NSString *)message stack:(NSString *)stack
{
    DLog(@"error_other_decrypting_wallet");
    
    if (message == nil || message.length == 0) {
        return;
    }

    // This error message covers the case where the GUID is 36 characters long but is not valid. This can only be checked after JS has been loaded. To avoid multiple error messages, it finds a localized "identifier" substring in the error description. Currently, different manual pairing error messages are sent to both my-wallet.js and wallet-ios.js (in this case, also to the same error callback), so a cleaner approach that avoids a substring search would either require more distinguishable error callbacks (separated by scope) or thorough refactoring.
    
    NSRange identifierRange = [message rangeOfString:BC_STRING_IDENTIFIER options:NSCaseInsensitiveSearch range:NSMakeRange(0, message.length) locale:[NSLocale currentLocale]];
    NSRange connectivityErrorRange = [message rangeOfString:ERROR_FAILED_NETWORK_REQUEST options:NSCaseInsensitiveSearch range:NSMakeRange(0, message.length) locale:[NSLocale currentLocale]];
    if (identifierRange.location != NSNotFound) {
        [AlertViewPresenter.shared standardNotifyWithTitle:BC_STRING_ERROR message:message in:nil handler:nil];
        [self error_restoring_wallet];
        return;
    } else if (connectivityErrorRange.location != NSNotFound) {
        dispatch_time_t when = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(ANIMATION_DURATION_LONG * NSEC_PER_SEC));
        dispatch_after(when, dispatch_get_main_queue(), ^{
            [AlertViewPresenter.shared standardNotifyWithTitle:BC_STRING_ERROR message:[LocalizationConstantsObjcBridge requestFailedCheckConnection] in:nil handler:nil];
        });
        [self error_restoring_wallet];
        return;
    }
    
    if (![KeychainItemWrapper guid]) {
        // This error is used whe trying to login with incorrect passwords or when the account is locked, so present an alert if the app has no guid, since it currently conflicts with makeNotice when backgrounding after changing password in-app
        [AlertViewPresenter.shared standardNotifyWithTitle:BC_STRING_ERROR message:message in:nil handler:nil];
        return;
    }
    
    if ([message hasPrefix:@"TypeError:"]) {
        dispatch_time_t when = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(ANIMATION_DURATION_LONG * NSEC_PER_SEC));
        dispatch_after(when, dispatch_get_main_queue(), ^{
            NSString *value = [message substringFromIndex:[@"TypeError:" length]];
            [AlertViewPresenter.shared standardNotifyWithTitle:BC_STRING_ERROR message:value in:nil handler:nil];
        });
        [self logJavaScriptTypeError:message stack:stack];
    }
}

- (void)error_restoring_wallet
{
    DLog(@"error_restoring_wallet");
    if ([delegate respondsToSelector:@selector(walletFailedToDecrypt)]) {
        [delegate walletFailedToDecrypt];
    } else {
        DLog(@"Error: delegate of class %@ does not respond to selector walletFailedToDecrypt!", [delegate class]);
    }
}

- (void)did_decrypt
{
    DLog(@"did_decrypt");

    if (self.btcSocket) {
        [self.btcSocket closeWithCode:WEBSOCKET_CODE_DECRYPTED_WALLET reason:WEBSOCKET_CLOSE_REASON_DECRYPTED_WALLET];
    } else {
        [self setupSocket:LegacyAssetTypeBitcoin];
    }

    if (self.bchSocket) {
        [self.bchSocket closeWithCode:WEBSOCKET_CODE_DECRYPTED_WALLET reason:WEBSOCKET_CLOSE_REASON_DECRYPTED_WALLET];
    } else {
        [self setupSocket:LegacyAssetTypeBitcoinCash];
    }

    [self setupEthSocket];

    NSString *sharedKey = [[self.context evaluateScriptCheckIsOnMainQueue:@"MyWallet.wallet.sharedKey"] toString];
    NSString *guid = [[self.context evaluateScriptCheckIsOnMainQueue:@"MyWallet.wallet.guid"] toString];

    if ([delegate respondsToSelector:@selector(walletDidDecryptWithSharedKey:guid:)]) {
        [delegate walletDidDecryptWithSharedKey:sharedKey guid:guid];
    } else {
        DLog(@"Error: delegate of class %@ does not respond to selector walletDidDecrypt!", [delegate class]);
    }
}

- (void)did_load_wallet
{
    DLog(@"did_load_wallet");

    [self getHistoryForAllAssets];

    if (self.isNew) {
        NSString *currencyCode = [[NSLocale currentLocale] objectForKey:NSLocaleCurrencyCode];
        if ([[self.btcRates allKeys] containsObject:currencyCode]) {
            [self changeLocalCurrency:currencyCode];
        }
    }

    if ([delegate respondsToSelector:@selector(walletDidFinishLoad)]) {
        [delegate walletDidFinishLoad];
    } else {
        DLog(@"Error: delegate of class %@ does not respond to selector walletDidFinishLoad!", [delegate class]);
    }
}

- (void)on_create_new_account:(NSString*)_guid sharedKey:(NSString*)_sharedKey password:(NSString*)_password
{
    DLog(@"on_create_new_account:");

    if ([delegate respondsToSelector:@selector(didCreateNewAccount:sharedKey:password:)]) {
        [delegate didCreateNewAccount:_guid sharedKey:_sharedKey password:_password];
    } else {
        DLog(@"Error: delegate of class %@ does not respond to selector didCreateNewAccount:sharedKey:password:!", [delegate class]);
    }
}

/* Begin Key Importer */

- (void)on_add_key:(NSString*)address
{
    // TODO: call Swift `importKey` directly once available
    [[KeyImportCoordinator sharedInstance] on_add_keyWithAddress:address];
}

- (void)on_add_incorrect_private_key:(NSString *)address
{
    // TODO: remove bridging function call
    [[KeyImportCoordinator sharedInstance] on_add_incorrect_private_keyWithAddress:address];
}

- (void)on_add_private_key_start
{
    // TODO: remove bridging function call
    [[KeyImportCoordinator sharedInstance] on_add_private_key_start];
}

- (void)on_add_private_key_to_legacy_address:(NSString *)address
{
    // TODO: remove bridging function call
    [[KeyImportCoordinator sharedInstance] on_add_private_key_to_legacy_addressWithAddress:address];
}

- (void)on_error_adding_private_key:(NSString*)error
{
    // TODO: remove bridging function call
    [[KeyImportCoordinator sharedInstance] on_error_adding_private_keyWithError:error];
}

- (void)on_error_adding_private_key_watch_only:(NSString*)error
{
    // TODO: remove bridging function call
    [[KeyImportCoordinator sharedInstance] on_error_adding_private_key_watch_onlyWithError:error];
}

/* End Key Importer */

- (void)on_error_creating_new_account:(NSString*)message
{
    DLog(@"on_error_creating_new_account:");

    if ([delegate respondsToSelector:@selector(errorCreatingNewAccount:)]) {
        [delegate errorCreatingNewAccount:message];
    } else {
        DLog(@"Error: delegate of class %@ does not respond to selector errorCreatingNewAccount:!", [delegate class]);
    }
}

- (void)on_backup_wallet_start
{
    DLog(@"on_backup_wallet_start");
}

- (void)on_backup_wallet_error
{
    DLog(@"on_backup_wallet_error");

    if ([delegate respondsToSelector:@selector(didFailBackupWallet)]) {
        [delegate didFailBackupWallet];
    } else {
        DLog(@"Error: delegate of class %@ does not respond to selector didFailBackupWallet!", [delegate class]);
    }

    [self resetSyncStatus];
}

- (void)on_backup_wallet_success
{
    DLog(@"on_backup_wallet_success");
    if ([delegate respondsToSelector:@selector(didBackupWallet)]) {
        [delegate didBackupWallet];
    } else {
        DLog(@"Error: delegate of class %@ does not respond to selector didBackupWallet!", [delegate class]);
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:[ConstantsObjcBridge notificationKeyBackupSuccess] object:nil];

    self.isSyncing = NO;

    if (self.isSettingDefaultAccount) {
        if ([self.delegate respondsToSelector:@selector(didSetDefaultAccount)]) {
            [self.delegate didSetDefaultAccount];
        } else {
            DLog(@"Error: delegate of class %@ does not respond to selector didSetDefaultAccount!", [delegate class]);
        }
    }

    if (self.shouldLoadMetadata) {
        self.shouldLoadMetadata = NO;
        [self loadMetadata];
    }
}

- (void)did_fail_set_guid
{
    DLog(@"did_fail_set_guid");

    if ([delegate respondsToSelector:@selector(walletFailedToLoad)]) {
        [delegate walletFailedToLoad];
    } else {
        DLog(@"Error: delegate of class %@ does not respond to selector walletFailedToLoad!", [delegate class]);
    }
}

- (void)on_change_local_currency_success
{
    DLog(@"on_change_local_currency_success");
    [self getHistory];
}

- (void)on_change_currency_error
{
    DLog(@"on_change_local_currency_error");
    [AlertViewPresenter.shared standardNotifyWithTitle:BC_STRING_SETTINGS_ERROR_UPDATING_TITLE message:BC_STRING_SETTINGS_ERROR_LOADING_MESSAGE in:nil handler:nil];
}

- (void)on_get_account_info_success:(NSString *)accountInfo
{
    DLog(@"on_get_account_info_success");
    self.accountInfo = [accountInfo getJSONObject];
    self.hasLoadedAccountInfo = YES;
    [[NSNotificationCenter defaultCenter] postNotificationName:NOTIFICATION_KEY_GET_ACCOUNT_INFO_SUCCESS object:nil];

    if ([delegate respondsToSelector:@selector(walletDidGetAccountInfo:)]) {
        [self.delegate walletDidGetAccountInfo:self];
    }
}

- (void)on_get_btc_exchange_rates_success:(NSString *)currencies
{
    DLog(@"on_get_btc_exchange_rates_success");
    NSDictionary *allCurrencySymbolsDictionary = [currencies getJSONObject];
    NSMutableDictionary *currencySymbolsWithNames = [[NSMutableDictionary alloc] initWithDictionary:allCurrencySymbolsDictionary];
    NSDictionary *currencyNames = [CurrencySymbol currencyNames];

    for (NSString *abbreviatedFiatString in [allCurrencySymbolsDictionary allKeys]) {
        NSDictionary *values = allCurrencySymbolsDictionary[abbreviatedFiatString]; // should never be nil
        NSMutableDictionary *valuesWithName = [[NSMutableDictionary alloc] initWithDictionary:values]; // create a mutable dictionary of the current dictionary values
        NSString *currencyName = currencyNames[abbreviatedFiatString];
        if (currencyName) {
            valuesWithName[DICTIONARY_KEY_NAME] = currencyName;
            currencySymbolsWithNames[abbreviatedFiatString] = valuesWithName;
        } else {
            DLog(@"Warning: no name found for currency %@", abbreviatedFiatString);
        }
    }

    self.btcRates = currencySymbolsWithNames;

    if ([self.delegate respondsToSelector:@selector(walletDidGetBtcExchangeRates)]) {
        [self.delegate walletDidGetBtcExchangeRates];
    }
}

- (void)on_get_history_success
{
    DLog(@"on_get_history_success");
}

- (void)on_generate_key
{
    DLog(@"on_generate_key");
    if ([delegate respondsToSelector:@selector(didGenerateNewAddress)]) {
        [delegate didGenerateNewAddress];
    } else {
        DLog(@"Error: delegate of class %@ does not respond to selector didGenerateNewAddress!", [delegate class]);
    }
}

- (void)on_error_creating_new_address:(NSString*)error
{
    DLog(@"on_error_creating_new_address");
    [AlertViewPresenter.shared standardNotifyWithTitle:BC_STRING_ERROR message:error in:nil handler:nil];
}

- (void)on_add_new_account
{
    DLog(@"on_add_new_account");

    [self subscribeToXPub:[self getXpubForAccount:[self getActiveAccountsCount:LegacyAssetTypeBitcoin] - 1 assetType:LegacyAssetTypeBitcoin] assetType:LegacyAssetTypeBitcoin];

    dispatch_async(dispatch_get_main_queue(), ^{
        [LoadingViewPresenter.shared showWith:[LocalizationConstantsObjcBridge syncingWallet]];
    });
}

- (void)on_error_add_new_account:(NSString*)error
{
    DLog(@"on_error_generating_new_address");
    [AlertViewPresenter.shared standardNotifyWithTitle:BC_STRING_ERROR message:error in:nil handler:nil];
}

- (void)on_success_recover_with_passphrase:(NSDictionary *)recoveredWalletDictionary
{
    DLog(@"on_recover_with_passphrase_success_guid:sharedKey:password:");

    if ([delegate respondsToSelector:@selector(didRecoverWallet)]) {
        [delegate didRecoverWallet];
    } else {
        DLog(@"Error: delegate of class %@ does not respond to selector didRecoverWallet!", [delegate class]);
    }

    [self loadWalletWithGuid:recoveredWalletDictionary[@"guid"] sharedKey:recoveredWalletDictionary[@"sharedKey"] password:recoveredWalletDictionary[@"password"]];
}

- (void)on_error_recover_with_passphrase:(NSString *)error
{
    DLog(@"on_error_recover_with_passphrase:");
    [self loading_stop];
    if ([error isEqualToString:ERROR_INVALID_PASSPHRASE]) {
        [AlertViewPresenter.shared standardNotifyWithTitle:BC_STRING_ERROR message:BC_STRING_INVALID_RECOVERY_PHRASE in:nil handler:nil];
    } else if ([error isEqualToString:@""]) {
        [AlertViewPresenter.shared internetConnection];
    } else if ([error isEqualToString:ERROR_NO_METADATA]) {
        // Not possible to recover wallet from mnemonic only, old flow should be used.
    } else if ([error isEqualToString:ERROR_TIMEOUT_REQUEST]){
        [AlertViewPresenter.shared standardNotifyWithTitle:BC_STRING_ERROR message:LocalizationConstantsObjcBridge.timedOut in:nil handler:nil];
    } else {
        [AlertViewPresenter.shared standardNotifyWithTitle:BC_STRING_ERROR message:error in:nil handler:nil];
    }
    if ([delegate respondsToSelector:@selector(didFailRecovery)]) {
        [delegate didFailRecovery];
    } else {
        DLog(@"Error: delegate of class %@ does not respond to selector didFailRecovery!", [delegate class]);
    }
}

- (void)on_progress_recover_with_passphrase:(NSString *)totalReceived finalBalance:(NSString *)finalBalance
{
    uint64_t fundsInAccount = [finalBalance longLongValue];

    dispatch_async(dispatch_get_main_queue(), ^{
        if ([totalReceived longLongValue] == 0) {
            self.emptyAccountIndex++;
            [LoadingViewPresenter.shared showWith:[NSString stringWithFormat:BC_STRING_LOADING_RECOVERING_WALLET_CHECKING_ARGUMENT_OF_ARGUMENT, self.emptyAccountIndex, self.emptyAccountIndex > RECOVERY_ACCOUNT_DEFAULT_NUMBER ? self.emptyAccountIndex : RECOVERY_ACCOUNT_DEFAULT_NUMBER]];
        } else {
            self.emptyAccountIndex = 0;
            self.recoveredAccountIndex++;
            [LoadingViewPresenter.shared showWith:[NSString stringWithFormat:BC_STRING_LOADING_RECOVERING_WALLET_ARGUMENT_FUNDS_ARGUMENT, self.recoveredAccountIndex, [NSNumberFormatter formatMoney:fundsInAccount]]];
        }
    });
}

- (void)on_error_downloading_account_settings
{
    DLog(@"on_error_downloading_account_settings");
    [AlertViewPresenter.shared standardNotifyWithTitle:BC_STRING_SETTINGS_ERROR_LOADING_TITLE message:BC_STRING_SETTINGS_ERROR_LOADING_MESSAGE in:nil handler:nil];
    [[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithBool:NO] forKey:USER_DEFAULTS_KEY_LOADED_SETTINGS];
}

- (void)on_update_email_error
{
    [AlertViewPresenter.shared standardNotifyWithTitle:BC_STRING_ERROR message:BC_STRING_INVALID_EMAIL_ADDRESS in:nil handler:nil];
}

- (void)on_error_get_history:(NSString *)error
{
    [self loading_stop];
    if ([self.delegate respondsToSelector:@selector(didFailGetHistory:)]) {
        [self.delegate didFailGetHistory:error];
    }
}

- (void)return_to_addresses_screen
{
    DLog(@"return_to_addresses_screen");
    if ([self.delegate respondsToSelector:@selector(returnToAddressesScreen)]) {
        [self.delegate returnToAddressesScreen];
    }
}

- (void)did_archive_or_unarchive
{
    DLog(@"did_archive_or_unarchive");

    [self.btcSocket closeWithCode:WEBSOCKET_CODE_ARCHIVE_UNARCHIVE reason:WEBSOCKET_CLOSE_REASON_ARCHIVED_UNARCHIVED];
    [self.bchSocket closeWithCode:WEBSOCKET_CODE_ARCHIVE_UNARCHIVE reason:WEBSOCKET_CLOSE_REASON_ARCHIVED_UNARCHIVED];
}

- (void)did_get_swipe_addresses:(NSArray *)swipeAddresses asset_type:(LegacyAssetType)assetType
{
    DLog(@"did_get_swipe_addresses");

    if ([self.delegate respondsToSelector:@selector(didGetSwipeAddresses:assetType:)]) {
        [self.delegate didGetSwipeAddresses:swipeAddresses assetType:assetType];
    } else {
        DLog(@"Error: delegate of class %@ does not respond to selector didGetSwipeAddresses!", [delegate class]);
    }
}

- (void)eth_socket_send:(NSString *)message
{
    if (self.ethSocket && self.ethSocket.readyState == SR_OPEN) {
        DLog(@"Sending eth socket message %@", message);
        [self sendEthSocketMessage:message];
    } else {
        DLog(@"Will send eth socket message %@", message);
        [self.pendingEthSocketMessages insertObject:message atIndex:0];
        [self.ethSocket open];
    }
}

- (void)sendEthSocketMessage:(NSString *)message
{
    NSError *error;
    [self.ethSocket sendString:message error:&error];
    if (error) DLog(@"Error sending eth socket message: %@", [error localizedDescription]);
}

- (void)did_fetch_bch_history
{
    if ([self.delegate respondsToSelector:@selector(didFetchBitcoinCashHistory)]) {
        [self.delegate didFetchBitcoinCashHistory];
    } else {
        DLog(@"Error: delegate of class %@ does not respond to selector didFetchBitcoinCashHistory!", [delegate class]);
    }
}

- (void)did_get_bitcoin_cash_exchange_rates:(NSDictionary *)rates
{
    NSString *currency = self.accountInfo[DICTIONARY_KEY_CURRENCY];
    if (rates == nil || currency == nil) {
        return;
    }
    self.bitcoinCashExchangeRates = rates;
}

- (void)on_get_account_info_and_exchange_rates
{
    if ([self.delegate respondsToSelector:@selector(walletDidGetAccountInfoAndExchangeRates:)]) {
        [self.delegate walletDidGetAccountInfoAndExchangeRates:self];
    } else {
        DLog(@"Error: delegate of class %@ does not respond to selector didGetAvailableEthBalance:!", [delegate class]);
    }
}

# pragma mark - Calls from Obj-C to JS for HD wallet

- (void)upgradeToV3Wallet
{
    if (![self isInitialized]) {
        return;
    }

    DLog(@"Creating HD Wallet");
    [self.context evaluateScriptCheckIsOnMainQueue:[NSString stringWithFormat:@"MyWalletPhone.upgradeToV3(\"%@\");", [LocalizationConstantsObjcBridge myBitcoinWallet], nil]];
}

- (BOOL)hasAccount
{
    return [self didUpgradeToHd];
}

- (BOOL)didUpgradeToHd
{
    if (![self isInitialized]) {
        return NO;
    }

    return [[self.context evaluateScriptCheckIsOnMainQueue:@"MyWallet.wallet.isUpgradedToHD"] toBool];
}

- (NSString *_Nullable)getMnemonic:(NSString *_Nullable)secondPassword
{
    if (!self.isInitialized) {
        return nil;
    }
    JSValue *mnemonicValue = [self.context evaluateScriptCheckIsOnMainQueue:[NSString stringWithFormat:@"MyWalletPhone.getMnemonicPhrase(\"%@\")", [secondPassword escapedForJS]]];
    return [mnemonicValue toString];
}

- (BOOL)isRecoveryPhraseVerified {
    if (![self isInitialized]) {
        return NO;
    }

    if (![self didUpgradeToHd]) {
        return NO;
    }

    return [[self.context evaluateScriptCheckIsOnMainQueue:@"MyWallet.wallet.hdwallet.isMnemonicVerified"] toBool];
}

- (void)markRecoveryPhraseVerifiedWithCompletion:(void (^ _Nullable)(void))completion error: (void (^ _Nullable)(void))error
{
    [self.context invokeOnceWithStringFunctionBlock:^(NSString * _Nonnull response) {
        if (completion != nil) {
            completion();
        }
    } forJsFunctionName:@"objc_wallet_mnemonic_verification_updated"];
    
    [self.context invokeOnceWithFunctionBlock:^{
        if (error != nil) {
            error();
        }
    } forJsFunctionName:@"objc_wallet_mnemonic_verification_error"];
    
    [self.context evaluateScriptCheckIsOnMainQueue:@"MyWalletPhone.markMnemonicAsVerified()"];
}

- (int)getActiveAccountsCount:(LegacyAssetType)assetType
{
    if (![self isInitialized]) {
        return 0;
    }

    if (assetType == LegacyAssetTypeBitcoin) {
        return [[[self.context evaluateScriptCheckIsOnMainQueue:@"MyWalletPhone.getActiveAccountsCount()"] toNumber] intValue];
    } else if (assetType == LegacyAssetTypeBitcoinCash) {
        return [[[self.context evaluateScriptCheckIsOnMainQueue:@"MyWalletPhone.bch.getActiveAccountsCount()"] toNumber] intValue];
    }
    return 0;

}

- (int)getAllAccountsCount:(LegacyAssetType)assetType
{
    if (![self isInitialized]) {
        return 0;
    }

    if (assetType == LegacyAssetTypeBitcoin) {
        return [[[self.context evaluateScriptCheckIsOnMainQueue:@"MyWalletPhone.getAllAccountsCount()"] toNumber] intValue];
    } else if (assetType == LegacyAssetTypeBitcoinCash) {
        return [[[self.context evaluateScriptCheckIsOnMainQueue:@"MyWalletPhone.bch.getAllAccountsCount()"] toNumber] intValue];
    }
    return 0;
}

- (int)getDefaultAccountIndexForAssetType:(LegacyAssetType)assetType
{
    if (![self isInitialized]) {
        return 0;
    }

    if (assetType == LegacyAssetTypeBitcoin) {
        return [[[self.context evaluateScriptCheckIsOnMainQueue:@"MyWalletPhone.getDefaultAccountIndex()"] toNumber] intValue];
    } else if (assetType == LegacyAssetTypeBitcoinCash) {
        return [[[self.context evaluateScriptCheckIsOnMainQueue:@"MyWalletPhone.bch.getDefaultAccountIndex()"] toNumber] intValue];
    }
    return 0;
}

- (void)setDefaultAccount:(int)index assetType:(LegacyAssetType)assetType
{
    if (![self isInitialized]) {
        return;
    }

    if (assetType == LegacyAssetTypeBitcoin) {
        [self.context evaluateScriptCheckIsOnMainQueue:[NSString stringWithFormat:@"MyWalletPhone.setDefaultAccount(%d)", index]];
        self.isSettingDefaultAccount = YES;
    } else if (assetType == LegacyAssetTypeBitcoinCash) {
        [self.context evaluateScriptCheckIsOnMainQueue:[NSString stringWithFormat:@"MyWalletPhone.bch.setDefaultAccount(%d)", index]];
        [self getHistory];
        if ([self.delegate respondsToSelector:@selector(didSetDefaultAccount)]) {
            [self.delegate didSetDefaultAccount];
        } else {
            DLog(@"Error: delegate of class %@ does not respond to selector didSetDefaultAccount!", [delegate class]);
        }
    }
}

- (BOOL)hasLegacyAddresses:(LegacyAssetType)assetType
{
    if (![self isInitialized]) {
        return NO;
    }

    if (assetType == LegacyAssetTypeBitcoin) {
        return [[self.context evaluateScriptCheckIsOnMainQueue:@"MyWallet.wallet.addresses.length > 0"] toBool];
    } else if (assetType == LegacyAssetTypeBitcoinCash) {
        return [[self.context evaluateScriptCheckIsOnMainQueue:@"MyWalletPhone.bch.hasLegacyAddresses()"] toBool];
    }
    return NO;
}

- (uint64_t)getTotalActiveBalance
{
    if (![self isInitialized]) {
        return 0;
    }

    return [[[self.context evaluateScriptCheckIsOnMainQueue:@"MyWalletPhone.totalActiveBalance()"] toNumber] longLongValue];
}

- (uint64_t)getTotalBalanceForActiveLegacyAddresses:(LegacyAssetType)assetType
{
    if (![self isInitialized]) {
        return 0;
    }

    if (assetType == LegacyAssetTypeBitcoin) {
        return [[[self.context evaluateScriptCheckIsOnMainQueue:@"MyWallet.wallet.balanceActiveLegacy"] toNumber] longLongValue];
    } else if (assetType == LegacyAssetTypeBitcoinCash) {
        return [[[self.context evaluateScriptCheckIsOnMainQueue:@"MyWalletPhone.bch.balanceActiveLegacy()"] toNumber] longLongValue];
    }
    DLog(@"Error getting total balance for active legacy addresses: unsupported asset type!");
    return 0;
}

- (id)getBalanceForAccount:(int)account assetType:(LegacyAssetType)assetType
{
    if (assetType == LegacyAssetTypeBitcoin) {
        if (![self isInitialized]) {
            return @0;
        }
        return [[self.context evaluateScriptCheckIsOnMainQueue:[NSString stringWithFormat:@"MyWalletPhone.getBalanceForAccount(%d)", account]] toNumber];
    } else if (assetType == LegacyAssetTypeBitcoinCash) {
        if (![self isInitialized]) {
            return @0;
        }
        return [[self.context evaluateScriptCheckIsOnMainQueue:[NSString stringWithFormat:@"MyWalletPhone.bch.getBalanceForAccount(%d)", account]] toNumber];
    }
    return nil;
}

- (NSString *)getLabelForAccount:(int)account assetType:(LegacyAssetType)assetType
{
    if (![self isInitialized]) {
        return nil;
    }

    if (assetType == LegacyAssetTypeBitcoin) {
        return [[self.context evaluateScriptCheckIsOnMainQueue:[NSString stringWithFormat:@"MyWalletPhone.getLabelForAccount(%d)", account]] toString];
    } else if (assetType == LegacyAssetTypeBitcoinCash) {
        return [[self.context evaluateScriptCheckIsOnMainQueue:[NSString stringWithFormat:@"MyWalletPhone.bch.getLabelForAccount(%d)", account]] toString];
    }
    return nil;
}

- (void)createAccountWithLabel:(NSString *)label
{
    if ([self isInitialized] && Reachability.hasInternetConnection) {
        // Show loading text
        [self loading_start_create_account];

        self.isSyncing = YES;

        // Wait a little bit to make sure the loading text is showing - then execute the blocking and kind of long create account
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(ANIMATION_DURATION * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self.context evaluateScriptCheckIsOnMainQueue:[NSString stringWithFormat:@"MyWalletPhone.createAccount(\"%@\")", [label escapedForJS]]];
        });
    }
}

- (NSString *)getReceiveAddressForAccount:(int)account assetType:(LegacyAssetType)assetType
{
    if (![self isInitialized]) {
        return nil;
    }

    if (assetType == LegacyAssetTypeBitcoin) {
        return [[self.context evaluateScriptCheckIsOnMainQueue:[NSString stringWithFormat:@"MyWalletPhone.getReceivingAddressForAccount(%d)", account]] toString];
    } else if (assetType == LegacyAssetTypeBitcoinCash) {
        return [[self.context evaluateScriptCheckIsOnMainQueue:[NSString stringWithFormat:@"MyWalletPhone.bch.getReceivingAddressForAccount(%d)", account]] toString];
    }
    DLog(@"Warning: unknown asset type!");
    return nil;
}

#pragma mark - Callbacks from JS to Obj-C for HD wallet

- (void)reload
{
    DLog(@"reload");

    [AppCoordinator.shared reload];
}

- (void)logging_out
{
    DLog(@"logging_out");
}

# pragma mark - Cyrpto helpers, called from JS

- (void)crypto_scrypt:(id)_password salt:(id)salt n:(NSNumber*)N r:(NSNumber*)r p:(NSNumber*)p dkLen:(NSNumber*)derivedKeyLen success:(JSValue *)_success error:(JSValue *)_error
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [LoadingViewPresenter.shared showWith:BC_STRING_DECRYPTING_PRIVATE_KEY];
    });

    dispatch_async(dispatch_get_global_queue( DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSData * data = [self _internal_crypto_scrypt:_password salt:salt n:[N unsignedLongLongValue] r:[r unsignedIntValue] p:[p unsignedIntValue] dkLen:[derivedKeyLen unsignedIntValue]];

        dispatch_async(dispatch_get_main_queue(), ^{
            if (data) {
                [_success callWithArguments:@[[data hexadecimalString]]];
            } else {
                [LoadingViewPresenter.shared hide];
                [_error callWithArguments:@[@"Scrypt Error"]];
            }
        });
    });
}

- (NSData*)_internal_crypto_scrypt:(id)_password salt:(id)_salt n:(uint64_t)N r:(uint32_t)r p:(uint32_t)p dkLen:(uint32_t)derivedKeyLen
{
    uint8_t * _passwordBuff = NULL;
    size_t _passwordBuffLen = 0;
    if ([_password isKindOfClass:[NSArray class]]) {
        _passwordBuff = alloca([_password count]);
        _passwordBuffLen = [_password count];

        {
            int ii = 0;
            for (NSNumber * number in _password) {
                _passwordBuff[ii] = [number shortValue];
                ++ii;
            }
        }
    } else if ([_password isKindOfClass:[NSString class]]) {
        const char *passwordUTF8String = [_password UTF8String];
        _passwordBuff = (uint8_t*)passwordUTF8String;
        _passwordBuffLen = strlen(passwordUTF8String);
    } else {
        DLog(@"Scrypt password unsupported type");
        return nil;
    }

    uint8_t * _saltBuff = NULL;
    size_t _saltBuffLen = 0;

    if ([_salt isKindOfClass:[NSArray class]]) {
        _saltBuff = alloca([_salt count]);
        _saltBuffLen = [_salt count];

        {
            int ii = 0;
            for (NSNumber * number in _salt) {
                _saltBuff[ii] = [number shortValue];
                ++ii;
            }
        }
    } else if ([_salt isKindOfClass:[NSString class]]) {
        const char *saltUTF8String = [_salt UTF8String];
        _saltBuff = (uint8_t*)saltUTF8String;
        _saltBuffLen = strlen(saltUTF8String);
    } else {
        DLog(@"Scrypt salt unsupported type");
        return nil;
    }

    uint8_t * derivedBytes = malloc(derivedKeyLen);

    if (crypto_scrypt((uint8_t*)_passwordBuff, _passwordBuffLen, (uint8_t*)_saltBuff, _saltBuffLen, N, r, p, derivedBytes, derivedKeyLen) == -1) {
        return nil;
    }

    return [NSData dataWithBytesNoCopy:derivedBytes length:derivedKeyLen];
}

#pragma mark - Debugging

- (void)useDebugSettingsIfSet
{
    [self updateServerURL:[BlockchainAPI.shared walletUrl]];

    [self updateWebSocketURL:[BlockchainAPI.shared webSocketUri]];

    [self updateAPIURL:[BlockchainAPI.shared apiUrl]];

#ifdef DEBUG
    BOOL testnetOn = [[[NSUserDefaults standardUserDefaults] objectForKey:USER_DEFAULTS_KEY_ENV] isEqual:ENV_INDEX_TESTNET];
    NSString *network;
    if (testnetOn) {
        network = NETWORK_TESTNET;
    } else {
        network = NETWORK_MAINNET;
    }

    [self.context evaluateScriptCheckIsOnMainQueue:[NSString stringWithFormat:@"MyWalletPhone.changeNetwork(\"%@\")", [network escapedForJS]]];
#endif
}

@end
