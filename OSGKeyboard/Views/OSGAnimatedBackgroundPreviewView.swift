// OSGAnimatedBackgroundPreviewView.swift
// OSGKeyboard · Main App (DEBUG-only)
//
// Standalone preview host for `OSGAnimatedMeshBackground`.
// Open from anywhere with `OSGAnimatedBackgroundPreviewView()`.
//
// Tapping the screen swaps the palette; long-press pauses/resumes the animation
// so you can capture a still frame for App Store screenshots.

#if DEBUG
import SwiftUI

struct OSGAnimatedBackgroundPreviewView: View {
    private enum PaletteChoice: String, CaseIterable, Identifiable {
        case aurora, polar, ember
        var id: String { rawValue }
        var label: String {
            switch self {
            case .aurora: return "Aurora"
            case .polar:  return "Polar"
            case .ember:  return "Ember"
            }
        }
        var palette: AnimatedMeshPalette {
            switch self {
            case .aurora: return .aurora
            case .polar:  return .polar
            case .ember:  return .ember
            }
        }
    }

    @State private var choice: PaletteChoice = .aurora
    @State private var paused: Bool = false

    var body: some View {
        ZStack {
            OSGAnimatedMeshBackground(palette: choice.palette, paused: paused)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Spacer()
                Text(choice.label)
                    .font(.system(size: 56, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))
                Text(paused ? "paused — long-press to resume" : "tap to switch · long-press to pause")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.55))
                Spacer().frame(height: 12)
                paletteDots
                    .padding(.bottom, 32)
            }
        }
        .background(Color.black)
        .preferredColorScheme(.dark)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.4)) {
                let all = PaletteChoice.allCases
                let next = all.firstIndex(of: choice).map { all[($0 + 1) % all.count] } ?? choice
                choice = next
            }
        }
        .onLongPressGesture(minimumDuration: 0.5) {
            paused.toggle()
        }
    }

    private var paletteDots: some View {
        HStack(spacing: 10) {
            ForEach(PaletteChoice.allCases) { item in
                Circle()
                    .fill(item == choice ? Color.white : Color.white.opacity(0.3))
                    .frame(width: 8, height: 8)
            }
        }
    }
}

#Preview("Aurora · polar · ember") {
    OSGAnimatedBackgroundPreviewView()
}
#endif
