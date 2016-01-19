import Foundation

public enum StubBehavior {
    case Immediate
    case Delayed(NSTimeInterval)
}

/// Request provider class. Requests should be made through this class only.
public class MoyaStubProvider<Target: TargetType>: MoyaProvider<Target> {

    public let stubBehavior: StubBehavior

    /// Initializes a provider.
    public init(endpointClosure: EndpointClosure = DefaultEndpointMapping,
                requestClosure: RequestClosure = DefaultRequestMapping,
                stubBehavior: StubBehavior = .Immediate,
                manager: Manager = DefaultAlamofireManager(),
                plugins: [PluginType] = []) {

        self.stubBehavior = stubBehavior
        super.init(endpointClosure: endpointClosure, requestClosure: requestClosure, manager: manager, plugins: plugins)
    }

    /// Designated request-making method. Returns a Cancellable token to cancel the request later.
    public override func request(target: Target, completion: Moya.Completion) -> Cancellable {
        let endpoint = self.endpoint(target)
        var cancellableToken = CancellableWrapper()

        let performNetworking = { (request: NSURLRequest) in
            if cancellableToken.isCancelled { return }

            cancellableToken.innerCancellable = self.stubRequest(target, request: request, completion: completion, endpoint: endpoint)
        }

        requestClosure(endpoint, performNetworking)

        return cancellableToken
    }

    /// When overriding this method, take care to `notifyPluginsOfImpendingStub` and to perform the stub using the `createStubFunction` method.
    /// Note: this was previously in an extension, however it must be in the original class declaration to allow subclasses to override.
    internal func stubRequest(target: Target, request: NSURLRequest, completion: Moya.Completion, endpoint: Endpoint<Target>) -> CancellableToken {
        let cancellableToken = CancellableToken { }
        notifyPluginsOfImpendingStub(request, target: target)
        let plugins = self.plugins
        let stub: () -> () = createStubFunction(cancellableToken, forTarget: target, withCompletion: completion, endpoint: endpoint, plugins: plugins)
        switch self.stubBehavior {
        case .Immediate:
            stub()
        case .Delayed(let delay):
            let killTimeOffset = Int64(CDouble(delay) * CDouble(NSEC_PER_SEC))
            let killTime = dispatch_time(DISPATCH_TIME_NOW, killTimeOffset)
            dispatch_after(killTime, dispatch_get_main_queue()) {
                stub()
            }
        }

        return cancellableToken
    }

    /// Creates a function which, when called, executes the appropriate stubbing behavior for the given parameters.
    internal final func createStubFunction(token: CancellableToken, forTarget target: Target, withCompletion completion: Moya.Completion, endpoint: Endpoint<Target>, plugins: [PluginType]) -> (() -> ()) {
        return {
            if (token.canceled) {
                let error = Moya.Error.Underlying(NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled, userInfo: nil))
                plugins.forEach { $0.didReceiveResponse(.Failure(error), target: target) }
                completion(result: .Failure(error))
                return
            }

            switch endpoint.sampleResponseClosure() {
            case .NetworkResponse(let statusCode, let data):
                let response = Moya.Response(statusCode: statusCode, data: data, response: nil)
                plugins.forEach { $0.didReceiveResponse(.Success(response), target: target) }
                completion(result: .Success(response))
            case .NetworkError(let error):
                let error = Moya.Error.Underlying(error)
                plugins.forEach { $0.didReceiveResponse(.Failure(error), target: target) }
                completion(result: .Failure(error))
            }
        }
    }

    /// Notify all plugins that a stub is about to be performed. You must call this if overriding `stubRequest`.
    internal final func notifyPluginsOfImpendingStub(request: NSURLRequest, target: Target) {
        let alamoRequest = manager.request(request)
        plugins.forEach { $0.willSendRequest(alamoRequest, target: target) }
    }
}
