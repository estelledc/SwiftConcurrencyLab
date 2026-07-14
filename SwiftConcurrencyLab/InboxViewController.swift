import UIKit

@MainActor
final class InboxViewController: UITableViewController {
    private let conversations = [
        ConversationSnapshot(id: "engineering", title: "Engineering", preview: "并发实验在 14:00 开始", unreadCount: 2, avatarToken: "E"),
        ConversationSnapshot(id: "ios-study", title: "iOS Study", preview: "先预测，再观察任务时序", unreadCount: 1, avatarToken: "I"),
        ConversationSnapshot(id: "design", title: "Design", preview: "新的收件箱原型已就绪", unreadCount: 0, avatarToken: "D")
    ]
    override func viewDidLoad() { super.viewDidLoad(); title = "Inbox"; tableView.register(ConversationCell.self, forCellReuseIdentifier: "conversation"); tableView.accessibilityIdentifier = "inboxTable" }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { conversations.count }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let item = conversations[indexPath.row]; let cell = tableView.dequeueReusableCell(withIdentifier: "conversation", for: indexPath) as! ConversationCell
        cell.configure(with: item)
        cell.accessoryType = item.unreadCount > 0 ? .detailButton : .none; cell.accessibilityIdentifier = "conversation_\(item.id)"; return cell
    }
}
