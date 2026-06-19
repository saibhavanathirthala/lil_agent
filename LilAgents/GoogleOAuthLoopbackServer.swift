import Foundation
import Network

final class GoogleOAuthLoopbackServer {
    private var listener: NWListener?
    private var timeoutWorkItem: DispatchWorkItem?
    private var didFinish = false
    var onCode: ((Result<String, Error>) -> Void)?

    func start(completion: @escaping (Result<UInt16, Error>) -> Void) {
        do {
            let params = NWParameters.tcp
            params.acceptLocalOnly = true
            let listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: 0)!)
            self.listener = listener

            var didResume = false
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    guard !didResume, let port = listener.port?.rawValue else { return }
                    didResume = true
                    completion(.success(port))
                case .failed(let error):
                    guard !didResume else { return }
                    didResume = true
                    completion(.failure(error))
                default:
                    break
                }
            }

            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection)
            }

            listener.start(queue: .global(qos: .userInitiated))

            let timeout = DispatchWorkItem { [weak self] in
                self?.finish(.failure(GoogleOAuthError.authTimeout))
                self?.stop()
            }
            timeoutWorkItem = timeout
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 180, execute: timeout)
        } catch {
            completion(.failure(error))
        }
    }

    func stop() {
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
        listener?.cancel()
        listener = nil
    }

    private func finish(_ result: Result<String, Error>) {
        guard !didFinish else { return }
        didFinish = true
        DispatchQueue.main.async { [weak self] in
            self?.onCode?(result)
        }
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .userInitiated))
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, _, _ in
            guard let self, let data, let request = String(data: data, encoding: .utf8) else { return }
            let firstLine = request.split(separator: "\r\n", omittingEmptySubsequences: false).first
                ?? request.split(separator: "\n").first
            guard let firstLine else { return }

            let parts = firstLine.split(separator: " ")
            guard parts.count >= 2 else { return }
            let path = String(parts[1])
            guard let url = URL(string: "http://127.0.0.1\(path)"),
                  let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return }

            if let code = items.first(where: { $0.name == "code" })?.value {
                self.reply(connection, title: "Connected!", message: "Google Calendar is linked. You can close this tab and return to Jazz.")
                self.finish(.success(code))
                return
            }

            if let error = items.first(where: { $0.name == "error" })?.value {
                let detail = items.first(where: { $0.name == "error_description" })?.value ?? error
                self.reply(connection, title: "Sign-in failed", message: detail)
                self.finish(.failure(GoogleOAuthError.apiError(detail)))
            }
        }
    }

    private func reply(_ connection: NWConnection, title: String, message: String) {
        let body = """
        <!doctype html><html><body style="font-family:-apple-system,sans-serif;padding:40px;text-align:center">\
        <h2>\(title)</h2><p>\(message)</p></body></html>
        """
        let response = """
        HTTP/1.1 200 OK\r
        Content-Type: text/html; charset=utf-8\r
        Content-Length: \(body.utf8.count)\r
        Connection: close\r
        \r
        \(body)
        """
        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
