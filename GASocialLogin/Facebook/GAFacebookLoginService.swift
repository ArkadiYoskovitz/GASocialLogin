//
//  GAFacebookLoginService.swift
//  GASocialLogin
//
//  Created by ido meirov on 04/09/2018.
//

import Foundation
import FBSDKLoginKit

public typealias GAFacebookUserData = [String : Any]
public typealias GAFacebookToken    = FBSDKAccessToken


/// Login result
///
/// - success: log in and get user data successd
/// - error: the error from facebook sdk
/// - missingPermissions: no Permissions
/// - unknownError: unknown error
/// - cancelled: user prass on cancel
public enum GAFacebookResult
{
    case success(GAFacebookProfile, GAFacebookUserData)
    case error(Error)
    case missingPermissions
    case unknownError
    case cancelled
}


/// Base user model
public struct GAFacebookProfile
{
    public let facebookId   : String?
    public let facebookToken: String?
    public let firstName    : String?
    public let lastName     : String?
    public let email        : String?
}

extension GASocialLogin
{
    public var facebookLoginService: GAFacebookLoginService?
    {
        guard let service = services[GAFacebookLoginService.serviceKey] as? GAFacebookLoginService else
        {
            assertionFailure("You did not pass GAFacebookLoginConfiguration in the GASocialLogin configure method")
            debugPrint("you did not pass GAFacebookLoginConfiguration in the GASocialLogin configure method")
            return nil
        }
        
        return service
    }
}

extension GASocialLogin
{
    public typealias GAFacebookCompletion = (GAFacebookResult) -> Void
    public typealias GAFacebookAccessTokenValidationCompletion = (Bool, Error?) -> Void
    
    public class GAFacebookLoginService: NSObject
    {
        // MARK: - Properties
        static let serviceKey                           = "GASocialLogin.GAFacebookLoginService"
        public private(set) var currentFacebookProfile  : GAFacebookProfile? // the current Facebook user loged in Profile
        public var saveLastLoginToken                   : Bool // should auto save user token (default value is false)
        public let facebookURLScheme                    : String
        
        /// Facebook manager
        public let loginManager : FBSDKLoginManager = {
            
            let manager = FBSDKLoginManager()
            return manager
        }()
        
        
        /// Default permissions if user do not give any permissions
        public static let defaultPermissionsKeys = [
            "email",
            "public_profile"
        ]
        
        
        /// Default fields for graph request if user do not give any fields
        public static let defaultUserFields = "id, name, email, first_name, last_name"
        
        // MARK: - Enume
        /// User base metadata keys
        private enum FacebookKeys : String , CustomStringConvertible
        {
            case id            = "id"
            case email         = "email"
            case publicProfile = "public_profile"
            case firstName     = "first_name"
            case lastName      = "last_name"
            case name          = "name"
            
            var description : String { return rawValue }
        }
        
        // MARK: - Object life cycle
        public init(facebookURLScheme: String, saveLastLoginToken: Bool = false)
        {
            self.saveLastLoginToken = saveLastLoginToken
            self.facebookURLScheme  = facebookURLScheme
            super.init()
        }
        
        // MARK: - Public API Login
        
        /// imaplate facebook logIn withReadPermissions and then call to use FBSDKGraphRequest to get user base data
        ///
        /// - Parameters:
        ///   - permissions: the permissions for faacebook log in (default value is defaultPermissionsKeys)
        ///   - fields: the fields for facebook FBSDKGraphRequest (default value is defaultUserFields)
        ///   - viewController: the current present view controller
        ///   - completion: the call back with the results
        public func loginUser(byPermissions permissions: [String] = defaultPermissionsKeys, byFields fields: String = defaultUserFields,from viewController: UIViewController, with completion: @escaping GAFacebookCompletion)
        {
            loginManager.logIn(withReadPermissions: permissions, from: viewController) { [weak self] (result, error) in
                
                guard let strongSelf = self else { return }
                guard let result = result   else { strongSelf.handelError(for: error, with: completion) ; return }
                
                switch result.isCancelled {
                case true:
                    print("FACEBOOK LOGIN: CANCELLED")
                    self?.currentFacebookProfile = nil
                    completion(.cancelled)
                    
                case false:
                    print("FACEBOOK LOGIN: SUCCESS - PERMISSIONS: \(result.grantedPermissions)")
                    
                    strongSelf.getUserInfo(byFields: fields, loginResult: result, completion: completion)
                }
            }
        }
        
        
        /// Check ig given token is validate using facebook graph request
        /// GET https://graph.accountkit.com/v1.3/me/?access_token=<access_token>.
        ///
        /// - Parameters:
        ///   - token: the token to check (default value is FBSDKAccessToken.current().tokenString)
        ///   - completion: the completion handler return true if get data from facebook
        public func checkAccessTokenValidation(token: String = FBSDKAccessToken.current().tokenString, completion: GAFacebookAccessTokenValidationCompletion?)
        {
            let params = ["access_token" : token]
            let graphRequest = FBSDKGraphRequest(graphPath: "me", parameters: params)
            
            _ = graphRequest?.start(completionHandler: { (connection, result, error) in
                
                if let error = error
                {
                    completion?(false, error)
                    return
                }
                
                guard result != nil else
                {
                    completion?(false, nil)
                    return
                    
                }
                
                completion?(true, nil)
            })
        }
        
        /// MARK: - Private
        
        /// Call to FBSDKGraphRequest.start by given fields
        ///
        /// - Parameters:
        ///   - fields: fields for facebook FBSDKGraphRequest
        ///   - loginResult: the result of the login as FBSDKLoginManagerLoginResult
        ///   - completion: the call back with the results
        private func getUserInfo(byFields fields: String, loginResult: FBSDKLoginManagerLoginResult, completion: @escaping GAFacebookCompletion)
        {
            guard FBSDKAccessToken.current() != nil else {
                print("FACEBOOK: user not logged in: aborting action")
                currentFacebookProfile = nil
                completion(.unknownError)
                return
            }
            
            let params = ["fields" : fields]
            let graphRequest = FBSDKGraphRequest(graphPath: "me", parameters: params)
            
            _ = graphRequest?.start { [weak self] (connection, result, error) in
                
                guard let strongSelf = self else { return }
                
                guard let userData = result as? GAFacebookUserData else { strongSelf.handelError(for: error, with: completion) ; return }
                
                strongSelf.generateFacebookProfile(with: loginResult, from: userData, with: completion)
            }
        }
        
        private func generateFacebookProfile(with loginResult: FBSDKLoginManagerLoginResult, from userData: GAFacebookUserData, with completion: @escaping GAFacebookCompletion)
        {
            let facebookId  = userData[FacebookKeys.id.description] as? String
            let email       = userData[FacebookKeys.email.description] as? String
            let firstName   = userData[FacebookKeys.firstName.description] as? String
            let lastName    = userData[FacebookKeys.lastName.description] as? String
            
            let facebookToken = loginResult.token.tokenString as String
            
            print("FACEBOOK: GRAPH REQUEST: SUCCESS")
            let profile = GAFacebookProfile(facebookId: facebookId, facebookToken: facebookToken,
                                            firstName: firstName, lastName: lastName, email: email)
            
            currentFacebookProfile = profile
            
            completion(.success(profile, userData))
        }
        
        private func handelError(for error: Error?, with completion: @escaping GAFacebookCompletion)
        {
            currentFacebookProfile = nil
            guard let error = error else { completion(.unknownError) ; return }
            completion(.error(error))
        }
    }
}

// MARK: - Login Token
extension GASocialLogin.GAFacebookLoginService
{
    // MARK: - Properties
    
    /// Return the current FBSDKAccessToken if nil return the lastLogInToken
    public var logInToken: GAFacebookToken?
    {
        guard let currentToken = FBSDKAccessToken.current() else { return nil }
        
        return currentToken
    }
    
    /// Return the logInToken permissions
    public var currentTokenPermissions: Set<String>?
    {
        guard let currentToken  = logInToken                                else { return nil }
        guard let permissions   = currentToken.permissions as? Set<String>  else { return nil }
        return  permissions
    }
}

// MARK: -  GASocialLoginService
extension GASocialLogin.GAFacebookLoginService: GASocialLoginService
{
    // MARK: - Public API Application Handler
    
    /// Call to facebook FBSDKApplicationDelegate.sharedInstance().application(, didFinishLaunchingWithOptions:).
    /// Need to call application(_ application:, didFinishLaunchingWithOptions launchOptions:) -> Bool
    /// in the main app delegate
    ///
    /// - Parameters:
    ///   - application: UIApplication
    ///   - launchOptions: [UIApplicationLaunchOptionsKey: Any]?
    public func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplicationLaunchOptionsKey : Any]? = nil) -> Bool
    {
        FBSDKApplicationDelegate.sharedInstance().application(application, didFinishLaunchingWithOptions: launchOptions)
        return true
    }
    
    /// Call to facebook FBSDKApplicationDelegate.sharedInstance().application(, open:, sourceApplication:, annotation:).
    /// need to call on application(_ app: , open url: , options: ) -> Bool
    /// in the main app delegate.
    ///
    /// - Parameters:
    ///   - application: UIApplication
    ///   - url: url object
    ///   - options: [UIApplicationOpenURLOptionsKey : Any]
    /// - Returns: return the result from facebook
    public func application(_ app: UIApplication, open url: URL, options: [UIApplicationOpenURLOptionsKey : Any] = [:]) -> Bool
    {
        let sourceApplicationValue = options[UIApplicationOpenURLOptionsKey.sourceApplication] as! String
        let        annotationValue = options[UIApplicationOpenURLOptionsKey.annotation]        as? String
        
        guard url.scheme == facebookURLScheme else { return true }
        
        return FBSDKApplicationDelegate.sharedInstance().application(app, open: url, sourceApplication: sourceApplicationValue, annotation: annotationValue)
    }
}
