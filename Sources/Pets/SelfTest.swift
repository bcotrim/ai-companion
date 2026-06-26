import Foundation

enum SelfTest {
    static func run() -> Int32 {
        let decoder = JSONDecoder()

        func send(_ json: String, expect expected: DisplayState, _ label: String) -> Bool {
            guard let data = json.data(using: .utf8),
                  let event = try? decoder.decode(HookEvent.self, from: data)
            else {
                print("FAIL \(label): could not decode event")
                return false
            }
            let model = StateModel()
            model.handle(event)
            guard model.display == expected else {
                print("FAIL \(label): expected \(expected), got \(model.display)")
                return false
            }
            return true
        }

        let checks = [
            send(#"{"hook_event_name":"SessionStart","session_id":"s1","cwd":"/tmp/demo"}"#,
                 expect: .idle, "session start"),
            send(#"{"hook_event_name":"UserPromptSubmit","session_id":"s1","prompt":"Build it"}"#,
                 expect: .working, "prompt submit"),
            send(#"{"hook_event_name":"PermissionRequest","session_id":"s1","message":"Run tests?"}"#,
                 expect: .waiting, "permission request"),
            send(#"{"hook_event_name":"SubagentStart","session_id":"s2","subagent_type":"Explore"}"#,
                 expect: .subagent, "subagent start"),
            send(#"{"hook_event_name":"PreCompact","session_id":"s3"}"#,
                 expect: .compacting, "pre compact"),
            send(#"{"hook_event_name":"StopFailure","session_id":"s4","notification_type":"server_error"}"#,
                 expect: .failed, "stop failure"),
        ]

        if checks.allSatisfy({ $0 }) {
            print("Self-test OK")
            return 0
        }
        return 1
    }
}
