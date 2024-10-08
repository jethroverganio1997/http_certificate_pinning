import Flutter
import UIKit
import CryptoSwift
import Alamofire

public class SwiftHttpCertificatePinningPlugin: NSObject, FlutterPlugin {

    let session = Alamofire.Session.default
    var fingerprints: Array<String>?
    var flutterResult: FlutterResult?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "http_certificate_pinning", binaryMessenger: registrar.messenger())
        let instance = SwiftHttpCertificatePinningPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch (call.method) {
        case "check":
            if let _args = call.arguments as? Dictionary<String, AnyObject> {
                self.check(call: call, args: _args, flutterResult: result)
            } else {
                result(
                    FlutterError(
                        code: "Invalid Arguments",
                        message: "Please specify arguments",
                        details: nil)
                )
            }
            break
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    public func check(
        call: FlutterMethodCall,
        args: Dictionary<String, AnyObject>,
        flutterResult: @escaping FlutterResult
    ) {
        guard let urlString = args["url"] as? String,
              let headers = args["headers"] as? Dictionary<String, String>,
              let fingerprints = args["fingerprints"] as? Array<String>,
              let type = args["type"] as? String
        else {
            flutterResult(
                FlutterError(
                    code: "Params incorrect",
                    message: "Les params sont incorrect",
                    details: nil
                )
            )
            return
        }

        self.fingerprints = fingerprints

        var timeout = 60
        if let timeoutArg = args["timeout"] as? Int {
            timeout = timeoutArg
        }
        
        // Configure the session with custom settings
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = TimeInterval(timeout)
        
        // Initialize the session with the configuration
        let session = Alamofire.Session(configuration: configuration)
        
        var resultDispatched = false
        
        // Making the request with the session
        session.request(urlString, method: .get, headers: HTTPHeaders(headers)).validate().responseJSON { response in
            switch response.result {
            case .success:
                break
            case .failure(let error):
                if (!resultDispatched) {
                    flutterResult(
                        FlutterError(
                            code: "URL Format",
                            message: error.localizedDescription,
                            details: nil
                        )
                    )
                }
                break
            }
        }

        // Set up certificate pinning
        session.session.delegate.taskDidReceiveChallenge = { session, task, challenge in
            guard let serverTrust = challenge.protectionSpace.serverTrust,
                  let certificate = SecTrustGetCertificateAtIndex(serverTrust, 0) else {
                flutterResult(
                    FlutterError(
                        code: "ERROR CERT",
                        message: "Invalid Certificate",
                        details: nil
                    )
                )
                return (.cancelAuthenticationChallenge, nil)
            }

            // Set SSL policies for domain name check
            let policies: [SecPolicy] = [SecPolicyCreateSSL(true, challenge.protectionSpace.host as CFString)]
            SecTrustSetPolicies(serverTrust, policies as CFTypeRef)

            // Evaluate server certificate
            var result: SecTrustResultType = .invalid
            SecTrustEvaluate(serverTrust, &result)
            let isServerTrusted = (result == .unspecified || result == .proceed)

            let serverCertData = SecCertificateCopyData(certificate) as Data
            var serverCertSha = serverCertData.sha256().toHexString()

            if (type == "SHA1") {
                serverCertSha = serverCertData.sha1().toHexString()
            }

            var isSecure = false
            if var fp = self.fingerprints {
                fp = fp.compactMap { $0.replacingOccurrences(of: " ", with: "") }

                isSecure = fp.contains { $0.caseInsensitiveCompare(serverCertSha) == .orderedSame }
            }

            if isServerTrusted && isSecure {
                flutterResult("CONNECTION_SECURE")
                resultDispatched = true
            } else {
                flutterResult(
                    FlutterError(
                        code: "CONNECTION_NOT_SECURE",
                        message: nil,
                        details: nil
                    )
                )
                resultDispatched = true
            }

            return (.cancelAuthenticationChallenge, nil)
        }
    }
}
