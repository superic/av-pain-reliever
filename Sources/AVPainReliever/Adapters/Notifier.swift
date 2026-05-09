import Foundation

/// Surface a transient banner-style notification to the user. The
/// engine never instantiates a notifier; concrete implementations
/// are injected (the app target picks the bundled vs unbundled
/// backend; tests inject a recording mock).
public protocol Notifier {
    /// Post a notification with an optional thumbnail icon and inline
    /// action button.
    ///
    /// `iconSymbol` is an optional SF Symbol name; when supplied,
    /// backends that support it render the symbol as a thumbnail
    /// attached to the notification. Backends that can't surface a
    /// thumbnail simply post the title + body unchanged.
    ///
    /// `actionTitle` becomes the button label; `onAction` fires when
    /// the user clicks the button (NOT when they click the body).
    /// Both are best-effort: backends that can't render an action
    /// button drop it and `onAction` never fires.
    func notify(
        title: String,
        body: String?,
        iconSymbol: String?,
        actionTitle: String?,
        onAction: (() -> Void)?
    )
}

extension Notifier {
    /// Convenience for action-less, icon-less notifications. Forwards
    /// to the full method so backends only have to implement one
    /// signature.
    public func notify(title: String, body: String?) {
        notify(title: title, body: body, iconSymbol: nil, actionTitle: nil, onAction: nil)
    }

    /// Convenience for a notification with just an icon thumbnail.
    public func notify(title: String, body: String?, iconSymbol: String?) {
        notify(title: title, body: body, iconSymbol: iconSymbol, actionTitle: nil, onAction: nil)
    }
}
