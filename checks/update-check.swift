import Foundation
import CryptoKit

// Verify the published archive against the exact public key shipped with quick.
let arguments = CommandLine.arguments
precondition(arguments.count == 4, "Usage: update-check.swift appcast.xml update.dmg X.Y.Z")
let feed = try XMLDocument(contentsOf:URL(fileURLWithPath:arguments[1]),options:[])
let items = try feed.nodes(forXPath:"/rss/channel/item")
precondition(items.count == 1, "The feed must contain this release only")
let item = items[0] as! XMLElement
let enclosure = item.elements(forName:"enclosure").first!
let version = item.elements(forName:"sparkle:version").first!.stringValue!
precondition(version == arguments[3], "Feed version does not match the release tag")
let expectedURL = "https://github.com/imkratos/quick/releases/download/v\(version)/quick-\(version)-macos-arm64.dmg"
precondition(enclosure.attribute(forName:"url")?.stringValue == expectedURL)
let archive = try Data(contentsOf:URL(fileURLWithPath:arguments[2]))
precondition(enclosure.attribute(forName:"length")?.stringValue == String(archive.count))
let configuration = try PropertyListSerialization.propertyList(from:Data(contentsOf:URL(fileURLWithPath:"Resources/Updater.plist")),format:nil) as! [String:Any]
let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation:Data(base64Encoded:configuration["SUPublicEDKey"] as! String)!)
let signature = Data(base64Encoded:enclosure.attribute(forName:"sparkle:edSignature")!.stringValue!)!
precondition(publicKey.isValidSignature(signature,for:archive), "Update signature does not match the shipped public key")
var tampered = archive
// An altered download must fail verification.
tampered[0] ^= 1
precondition(!publicKey.isValidSignature(signature,for:tampered))
print("更新检查通过：版本、下载地址、文件大小、公钥签名验证和篡改拒绝")
