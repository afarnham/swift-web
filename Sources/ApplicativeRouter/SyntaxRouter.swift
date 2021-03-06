import Foundation
import Prelude
import Optics
import UrlFormEncoding

// MARK: - Syntax Router

// TODO: should this be generic over any monoid `M` instead of using `RequestData` directly?
// TODO: generic over an error semigroup too?
public struct Router<A> {
  let parse: (RequestData) -> (rest: RequestData, match: A)?
  let print: (A) -> RequestData?
  let template: (A) -> RequestData?

  public func match(request: URLRequest) -> A? {
    return (self <% end).parse(requestData(from: request))?.match
  }

  public func match(url: URL) -> A? {
    return match(request: URLRequest(url: url))
  }

  public func match(string: String) -> A? {
    return URL(string: string).flatMap(match(url:))
  }

  public func request(for a: A) -> URLRequest? {
    return self.request(for: a, base: nil)
  }

  public func request(for a: A, base: URL?) -> URLRequest? {
    return self.print(a).flatMap { ApplicativeRouter.request(from: $0, base: base) }
  }

  public func url(for a: A) -> URL? {
    return self.print(a).flatMap(request(from:)).flatMap { $0.url }
  }

  public func url(for a: A, base: URL?) -> URL? {
    return self.print(a).flatMap { ApplicativeRouter.request(from: $0, base: base) }.flatMap { $0.url }
  }

  public func absoluteString(for a: A) -> String? {
    return (self.url(for: a)?.absoluteString)
      .map { $0 == "/" ? "/" : "/" + $0 }
  }

  public func templateRequest(for a: A) -> URLRequest? {
    return self.template(a).flatMap(request(from:))
  }

  public func templateUrl(for a: A) -> URL? {
    return self.templateRequest(for: a).flatMap { $0.url }
  }
}

extension Router: ExpressibleByUnicodeScalarLiteral where A == Prelude.Unit {
  public typealias UnicodeScalarLiteralType = String.UnicodeScalarLiteralType

  public init(unicodeScalarLiteral value: UnicodeScalarLiteralType) {
    self = lit(String(value))
  }
}

extension Router: ExpressibleByExtendedGraphemeClusterLiteral where A == Prelude.Unit {
  public typealias ExtendedGraphemeClusterLiteralType = String.ExtendedGraphemeClusterLiteralType

  public init(extendedGraphemeClusterLiteral value: ExtendedGraphemeClusterLiteralType) {
    self = lit(String(value))
  }
}

extension Router: ExpressibleByStringLiteral where A == Prelude.Unit {
  public typealias StringLiteralType = String

  public init(stringLiteral value: String) {
    self = lit(value)
  }
}

// Functor

extension Router {
  public func map<B>(_ f: PartialIso<A, B>) -> Router<B> {
    return f <¢> self
  }

  public static func <¢> <B> (lhs: PartialIso<A, B>, rhs: Router) -> Router<B> {
    return Router<B>(
      parse: { route in
        guard let (rest, match) = rhs.parse(route) else { return nil }
        return lhs.apply(match).map { (rest, $0) }
      },
      print: lhs.unapply >=> rhs.print,
      template: lhs.unapply >=> rhs.template
    )
  }
}

// Apply

extension Router {
  /// TODO: use `Tuple`?
  /// Processes with the left and right side routers, and if they succeed returns the pair of their results.
  public static func <%> <B> (lhs: Router, rhs: Router<B>) -> Router<(A, B)> {
    return Router<(A, B)>(
      parse: { str in
        guard let (more, a) = lhs.parse(str) else { return nil }
        guard let (rest, b) = rhs.parse(more) else { return nil }
        return (rest, (a, b))
      },
      print: { ab in
        let lhsPrint = lhs.print(ab.0)
        let rhsPrint = rhs.print(ab.1)
        return (curry(<>) <¢> lhsPrint <*> rhsPrint) ?? lhsPrint ?? rhsPrint
      },
      template: { ab in
        let lhsPrint = lhs.template(ab.0)
        let rhsPrint = rhs.template(ab.1)
        return (curry(<>) <¢> lhsPrint <*> rhsPrint) ?? lhsPrint ?? rhsPrint
    })
  }

  /// Processes with the left and right side routers, discarding the result of the left side.
  public static func %> (x: Router<Prelude.Unit>, y: Router) -> Router {
    return (PartialIso.commute >>> PartialIso.unit.inverted) <¢> x <%> y
  }
}

extension Router where A == Prelude.Unit {
  /// Processes with the left and right routers, discarding the result of the right side.
  public static func <% <B>(x: Router<B>, y: Router) -> Router<B> {
    return PartialIso.unit.inverted <¢> x <%> y
  }
}

// Alternative

extension Router {
  /// Processes with the left side router, and if that fails uses the right side router.
  public static func <|> (lhs: Router, rhs: Router) -> Router {
    return .init(
      parse: { lhs.parse($0) ?? rhs.parse($0) },
      print: { lhs.print($0) ?? rhs.print($0) },
      template: { lhs.template($0) ?? rhs.template($0) }
    )
  }
}

// Plus

extension Router {
  /// A router that always fails and doesn't print anything.
  public static var empty: Router {
    return Router(
      parse: const(nil),
      print: const(nil),
      template: const(nil)
    )
  }
}

private func requestData(from request: URLRequest) -> RequestData {
  let method = request.httpMethod.flatMap(Method.init(string:)) ?? .get

  guard let url = request.url else {
    return .init(method: method, path: [], query: [], body: request.httpBody)
  }

  let query = parse(query: url.query ?? "")

  let path = url.path.components(separatedBy: "/")
    |> mapOptional { $0.isEmpty ? nil : $0 }

  return .init(method: method, path: path, query: query, body: request.httpBody)
}

private func request(from data: RequestData) -> URLRequest? {

  return request(from: data, base: nil)
}

private func request(from data: RequestData, base: URL?) -> URLRequest? {
  // Due to this bug https://bugs.swift.org/browse/SR-6527, if `URLComponents` doesn't contain any path or
  // query information, it will fail to create a `URL`. We have to guard against that case and just return
  // the base url.
  return
    (
      data.path.isEmpty && data.query.isEmpty
        ? (base ?? URL(string: "/"))
        : urlComponents(from: data).url(relativeTo: base)
      )
      .map {
        URLRequest(url: $0)
          |> \.httpMethod .~ data.method?.rawValue
          |> \.httpBody .~ data.body
  }
}

private func urlComponents(from route: RequestData) -> URLComponents {
  var components = URLComponents()
  components.path = route.path.joined(separator: "/")

  let query = route.query.filter { $0.value != nil }
  if !query.isEmpty {
    components.queryItems = query.map(URLQueryItem.init(name:value:))
  }

  return components
}
