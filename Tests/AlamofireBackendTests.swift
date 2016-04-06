import XCTest
import OHHTTPStubs
import Alamofire
@testable import MoyaX

class AlamofireBackendTests: XCTestCase {
    let data = "Half measures are as bad as nothing at all.".dataUsingEncoding(NSUTF8StringEncoding)!
    var endpoint: Endpoint!
    var backend: AlamofireBackend!

    override func setUp() {
        super.setUp()
        self.endpoint = Endpoint(target: TestTarget())
    }

    override func tearDown() {
        OHHTTPStubs.removeAllStubs()
        super.tearDown()
    }

    func testRequest() {
        // Given
        OHHTTPStubs.stubRequestsPassingTest({$0.URL!.path == "/foo/bar"}) { _ in
            return OHHTTPStubsResponse(data: self.data, statusCode: 200, headers: nil).responseTime(0.5)
        }

        self.backend = AlamofireBackend()

        var result: MoyaX.Result<MoyaX.Response, MoyaX.Error>?

        let expectation = expectationWithDescription("do request")

        // When
        backend.request(self.endpoint) { closureResult in
            result = closureResult
            expectation.fulfill()
        }

        waitForExpectationsWithTimeout(2, handler: nil)

        //Then
        if let result = result {
            switch result {
            case .Response:
                break
            default:
                XCTFail("the request should be success.")
            }
        } else {
            XCTFail("result should not be nil")
        }
    }

    func testCancelRequest() {
        // Given
        OHHTTPStubs.stubRequestsPassingTest({$0.URL!.path == "/foo/bar"}) { _ in
            return OHHTTPStubsResponse(data: self.data, statusCode: 200, headers: nil).responseTime(2)
        }

        self.backend = AlamofireBackend()

        var result: MoyaX.Result<MoyaX.Response, MoyaX.Error>?

        let expectation = expectationWithDescription("do request")

        // When
        let cancellableToken = backend.request(self.endpoint) { closureResult in
            result = closureResult
            expectation.fulfill()
        }

        cancellableToken.cancel()

        waitForExpectationsWithTimeout(3, handler: nil)

        // Then
        if let result = result {
            switch result {
            case let .Incomplete(error):
                guard case .Cancelled = error else {
                    XCTFail("error should be MoyaX.Error.Cancelled")
                    break
                }
            default:
                XCTFail("the request should be fail.")
            }
        } else {
            XCTFail("result should not be nil")
        }
    }

    func testRequestWithHook() {
        // Given
        OHHTTPStubs.stubRequestsPassingTest({$0.URL!.path == "/foo/bar"}) { _ in
            return OHHTTPStubsResponse(data: self.data, statusCode: 200, headers: nil).responseTime(1)
        }

        var calledWillPerformRequest = false
        let willPerformRequest: (Endpoint, Alamofire.Request) -> () = { _, _ in
            calledWillPerformRequest = true
        }

        var calledDidReceiveResponse = false
        let didReceiveResponse: (Endpoint, Alamofire.Response<NSData, NSError>) -> () = { _, _ in
            calledDidReceiveResponse = true
        }

        self.backend = AlamofireBackend(willPerformRequest: willPerformRequest, didReceiveResponse: didReceiveResponse)

        var result: MoyaX.Result<MoyaX.Response, MoyaX.Error>?

        let expectation = expectationWithDescription("do request")

        // When
        backend.request(self.endpoint) { closureResult in
            result = closureResult
            expectation.fulfill()
        }

        waitForExpectationsWithTimeout(2, handler: nil)

        // Then
        if let result = result {
            switch result {
            case .Response:
                break
            default:
                XCTFail("the request should be success.")
            }

            XCTAssertTrue(calledWillPerformRequest)
            XCTAssertTrue(calledDidReceiveResponse)
        } else {
            XCTFail("result should not be nil")
        }
    }
}