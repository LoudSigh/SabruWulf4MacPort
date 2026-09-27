import Combine
import GameCore
import SwiftUI

struct GameView: View {
  @Environment(\.scenePhase) private var scenePhase
  @State private var game = GameState()
  #if os(macOS)
    @FocusState private var keyboardFocused: Bool
  #endif

  private let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: Room.width)
  private let timer = Timer.publish(every: 0.65, on: .main, in: .common).autoconnect()

  var body: some View {
    GeometryReader { viewport in
      let contentWidth = max(0, viewport.size.width - 32)
      let boardWidth = min(contentWidth, 470)
      ScrollView {
        VStack(spacing: 18) {
          Text("Sabre Wulf")
            .font(.largeTitle.bold())
          Text("Original placeholder maze • mechanics not verified against any historical game")
            .font(.footnote)
            .multilineTextAlignment(.center)
          HStack {
            Label("Health \(game.health)", systemImage: "heart.fill")
            Spacer()
            Text("Room \(game.roomID.x + 1), \(game.roomID.y + 1)")
            Spacer()
            Label("\(game.collected.count) / 4", systemImage: "circle.hexagongrid.fill")
          }
          .font(.headline)

          board
            .frame(
              width: boardWidth,
              height: boardWidth * CGFloat(Room.height) / CGFloat(Room.width))

          Text(status)
            .font(.subheadline)
            .accessibilityAddTraits(.updatesFrequently)

          HStack(spacing: 18) {
            Button(game.isPaused ? "Resume" : "Pause") { game.togglePause() }
              .disabled(game.isGameOver)
              .keyboardShortcut("p", modifiers: [])
            Button("Reset") { game.reset() }
              .keyboardShortcut("r", modifiers: [])
          }
          .buttonStyle(.borderedProminent)

          VStack(spacing: 5) {
            directionButton("Up", symbol: "arrow.up", direction: .north)
            HStack(spacing: 36) {
              directionButton("Left", symbol: "arrow.left", direction: .west)
              directionButton("Down", symbol: "arrow.down", direction: .south)
              directionButton("Right", symbol: "arrow.right", direction: .east)
            }
          }
          .buttonStyle(.bordered)
          Text("Move with arrow buttons. On Mac: arrow keys or WASD. P pauses; R resets.")
            .font(.caption)
            .multilineTextAlignment(.center)
        }
        .frame(width: min(contentWidth, 650))
        .padding()
        .frame(maxWidth: .infinity)
      }
      .background(Color(red: 0.06, green: 0.12, blue: 0.16))
      .foregroundStyle(.white)
      .onReceive(timer) { _ in
        if scenePhase == .active { game.tick() }
      }
      .onChange(of: scenePhase) { _, phase in
        if phase != .active && !game.isPaused && !game.isGameOver {
          game.togglePause()
        }
      }
      #if os(macOS)
        .focusable()
        .focused($keyboardFocused)
        .onAppear { keyboardFocused = true }
        .onKeyPress { press in
          let direction: Direction?
          switch press.key {
          case .upArrow: direction = .north
          case .downArrow: direction = .south
          case .leftArrow: direction = .west
          case .rightArrow: direction = .east
          default:
            switch press.characters.lowercased() {
            case "w": direction = .north
            case "s": direction = .south
            case "a": direction = .west
            case "d": direction = .east
            default: direction = nil
            }
          }
          guard let direction else { return .ignored }
          game.move(direction)
          return .handled
        }
      #endif
    }
  }

  private var board: some View {
    GeometryReader { geometry in
      let side = min(
        (geometry.size.width - 8 * 3) / 9,
        (geometry.size.height - 6 * 3) / 7)
      LazyVGrid(columns: columns, spacing: 3) {
        ForEach(0..<(Room.width * Room.height), id: \.self) { index in
          let point = GridPoint(index % Room.width, index / Room.width)
          tile(at: point)
            .frame(height: side)
        }
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      "Maze, room \(game.roomID.x + 1), \(game.roomID.y + 1). Player at column \(game.player.x + 1), row \(game.player.y + 1). Health \(game.health). \(game.collected.count) items collected."
    )
  }

  private func tile(at point: GridPoint) -> some View {
    let isWall = game.room.walls.contains(point)
    let isPlayer = game.player == point
    let isEnemy = game.enemy == point
    let isItem = game.room.item == point && !game.collected.contains(game.roomID)
    let isGate =
      (point.x == 4 && (point.y == 0 || point.y == 6))
      || (point.y == 3 && (point.x == 0 || point.x == 8))
    return RoundedRectangle(cornerRadius: 5)
      .fill(
        isWall
          ? Color.gray.opacity(0.75)
          : isGate ? Color.teal.opacity(0.45) : Color(red: 0.12, green: 0.23, blue: 0.25)
      )
      .overlay {
        if isPlayer {
          Circle().fill(.cyan).padding(5)
        } else if isEnemy {
          Image(systemName: "triangle.fill").foregroundStyle(.orange)
        } else if isItem {
          Image(systemName: "sparkle").foregroundStyle(.yellow)
        }
      }
  }

  private func directionButton(_ name: String, symbol: String, direction: Direction) -> some View {
    Button {
      game.move(direction)
    } label: {
      Image(systemName: symbol)
        .font(.title3.bold())
        .frame(width: 54, height: 40)
    }
    .accessibilityLabel("Move \(name)")
    .disabled(game.isPaused || game.isGameOver)
  }

  private var status: String {
    if game.isGameOver { return "Game over. Select Reset to try again." }
    if game.isPaused { return "Paused. Select Resume to continue." }
    if game.collected.count == 4 { return "All four items collected! Explore or reset." }
    return "Collect the yellow markers. Avoid the orange patrol."
  }
}
