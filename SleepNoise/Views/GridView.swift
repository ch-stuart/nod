import SwiftUI
import UIKit

struct GridView: View {
    @State private var engine = GridEngine()
    @State private var dotPosition: CGPoint = GridView.loadSavedPosition()
    @State private var overlappingBookmarks: Set<BookmarkKey> = []

    private let dotDiameter: CGFloat = 40
    private let dotHitPadding: CGFloat = 20
    private let dotEdgeGutter: CGFloat = 5

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(engine.bookmarks.indices, id: \.self) { i in
                    Text("*")
                        .font(.system(size: 20, weight: .thin))
                        .foregroundStyle(.white.opacity(0.25))
                        .position(dotCenter(for: engine.bookmarks[i], in: geo.size))
                        .allowsHitTesting(false)
                }

                Circle()
                    .fill(engine.isRunning ? Color(white: 0.98).opacity(0.9) : Color.white.opacity(0.4))
                    .frame(width: dotDiameter, height: dotDiameter)
                    .shadow(color: .black.opacity(0.25), radius: 4)
                    .position(dotCenter(for: dotPosition, in: geo.size))
                    .animation(.easeOut(duration: 0.05), value: dotPosition)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                updateDotPosition(for: value.location, in: geo.size)
                            }
                    )
            }
            .contentShape(Rectangle())
            .onTapGesture(coordinateSpace: .local) { location in
                handleTap(at: location, in: geo.size)
            }
            .onAppear {
                engine.bookmarkProximity = Double(dotDiameter / 2) / Double(geo.size.width)
                engine.setPosition(x: Float(dotPosition.x), y: Float(dotPosition.y))
                // Seed overlapping state so we don't fire a spurious haptic on first appear
                overlappingBookmarks = bookmarksNear(dotPosition)
            }
        }
        .background {
            backgroundView.ignoresSafeArea()
        }
    }

    private var backgroundView: some View {
        ZStack {
            LinearGradient(
                stops: [
                    .init(color: Color(red: 0.88, green: 0.90, blue: 0.92), location: 0),
                    .init(color: Color(red: 0.55, green: 0.67, blue: 0.76), location: 0.27),
                    .init(color: Color(red: 0.67, green: 0.52, blue: 0.68), location: 0.56),
                    .init(color: Color(red: 0.77, green: 0.46, blue: 0.39), location: 0.82),
                    .init(color: Color(red: 0.30, green: 0.21, blue: 0.18), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            LinearGradient(
                stops: [
                    .init(color: .white.opacity(0.52), location: 0),
                    .init(color: .black.opacity(0.60), location: 1),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .blendMode(.multiply)
            Rectangle()
                .fill(
                    ImagePaint(
                        image: Image("BackgroundNoise"),
                        scale: 0.2
                    )
                )
                .opacity(0.10)
        }
    }

    private func handleTap(at location: CGPoint, in size: CGSize) {
        engine.toggle()
    }

    private func updateDotPosition(for location: CGPoint, in size: CGSize) {
        let inset = dotDiameter / 2 + dotEdgeGutter
        let usableWidth = max(size.width - inset * 2, 1)
        let usableHeight = max(size.height - inset * 2, 1)
        let x = Float((location.x - inset) / usableWidth).clamped(to: 0...1)
        let y = Float((location.y - inset) / usableHeight).clamped(to: 0...1)
        let point = CGPoint(x: Double(x), y: Double(y))
        dotPosition = point
        GridView.savePosition(point)

        engine.setPosition(x: x, y: y)

        let nowOverlapping = bookmarksNear(point)
        if !nowOverlapping.subtracting(overlappingBookmarks).isEmpty {
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        }
        overlappingBookmarks = nowOverlapping
    }

    private func bookmarksNear(_ pos: CGPoint) -> Set<BookmarkKey> {
        Set(engine.bookmarks.filter { b in
            hypot(pos.x - b.x, pos.y - b.y) < engine.bookmarkProximity
        }.map { BookmarkKey($0) })
    }

    private static let positionKey = "lastDotPosition"

    private static func loadSavedPosition() -> CGPoint {
        guard let dict = UserDefaults.standard.dictionary(forKey: positionKey),
              let x = dict["x"] as? Double,
              let y = dict["y"] as? Double else { return CGPoint(x: 0.75, y: 0.75) }
        return CGPoint(x: x, y: y)
    }

    private static func savePosition(_ point: CGPoint) {
        UserDefaults.standard.set(["x": point.x, "y": point.y], forKey: positionKey)
    }

    private func dotCenter(for position: CGPoint, in size: CGSize) -> CGPoint {
        let inset = dotDiameter / 2 + dotEdgeGutter
        let usableWidth = max(size.width - inset * 2, 0)
        let usableHeight = max(size.height - inset * 2, 0)
        return CGPoint(
            x: inset + position.x * usableWidth,
            y: inset + position.y * usableHeight
        )
    }
}

private extension Float {
    func clamped(to range: ClosedRange<Float>) -> Float {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

private struct BookmarkKey: Hashable {
    let x: Double
    let y: Double
    init(_ p: CGPoint) { x = p.x; y = p.y }
}
