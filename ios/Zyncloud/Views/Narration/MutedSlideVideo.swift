import AVKit
import SwiftUI

/// One silent, auto-playing video slide.
///
/// Wrapped rather than using `VideoPlayer` directly so the transport controls stay off — they
/// would swallow the taps that drive the slideshow — and so the mute is set on the player, which
/// is the only place it survives the item being attached.
struct MutedSlideVideo: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context _: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.showsPlaybackControls = false
        controller.videoGravity = .resizeAspect
        controller.view.backgroundColor = .black

        let player = AVPlayer(url: url)
        player.isMuted = true
        controller.player = player
        player.play()

        return controller
    }

    func updateUIViewController(_: AVPlayerViewController, context _: Context) {}

    static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator _: ()) {
        controller.player?.pause()
        controller.player = nil
    }
}
