import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
  var window: UIWindow?
  func scene(
    _ scene: UIScene, willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    guard let windowScene = scene as? UIWindowScene else { return }
    let inbox = UINavigationController(rootViewController: InboxViewController())
    inbox.tabBarItem = UITabBarItem(title: "Inbox", image: UIImage(systemName: "tray"), tag: 0)
    let learn = UINavigationController(rootViewController: LabListViewController())
    learn.tabBarItem = UITabBarItem(title: "Learn", image: UIImage(systemName: "bolt"), tag: 1)
    let tabs = UITabBarController()
    tabs.viewControllers = [inbox, learn]
    let window = UIWindow(windowScene: windowScene)
    window.rootViewController = tabs
    self.window = window
    window.makeKeyAndVisible()
  }
}
