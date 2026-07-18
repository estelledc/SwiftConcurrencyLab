import UIKit

@MainActor
final class InboxViewController: UITableViewController {
  private let conversations: [ConversationSnapshot] = (0..<40).map { index in
    if index == 0 {
      return ConversationSnapshot(
        id: "engineering", title: "Engineering", preview: "Slow avatar: scroll now to force reuse",
        unreadCount: 2, avatarToken: "E")
    }
    return ConversationSnapshot(
      id: "thread-\(index)",
      title: "Conversation \(index)",
      preview: "Reusable row \(index)",
      unreadCount: index.isMultiple(of: 4) ? 1 : 0,
      avatarToken: String(index % 10)
    )
  }
  override func viewDidLoad() {
    super.viewDidLoad()
    title = "Inbox"
    tableView.register(ConversationCell.self, forCellReuseIdentifier: "conversation")
    tableView.accessibilityIdentifier = "inboxTable"
  }
  override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    conversations.count
  }
  override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath)
    -> UITableViewCell
  {
    let item = conversations[indexPath.row]
    let cell =
      tableView.dequeueReusableCell(withIdentifier: "conversation", for: indexPath)
      as! ConversationCell
    cell.configure(with: item)
    cell.accessoryType = item.unreadCount > 0 ? .detailButton : .none
    cell.accessibilityIdentifier = "conversation_\(item.id)"
    return cell
  }
}
