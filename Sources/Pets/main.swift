import AppKit

setbuf(stdout, nil)

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let controller = PetController()
let model = StateModel()
model.onChange = { controller.apply(state: $0) }

let decoder = JSONDecoder()
let server = try HttpServer(port: serverPort) { body in
    if let event = try? decoder.decode(HookEvent.self, from: body) {
        print("event: \(event.hook_event_name ?? "?") session: \(event.session_id ?? "?")")
        model.handle(event)
    }
} onFailure: { error in
    let alert = NSAlert()
    alert.messageText = "Pets can't listen on 127.0.0.1:\(serverPort)"
    alert.informativeText = "Is another pets instance running?\n(\(error.localizedDescription))"
    alert.runModal()
    NSApp.terminate(nil)
}
server.stateProvider = { model.debugJSON }
server.start()

app.run()
