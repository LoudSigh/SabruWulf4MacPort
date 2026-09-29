import AVFoundation
import Combine
import GameCore
import SwiftUI
import UniformTypeIdentifiers

private enum SoundtrackImportError: Error, LocalizedError {
  case missingFile
  case tooLarge
  case invalidAudio

  var errorDescription: String? {
    switch self {
    case .missingFile:
      "Select a local WAV, M4A or other supported audio file."
    case .tooLarge:
      "The alternative soundtrack exceeds the 20 MB import limit."
    case .invalidAudio:
      "The selected file is not playable audio. Render the optional AY file to WAV first."
    }
  }
}

struct GameView: View {
  @Environment(\.scenePhase) private var scenePhase
  @State private var game = GameState()
  @State private var importingSoundtrack = false
  @State private var soundtrack: AVAudioPlayer?
  @State private var soundtrackName: String?
  @State private var soundtrackError: String?
  @State private var soundtrackVolume = 0.45
  @State private var playingSoundtrack = false
  @State private var referenceExpanded = true
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
          DisclosureGroup(
            "Explore source-backed 16 × 16 world", isExpanded: $referenceExpanded
          ) {
            WorldReferenceView()
              .padding(.top, 12)
          }
          .frame(maxWidth: 470)
          Text("Playable placeholder prototype (not the original game)")
            .font(.headline)
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
          VStack(spacing: 8) {
            Text("Optional local audio · not verified against 48K gameplay")
              .font(.headline)
            Button("Import your local audio (WAV or M4A)") {
              importingSoundtrack = true
            }
            .buttonStyle(.bordered)
            if let soundtrackName {
              Text("Local audio: \(soundtrackName)")
                .font(.caption)
              HStack {
                Button(playingSoundtrack ? "Pause soundtrack" : "Play soundtrack") {
                  toggleSoundtrack()
                }
                .disabled(game.isPaused || game.isGameOver)
                Button("Remove soundtrack") {
                  pauseSoundtrack()
                  soundtrack = nil
                  self.soundtrackName = nil
                  soundtrackError = nil
                }
              }
              .buttonStyle(.bordered)
              Slider(value: $soundtrackVolume, in: 0...1) {
                Text("Alternative soundtrack volume")
              }
              .onChange(of: soundtrackVolume) { _, volume in
                soundtrack?.volume = Float(volume)
              }
            }
            if let soundtrackError {
              Text(soundtrackError)
                .font(.caption)
                .foregroundStyle(.orange)
                .accessibilityAddTraits(.updatesFrequently)
            }
            Text("Audio is opt-in and stays on your device. The supplied AY file has four beeper-only tracks; render one to WAV locally. Playback loops, without original in-game cue timing.")
              .font(.caption)
              .multilineTextAlignment(.center)
          }
          .frame(maxWidth: 470)
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
        if phase != .active { pauseSoundtrack() }
        if phase != .active && !game.isPaused && !game.isGameOver {
          game.togglePause()
        }
      }
      .onChange(of: game.isPaused) { _, paused in
        if paused { pauseSoundtrack() }
      }
      .onChange(of: game.isGameOver) { _, over in
        if over { pauseSoundtrack() }
      }
      .fileImporter(
        isPresented: $importingSoundtrack,
        allowedContentTypes: [.audio],
        allowsMultipleSelection: false
      ) { result in
        do {
          guard let url = try result.get().first else {
            throw SoundtrackImportError.missingFile
          }
          let accessed = url.startAccessingSecurityScopedResource()
          defer { if accessed { url.stopAccessingSecurityScopedResource() } }
          let handle = try FileHandle(forReadingFrom: url)
          defer { handle.closeFile() }
          let maximumBytes = 20_000_000
          guard let audio = try handle.read(upToCount: maximumBytes + 1),
                !audio.isEmpty else {
            throw SoundtrackImportError.invalidAudio
          }
          guard audio.count <= maximumBytes else {
            throw SoundtrackImportError.tooLarge
          }
          let player = try AVAudioPlayer(data: audio)
          guard player.duration.isFinite, player.duration > 0,
                player.prepareToPlay() else {
            throw SoundtrackImportError.invalidAudio
          }
          player.numberOfLoops = -1
          player.volume = Float(soundtrackVolume)
          pauseSoundtrack()
          soundtrack = player
          soundtrackName = url.lastPathComponent
          soundtrackError = nil
        } catch {
          soundtrackError = error.localizedDescription
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

  private func toggleSoundtrack() {
    guard let soundtrack else {
      soundtrackError = SoundtrackImportError.missingFile.localizedDescription
      return
    }
    if playingSoundtrack {
      pauseSoundtrack()
    } else if soundtrack.play() {
      playingSoundtrack = true
      soundtrackError = nil
    } else {
      soundtrackError = SoundtrackImportError.invalidAudio.localizedDescription
    }
  }

  private func pauseSoundtrack() {
    soundtrack?.pause()
    playingSoundtrack = false
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
