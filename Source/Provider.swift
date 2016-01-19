import Foundation

/// Request provider class. Requests should be made through this class only.
public class MoyaProvider<Target: TargetType> {

    /// Closure that defines the endpoints for the provider.
    public typealias EndpointClosure = Target -> Endpoint<Target>

    /// Closure that resolves an Endpoint into an NSURLRequest.
    public typealias RequestClosure = (Endpoint<Target>, NSURLRequest -> Void) -> Void

    public let endpointClosure: EndpointClosure
    public let requestClosure: RequestClosure
    public let manager: Manager

    /// A list of plugins
    /// e.g. for logging, network activity indicator or credentials
    public let plugins: [PluginType]

    /// Initializes a provider.
    public init(endpointClosure: EndpointClosure = DefaultEndpointMapping,
                requestClosure: RequestClosure = DefaultRequestMapping,
                manager: Manager = DefaultAlamofireManager(),
                plugins: [PluginType] = []) {

        self.endpointClosure = endpointClosure
        self.requestClosure = requestClosure
        self.manager = manager
        self.plugins = plugins
    }

    /// Returns an Endpoint based on the token, method, and parameters by invoking the endpointsClosure.
    public func endpoint(token: Target) -> Endpoint<Target> {
        return endpointClosure(token)
    }

    /// Designated request-making method. Returns a Cancellable token to cancel the request later.
    public func request(target: Target, completion: Moya.Completion) -> Cancellable {
        let endpoint = self.endpoint(target)
        var cancellableToken = CancellableWrapper()

        let performNetworking = { (request: NSURLRequest) in
            if cancellableToken.isCancelled { return }

            cancellableToken.innerCancellable = self.sendRequest(target, request: request, completion: completion)
        }

        requestClosure(endpoint, performNetworking)

        return cancellableToken
    }
}

internal extension MoyaProvider {
    func sendRequest(target: Target, request: NSURLRequest, completion: Moya.Completion) -> CancellableToken {
        let alamoRequest = manager.request(request)
        let plugins = self.plugins

        // Give plugins the chance to alter the outgoing request
        plugins.forEach { $0.willSendRequest(alamoRequest, target: target) }

        // Perform the actual request
        alamoRequest.response { (_, response: NSHTTPURLResponse?, data: NSData?, error: NSError?) -> () in
            let result = convertResponseToResult(response, data: data, error: error)
            // Inform all plugins about the response
            plugins.forEach { $0.didReceiveResponse(result, target: target) }
            completion(result: result)
        }

        alamoRequest.resume()

        return CancellableToken(request: alamoRequest)
    }
}
