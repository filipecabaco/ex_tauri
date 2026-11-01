// ex_tauri's iOS shell: the web view behaves like an app, not a page in Safari.
//
//   formAccessoryBar        false (default): no previous / next / done bar above
//                           the keyboard. WKWebView adds it to every text field and
//                           iOS has no switch for it: it is the content view's
//                           inputAccessoryView, so the content view gets a
//                           subclass that answers nil (as Capacitor's Keyboard
//                           plugin does).
//   dismissKeyboardOnSwipe  true (default): a downward swipe anywhere puts the
//                           keyboard away, as in Messages; dragging the web view's
//                           own scroll view does it interactively.
//   keyboardResize          true (default): while the keyboard is up the web view
//                           is only as tall as the space above it, so a page laid
//                           out at 100% / 100dvh keeps its bottom bar and text field
//                           in sight. WKWebView does not shrink on its own: the
//                           keyboard covers the page. The page also gets
//                           <html data-keyboard="open"> and the CSS variable
//                           --ex-tauri-keyboard-height, to hide a tab bar, say.
//   appLikePage             true (default): every page gets a viewport that does
//                           not zoom and draws under the notch, and the touch CSS
//                           an app wants (no double-tap zoom, no grey tap flash, no
//                           text inflation), before its own code runs. An app gets
//                           this without knowing it needs it.
//
// Set from Elixir with `config :ex_tauri, :ios, form_accessory_bar: true`,
// `dismiss_keyboard_on_swipe: false` or `keyboard_resize: false`; `mix ex_tauri.ios
// init` writes them to tauri.ios.conf.json (`plugins.ex-tauri`).

import Tauri
import UIKit
import WebKit

struct ExTauriShellConfig: Decodable {
  var formAccessoryBar: Bool?
  var dismissKeyboardOnSwipe: Bool?
  var keyboardResize: Bool?
  var appLikePage: Bool?
}

/// Runs at document start on every page the web view loads: the backend's pages
/// come after the bundled loading page, so all of them get it.
private let appLikePageScript = """
  (function () {
    var wanted = { "width": "device-width", "initial-scale": "1", "maximum-scale": "1",
                   "user-scalable": "no", "viewport-fit": "cover" };
    function viewport() {
      var meta = document.querySelector('meta[name="viewport"]');
      if (!meta) {
        meta = document.createElement("meta");
        meta.name = "viewport";
        (document.head || document.documentElement).appendChild(meta);
      }
      var parts = {};
      (meta.content || "").split(",").forEach(function (p) {
        var kv = p.split("=");
        if (kv[0].trim()) parts[kv[0].trim()] = (kv[1] || "").trim();
      });
      for (var k in wanted) parts[k] = wanted[k];
      meta.content = Object.keys(parts).map(function (k) { return k + "=" + parts[k]; }).join(", ");
    }
    function style() {
      var css = document.createElement("style");
      css.id = "ex-tauri-app-like";
      css.textContent =
        "html{-webkit-text-size-adjust:100%;text-size-adjust:100%;touch-action:manipulation;" +
        "-webkit-tap-highlight-color:transparent}";
      (document.head || document.documentElement).prepend(css);
    }
    viewport(); style();
    document.addEventListener("DOMContentLoaded", viewport);
  })();
  """

class ExTauriShellPlugin: Plugin, UIGestureRecognizerDelegate {
  private weak var webview: WKWebView?
  /// The web view's height before the keyboard came up, to give back after.
  private var fullHeight: CGFloat?

  override func load(webview: WKWebView) {
    self.webview = webview
    let config = (try? parseConfig(ExTauriShellConfig.self)) ?? ExTauriShellConfig()

    DispatchQueue.main.async {
      if config.formAccessoryBar != true { Self.hideFormAccessoryBar(in: webview) }
      if config.dismissKeyboardOnSwipe != false { self.dismissKeyboardOnSwipe(in: webview) }
      if config.keyboardResize != false { self.resizeForKeyboard() }
      if config.appLikePage != false { self.makePagesAppLike(in: webview) }
    }
  }

  // MARK: - App-like pages

  private func makePagesAppLike(in webview: WKWebView) {
    let script = WKUserScript(source: appLikePageScript, injectionTime: .atDocumentStart, forMainFrameOnly: true)
    webview.configuration.userContentController.addUserScript(script)
    // The page already showing (the loading page) predates the script.
    webview.evaluateJavaScript(appLikePageScript, completionHandler: nil)
  }

  // MARK: - Keyboard resize

  private func resizeForKeyboard() {
    let center = NotificationCenter.default
    center.addObserver(self, selector: #selector(keyboardWillChange(_:)), name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
    center.addObserver(self, selector: #selector(keyboardWillHide(_:)), name: UIResponder.keyboardWillHideNotification, object: nil)
    // Resizing is the shell's job here: iOS's own attempt (scrolling the page up
    // under a fixed layout) is what pushes headers off screen.
    webview?.scrollView.contentInsetAdjustmentBehavior = .never
  }

  @objc private func keyboardWillChange(_ note: Notification) {
    guard let webview = webview, let window = webview.window,
      let end = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue
    else { return }

    let full = fullHeight ?? webview.frame.height
    let keyboardTop = webview.superview?.convert(window.convert(end, from: nil), from: window).minY ?? end.minY
    let covered = max(0, webview.frame.minY + full - keyboardTop)

    // A keyboard moving off screen also arrives here, with nothing covered.
    guard covered > 0 else {
      keyboardWillHide(note)
      return
    }

    fullHeight = full
    animate(note) {
      webview.frame.size.height = full - covered
      webview.scrollView.contentOffset = .zero
    }
    tell(open: true, height: covered)
  }

  @objc private func keyboardWillHide(_ note: Notification) {
    guard let webview = webview, let full = fullHeight else { return }
    fullHeight = nil
    animate(note) { webview.frame.size.height = full }
    tell(open: false, height: 0)
  }

  private func animate(_ note: Notification, _ change: @escaping () -> Void) {
    let duration = (note.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double) ?? 0.25
    let curve = (note.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt) ?? 7
    UIView.animate(withDuration: duration, delay: 0, options: UIView.AnimationOptions(rawValue: curve << 16), animations: change)
  }

  private func tell(open: Bool, height: CGFloat) {
    let js = """
      document.documentElement.dataset.keyboard = "\(open ? "open" : "closed")";
      document.documentElement.style.setProperty("--ex-tauri-keyboard-height", "\(Int(height))px");
      """
    webview?.evaluateJavaScript(js, completionHandler: nil)
  }

  // MARK: - Form accessory bar

  private static func hideFormAccessoryBar(in webview: WKWebView) {
    guard let content = webview.scrollView.subviews.first(where: { String(describing: type(of: $0)).hasPrefix("WKContent") }),
      let original = object_getClass(content)
    else { return }

    let name = "\(original)_ExTauriNoFormAccessory"
    var subclass: AnyClass? = NSClassFromString(name)

    if subclass == nil, let created = objc_allocateClassPair(original, name, 0),
      let nothing = class_getInstanceMethod(NoAccessory.self, #selector(getter: NoAccessory.inputAccessoryView))
    {
      class_addMethod(created, #selector(getter: UIResponder.inputAccessoryView), method_getImplementation(nothing), method_getTypeEncoding(nothing))
      objc_registerClassPair(created)
      subclass = created
    }

    if let subclass = subclass { object_setClass(content, subclass) }
  }

  // MARK: - Swipe down to dismiss

  private func dismissKeyboardOnSwipe(in webview: WKWebView) {
    webview.scrollView.keyboardDismissMode = .interactive

    // Pages usually scroll inside their own elements, not the web view's scroll
    // view, so the swipe is watched on the web view itself, alongside whatever
    // the page does with it.
    let swipe = UIPanGestureRecognizer(target: self, action: #selector(swiped(_:)))
    swipe.cancelsTouchesInView = false
    swipe.delaysTouchesBegan = false
    swipe.delegate = self
    webview.addGestureRecognizer(swipe)
  }

  @objc private func swiped(_ gesture: UIPanGestureRecognizer) {
    guard gesture.state == .ended, let view = gesture.view else { return }
    let moved = gesture.translation(in: view)
    let speed = gesture.velocity(in: view)

    // Clearly down, not sideways, and meant: a short fast flick or a long drag.
    if moved.y > 30, moved.y > abs(moved.x) * 1.5, speed.y > 250 || moved.y > 120 {
      webview?.endEditing(true)
    }
  }

  func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
    true
  }
}

/// Lends its getter to the content view's subclass.
private final class NoAccessory: NSObject {
  @objc var inputAccessoryView: AnyObject? { nil }
}

@_cdecl("init_plugin_ex_tauri")
func initPlugin() -> Plugin {
  return ExTauriShellPlugin()
}
