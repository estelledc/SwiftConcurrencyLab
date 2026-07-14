import UIKit

/// A real reuse boundary: the Task belongs to the cell's current represented model,
/// is cancelled on reuse, and verifies identity before committing a result.
@MainActor
final class ConversationCell: UITableViewCell {
    private let avatar = UILabel()
    private var avatarTask: Task<Void, Never>?
    private var representedID: String?
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        avatar.translatesAutoresizingMaskIntoConstraints = false; avatar.textAlignment = .center; avatar.textColor = .white; avatar.font = .boldSystemFont(ofSize: 14); avatar.layer.cornerRadius = 15; avatar.clipsToBounds = true
        contentView.addSubview(avatar); NSLayoutConstraint.activate([avatar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16), avatar.centerYAnchor.constraint(equalTo: contentView.centerYAnchor), avatar.widthAnchor.constraint(equalToConstant: 30), avatar.heightAnchor.constraint(equalToConstant: 30)])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func configure(with item: ConversationSnapshot) {
        avatarTask?.cancel(); representedID = item.id; avatar.text = "…"; avatar.backgroundColor = .systemGray
        var content = defaultContentConfiguration(); content.text = item.title; content.secondaryText = item.preview; content.image = nil; content.imageToTextPadding = 48; self.contentConfiguration = content
        let id = item.id; let token = item.avatarToken
        avatarTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(id == "engineering" ? 45 : 10))
            guard !Task.isCancelled, self?.representedID == id else { return }
            self?.avatar.text = token; self?.avatar.backgroundColor = .systemIndigo
        }
    }
    override func prepareForReuse() { super.prepareForReuse(); avatarTask?.cancel(); avatarTask = nil; representedID = nil; avatar.text = "…" }
    deinit { avatarTask?.cancel() }
}
