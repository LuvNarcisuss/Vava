import UIKit

@MainActor final class ChatsScreen: ListScreen {
    override func viewDidLoad() {
        super.viewDidLoad()
        heading.text = "Chats"
        render([
            Theme.card([
                Theme.label("Messaging is unavailable", size: 25, display: true),
                Theme.label(
                    "Vava stores your activity on this device. Sending messages to other players requires a connected messaging service."
                ),
            ])
        ])
    }
}
