//
//  Keychain.swift
//  cert-wallet
//
//  Created by Chris Downie on 8/9/16.
//  Copyright © 2016 Digital Certificates Project.
//

import Foundation
import Security

class Keychain {
    private var seedPhrase : String {
        return mnemonic.words.flatMap({ $0 as? String}).joined(separator: " ")
    }
    private var unusedKeyIndex : UInt32
    private let mnemonic : BTCMnemonic
    private let keychain : BTCKeychain
    private let accountKeychain : BTCKeychain
    
    init(seedPhrase: String, unusedKeyIndex: UInt32 = 0) {
        let words = seedPhrase.components(separatedBy: " ")
        guard let mnemonic = BTCMnemonic(words: words, password: "", wordListType: .english) else {
            fatalError("Can't start a Keychain with invalid phrase:\"\(seedPhrase)\"")
        }
        self.unusedKeyIndex = unusedKeyIndex
        self.mnemonic = mnemonic
        keychain = BTCKeychain(seed: mnemonic.data)
        accountKeychain = keychain.derivedKeychain(withPath: "m/44'/0'/0'")
    }
    
    func nextPublicKey() -> String {
        let key = accountKeychain.key(at: unusedKeyIndex)
        unusedKeyIndex += 1
        
        return key?.publicKey.hex() ?? ""
    }
    
    func has(publicKey : String) -> Bool {
        guard let keyData = publicKey.asHexData() else {
            // If the publicKey isn't a valid hex string, then this keychain obviously doesn't have it.
            return false
        }
        
        let key = BTCKey(publicKey: keyData)
        let limit : UInt = 10 // arbitrary. What's a good limit?
        
        return nil == accountKeychain.find(forPublicKey: key, hardened: true, limit: limit) // Also unsure of hardened value.
    }
    
    
}

// MARK: Static methods for seed phrase generation
extension Keychain {
    static func generateSeedPhrase() -> String {
        let randomData = BTCRandomDataWithLength(32) as Data
        return generateSeedPhrase(withRandomData: randomData)
    }
    
    static func generateSeedPhrase(withRandomData randomData: Data) -> String {
        let mn = BTCMnemonic(entropy: randomData, password: "", wordListType: .english)
        
        return mn?.words.flatMap({ $0 as? String }).joined(separator: " ") ?? ""
    }
}

// MARK: Singleton access, and loading/storing
extension Keychain {
    static private var seedPhraseKey = "org.blockcerts.seed-phrase"
    static private var _shared : Keychain? = nil
    static var shared : Keychain {
        if _shared == nil {
            // Implicitly unwrapped String, because it will either be loaded from memory or generated
            var seedPhrase : String! = loadSeedPhrase()
            if seedPhrase == nil {
                seedPhrase = generateSeedPhrase()
                save(seedPhrase: seedPhrase)
            }
            _shared = Keychain(seedPhrase: seedPhrase)
        }
        return _shared!
    }
    
    private static func loadSeedPhrase() -> String? {
        let query : [String : Any] = [
            String(kSecClass): kSecClassGenericPassword,
            String(kSecAttrAccount): seedPhraseKey,
            String(kSecReturnData): kCFBooleanTrue,
            String(kSecMatchLimit): kSecMatchLimitOne
        ]
        
        var dataTypeRef : CFTypeRef?
        let result = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        
        guard result == noErr,
            let dataType = dataTypeRef as? Data else {
            return nil
        }
        
        return String(data:dataType, encoding: .utf8)
    }
    
    @discardableResult private static func save(seedPhrase: String) -> Bool {
        guard let data = seedPhrase.data(using: .utf8) else {
            return false;
        }
        
        let attributes : [String : Any] = [
            String(kSecClass) : kSecClassGenericPassword,
            String(kSecAttrAccount) : seedPhraseKey,
            String(kSecValueData) : data
        ]
        var returnValue : CFTypeRef?
        let result = SecItemAdd(attributes as CFDictionary, &returnValue)
        
        return result == noErr
    }
    
    @discardableResult static func destroyShared() -> Bool {
        let query = [
            String(kSecClass) : kSecClassGenericPassword
        ]
        let result = SecItemDelete(query as CFDictionary)
        _shared = nil

        return result == noErr
    }
    
    @discardableResult static func updateShared(with seedPhrase: String) {
        // TODO: Do I need some kind of semaphore or something to make sure these two lines run one at a time?
        // If they don't, then it's possible we'll delete the key, the singleton will be recreated
        // with a random seed phrase, and the new seed phrase will be saved to the keychain. This will correct
        // itself when the app dies & is re-launched, but in the meantime the user might issue public keys
        // for a seed phrase he doesn't actually know.
        destroyShared()
        save(seedPhrase: seedPhrase)
    }
    

}
