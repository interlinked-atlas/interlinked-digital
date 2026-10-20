import SwiftUI
import AVFoundation

struct LiquidMetalView: View {
    var size: CGFloat = 80
    var clipToCircle: Bool = true
    var videoFile: String = "liquid-metal"   // pass "liquid-metal@2x" for splash
    var onVideoEnd: (() -> Void)? = nil

    @StateObject private var player = LiquidMetalPlayer()

    var body: some View {
        AVLayerView(player: player.avPlayer)
            .frame(width: size, height: size)
            .modifier(CircleClipModifier(active: clipToCircle))
            .shadow(color: Color(hex: "#C0C8D8").opacity(0.40), radius: size * 0.20, x: 0, y: 0)
            .shadow(color: Color(hex: "#A8B8D0").opacity(0.15), radius: size * 0.45, x: 0, y: 0)
            .onAppear  { player.load(videoFile, onVideoEnd: onVideoEnd); player.play()  }
            .onDisappear { player.pause() }
    }
}

// MARK: - AVPlayerLayer NSViewRepresentable

private struct AVLayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> NSView {
        let view = AVPlayerLayerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class AVPlayerLayerView: NSView {
    override func makeBackingLayer() -> CALayer { AVPlayerLayer() }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

    override init(frame: CGRect) {
        super.init(frame: frame)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        playerLayer.frame = bounds
    }
}

// MARK: - Looping player

private final class LiquidMetalPlayer: ObservableObject {
    let avPlayer = AVPlayer()
    private var observer: NSObjectProtocol?

    private func videoURL(_ name: String) -> URL? {
        // Bundle.module looks at wrong path in a packaged .app; use explicit fallbacks
        // Try both .mp4 and .mov extensions
        for ext in ["mp4", "mov"] {
            let candidates: [URL?] = [
                Bundle.atlasResources.url(forResource: name, withExtension: ext),
                Bundle.main.resourceURL?.appendingPathComponent("ATLAS_ATLAS.bundle/\(name).\(ext)"),
                Bundle.main.url(forResource: name, withExtension: ext),
            ]
            if let found = candidates.compactMap({ $0 }).first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
                return found
            }
        }
        return nil
    }

    func load(_ name: String, onVideoEnd: (() -> Void)? = nil) {
        guard avPlayer.currentItem == nil,
              let url = videoURL(name) else { return }
        let item = AVPlayerItem(url: url)
        avPlayer.replaceCurrentItem(with: item)
        avPlayer.isMuted = true
        avPlayer.actionAtItemEnd = .none
        observer = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            if let onVideoEnd {
                onVideoEnd()
            } else {
                self?.avPlayer.seek(to: .zero)
                self?.avPlayer.play()
            }
        }
    }

    func play()  { avPlayer.play()  }
    func pause() { avPlayer.pause() }

    deinit {
        if let obs = observer { NotificationCenter.default.removeObserver(obs) }
    }
}

// MARK: - Helpers

private struct CircleClipModifier: ViewModifier {
    let active: Bool
    func body(content: Content) -> some View {
        if active { content.clipShape(Circle()) } else { content }
    }
}
